import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'package:syncfusion_flutter_datepicker/datepicker.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as syncpdf;

class ReportPage extends StatefulWidget {
  const ReportPage({Key? key}) : super(key: key);

  @override
  _ReportPageState createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  // Current user
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Firebase instances
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Transaction data
  List<TransactionRecord> _transactions = [];
  List<TransactionRecord> _filteredTransactions = [];

  // Date filters
  DateTime _selectedStartDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _selectedEndDate = DateTime.now();
  String _selectedPeriod = 'Month'; // 'Year', 'Month', 'Day'

  // Loading states
  bool _isLoading = true;
  bool _isUploading = false;

  // Chart data
  List<ChartData> _incomeData = [];
  List<ChartData> _expenseData = [];

  // Summary statistics
  double _totalIncome = 0;
  double _totalExpense = 0;
  double _netAmount = 0;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  // Load transactions from Firestore
  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
    });

    try {
      if (_currentUser != null) {
        final QuerySnapshot snapshot = await _firestore
            .collection('users')
            .doc(_currentUser!.uid)
            .collection('transactions')
            .orderBy('date', descending: true)
            .get();

        _transactions = snapshot.docs
            .map((doc) => TransactionRecord.fromFirestore(doc))
            .toList();

        _applyDateFilter();

        // Show toast if transactions were just uploaded
        if (_transactions.isNotEmpty && ModalRoute.of(context)?.settings.arguments == 'just_uploaded') {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${_transactions.length} transactions loaded successfully')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading transactions: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Apply date filters to transactions
  void _applyDateFilter() {
    setState(() {
      _filteredTransactions = _transactions.where((transaction) {
        return transaction.date.isAfter(_selectedStartDate) &&
            transaction.date.isBefore(_selectedEndDate.add(const Duration(days: 1)));
      }).toList();

      _calculateSummary();
      _generateChartData();
    });
  }

  // Calculate summary statistics
  void _calculateSummary() {
    _totalIncome = 0;
    _totalExpense = 0;

    for (var transaction in _filteredTransactions) {
      if (transaction.type.toLowerCase().contains('income') ||
          transaction.type.toLowerCase().contains('deposit') ||
          transaction.type.toLowerCase().contains('transfer') ||
          transaction.type.toLowerCase().contains('reload')) {
        _totalIncome += transaction.amount;
      } else {
        _totalExpense += transaction.amount;
      }
    }

    _netAmount = _totalIncome - _totalExpense;
  }

  // Generate data for charts
  void _generateChartData() {
    // Clear previous data
    _incomeData = [];
    _expenseData = [];

    // Group by date according to selected period
    Map<String, double> incomeMap = {};
    Map<String, double> expenseMap = {};

    for (var transaction in _filteredTransactions) {
      String key;
      if (_selectedPeriod == 'Year') {
        key = DateFormat('yyyy').format(transaction.date);
      } else if (_selectedPeriod == 'Month') {
        key = DateFormat('MMM yyyy').format(transaction.date);
      } else {
        key = DateFormat('dd MMM').format(transaction.date);
      }

      if (transaction.type.toLowerCase().contains('income') ||
          transaction.type.toLowerCase().contains('deposit') ||
          transaction.type.toLowerCase().contains('transfer') ||
          transaction.type.toLowerCase().contains('reload')) {
        incomeMap[key] = (incomeMap[key] ?? 0) + transaction.amount;
      } else {
        expenseMap[key] = (expenseMap[key] ?? 0) + transaction.amount;
      }
    }

    // Sort keys by date
    List<String> sortedKeys = [...{...incomeMap.keys, ...expenseMap.keys}].toList();
    if (_selectedPeriod == 'Year') {
      sortedKeys.sort();
    } else if (_selectedPeriod == 'Month') {
      sortedKeys.sort((a, b) {
        try {
          DateTime dateA = DateFormat('MMM yyyy').parse(a);
          DateTime dateB = DateFormat('MMM yyyy').parse(b);
          return dateA.compareTo(dateB);
        } catch (e) {
          return a.compareTo(b);
        }
      });
    } else {
      sortedKeys.sort((a, b) {
        try {
          DateTime dateA = DateFormat('dd MMM').parse(a);
          DateTime dateB = DateFormat('dd MMM').parse(b);
          return dateA.compareTo(dateB);
        } catch (e) {
          return a.compareTo(b);
        }
      });
    }

    // Create chart data points
    for (var key in sortedKeys) {
      if (incomeMap.containsKey(key)) {
        _incomeData.add(ChartData(key, incomeMap[key]!));
      } else {
        _incomeData.add(ChartData(key, 0));
      }

      if (expenseMap.containsKey(key)) {
        _expenseData.add(ChartData(key, expenseMap[key]!));
      } else {
        _expenseData.add(ChartData(key, 0));
      }
    }
  }

  // Process transaction file without using Firebase Storage
  Future<void> _uploadFile() async {
    setState(() {
      _isUploading = true;
    });

    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'csv', 'xlsx', 'xls'],
      );

      if (result != null) {
        File file = File(result.files.single.path!);
        String fileName = result.files.single.name;
        String fileExtension = fileName.split('.').last.toLowerCase();

        // Extract transaction data based on file type
        List<TransactionRecord> extractedRecords = [];

        if (fileExtension == 'pdf') {
          extractedRecords = await _extractFromPDF(file);
        } else if (fileExtension == 'csv') {
          extractedRecords = await _extractFromCSV(file);
        } else if (fileExtension == 'xlsx' || fileExtension == 'xls') {
          extractedRecords = await _extractFromExcel(file);
        }

        // Save extracted records to Firestore
        if (extractedRecords.isNotEmpty) {
          for (var record in extractedRecords) {
            await _firestore
                .collection('users')
                .doc(_currentUser!.uid)
                .collection('transactions')
                .add(record.toMap());
          }

          // Save the file processing metadata to Firestore
          await _firestore
              .collection('users')
              .doc(_currentUser!.uid)
              .collection('file_uploads')
              .add({
            'fileName': fileName,
            'uploadDate': Timestamp.now(),
            'recordCount': extractedRecords.length,
            'fileType': fileExtension,
          });

          // Reload transactions
          await _loadTransactions();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Successfully processed ${extractedRecords.length} transactions')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('No transactions found in the file')),
          );
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing file: $e')),
      );
    } finally {
      setState(() {
        _isUploading = false;
      });
    }
  }

  // Extract transactions from PDF (handling password protection)
  Future<List<TransactionRecord>> _extractFromPDF(File file) async {
    List<TransactionRecord> records = [];

    try {
      // Try to open the PDF using Syncfusion
      syncpdf.PdfDocument? document;
      String allText = '';

      try {
        // First try without password
        document = syncpdf.PdfDocument(
          inputBytes: await file.readAsBytes(),
        );

        // Extract text from each page
        syncpdf.PdfTextExtractor extractor = syncpdf.PdfTextExtractor(document);
        allText = extractor.extractText();

      } catch (e) {
        // PDF might be password protected
        if (document != null) {
          document.dispose();
          document = null;
        }

        // Show dialog to get password
        String? password = await _showPasswordDialog();

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
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Invalid password or corrupted PDF')),
            );
          }
        }
      }

      // Parse transactions from text
      if (allText.isNotEmpty) {
        records = _parseTransactionsFromText(allText);
      }

      // Dispose document
      if (document != null) {
        document.dispose();
      }
    } catch (e) {
      debugPrint('Error extracting PDF: $e');
    }

    return records;
  }

  // Show dialog to get PDF password
  Future<String?> _showPasswordDialog() async {
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

  // Extract transactions from CSV
  Future<List<TransactionRecord>> _extractFromCSV(File file) async {
    List<TransactionRecord> records = [];

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

        if (dateIndex >= 0 && statusIndex >= 0 && typeIndex >= 0 && amountIndex >= 0) {
          // Process data rows
          for (int i = 1; i < lines.length; i++) {
            List<String> values = lines[i].split(',');
            int maxIndex = [dateIndex, statusIndex, typeIndex, amountIndex].reduce((a, b) => a > b ? a : b);
            if (values.length > maxIndex) {
              try {
                DateTime date = _parseDate(values[dateIndex]);
                String status = values[statusIndex];
                String type = values[typeIndex];
                double amount = double.tryParse(values[amountIndex].replaceAll(RegExp(r'[^\d\.]'), '')) ?? 0;

                records.add(TransactionRecord(
                  date: date,
                  status: status,
                  type: type,
                  amount: amount,
                ));
              } catch (e) {
                debugPrint('Error parsing row $i: $e');
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('Error extracting CSV: $e');
    }

    return records;
  }

  // Extract transactions from Excel
  Future<List<TransactionRecord>> _extractFromExcel(File file) async {
    List<TransactionRecord> records = [];

    try {
      // Add excel package to pubspec.yaml: excel: ^2.1.0
      // Import in the file: import 'package:excel/excel.dart';

      // For now, we'll use a workaround with Syncfusion XlsIO
      // First, read the file bytes
      Uint8List bytes = await file.readAsBytes();

      // Convert Excel to CSV
      syncpdf.PdfDocument document = syncpdf.PdfDocument();
      syncpdf.PdfPage page = document.pages.add();
      syncpdf.PdfGrid grid = syncpdf.PdfGrid();

      // Here we would parse the Excel file
      // For this workaround, we'll write code that attempts to parse Excel by saving it as text
      // And then parsing it with our existing CSV parser

      // Create a temporary file
      final Directory tempDir = await getTemporaryDirectory();
      final String tempPath = '${tempDir.path}/temp_excel.csv';
      final File tempFile = File(tempPath);

      // Use ProcessRunCommand or another approach to convert Excel to CSV
      // For simplicity, we'll just write a message to the console for now
      debugPrint('Excel file detected: ${file.path}');
      debugPrint('To fully support Excel files, add the excel package to pubspec.yaml');

      // Alternative approach: try to read Excel as CSV directly
      // This might work for simple Excel files
      try {
        String csvContent = String.fromCharCodes(bytes);
        return await _extractFromCSV(File(file.path));
      } catch (e) {
        debugPrint('Failed to read Excel as CSV: $e');
      }
    } catch (e) {
      debugPrint('Error extracting Excel: $e');
    }

    return records;
  }

  // Parse transactions from text using pattern matching
  List<TransactionRecord> _parseTransactionsFromText(String text) {
    List<TransactionRecord> records = [];

    // Use regex to find transaction patterns
    // This is a simplified example and would need to be adjusted based on actual PDF format
    RegExp datePattern = RegExp(r'\d{1,2}/\d{1,2}/\d{2,4}|\d{1,2}-\d{1,2}-\d{2,4}');
    RegExp amountPattern = RegExp(r'\$?\d+,?\d*\.\d{2}|RM\d+\.\d{2}');

    // Split text by lines
    List<String> lines = text.split('\n');

    // Enhanced approach to find transaction data in tables or structured text
    // Look for sections that might contain transaction data (e.g., tables)
    bool inTransactionSection = false;
    List<String> potentialTransactionLines = [];

    // First check if the text contains Malaysian Ringgit (RM) format transactions
    bool isMalaysianFormat = text.contains('RM') && text.contains('Transaction Type');

    if (isMalaysianFormat) {
      // Handle Malaysian bank statement format
      for (int i = 0; i < lines.length; i++) {
        String line = lines[i];

        // Look for transaction table headers
        if (line.contains('Date') && line.contains('Status') && line.contains('Transaction Type')) {
          inTransactionSection = true;
          continue;
        }

        // Process transaction rows
        if (inTransactionSection && line.contains('RM') && datePattern.hasMatch(line)) {
          try {
            // Extract date
            Match? dateMatch = datePattern.firstMatch(line);
            String dateStr = dateMatch?.group(0) ?? '';
            DateTime date = _parseDate(dateStr);

            // Extract amount - look for RM pattern
            RegExp rmPattern = RegExp(r'RM\d+\.\d{2}');
            Match? amountMatch = rmPattern.firstMatch(line);
            String amountStr = amountMatch?.group(0) ?? '';
            double amount = double.tryParse(amountStr.replaceAll('RM', '')) ?? 0;

            // Extract transaction type
            String type = 'Unknown';
            if (line.contains('Transfer')) {
              type = 'Transfer';
            } else if (line.contains('Payment')) {
              type = 'Payment';
            } else if (line.contains('Reload')) {
              type = 'Reload';
            } else if (line.contains('DuitNow')) {
              type = 'DuitNow';
            }

            // Add to records
            records.add(TransactionRecord(
              date: date,
              status: 'Completed',
              type: type,
              amount: amount,
            ));
          } catch (e) {
            debugPrint('Error parsing Malaysian format transaction: $e');
          }
        }
      }

      return records; // Return early for Malaysian format
    }

    for (String line in lines) {
      // Detect potential transaction table headers
      if (line.toLowerCase().contains('date') &&
          (line.toLowerCase().contains('amount') || line.toLowerCase().contains('transaction')) &&
          !inTransactionSection) {
        inTransactionSection = true;
        continue;
      }

      // If we're in a transaction section, collect lines that might be transactions
      if (inTransactionSection) {
        // End of transaction section detection
        if (line.trim().isEmpty || line.toLowerCase().contains('total') || line.toLowerCase().contains('balance')) {
          inTransactionSection = false;
        } else {
          potentialTransactionLines.add(line);
        }
      }

      // Regardless of sections, check if line contains transaction data
      if (datePattern.hasMatch(line) && amountPattern.hasMatch(line)) {
        try {
          // Extract date
          Match? dateMatch = datePattern.firstMatch(line);
          String dateStr = dateMatch?.group(0) ?? '';
          DateTime date = _parseDate(dateStr);

          // Extract amount
          Match? amountMatch = amountPattern.firstMatch(line);
          String amountStr = amountMatch?.group(0) ?? '';
          // Handle both $ and RM formats
          double amount = double.tryParse(amountStr.replaceAll(RegExp(r'[^\d\.]'), '')) ?? 0;

          // Determine transaction type and status - improved heuristics
          String type;
          if (line.toLowerCase().contains('deposit') || line.toLowerCase().contains('credit')) {
            type = 'Deposit';
          } else if (line.toLowerCase().contains('income') || line.toLowerCase().contains('salary')) {
            type = 'Income';
          } else if (line.toLowerCase().contains('withdraw') || line.toLowerCase().contains('debit')) {
            type = 'Withdrawal';
          } else if (line.toLowerCase().contains('payment') || line.toLowerCase().contains('purchase')) {
            type = 'Payment';
          } else {
            type = 'Expense';
          }

          String status;
          if (line.toLowerCase().contains('complete') || line.toLowerCase().contains('cleared') ||
              line.toLowerCase().contains('success')) {
            status = 'Completed';
          } else if (line.toLowerCase().contains('pending') || line.toLowerCase().contains('processing')) {
            status = 'Pending';
          } else if (line.toLowerCase().contains('fail') || line.toLowerCase().contains('rejected')) {
            status = 'Failed';
          } else if (line.toLowerCase().contains('cancel') || line.toLowerCase().contains('reversed')) {
            status = 'Canceled';
          } else {
            status = 'Completed'; // Default
          }

          records.add(TransactionRecord(
            date: date,
            status: status,
            type: type,
            amount: amount,
          ));
        } catch (e) {
          debugPrint('Error parsing transaction line: $e');
        }
      }
    }

    // Process any potential transaction lines from tables that weren't caught above
    for (String line in potentialTransactionLines) {
      if (!datePattern.hasMatch(line) || !amountPattern.hasMatch(line)) continue;

      try {
        // Extract date
        Match? dateMatch = datePattern.firstMatch(line);
        String dateStr = dateMatch?.group(0) ?? '';
        DateTime date = _parseDate(dateStr);

        // Extract amount
        Match? amountMatch = amountPattern.firstMatch(line);
        String amountStr = amountMatch?.group(0) ?? '';
        double amount = double.tryParse(amountStr.replaceAll(RegExp(r'[^\d\.]'), '')) ?? 0;

        // Try to determine transaction type and status from column position
        List<String> columns = line.split(RegExp(r'\s{2,}'));
        String type = 'Expense';
        String status = 'Completed';

        if (columns.length >= 3) {
          // Try to determine type from description column
          String descCol = columns.length >= 3 ? columns[1].toLowerCase() : '';
          if (descCol.contains('deposit') || descCol.contains('credit')) {
            type = 'Deposit';
          } else if (descCol.contains('income') || descCol.contains('salary')) {
            type = 'Income';
          } else if (descCol.contains('withdraw') || descCol.contains('debit')) {
            type = 'Withdrawal';
          }

          // Try to determine status from status column if available
          String statusCol = columns.length >= 4 ? columns[2].toLowerCase() : '';
          if (statusCol.contains('pend')) {
            status = 'Pending';
          } else if (statusCol.contains('fail') || statusCol.contains('reject')) {
            status = 'Failed';
          } else if (statusCol.contains('cancel')) {
            status = 'Canceled';
          }
        }

        // Add record if not already in the list (avoid duplicates)
        bool isDuplicate = records.any((record) =>
        record.date.day == date.day &&
            record.date.month == date.month &&
            record.date.year == date.year &&
            record.amount == amount);

        if (!isDuplicate) {
          records.add(TransactionRecord(
            date: date,
            status: status,
            type: type,
            amount: amount,
          ));
        }
      } catch (e) {
        debugPrint('Error parsing transaction line from table: $e');
      }
    }

    return records;
  }

  // Parse date from various formats
  DateTime _parseDate(String dateStr) {
    // Try different date formats
    List<String> formats = [
      'MM/dd/yyyy',
      'dd/MM/yyyy',
      'yyyy/MM/dd',
      'MM-dd-yyyy',
      'dd-MM-yyyy',
      'yyyy-MM-dd',
    ];

    for (String format in formats) {
      try {
        return DateFormat(format).parse(dateStr);
      } catch (_) {
        // Try next format
      }
    }

    // Default to current date if parsing fails
    return DateTime.now();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload),
            onPressed: _isUploading ? null : () {
              // Navigate to upload page
              Navigator.pushNamed(context, '/upload').then((_) {
                // Reload transactions when returning from upload page
                _loadTransactions();
              });
            },
            tooltip: 'Upload Transaction File',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date filter section - updated to match the image
            Card(
              elevation: 2,
              color: const Color(0xFFFFF8E1), // Light beige background color
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Filter by Date',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Segmented control with rounded corners
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildFilterOption('Year', _selectedPeriod == 'Year'),
                            _buildFilterOption('Month', _selectedPeriod == 'Month'),
                            _buildFilterOption('Day', _selectedPeriod == 'Day'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Showing data from ${DateFormat('MMM dd, yyyy').format(_selectedStartDate)} to ${DateFormat('MMM dd, yyyy').format(_selectedEndDate)}',
                            style: const TextStyle(
                              fontStyle: FontStyle.italic,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          height: 28,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: TextButton(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed: () => _showDateRangePicker(),
                            child: const Text(
                              'Custom Range',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Summary section - updated to match the image
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Income',
                    amount: _totalIncome,
                    icon: Icons.arrow_upward,
                    color: Colors.green,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Expense',
                    amount: _totalExpense,
                    icon: Icons.arrow_downward,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildSummaryCard(
                    title: 'Net',
                    amount: _netAmount,
                    icon: Icons.account_balance_wallet,
                    color: Colors.blue,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Chart section - conditionally shown if there's data
            if (_incomeData.isNotEmpty || _expenseData.isNotEmpty)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Income vs Expenses',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 250,
                        child: SfCartesianChart(
                          primaryXAxis: CategoryAxis(),
                          legend: Legend(isVisible: true),
                          tooltipBehavior: TooltipBehavior(enable: true),
                          series: <CartesianSeries>[
                            ColumnSeries<ChartData, String>(
                              name: 'Income',
                              dataSource: _incomeData,
                              xValueMapper: (ChartData data, _) => data.category,
                              yValueMapper: (ChartData data, _) => data.value,
                              color: Colors.green,
                            ),
                            ColumnSeries<ChartData, String>(
                              name: 'Expense',
                              dataSource: _expenseData,
                              xValueMapper: (ChartData data, _) => data.category,
                              yValueMapper: (ChartData data, _) => data.value,
                              color: Colors.red,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Transactions list - updated to match the image
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Transactions',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '${_filteredTransactions.length} items',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _filteredTransactions.isEmpty
                        ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Text(
                          'No transactions found for the selected period',
                          style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    )
                        : ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _filteredTransactions.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final transaction = _filteredTransactions[index];
                        return ListTile(
                          title: Text(
                            transaction.type,
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Text(
                            '${DateFormat('MMM dd, yyyy').format(transaction.date)} • ${transaction.status}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          trailing: Text(
                            '\$${transaction.amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: transaction.type.toLowerCase().contains('income') ||
                                  transaction.type.toLowerCase().contains('deposit') ||
                                  transaction.type.toLowerCase().contains('transfer') ||
                                  transaction.type.toLowerCase().contains('reload')
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Custom filter option widget
  Widget _buildFilterOption(String text, bool isSelected) {
    return Expanded(
      child: Material(
        color: isSelected ? Colors.amber.shade100 : Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedPeriod = text;
              _applyDateFilter();
            });
          },
          child: Container(
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(right: 4),
                    child: Icon(Icons.check, size: 16),
                  ),
                Text(
                  text,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Build a summary card widget - updated to match the image
  Widget _buildSummaryCard({
    required String title,
    required double amount,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '\$${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Show date range picker dialog
  void _showDateRangePicker() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _selectedStartDate,
        end: _selectedEndDate,
      ),
      builder: (BuildContext context, Widget? child) {
        return Theme(
          data: ThemeData.light().copyWith(
            colorScheme: const ColorScheme.light().copyWith(
              primary: Colors.amber,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _selectedStartDate = picked.start;
        _selectedEndDate = picked.end;
        _applyDateFilter();
      });
    }
  }
}

// Transaction record model
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

  // Create from Firestore document
  factory TransactionRecord.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return TransactionRecord(
      date: (data['date'] as Timestamp).toDate(),
      status: data['status'] ?? '',
      type: data['type'] ?? '',
      amount: (data['amount'] ?? 0).toDouble(),
    );
  }

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

// Chart data model
class ChartData {
  final String category;
  final double value;

  ChartData(this.category, this.value);
}