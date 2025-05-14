import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert'; // Add for CSV parsing
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:open_file/open_file.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:dotted_border/dotted_border.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Add for direct Firestore access
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncpdf; // For PDF text extraction
import 'package:intl/intl.dart'; // For date parsing
import 'firebase_file_service.dart';
import 'dart:math' as math;

class UploadPage extends StatefulWidget {
  const UploadPage({Key? key}) : super(key: key);

  @override
  _UploadPageState createState() => _UploadPageState();
}

class _UploadPageState extends State<UploadPage> {
  List<FirebaseFileInfo> uploadedFiles = [];
  bool isLoading = true;
  bool isProcessing = false;
  final FirebaseFileService _fileService = FirebaseFileService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadFiles();
  }

  Future<void> _requestPermissions() async {
    // Request storage permissions
    await [Permission.storage].request();
  }

  Future<void> _loadFiles() async {
    setState(() {
      isLoading = true;
    });

    try {
      // Check if user is logged in
      if (FirebaseAuth.instance.currentUser == null) {
        // Navigate to login screen
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      // Get files from Firestore
      final files = await _fileService.getFiles();
      setState(() {
        uploadedFiles = files;
        isLoading = false;
      });
    } catch (e) {
      print('Error loading files: $e');
      setState(() {
        isLoading = false;
      });
    }
  }

  Future<void> _pickFile() async {
    try {
      // Allow multiple file types including images
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );

      if (result != null) {
        final path = result.files.single.path;
        final name = result.files.single.name;

        if (path != null && name != null) {
          // Show loading indicator
          setState(() {
            isLoading = true;
          });

          // Get file extension to handle different file types appropriately
          final fileExtension = name.contains('.')
              ? name.split('.').last.toLowerCase()
              : '';

          // Check if the file is a PDF and if it is password protected
          bool isPasswordProtected = false;
          if (fileExtension == 'pdf') {
            isPasswordProtected = await _showPasswordProtectionDialog(
              context,
              name,
            );
          }

          // Create a file to get size and other info
          final file = File(path);

          // Upload to Firebase - this should work for any file type
          final fileId = await _fileService.uploadFile(
            file,
            name,
            isPasswordProtected: isPasswordProtected,
          );

          // Process the file to extract transactions if it's a supported format
          List<TransactionRecord> extractedTransactions = [];
          if (fileExtension == 'pdf') {
            // Show processing indicator
            setState(() {
              isProcessing = true;
            });

            // Extract transactions from PDF
            extractedTransactions = await _extractTransactionsFromFile(file, fileExtension, isPasswordProtected);

            // Save transactions to Firestore
            if (extractedTransactions.isNotEmpty) {
              await _saveTransactionsToFirestore(extractedTransactions);

              // Show success message with transaction count
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${extractedTransactions.length} transactions extracted and saved')),
              );
            }

            setState(() {
              isProcessing = false;
            });
          }

          // Reload the files list
          await _loadFiles();

          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('File uploaded successfully')),
          );
        }
      }
    } catch (e) {
      print('Error picking file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error uploading file: $e')),
      );
      setState(() {
        isLoading = false;
        isProcessing = false;
      });
    }
  }

  // Method to extract transactions from various file types
  Future<List<TransactionRecord>> _extractTransactionsFromFile(
      File file,
      String fileExtension,
      bool isPasswordProtected
      ) async {
    List<TransactionRecord> transactions = [];

    try {
      if (fileExtension == 'pdf') {
        // Extract from PDF
        transactions = await _extractFromPDF(file, isPasswordProtected);
      } else if (fileExtension == 'csv') {
        // Extract from CSV
        transactions = await _extractFromCSV(file);
      } else if (fileExtension == 'xlsx' || fileExtension == 'xls') {
        // Extract from Excel - this would need additional implementation
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Excel parsing not implemented yet')),
        );
      }
    } catch (e) {
      print('Error extracting transactions: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error parsing transactions: $e')),
      );
    }

    return transactions;
  }

  // Method to extract transactions from PDF with improved detection
  Future<List<TransactionRecord>> _extractFromPDF(File file, bool isPasswordProtected) async {
    List<TransactionRecord> transactions = [];

    try {
      // Try to open the PDF using Syncfusion
      syncpdf.PdfDocument? document;
      String? password;
      String allText = '';

      try {
        // First try without password
        document = syncpdf.PdfDocument(
          inputBytes: await file.readAsBytes(),
        );

        // Extract text from each page
        syncpdf.PdfTextExtractor extractor = syncpdf.PdfTextExtractor(document);
        allText = extractor.extractText();

        print("Successfully extracted text from PDF: ${allText.length} characters");
      } catch (e) {
        print("Error extracting PDF without password: $e");
        // PDF might be password protected or encrypted
        if (document != null) {
          document.dispose();
          document = null;
        }

        if (isPasswordProtected) {
          // Show dialog to get password
          password = await _showPDFPasswordInputDialog();

          if (password != null) {
            try {
              // Try with password
              document = syncpdf.PdfDocument(
                inputBytes: await file.readAsBytes(),
                password: password,
              );

              // Extract text from each page
              syncpdf.PdfTextExtractor extractor = syncpdf.PdfTextExtractor(document);
              allText = extractor.extractText();
              print("Successfully extracted text from password-protected PDF");
            } catch (e) {
              print("Error extracting password-protected PDF: $e");
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Invalid password or corrupted PDF')),
              );
            }
          }
        } else {
          // Try to open as encrypted PDF
          try {
            document = syncpdf.PdfDocument(
              inputBytes: await file.readAsBytes(),
            );

            // Extract text from each page
            syncpdf.PdfTextExtractor extractor = syncpdf.PdfTextExtractor(document);
            allText = extractor.extractText();
            print("Successfully extracted text from encrypted PDF");
          } catch (e) {
            print("Failed to extract encrypted PDF: $e");
          }
        }
      }

      // Log the first 500 characters to help debugging
      if (allText.isNotEmpty) {
        // Fix 1: Import dart:math and use math.min
        print("PDF content preview: ${allText.substring(0, math.min(500, allText.length))}");

        // Parse transactions from the extracted text
        transactions = _parseTransactionsFromText(allText);
        print("Found ${transactions.length} transactions");

        // If no transactions found, try alternative parsing
        if (transactions.isEmpty) {
          transactions = _parseTransactionsAlternative(allText);
          print("Alternative parsing found ${transactions.length} transactions");
        }
      } else {
        print("No text extracted from PDF");
      }

      // Dispose document
      if (document != null) {
        document.dispose();
      }
    } catch (e) {
      print('Error in PDF extraction process: $e');
    }

    return transactions;
  }

// Alternative parsing for transactions with more flexible patterns
  List<TransactionRecord> _parseTransactionsAlternative(String text) {
    List<TransactionRecord> transactions = [];

    try {
      // More relaxed patterns for various date formats
      RegExp datePattern = RegExp(r'\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\d{4}[/-]\d{1,2}[/-]\d{1,2}');

      // Various amount patterns (RM, $, numbers followed by decimal)
      RegExp amountPattern = RegExp(r'(?:RM|MYR|USD|\$)?\s*\d+(?:[,.]\d+)?');

      // Common transaction types
      List<String> transactionTypes = [
        'transfer', 'payment', 'deposit', 'withdrawal', 'reload',
        'duitnow', 'qr', 'purchase', 'income', 'expense', 'salary'
      ];

      // Split text into lines and clean
      List<String> lines = text.split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();

      // Process each line
      for (var line in lines) {
        // Skip very short lines
        if (line.length < 5) continue;

        // Convert to lowercase for easier pattern matching
        String lowerLine = line.toLowerCase();

        // Look for date pattern
        Match? dateMatch = datePattern.firstMatch(line);
        if (dateMatch == null) continue;

        try {
          String dateStr = dateMatch.group(0) ?? '';
          DateTime date = _parseDate(dateStr);

          // Look for amount pattern
          Match? amountMatch = amountPattern.firstMatch(line);
          if (amountMatch == null) continue;

          String amountStr = amountMatch.group(0) ?? '';
          // Clean the amount string
          amountStr = amountStr.replaceAll(RegExp(r'[^\d.]'), '');
          double amount = double.tryParse(amountStr) ?? 0.0;

          if (amount <= 0) continue; // Skip zero or negative amounts

          // Determine transaction type
          String type = 'Unknown';
          for (var typeStr in transactionTypes) {
            if (lowerLine.contains(typeStr)) {
              type = typeStr.substring(0, 1).toUpperCase() + typeStr.substring(1);
              break;
            }
          }

          // Determine status
          String status = 'Completed';
          if (lowerLine.contains('pending') || lowerLine.contains('process')) {
            status = 'Pending';
          } else if (lowerLine.contains('fail') || lowerLine.contains('reject')) {
            status = 'Failed';
          } else if (lowerLine.contains('cancel')) {
            status = 'Canceled';
          } else if (lowerLine.contains('success')) {
            status = 'Completed';
          }

          // Create and add transaction record
          transactions.add(TransactionRecord(
              date: date,
              status: status,
              type: type,
              amount: amount
          ));
        } catch (e) {
          print('Error parsing transaction line: $e');
        }
      }
    } catch (e) {
      print('Error in alternative transaction parsing: $e');
    }

    return transactions;
  }


  // Extract transactions from CSV
  Future<List<TransactionRecord>> _extractFromCSV(File file) async {
    List<TransactionRecord> transactions = [];

    try {
      String content = await file.readAsString();
      List<String> lines = LineSplitter().convert(content);

      if (lines.isNotEmpty) {
        // Skip header row
        List<String> headers = lines.first.split(',');

        // Find indices for required fields (date, status, type, amount)
        int dateIndex = headers.indexWhere((h) => h.toLowerCase().contains('date'));
        int statusIndex = headers.indexWhere((h) => h.toLowerCase().contains('status'));
        int typeIndex = headers.indexWhere((h) => h.toLowerCase().contains('type'));
        int amountIndex = headers.indexWhere((h) => h.toLowerCase().contains('amount'));

        if (dateIndex >= 0 && typeIndex >= 0 && amountIndex >= 0) {
          // Process data rows
          for (int i = 1; i < lines.length; i++) {
            List<String> values = lines[i].split(',');
            int maxIndex = [dateIndex, statusIndex, typeIndex, amountIndex].reduce(
                    (a, b) => a > b ? a : b
            );

            if (values.length > maxIndex) {
              try {
                DateTime date = _parseDate(values[dateIndex]);
                String status = statusIndex >= 0 ? values[statusIndex] : 'Completed';
                String type = values[typeIndex];
                String amountStr = values[amountIndex].replaceAll(RegExp(r'[^\d\.-]'), '');
                double amount = double.tryParse(amountStr) ?? 0;

                transactions.add(TransactionRecord(
                  date: date,
                  status: status,
                  type: type,
                  amount: amount,
                ));
              } catch (e) {
                print('Error parsing row $i: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      print('Error extracting CSV: $e');
    }

    return transactions;
  }

  // Parse transactions from text using pattern matching
  List<TransactionRecord> _parseTransactionsFromText(String text) {
    List<TransactionRecord> transactions = [];

    // Define patterns for transaction data
    RegExp datePattern = RegExp(r'\d{1,2}/\d{1,2}/\d{2,4}|\d{1,2}-\d{1,2}-\d{2,4}');
    RegExp amountPattern = RegExp(r'RM\d+\.\d{2}');

    // Split text into lines
    List<String> lines = text.split('\n');

    // Look for table headers
    int headerIndex = -1;
    for (int i = 0; i < lines.length; i++) {
      if (lines[i].contains('Date') &&
          lines[i].contains('Status') &&
          lines[i].contains('Transaction Type') &&
          lines[i].contains('Amount')) {
        headerIndex = i;
        break;
      }
    }

    // Process transaction rows if header found
    if (headerIndex >= 0) {
      for (int i = headerIndex + 1; i < lines.length; i++) {
        String line = lines[i];

        // Skip if line is too short
        if (line.trim().length < 10) continue;

        try {
          // Extract date
          Match? dateMatch = datePattern.firstMatch(line);
          if (dateMatch == null) continue;

          String dateStr = dateMatch.group(0) ?? '';
          DateTime date = _parseDate(dateStr);

          // Extract amount - looking for RM pattern
          Match? amountMatch = amountPattern.firstMatch(line);
          if (amountMatch == null) continue;

          String amountStr = amountMatch.group(0) ?? '';
          double amount = double.tryParse(amountStr.replaceAll('RM', '')) ?? 0;

          // Extract transaction type and status
          // This is more complex and depends on the exact PDF format
          String type = 'Unknown';
          String status = 'Unknown';

          // Try to extract from common patterns
          if (line.contains('Transfer')) {
            type = 'Transfer';
          } else if (line.contains('Payment')) {
            type = 'Payment';
          } else if (line.contains('Reload')) {
            type = 'Reload';
          } else if (line.contains('QR')) {
            type = 'QR Payment';
          }

          if (line.contains('Success')) {
            status = 'Completed';
          } else if (line.contains('Fail')) {
            status = 'Failed';
          } else if (line.contains('Pending')) {
            status = 'Pending';
          }

          transactions.add(TransactionRecord(
            date: date,
            status: status,
            type: type,
            amount: amount,
          ));
        } catch (e) {
          print('Error parsing line: $e');
        }
      }
    } else {
      // Try a more generic approach for unstructured text
      bool inTransactionSection = false;

      for (String line in lines) {
        if (line.trim().isEmpty) continue;

        // Check if line contains date and amount
        if (datePattern.hasMatch(line) && amountPattern.hasMatch(line)) {
          try {
            Match? dateMatch = datePattern.firstMatch(line);
            String dateStr = dateMatch?.group(0) ?? '';
            DateTime date = _parseDate(dateStr);

            Match? amountMatch = amountPattern.firstMatch(line);
            String amountStr = amountMatch?.group(0) ?? '';
            double amount = double.tryParse(amountStr.replaceAll('RM', '')) ?? 0;

            String type;
            if (line.toLowerCase().contains('transfer')) {
              type = 'Transfer';
            } else if (line.toLowerCase().contains('payment')) {
              type = 'Payment';
            } else if (line.toLowerCase().contains('reload')) {
              type = 'Reload';
            } else if (line.toLowerCase().contains('qr')) {
              type = 'QR Payment';
            } else {
              type = 'Transaction';
            }

            String status;
            if (line.toLowerCase().contains('success')) {
              status = 'Completed';
            } else if (line.toLowerCase().contains('fail')) {
              status = 'Failed';
            } else if (line.toLowerCase().contains('pending')) {
              status = 'Pending';
            } else {
              status = 'Completed'; // Default
            }

            transactions.add(TransactionRecord(
              date: date,
              status: status,
              type: type,
              amount: amount,
            ));
          } catch (e) {
            print('Error parsing line: $e');
          }
        }
      }
    }

    return transactions;
  }

  // Enhanced date parsing function
  DateTime _parseDate(String dateStr) {
    // Clean the date string
    dateStr = dateStr.trim();

    // Try different date formats
    List<String> formats = [
      'dd/MM/yyyy',
      'MM/dd/yyyy',
      'yyyy/MM/dd',
      'dd-MM-yyyy',
      'MM-dd-yyyy',
      'yyyy-MM-dd',
      'd/M/yyyy',
      'M/d/yyyy',
      'yyyy/M/d',
      'd-M-yyyy',
      'M-d-yyyy',
      'yyyy-M-d',
    ];

    // Try parsing with each format
    for (String format in formats) {
      try {
        return DateFormat(format).parse(dateStr);
      } catch (e) {
        // Try next format
      }
    }

    // Try to extract date components manually
    try {
      List<String> parts = dateStr.split(RegExp(r'[/\-]'));
      if (parts.length == 3) {
        int? year, month, day;

        // Try to determine which component is the year
        if (parts[0].length == 4 || (int.tryParse(parts[0]) ?? 0) > 31) {
          // Format is likely yyyy-MM-dd
          year = int.tryParse(parts[0]);
          month = int.tryParse(parts[1]);
          day = int.tryParse(parts[2]);
        } else if (parts[2].length == 4 || (int.tryParse(parts[2]) ?? 0) > 31) {
          // Format is likely dd-MM-yyyy
          day = int.tryParse(parts[0]);
          month = int.tryParse(parts[1]);
          year = int.tryParse(parts[2]);
        } else {
          // Try to make a best guess based on typical ranges
          List<int?> numParts = parts.map((p) => int.tryParse(p)).toList();

          // If one part is > 31, it's likely the year (2-digit year)
          if (numParts[0] != null && numParts[0]! > 31) {
            year = numParts[0]! < 100 ? 2000 + numParts[0]! : numParts[0];
            month = numParts[1];
            day = numParts[2];
          } else if (numParts[2] != null && numParts[2]! > 31) {
            year = numParts[2]! < 100 ? 2000 + numParts[2]! : numParts[2];
            day = numParts[0];
            month = numParts[1];
          } else {
            // Best guess at MM/dd/yy or dd/MM/yy
            // Prefer dd/MM/yyyy for Malaysian format
            day = numParts[0];
            month = numParts[1];
            year = numParts[2] != null && numParts[2]! < 100 ? 2000 + numParts[2]! : numParts[2];
          }
        }

        // Create date if all parts are valid
        if (year != null && month != null && day != null) {
          if (year < 100) year += 2000; // Assume 2-digit years are 20xx
          if (month > 0 && month <= 12 && day > 0 && day <= 31) {
            return DateTime(year, month, day);
          }
        }
      }
    } catch (e) {
      print('Manual date parsing failed: $e');
    }

    // Default to current date if parsing fails
    print('Could not parse date: $dateStr, using current date');
    return DateTime.now();
  }

  // Save transactions to Firestore
  Future<void> _saveTransactionsToFirestore(List<TransactionRecord> transactions) async {
    try {
      final User? currentUser = FirebaseAuth.instance.currentUser;

      if (currentUser != null && transactions.isNotEmpty) {
        // Add each transaction to Firestore
        for (var transaction in transactions) {
          await _firestore
              .collection('users')
              .doc(currentUser.uid)
              .collection('transactions')
              .add(transaction.toMap());
        }

        // Also save metadata about this batch
        await _firestore
            .collection('users')
            .doc(currentUser.uid)
            .collection('transaction_uploads')
            .add({
          'timestamp': Timestamp.now(),
          'count': transactions.length,
          'source': 'file_upload',
        });
      }
    } catch (e) {
      print('Error saving transactions: $e');
      throw e;
    }
  }

  // Show dialog to get PDF password (for protected PDFs)
  Future<String?> _showPDFPasswordInputDialog() async {
    String? password;

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('PDF Password'),
          content: TextField(
            obscureText: true,
            decoration: const InputDecoration(
              hintText: 'Enter PDF password',
              border: OutlineInputBorder(),
            ),
            onChanged: (value) {
              password = value;
            },
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                password = null;
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );

    return password;
  }

  // Method to show a dialog asking if the PDF is password protected
  Future<bool> _showPasswordProtectionDialog(
      BuildContext context,
      String fileName,
      ) async {
    bool isPasswordProtected = false;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF Protection'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [Text('Is "$fileName" password protected?')],
        ),
        actions: [
          TextButton(
            onPressed: () {
              isPasswordProtected = false;
              Navigator.of(context).pop();
            },
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () {
              isPasswordProtected = true;
              Navigator.of(context).pop();
            },
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    return isPasswordProtected;
  }

  void _showFileDetails(FirebaseFileInfo fileInfo) async {
    // Show loading indicator
    setState(() {
      isLoading = true;
    });

    try {
      // Download the file
      final fileBytes = await _fileService.downloadFile(fileInfo.id);

      // Save to temporary file for viewing
      final tempPath = await _fileService.saveFileToDisk(fileBytes, fileInfo.name);

      setState(() {
        isLoading = false;
      });

      // Navigate to file details page
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => FirebaseFileDetailPage(
            fileInfo: fileInfo,
            filePath: tempPath,
            onDelete: _deleteFile,
            onAnalyze: _analyzeExistingFile,
          ),
        ),
      );
    } catch (e) {
      print('Error downloading file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening file: $e')),
      );
      setState(() {
        isLoading = false;
      });
    }
  }

  // Method to analyze an existing file
  Future<void> _analyzeExistingFile(FirebaseFileInfo fileInfo, String filePath) async {
    setState(() {
      isProcessing = true;
    });

    try {
      // Get file extension
      final fileExtension = fileInfo.fileExtension.toLowerCase();

      // Extract transactions from the file
      final file = File(filePath);
      final transactions = await _extractTransactionsFromFile(
          file,
          fileExtension,
          fileInfo.isPasswordProtected
      );

      if (transactions.isNotEmpty) {
        await _saveTransactionsToFirestore(transactions);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${transactions.length} transactions extracted and saved')),
        );

        // Navigate to report page to see the transactions
        Navigator.of(context).pushNamed('/report');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No transactions found in the file')),
        );
      }
    } catch (e) {
      print('Error analyzing file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error analyzing file: $e')),
      );
    } finally {
      setState(() {
        isProcessing = false;
      });
    }
  }

  void _deleteFile(FirebaseFileInfo fileInfo) async {
    try {
      await _fileService.deleteFile(fileInfo.id);
      await _loadFiles();
    } catch (e) {
      print('Error deleting file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error deleting file: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.grey[100],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            // Handle back navigation
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'Upload File',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        actions: [
          // Navigate to report page
          IconButton(
            icon: const Icon(Icons.bar_chart, color: Colors.black),
            onPressed: () {
              Navigator.of(context).pushNamed('/report');
            },
            tooltip: 'View Financial Report',
          ),
          // Sign out button
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.black),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 24.0),
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Upload Area
            GestureDetector(
              onTap: _pickFile,
              child: DottedBorder(
                borderType: BorderType.RRect,
                radius: const Radius.circular(8),
                color: Colors.black,
                strokeWidth: 1,
                dashPattern: const [5, 5],
                child: Container(
                  width: double.infinity,
                  height: 180,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.cloud_upload_outlined,
                          size: 50,
                          color: Colors.black,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          isProcessing
                              ? 'Processing transactions...'
                              : 'Upload transaction file',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.black,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Supported formats: PDF, CSV, Excel',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (isProcessing)
                          Padding(
                            padding: const EdgeInsets.only(top: 12.0),
                            child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.amber),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 40),

            // Always show the "Recent Uploaded File" section
            Container(
              alignment: Alignment.centerRight,
              child: Column(
                children: [
                  const Text(
                    'Recent Uploaded Files',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  Container(
                    height: 1,
                    width: 180,
                    color: Colors.black,
                    margin: const EdgeInsets.only(top: 2),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // List of uploaded files (if any)
            if (uploadedFiles.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: uploadedFiles.length,
                  itemBuilder: (context, index) {
                    final fileInfo = uploadedFiles[index];
                    // Determine file type icon based on extension
                    final fileExtension = fileInfo.fileExtension.toLowerCase();
                    final isImage = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'].contains(fileExtension);
                    final isPdf = fileExtension == 'pdf';
                    final isDoc = ['doc', 'docx', 'txt', 'rtf'].contains(fileExtension);
                    final isSpreadsheet = ['xls', 'xlsx', 'csv'].contains(fileExtension);

                    IconData fileIcon;
                    Color iconColor;

                    if (isImage) {
                      fileIcon = Icons.image;
                      iconColor = Colors.blue;
                    } else if (isPdf) {
                      fileIcon = Icons.picture_as_pdf;
                      iconColor = Colors.red;
                    } else if (isDoc) {
                      fileIcon = Icons.description;
                      iconColor = Colors.indigo;
                    } else if (isSpreadsheet) {
                      fileIcon = Icons.table_chart;
                      iconColor = Colors.green;
                    } else {
                      fileIcon = Icons.insert_drive_file;
                      iconColor = Colors.grey;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListTile(
                        leading: Icon(
                          fileIcon,
                          color: iconColor,
                        ),
                        title: Text(fileInfo.name),
                        subtitle: Text(
                          fileInfo.formattedSize,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (fileInfo.isPasswordProtected)
                              const Icon(
                                Icons.lock,
                                size: 16,
                                color: Colors.orange,
                              ),
                            const SizedBox(width: 8),
                            const Icon(Icons.arrow_forward_ios, size: 16),
                          ],
                        ),
                        onTap: () {
                          // Show file details when tapped
                          _showFileDetails(fileInfo);
                        },
                      ),
                    );
                  },
                ),
              ),

            if (uploadedFiles.isEmpty)
              const Expanded(
                child: Center(
                  child: Text(
                    "No files uploaded yet",
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// File Details Page for Firebase files
class FirebaseFileDetailPage extends StatefulWidget {
  final FirebaseFileInfo fileInfo;
  final String filePath;
  final Function(FirebaseFileInfo) onDelete;
  final Function(FirebaseFileInfo, String) onAnalyze;

  const FirebaseFileDetailPage({
    Key? key,
    required this.fileInfo,
    required this.filePath,
    required this.onDelete,
    required this.onAnalyze,
  }) : super(key: key);

  @override
  _FirebaseFileDetailPageState createState() => _FirebaseFileDetailPageState();
}

class _FirebaseFileDetailPageState extends State<FirebaseFileDetailPage> {
  bool isLoading = false;
  bool isAnalyzing = false;
  Uint8List? filePreview;
  String? pdfPassword; // Store PDF password if provided

  @override
  void initState() {
    super.initState();
    _loadFilePreview();
  }

  Future<void> _loadFilePreview() async {
    // List of common image file extensions
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];

    if (imageExtensions.contains(widget.fileInfo.fileExtension.toLowerCase())) {
      setState(() {
        isLoading = true;
      });

      try {
        // Load the file as bytes for preview
        final file = File(widget.filePath);
        final bytes = await file.readAsBytes();

        setState(() {
          filePreview = bytes;
          isLoading = false;
        });
      } catch (e) {
        print('Error loading preview: $e');
        setState(() {
          isLoading = false;
        });
      }
    }
  }

  Future<void> _openFile() async {
    try {
      final extension = widget.fileInfo.fileExtension.toLowerCase();
      final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];

      if (imageExtensions.contains(extension) && filePreview != null) {
        // Image viewer is built into the UI
        showDialog(
          context: context,
          builder: (context) => Dialog(
            child: Container(
              constraints: const BoxConstraints(
                maxWidth: double.infinity,
                maxHeight: 500,
              ),
              child: Image.memory(filePreview!, fit: BoxFit.contain),
            ),
          ),
        );
      } else if (extension == 'pdf') {
        // For PDF files with password protection
        if (widget.fileInfo.isPasswordProtected) {
          if (pdfPassword == null) {
            // If password isn't set, prompt for it
            _showPdfPasswordDialog(context);
            return;
          }

          // If we have a password, use it to open the PDF directly
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PDFViewPage(
                filePath: widget.filePath,
                password: pdfPassword,
              ),
            ),
          );
        } else {
          // For non-password protected PDFs
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => PDFViewPage(
                filePath: widget.filePath,
              ),
            ),
          );
        }
      } else {
        // For other file types, use OpenFile
        final result = await OpenFile.open(widget.filePath);
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: ${result.message}')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // Method to show PDF password dialog
  void _showPdfPasswordDialog(BuildContext context) {
    final TextEditingController passwordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PDF Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This PDF is password-protected. Please enter the password:',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: passwordController,
              decoration: const InputDecoration(
                labelText: 'PDF Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                pdfPassword = passwordController.text;
              });
              Navigator.of(context).pop();

              // Try opening with the provided password
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PDFViewPage(
                    filePath: widget.filePath,
                    password: pdfPassword,
                  ),
                ),
              );
            },
            child: const Text('Open PDF'),
          ),
        ],
      ),
    );
  }

  // Method to analyze the file for transactions with debugging
  Future<void> _analyzeFile() async {
    setState(() {
      isAnalyzing = true;
    });

    try {
      // Get file extension
      final fileExtension = widget.fileInfo.fileExtension.toLowerCase();
      final isPdf = fileExtension == 'pdf';

      // Show progress message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Analyzing file...')),
      );

      // Add debugging message to console
      print('Starting analysis of ${widget.fileInfo.name}');
      print('File type: $fileExtension, Password protected: ${widget.fileInfo.isPasswordProtected}');

      // Extract transactions from the file
      final file = File(widget.filePath);
      final transactions = await widget.onAnalyze(widget.fileInfo, widget.filePath);

      // Check if transactions were found
      if (transactions != null && transactions.isNotEmpty) {
        // Navigate to report page to see the transactions
        Navigator.of(context).pushNamed('/report', arguments: 'just_uploaded');
      } else {
        // If no transactions found, provide a more detailed error message
        if (isPdf) {
          // For PDFs, offer potential solutions
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('No Transactions Found'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('Could not find any transactions in this PDF file.'),
                  SizedBox(height: 16),
                  Text('Possible reasons:'),
                  SizedBox(height: 8),
                  Text('• The PDF may be scanned images rather than text'),
                  Text('• The transaction format is not recognized'),
                  Text('• The PDF may be encrypted or protected'),
                  SizedBox(height: 16),
                  Text('Would you like to try again with different settings?'),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    // You could add alternative extraction options here
                  },
                  child: const Text('Try Different Method'),
                ),
              ],
            ),
          );
        } else {
          // For other file types
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No transactions found in the file. Try another file format.'),
              duration: Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      print('Error analyzing file: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error analyzing file: $e'),
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      setState(() {
        isAnalyzing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.grey[100],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
        title: const Text(
          'File Details',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFilePreview(),
            const SizedBox(height: 24),
            _buildDetailItem(context, 'File Name', widget.fileInfo.name),
            _buildDetailItem(
              context,
              'File Type',
              widget.fileInfo.fileExtension.toUpperCase(),
            ),
            _buildDetailItem(
              context,
              'File Size',
              widget.fileInfo.formattedSize,
            ),
            _buildDetailItem(
              context,
              'Date Added',
              widget.fileInfo.formattedDate,
            ),
            _buildDetailItem(
              context,
              'Encrypted',
              widget.fileInfo.isEncrypted ? 'Yes' : 'No',
            ),
            _buildDetailItem(
              context,
              'Password Protected',
              widget.fileInfo.isPasswordProtected ? 'Yes' : 'No',
            ),
            _buildDetailItem(
              context,
              'Cloud Storage',
              'Yes (Firebase)',
            ),
            if (pdfPassword != null && widget.fileInfo.isPasswordProtected)
              _buildDetailItem(context, 'PDF Password', '••••••••'),
            const SizedBox(height: 32),
            _buildActionButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildFilePreview() {
    final imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];

    if (filePreview != null &&
        imageExtensions.contains(widget.fileInfo.fileExtension.toLowerCase())) {
      // If we have image preview data, show it
      return Container(
        height: 200,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Colors.grey[200],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.memory(filePreview!, fit: BoxFit.contain),
        ),
      );
    }

    // Otherwise show the file icon
    IconData iconData;
    Color iconColor;

    final extension = widget.fileInfo.fileExtension.toLowerCase();

    if (imageExtensions.contains(extension)) {
      iconData = Icons.image;
      iconColor = Colors.blue;
    } else if (['pdf'].contains(extension)) {
      iconData = Icons.picture_as_pdf;
      iconColor = Colors.red;
    } else if (['doc', 'docx', 'txt', 'rtf'].contains(extension)) {
      iconData = Icons.description;
      iconColor = Colors.indigo;
    } else if (['xls', 'xlsx', 'csv'].contains(extension)) {
      iconData = Icons.table_chart;
      iconColor = Colors.green;
    } else {
      iconData = Icons.insert_drive_file;
      iconColor = Colors.grey;
    }

    return Center(
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Icon(iconData, size: 80, color: iconColor),
              if (isLoading) const CircularProgressIndicator(),
              if (widget.fileInfo.isEncrypted ||
                  widget.fileInfo.isPasswordProtected)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(
                      color: Colors.black,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.lock,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            widget.fileInfo.name,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(BuildContext context, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final isPdf = widget.fileInfo.fileExtension.toLowerCase() == 'pdf';
    final isCsv = widget.fileInfo.fileExtension.toLowerCase() == 'csv';
    final isExcel = ['xls', 'xlsx'].contains(widget.fileInfo.fileExtension.toLowerCase());
    final canAnalyze = isPdf || isCsv || isExcel;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: const Icon(Icons.open_in_new),
                label: const Text('Open File'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: isLoading ? null : _openFile,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: () {
                  // Show delete confirmation dialog
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Delete File'),
                      content: Text(
                        'Are you sure you want to delete ${widget.fileInfo.name}? This will remove it from Firebase.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Cancel'),
                        ),
                        TextButton(
                          onPressed: () {
                            widget.onDelete(widget.fileInfo);
                            Navigator.of(context).pop();
                            Navigator.of(context).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('File deleted Successfully')),
                            );
                          },
                          child: const Text(
                            'Delete',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),

        // Add analyze button if file can be analyzed
        if (canAnalyze)
          Padding(
            padding: const EdgeInsets.only(top: 12.0),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: isAnalyzing
                    ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
                    : const Icon(Icons.bar_chart),
                label: Text(isAnalyzing ? 'Analyzing...' : 'Analyze Transactions'),
                style: ElevatedButton.styleFrom(
                  foregroundColor: Colors.white,
                  backgroundColor: Colors.amber,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                onPressed: isAnalyzing ? null : _analyzeFile,
              ),
            ),
          ),
      ],
    );
  }
}

// PDF View Page
class PDFViewPage extends StatelessWidget {
  final String filePath;
  final String? password;

  const PDFViewPage({Key? key, required this.filePath, this.password})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Viewer'),
        backgroundColor: Colors.grey[100],
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: PDFView(
        filePath: filePath,
        password: password, // Pass the password to the PDFView
        enableSwipe: true,
        swipeHorizontal: true,
        autoSpacing: false,
        pageFling: false,
        pageSnap: true,
        defaultPage: 0,
        fitPolicy: FitPolicy.BOTH,
        preventLinkNavigation: false,
        onRender: (_pages) {
          // PDF rendered
        },
        onError: (error) {
          // Handle errors - especially password errors
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $error'),
              duration: const Duration(seconds: 5),
            ),
          );
          // Go back if there's an error (likely wrong password)
          Navigator.of(context).pop();
        },
        onPageError: (page, error) {
          // Handle page errors
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error on page $page: $error')),
          );
        },
        onPageChanged: (int? page, int? total) {
          // Page changed
        },
        onViewCreated: (PDFViewController pdfViewController) {
          // PDF view created
        },
      ),
    );
  }
}

// Transaction Record model (same as in report_page.dart)
class TransactionRecord {
  final DateTime date;
  final String status;
  final String type;
  final double amount;

  TransactionRecord({
    required this.date,
    required this.status,
    required this.type,
    required this.amount,
  });

  // Convert to map for Firestore
  Map<String, dynamic> toMap() {
    return {
      'date': Timestamp.fromDate(date),
      'status': status,
      'type': type,
      'amount': amount,
    };
  }
}