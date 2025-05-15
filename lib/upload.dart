import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:dotted_border/dotted_border.dart';
import 'dart:io';
import 'dart:math' as math;

class UploadScreen extends StatefulWidget {
  const UploadScreen({Key? key}) : super(key: key);

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  bool _isUploading = false;
  bool _isAnalyzing = false;
  List<Map<String, dynamic>> _uploadedFiles = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  @override
  void initState() {
    super.initState();
    _loadUploadedFiles();
  }

  Future<void> _loadUploadedFiles() async {
    if (_currentUser == null) return;

    try {
      final QuerySnapshot snapshot = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('uploaded_files')
          .orderBy('uploadedAt', descending: true)
          .limit(50)
          .get();

      List<Map<String, dynamic>> files = [];
      WriteBatch batch = _firestore.batch();
      bool needsBatchCommit = false;

      for (var doc in snapshot.docs) {
        Map<String, dynamic> fileData = {
          'id': doc.id,
          ...doc.data() as Map<String, dynamic>
        };

        // Skip PDF files or files with no path
        if (fileData['type'] == 'pdf') {
          batch.delete(doc.reference); // Remove PDF files from the database
          needsBatchCommit = true;
          continue;
        }

        if (fileData['localPath'] != null) {
          File localFile = File(fileData['localPath']);
          if (await localFile.exists()) {
            // Additional check to make sure it's not a PDF file
            if (fileData['name']?.toLowerCase()?.endsWith('.pdf') == true) {
              await localFile.delete(); // Delete the file
              batch.delete(doc.reference); // Remove from database
              needsBatchCommit = true;
              continue;
            }
            files.add(fileData);
          } else {
            batch.delete(doc.reference);
            needsBatchCommit = true;
          }
        }
      }

      if (needsBatchCommit) {
        await batch.commit();
      }

      if (mounted) {
        setState(() {
          _uploadedFiles = files;
        });
      }
    } catch (e) {
      print('Error loading files: $e');
      if (mounted) {
        _showErrorSnackBar('Error loading uploaded files');
      }
    }
  }

  Future<void> _pickAndUploadFile() async {
    try {
      // Use FileType.any to allow selecting any file (so we can check and show proper error for PDF files)
      FilePickerResult? result = await FilePicker.platform.pickFiles();

      if (result != null) {
        PlatformFile file = result.files.first;

        Directory tempDir = await getTemporaryDirectory();
        String tempPath = '${tempDir.path}/temp_${file.name}';
        File tempFile = File(tempPath);

        if (file.bytes != null) {
          await tempFile.writeAsBytes(file.bytes!);
        } else if (file.path != null) {
          await File(file.path!).copy(tempPath);
        } else {
          throw Exception('No file data available');
        }

        Directory appDocDir = await getApplicationDocumentsDirectory();
        String fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
        String filePath = '${appDocDir.path}/uploads/$fileName';

        Directory uploadsDir = Directory('${appDocDir.path}/uploads');
        if (!await uploadsDir.exists()) {
          await uploadsDir.create(recursive: true);
        }

        File localFile = File(filePath);
        await tempFile.copy(filePath);
        await tempFile.delete();

        if (!await localFile.exists()) {
          throw Exception('Failed to save file locally');
        }

        // Double-check file type before saving to database
        String fileExtension = file.name.split('.').last.toLowerCase();
        if (fileExtension == 'pdf') {
          // Handle case where somehow a PDF file made it through
          await localFile.delete(); // Clean up
          setState(() {
            _isUploading = false;
          });
          _showPdfErrorDialog();
          return;
        } else if (fileExtension != 'csv' && fileExtension != 'xlsx') {
          // Handle other unsupported file types
          await localFile.delete(); // Clean up
          setState(() {
            _isUploading = false;
          });
          _showErrorSnackBar('Unsupported file format. Please upload CSV or XLSX files only.');
          return;
        }

        DocumentReference docRef = await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('uploaded_files')
            .add({
          'name': file.name,
          'fileName': fileName,
          'localPath': filePath,
          'size': file.size,
          'uploadedAt': Timestamp.now(),
          'type': file.extension?.toLowerCase(),
        });

        DocumentSnapshot verifyDoc = await docRef.get();
        if (!verifyDoc.exists) {
          throw Exception('Failed to save file metadata');
        }

        await _loadUploadedFiles();

        if (mounted) {
          _showSuccessSnackBar('File "${file.name}" uploaded successfully!');
        }
      }
    } catch (e) {
      print('Upload error: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to upload file: ${e.toString()}');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  Future<void> _analyzeFile(Map<String, dynamic> fileData) async {
    setState(() {
      _isAnalyzing = true;
    });

    try {
      // First check if the file type is supported
      String fileType = fileData['type'] ?? '';
      if (fileType == 'pdf') {
        _showPdfErrorDialog();
        setState(() {
          _isAnalyzing = false;
        });
        return;
      } else if (fileType != 'csv' && fileType != 'xlsx') {
        _showErrorSnackBar('Unsupported file type. Only CSV and XLSX files can be analyzed.');
        setState(() {
          _isAnalyzing = false;
        });
        return;
      }

      Map<String, dynamic> analysisResult;
      Map<String, dynamic> rawData = {};

      if (fileData['type'] == 'csv') {
        analysisResult = await _extractTransactionsFromCsv(fileData);

        if (analysisResult['totalTransactions'] == 0) {
          File localFile = File(fileData['localPath']);
          if (await localFile.exists()) {
            String content = await localFile.readAsString();
            rawData['rawText'] = content.length > 1000 ? content.substring(0, 1000) + '...' : content;
          }
        }
      } else if (fileData['type'] == 'xlsx') {
        analysisResult = await _extractTransactionsFromExcel(fileData);
      } else {
        _showErrorSnackBar('Unsupported file type');
        return;
      }

      if (analysisResult['totalTransactions'] == 0) {
        analysisResult['rawData'] = rawData;

        await _saveAnalysisResult(fileData['id'], {
          'status': 'failed',
          'error': 'No transactions found',
          'rawData': rawData,
          'timestamp': Timestamp.now(),
        });

        _showDetailedErrorDialog(
            'No transactions found in this file',
            'The file may not be in the expected format. The system is looking for transaction data with dates, amounts, and status information.',
            rawData
        );
        return;
      }

      await _saveAnalysisResult(fileData['id'], analysisResult);

      if (mounted) {
        _showSuccessSnackBar('Analysis completed successfully!');
        _showAnalysisResult(analysisResult);
      }
    } catch (e) {
      print('Analysis error: $e');

      String errorDetails = '';
      try {
        errorDetails = e.toString();
        if (e is Error) {
          errorDetails += '\n' + StackTrace.current.toString();
        }
      } catch (_) {
        errorDetails = 'Unknown error occurred';
      }

      try {
        await _saveAnalysisResult(fileData['id'], {
          'status': 'error',
          'error': errorDetails,
          'timestamp': Timestamp.now(),
        });
      } catch (_) {}

      if (mounted) {
        _showDetailedErrorDialog(
            'Analysis Failed',
            'Could not analyze the file. The system encountered an error while processing.',
            {'error': errorDetails}
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAnalyzing = false;
        });
      }
    }
  }

  // Helper method to clean extracted text
  String _cleanExtractedText(String text) {
    String cleaned = text;

    // Replace multiple spaces with single space
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');

    // Fix broken words across lines
    cleaned = cleaned.replaceAll(RegExp(r'(\w)-\s*\n\s*(\w)'), r'$1$2');

    // Normalize line endings
    cleaned = cleaned.replaceAll(RegExp(r'\r\n'), '\n');
    cleaned = cleaned.replaceAll(RegExp(r'\r'), '\n');

    // Remove excessive empty lines
    cleaned = cleaned.replaceAll(RegExp(r'\n\s*\n\s*\n'), '\n\n');

    return cleaned;
  }

  Future<Map<String, dynamic>> _extractTransactionsFromCsv(Map<String, dynamic> fileData) async {
    File localFile = File(fileData['localPath']);
    if (!await localFile.exists()) {
      throw Exception('File not found locally');
    }

    String content = await localFile.readAsString();
    return _analyzeTransactionText(content);
  }

  Future<Map<String, dynamic>> _extractTransactionsFromExcel(Map<String, dynamic> fileData) async {
    return {
      'totalTransactions': 0,
      'error': 'Excel transaction analysis not implemented yet'
    };
  }

  // Enhanced transaction text analysis specifically for TNG Wallet
  Map<String, dynamic> _analyzeTransactionText(String text) {
    List<String> lines = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    List<Map<String, dynamic>> transactions = [];

    String? transactionPeriod;
    double totalAmount = 0.0;
    Map<String, int> transactionTypes = {};
    Map<String, int> statusCount = {};

    print('=== ANALYZING TNG WALLET TEXT ===');
    print('Total lines: ${lines.length}');

    // Print first 30 lines for debugging
    print('First 30 lines of extracted text:');
    for (int i = 0; i < math.min(30, lines.length); i++) {
      print('Line $i: ${lines[i]}');
    }

    // Extract transaction period with more flexible patterns
    for (String line in lines) {
      // Look for the date range pattern anywhere in the line
      RegExp periodRegex = RegExp(r'(\d{1,2}\s+\w+\s+\d{4}\s*-\s*\d{1,2}\s+\w+\s+\d{4})');
      var match = periodRegex.firstMatch(line);
      if (match != null) {
        transactionPeriod = match.group(1);
        print('Found transaction period: $transactionPeriod');
        break;
      }
    }

    // Look for transactions using multiple strategies

    // Strategy 1: Find table with headers
    int tableStart = _findTransactionTable(lines);

    // Strategy 2: If no table found, look for transaction patterns anywhere
    if (tableStart == -1) {
      print('No table structure found, trying pattern-based extraction...');
      return _extractTransactionsWithPatterns(text, transactionPeriod);
    }

    // Parse transactions from the table
    print('Found transaction table starting at line $tableStart');

    // Process lines starting from the table
    for (int i = tableStart; i < lines.length; i++) {
      String line = lines[i];

      // Skip empty lines and footers
      if (line.isEmpty ||
          line.toLowerCase().contains('system generated') ||
          line.toLowerCase().contains('end of statement') ||
          line.toLowerCase().contains('page ')) {
        continue;
      }

      // Look for lines starting with date pattern
      RegExp dateRegex = RegExp(r'^(\d{1,2}/\d{1,2}/\d{4})');
      var dateMatch = dateRegex.firstMatch(line);

      if (dateMatch != null) {
        // Found potential transaction, collect following lines too
        List<String> transactionLines = [line];

        // Collect next few lines that might be part of this transaction
        for (int j = i + 1; j < math.min(i + 4, lines.length); j++) {
          // Stop if we hit another date (new transaction)
          if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}').hasMatch(lines[j])) {
            break;
          }
          // Stop if we hit empty line or known separators
          if (lines[j].isEmpty || lines[j].toLowerCase().contains('---')) {
            break;
          }
          transactionLines.add(lines[j]);
        }

        // Parse the complete transaction
        var transaction = _parseTransactionFromLines(transactionLines);
        if (transaction != null) {
          transactions.add(transaction);
          totalAmount += transaction['amount'] ?? 0.0;

          String type = transaction['type'] ?? 'Unknown';
          String status = transaction['status'] ?? 'Unknown';

          transactionTypes[type] = (transactionTypes[type] ?? 0) + 1;
          statusCount[status] = (statusCount[status] ?? 0) + 1;

          print('Successfully parsed transaction: ${transaction}');
        }
      }
    }

    // If still no transactions found, try more aggressive parsing
    if (transactions.isEmpty) {
      print('No transactions found in table, trying aggressive pattern matching...');
      return _extractTransactionsWithPatterns(text, transactionPeriod);
    }

    print('=== ANALYSIS COMPLETE ===');
    print('Found ${transactions.length} transactions');
    print('Total amount: RM$totalAmount');

    return {
      'transactionPeriod': transactionPeriod ?? 'Not found',
      'totalTransactions': transactions.length,
      'totalAmount': totalAmount,
      'transactionTypes': transactionTypes,
      'statusCount': statusCount,
      'transactions': transactions,
      'averageAmount': transactions.isNotEmpty ? totalAmount / transactions.length : 0.0,
    };
  }

  // Find the start of transaction table by looking for headers or data patterns
  int _findTransactionTable(List<String> lines) {
    // Strategy 1: Look for table headers
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i].toLowerCase();

      // Check if this line looks like a table header
      if ((line.contains('date') && line.contains('status') && line.contains('transaction')) ||
          (line.contains('date') && line.contains('amount')) ||
          (line.contains('date') && line.contains('type'))) {
        print('Found table header at line $i: ${lines[i]}');
        return i + 1; // Return the line after header
      }
    }

    // Strategy 2: Look for first transaction-like pattern
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];

      // Check if line starts with date and contains success/amount pattern
      if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}').hasMatch(line) &&
          (line.toLowerCase().contains('success') || line.toLowerCase().contains('failed')) &&
          line.contains('RM')) {
        print('Found first transaction pattern at line $i: $line');
        return i;
      }
    }

    return -1;
  }

  // Parse transaction from collected lines
  Map<String, dynamic>? _parseTransactionFromLines(List<String> transactionLines) {
    if (transactionLines.isEmpty) return null;

    // Combine all lines into one string for easier parsing
    String fullText = transactionLines.join(' ').replaceAll(RegExp(r'\s+'), ' ');
    print('Parsing transaction text: $fullText');

    // Extract date (must be at the beginning)
    RegExp dateRegex = RegExp(r'^(\d{1,2}/\d{1,2}/\d{4})');
    var dateMatch = dateRegex.firstMatch(fullText);
    if (dateMatch == null) return null;
    String date = dateMatch.group(1)!;

    // Extract status
    String status = 'Unknown';
    RegExp statusRegex = RegExp(r'\b(Success|Failed|Pending)\b', caseSensitive: false);
    var statusMatch = statusRegex.firstMatch(fullText);
    if (statusMatch != null) {
      status = statusMatch.group(1)!;
    }

    // Extract transaction type with more specific patterns
    String transactionType = 'Unknown';
    Map<String, RegExp> typePatterns = {
      'Payment': RegExp(r'\bPayment\b', caseSensitive: false),
      'DuitNow QR TNGD': RegExp(r'DuitNow QR TNGD|DuitNow QR|DuitNow', caseSensitive: false),
      'Receive from Wallet': RegExp(r'Receive from Wallet|Receive from', caseSensitive: false),
      'Transfer to Wallet': RegExp(r'Transfer to Wallet|Transfer to', caseSensitive: false),
      'Reload': RegExp(r'Top Up|Reload|Recharge', caseSensitive: false),
      'Withdrawal': RegExp(r'Withdraw|Cash Out', caseSensitive: false),
    };

    for (var entry in typePatterns.entries) {
      if (entry.value.hasMatch(fullText)) {
        transactionType = entry.key;
        break;
      }
    }

    // Extract amount
    RegExp amountRegex = RegExp(r'RM(\d+\.\d{2})');
    var amountMatch = amountRegex.firstMatch(fullText);
    if (amountMatch == null) return null;
    double amount = double.parse(amountMatch.group(1)!);

    // Extract description (look for known merchants or reference numbers)
    String description = '';
    List<String> merchants = ['SPEEDMART', 'MEETMEE', 'CHIN HUI LING', '99 SPEEDMART'];
    for (String merchant in merchants) {
      if (fullText.toUpperCase().contains(merchant)) {
        description = merchant;
        break;
      }
    }

    // If no merchant found, try to extract reference/description
    if (description.isEmpty) {
      // Look for long number sequences that might be references
      RegExp refRegex = RegExp(r'(\d{10,})');
      var refMatch = refRegex.firstMatch(fullText);
      if (refMatch != null) {
        description = 'Ref: ${refMatch.group(1)!.substring(0, 8)}...';
      }
    }

    return {
      'date': date,
      'status': status,
      'type': transactionType,
      'amount': amount,
      'description': description,
    };
  }

  // Fallback method using pattern matching across entire text
  Map<String, dynamic> _extractTransactionsWithPatterns(String text, String? transactionPeriod) {
    List<Map<String, dynamic>> transactions = [];

    print('=== PATTERN-BASED EXTRACTION ===');

    // Look for transaction patterns using regex
    // This regex looks for: Date + Status + Type + Amount pattern
    RegExp transactionRegex = RegExp(
        r'(\d{1,2}/\d{1,2}/\d{4})\s+' + // Date
            r'(Success|Failed|Pending)\s+' + // Status
            r'([^RM]+?)' + // Transaction type and description (non-greedy)
            r'RM(\d+\.\d{2})', // Amount
        caseSensitive: false,
        multiLine: true
    );

    var matches = transactionRegex.allMatches(text);

    for (var match in matches) {
      String date = match.group(1)!;
      String status = match.group(2)!;
      String typeAndDesc = match.group(3)!.trim();
      double amount = double.parse(match.group(4)!);

      // Extract transaction type from typeAndDesc
      String transactionType = 'Unknown';
      String description = '';

      if (typeAndDesc.toUpperCase().contains('PAYMENT')) {
        transactionType = 'Payment';
        // Extract merchant name after Payment
        RegExp merchantRegex = RegExp(r'Payment\s+(.+)', caseSensitive: false);
        var merchantMatch = merchantRegex.firstMatch(typeAndDesc);
        if (merchantMatch != null) {
          description = merchantMatch.group(1)!.trim();
        }
      } else if (typeAndDesc.toUpperCase().contains('DUITNOW')) {
        transactionType = 'DuitNow QR TNGD';
        RegExp merchantRegex = RegExp(r'DuitNow QR TNGD\s+(.+)', caseSensitive: false);
        var merchantMatch = merchantRegex.firstMatch(typeAndDesc);
        if (merchantMatch != null) {
          description = merchantMatch.group(1)!.trim();
        }
      } else if (typeAndDesc.toUpperCase().contains('RECEIVE')) {
        transactionType = 'Receive from Wallet';
        RegExp merchantRegex = RegExp(r'Receive from Wallet\s+(.+)', caseSensitive: false);
        var merchantMatch = merchantRegex.firstMatch(typeAndDesc);
        if (merchantMatch != null) {
          description = merchantMatch.group(1)!.trim();
        }
      } else if (typeAndDesc.toUpperCase().contains('TRANSFER')) {
        transactionType = 'Transfer to Wallet';
      } else if (typeAndDesc.toUpperCase().contains('TOP UP') || typeAndDesc.toUpperCase().contains('RELOAD')) {
        transactionType = 'Reload';
      }

      // Clean up description
      if (description.isNotEmpty) {
        // Extract merchant name or reference
        List<String> merchants = ['SPEEDMART', 'MEETMEE', 'CHIN HUI LING'];
        String upperDesc = description.toUpperCase();
        for (String merchant in merchants) {
          if (upperDesc.contains(merchant)) {
            description = merchant;
            break;
          }
        }
      }

      transactions.add({
        'date': date,
        'status': status,
        'type': transactionType,
        'amount': amount,
        'description': description,
      });

      print('Pattern extracted: $date, $status, $transactionType, RM$amount, $description');
    }

    // Calculate totals
    double totalAmount = 0.0;
    Map<String, int> transactionTypes = {};
    Map<String, int> statusCount = {};

    for (var transaction in transactions) {
      totalAmount += transaction['amount'];

      String type = transaction['type'];
      String status = transaction['status'];

      transactionTypes[type] = (transactionTypes[type] ?? 0) + 1;
      statusCount[status] = (statusCount[status] ?? 0) + 1;
    }

    return {
      'transactionPeriod': transactionPeriod ?? 'Not found',
      'totalTransactions': transactions.length,
      'totalAmount': totalAmount,
      'transactionTypes': transactionTypes,
      'statusCount': statusCount,
      'transactions': transactions,
      'averageAmount': transactions.isNotEmpty ? totalAmount / transactions.length : 0.0,
    };
  }

  // TNG Pattern matching fallback - simplified and focused
  Map<String, dynamic> _parseTNGPatterns(String text) {
    List<Map<String, dynamic>> transactions = [];

    print('=== TNG PATTERN MATCHING FALLBACK ===');

    // Split text by lines and look for transaction patterns
    List<String> lines = text.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();

    // Look for transaction period in the text
    String? transactionPeriod;
    for (String line in lines) {
      RegExp periodRegex = RegExp(r'(\d{1,2}\s+\w+\s+\d{4}\s*-\s*\d{1,2}\s+\w+\s+\d{4})');
      var match = periodRegex.firstMatch(line);
      if (match != null) {
        transactionPeriod = match.group(1);
        break;
      }
    }

    // Process each line looking for transactions
    for (int i = 0; i < lines.length; i++) {
      String line = lines[i];
      String fullTransaction = line;

      // Combine with next few lines if they don't start with a date
      for (int j = i + 1; j < math.min(i + 3, lines.length); j++) {
        if (!RegExp(r'^\d{1,2}/\d{1,2}/\d{4}').hasMatch(lines[j])) {
          fullTransaction += ' ' + lines[j];
        } else {
          break;
        }
      }

      // Check if this line/block contains a transaction
      RegExp transactionRegex = RegExp(
          r'(\d{1,2}/\d{1,2}/\d{4})\s+(Success|Failed|Pending)\s+(Payment|DuitNow QR TNGD|Receive from Wallet|Transfer to Wallet|Top Up|Reload)',
          caseSensitive: false
      );

      var match = transactionRegex.firstMatch(fullTransaction);
      if (match != null) {
        String date = match.group(1)!;
        String status = match.group(2)!;
        String type = match.group(3)!;

        // Extract amounts
        RegExp amountRegex = RegExp(r'RM(\d+\.\d{2})');
        var amountMatches = amountRegex.allMatches(fullTransaction);

        if (amountMatches.isNotEmpty) {
          double amount = double.parse(amountMatches.first.group(1)!);

          // Extract description (merchant names)
          String description = '';
          List<String> merchants = ['SPEEDMART', 'MEETMEE', 'CHIN HUI LING'];
          for (String merchant in merchants) {
            if (fullTransaction.toUpperCase().contains(merchant)) {
              description = merchant;
              break;
            }
          }

          transactions.add({
            'date': date,
            'status': status,
            'type': type == 'Top Up' ? 'Reload' : type, // Standardize Top Up to Reload
            'amount': amount,
            'description': description,
          });

          print('Pattern matched transaction: $date, $status, $type, RM$amount');
        }
      }
    }

    // Calculate summary
    double totalAmount = 0.0;
    Map<String, int> transactionTypes = {};
    Map<String, int> statusCount = {};

    for (var transaction in transactions) {
      totalAmount += transaction['amount'];

      String type = transaction['type'];
      String status = transaction['status'];

      transactionTypes[type] = (transactionTypes[type] ?? 0) + 1;
      statusCount[status] = (statusCount[status] ?? 0) + 1;
    }

    return {
      'transactionPeriod': transactionPeriod ?? 'Not found',
      'totalTransactions': transactions.length,
      'totalAmount': totalAmount,
      'transactionTypes': transactionTypes,
      'statusCount': statusCount,
      'transactions': transactions,
      'averageAmount': transactions.isNotEmpty ? totalAmount / transactions.length : 0.0,
    };
  }

  Future<void> _saveAnalysisResult(String fileId, Map<String, dynamic> analysisResult) async {
    await _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('uploaded_files')
        .doc(fileId)
        .update({
      'analysisResult': analysisResult,
      'analyzedAt': Timestamp.now(),
    });

    await _loadUploadedFiles();
  }

  // Enhanced error dialog with debug information
  void _showDetailedErrorDialog(String title, String message, Map<String, dynamic> debugData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              SizedBox(height: 16),

              // Show debug information if available
              if (debugData.containsKey('debugInfo')) ...[
                Text('Debug Information:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),

                if (debugData['debugInfo']['totalPages'] != null)
                  Text('• Total pages: ${debugData['debugInfo']['totalPages']}'),

                if (debugData['debugInfo']['totalTextLength'] != null)
                  Text('• Text extracted: ${debugData['debugInfo']['totalTextLength']} characters'),

                SizedBox(height: 16),
              ],

              Text('Troubleshooting Tips:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('• Make sure your file contains transaction data\n'
                  '• Check if the file has headers like Date, Status, Transaction Type, Amount\n'
                  '• Try uploading a different file format if available\n'
                  '• Contact support if the issue persists'),

              // Show raw text preview if available
              if (debugData.containsKey('rawText') && debugData['rawText'] != null) ...[
                SizedBox(height: 16),
                Text('File Preview:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Container(
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        debugData['rawText'],
                        style: TextStyle(fontFamily: 'monospace', fontSize: 12),
                      ),
                    ),
                  ),
                ),
              ],

              SizedBox(height: 16),
              Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info, color: Colors.blue, size: 16),
                        SizedBox(width: 8),
                        Text('TNG Wallet File Format', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue)),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text(
                      'For best results, ensure your TNG Wallet statement contains:\n'
                          '• Transaction table with Date, Status, Type, Amount columns\n'
                          '• Proper CSV or Excel formatting maintained',
                      style: TextStyle(fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _exportDebugInfo(debugData);
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFC700),
            ),
            child: Text('Export Debug Info'),
          ),
        ],
      ),
    );
  }

  void _exportDebugInfo(Map<String, dynamic> debugData) {
    print('=== EXPORTED DEBUG INFO ===');
    print(debugData.toString());
    _showSuccessSnackBar('Debug information logged to console');
  }

  void _showAnalysisResult(Map<String, dynamic> result) {
    if (result.containsKey('totalTransactions')) {
      _showTransactionAnalysisResult(result);
    } else if (result.containsKey('fileType')) {
      _showGeneralFileAnalysisResult(result);
    } else {
      _showGenericAnalysisResult(result);
    }
  }

  void _showTransactionAnalysisResult(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Transaction Analysis'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAnalysisRow('Transaction Period', result['transactionPeriod']),
                _buildAnalysisRow('Total Transactions', '${result['totalTransactions']}'),
                _buildAnalysisRow('Total Amount', 'RM${result['totalAmount'].toStringAsFixed(2)}'),
                _buildAnalysisRow('Average Amount', 'RM${result['averageAmount'].toStringAsFixed(2)}'),
                const SizedBox(height: 16),

                if ((result['transactionTypes'] as Map<String, dynamic>).isNotEmpty) ...[
                  const Text('Transaction Types:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...((result['transactionTypes'] as Map<String, dynamic>).entries
                      .map<Widget>((e) => Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text('• ${e.key}: ${e.value}'),
                  ))
                      .toList()),
                ] else ...[
                  const Text('Transaction Types: None identified',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],

                const SizedBox(height: 16),

                if ((result['statusCount'] as Map<String, dynamic>).isNotEmpty) ...[
                  const Text('Status Distribution:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...((result['statusCount'] as Map<String, dynamic>).entries
                      .map<Widget>((e) => Padding(
                    padding: const EdgeInsets.only(left: 16, bottom: 4),
                    child: Text('• ${e.key}: ${e.value}'),
                  ))
                      .toList()),
                ] else ...[
                  const Text('Status Distribution: None identified',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],

                if ((result['transactions'] as List).isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('Sample Transactions:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  ...(result['transactions'] as List).take(3).map<Widget>((transaction) =>
                      Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        color: Colors.grey[50],
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Date: ${transaction['date'] ?? 'Unknown'}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (transaction['type'] != null && transaction['type'].toString().isNotEmpty)
                                Text('Type: ${transaction['type']}'),
                              if (transaction['status'] != null && transaction['status'].toString().isNotEmpty)
                                Text('Status: ${transaction['status']}'),
                              Text('Amount: RM${transaction['amount']?.toStringAsFixed(2) ?? '0.00'}'),
                              if (transaction['balance'] != null && transaction['balance'] > 0)
                                Text('Balance: RM${transaction['balance'].toStringAsFixed(2)}'),
                              if (transaction['description'] != null && transaction['description'].toString().isNotEmpty)
                                Text('Description: ${transaction['description']}'),
                            ],
                          ),
                        ),
                      )
                  ).toList(),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFC700),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showGeneralFileAnalysisResult(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${result['fileType']} Analysis'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildAnalysisRow('File Type', result['fileType']),
                if (result['textLength'] != null)
                  _buildAnalysisRow('Text Length', '${result['textLength']} characters'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFC700),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showGenericAnalysisResult(Map<String, dynamic> result) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('File Analysis'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Analysis completed. See details below:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),

              ...result.entries.map((entry) {
                if (entry.value is Map || entry.value is List) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${entry.key}:', style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.all(8),
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_formatComplexValue(entry.value)),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                } else {
                  return _buildAnalysisRow(entry.key, entry.value?.toString() ?? 'N/A');
                }
              }).toList(),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFC700),
            ),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  String _formatComplexValue(dynamic value) {
    if (value is Map) {
      return value.entries
          .map((e) => '${e.key}: ${e.value.toString()}')
          .join('\n');
    } else if (value is List) {
      if (value.isEmpty) return '(empty)';
      return value.map((item) => '- $item').join('\n');
    }
    return value.toString();
  }

  Widget _buildAnalysisRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _deleteFile(Map<String, dynamic> fileData) async {
    try {
      if (fileData['localPath'] != null) {
        File localFile = File(fileData['localPath']);
        if (await localFile.exists()) {
          await localFile.delete();
        }
      }

      await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('uploaded_files')
          .doc(fileData['id'])
          .delete();

      await _loadUploadedFiles();

      if (mounted) {
        _showSuccessSnackBar('File "${fileData['name']}" deleted successfully!');
      }
    } catch (e) {
      print('Delete error: $e');
      if (mounted) {
        _showErrorSnackBar('Failed to delete file: ${e.toString()}');
      }
    }
  }

  void _showFileDetails(Map<String, dynamic> fileData) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(fileData['name']),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Size: ${_formatFileSize(fileData['size'])}'),
            Text('Type: ${fileData['type']?.toUpperCase() ?? 'Unknown'}'),
            Text('Uploaded: ${_formatDate(fileData['uploadedAt'])}'),
            if (fileData['analyzedAt'] != null)
              Text('Analyzed: ${_formatDate(fileData['analyzedAt'])}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          if (fileData['analysisResult'] != null)
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showAnalysisResult(fileData['analysisResult']);
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFFFC700),
              ),
              child: const Text('View Analysis'),
            ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _openFile(fileData);
            },
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFFFC700),
            ),
            child: const Text('Open File'),
          ),
        ],
      ),
    );
  }

  Future<void> _openFile(Map<String, dynamic> fileData) async {
    try {
      if (fileData['localPath'] != null) {
        File file = File(fileData['localPath']);
        if (await file.exists()) {
          await OpenFile.open(fileData['localPath']);
        } else {
          _showErrorSnackBar('File not found');
        }
      }
    } catch (e) {
      print('Error opening file: $e');
      _showErrorSnackBar('Error opening file: $e');
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String _formatDate(dynamic timestamp) {
    DateTime date;
    if (timestamp is Timestamp) {
      date = timestamp.toDate();
    } else if (timestamp is DateTime) {
      date = timestamp;
    } else {
      return 'Unknown';
    }
    return DateFormat('MMM dd, yyyy').format(date);
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showPdfErrorDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Expanded(child: Text('Unsupported File Format')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PDF files are no longer supported in this version of the application.'),
            SizedBox(height: 16),
            Text('Please upload one of the following file formats:',
                style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('• CSV files (.csv)'),
                  Text('• Excel files (.xlsx)'),
                ],
              ),
            ),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info, color: Colors.blue, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'If you have a PDF statement, please export it to CSV or Excel format before uploading.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK'),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F8F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Upload File',
          style: TextStyle(
            color: Colors.black,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          const SizedBox(height: 24),
          // Upload area with dotted border
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GestureDetector(
              onTap: _isUploading ? null : _pickAndUploadFile,
              child: DottedBorder(
                color: Colors.grey.shade400,
                strokeWidth: 2,
                dashPattern: const [8, 4],
                borderType: BorderType.RRect,
                radius: const Radius.circular(12),
                child: Container(
                  width: double.infinity,
                  height: 200,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isUploading)
                        const CircularProgressIndicator(
                          color: Color(0xFFFFC700),
                          strokeWidth: 3,
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(50),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.1),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.cloud_upload_outlined,
                            size: 48,
                            color: Colors.black87,
                          ),
                        ),
                      const SizedBox(height: 16),
                      Text(
                        _isUploading ? 'Uploading...' : 'Upload your file here',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade700,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (!_isUploading) ...[
                        const SizedBox(height: 8),
                        Text(
                          'Supported formats: CSV, XLSX',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'PDF files are not supported',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade400,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 48),

          // Recent uploaded files section
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Text(
                  'Recent Uploaded File',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                    decoration: TextDecoration.underline,
                    decorationThickness: 2,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // File list
          Expanded(
            child: _uploadedFiles.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 64,
                    color: Colors.grey.shade400,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No files uploaded yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: _uploadedFiles.length,
              itemBuilder: (context, index) {
                final file = _uploadedFiles[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC700).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        file['type'] == 'csv'
                            ? Icons.table_chart
                            : Icons.description,
                        color: const Color(0xFFFFC700),
                        size: 24,
                      ),
                    ),
                    title: Text(
                      file['name'],
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              _formatFileSize(file['size']),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              ' • ',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              _formatDate(file['uploadedAt']),
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (file['analysisResult'] != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.green.shade100,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text(
                                  'Analyzed',
                                  style: TextStyle(
                                    color: Colors.green,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    trailing: const Icon(
                      Icons.keyboard_arrow_right,
                      color: Colors.grey,
                      size: 24,
                    ),
                    onTap: () => _showFileOptions(file),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFileOptions(Map<String, dynamic> file) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              file['name'],
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Color(0xFFFFC700)),
              title: const Text('View Details'),
              onTap: () {
                Navigator.pop(context);
                _showFileDetails(file);
              },
            ),
            ListTile(
              leading: const Icon(Icons.open_in_new, color: Color(0xFFFFC700)),
              title: const Text('Open File'),
              onTap: () {
                Navigator.pop(context);
                _openFile(file);
              },
            ),
            ListTile(
              leading: Icon(
                _isAnalyzing ? Icons.hourglass_empty : Icons.analytics,
                color: _isAnalyzing ? Colors.grey : const Color(0xFFFFC700),
              ),
              title: Text(_isAnalyzing ? 'Analyzing...' : 'Analyze'),
              onTap: _isAnalyzing
                  ? null
                  : () {
                Navigator.pop(context);
                _analyzeFile(file);
              },
            ),
            if (file['analysisResult'] != null)
              ListTile(
                leading: const Icon(Icons.assessment, color: Color(0xFFFFC700)),
                title: const Text('View Analysis'),
                onTap: () {
                  Navigator.pop(context);
                  _showAnalysisResult(file['analysisResult']);
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Delete',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _showDeleteConfirmation(file);
              },
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirmation(Map<String, dynamic> file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Delete File'),
        content: Text('Are you sure you want to delete "${file['name']}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteFile(file);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}