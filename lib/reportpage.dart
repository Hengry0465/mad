import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_charts/charts.dart';
import 'dart:async'; // Import for StreamSubscription
import 'upload.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({Key? key}) : super(key: key);

  @override
  State<ReportPage> createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> with TickerProviderStateMixin {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final User? _currentUser = FirebaseAuth.instance.currentUser;

  // Add a StreamSubscription to listen for file changes
  StreamSubscription<QuerySnapshot>? _filesSubscription;

  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  // Data state
  bool _isLoading = true;
  bool _isRefreshing = false;
  List<Map<String, dynamic>> _transactions = [];
  Map<String, dynamic> _summary = {};

  // Cached data for performance
  List<ChartData> _cachedTypeData = [];
  List<ChartData> _cachedMonthlyData = [];
  List<ChartData> _cachedDailyData = [];

  // Filters
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _endDate = DateTime.now();
  String _selectedPeriod = 'Last 30 days';

  // UI state
  bool _showCharts = true;
  int _selectedTabIndex = 0;
  bool _isNavigating = false;

  // Filter options
  final List<String> _periodOptions = [
    'Last 7 days',
    'Last 30 days',
    'Last 90 days',
    'This year',
  ];

  // Color palette
  static const Color _primaryColor = Color(0xFFFFC700);
  static const Color _secondaryColor = Color(0xFF6259FF);
  static const Color _backgroundColor = Color(0xFFF8F9FA);
  static const Color _cardColor = Colors.white;
  static const Color _textPrimary = Color(0xFF1A1A1A);
  static const Color _textSecondary = Color(0xFF6B7280);

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadTransactionData();
    _setupFileListener(); // Add file listener
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _filesSubscription?.cancel(); // Cancel the stream subscription
    super.dispose();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));
  }

  // Set up a listener for file changes
  void _setupFileListener() {
    if (_currentUser == null) return;

    // Listen to changes in the uploaded_files collection
    _filesSubscription = _firestore
        .collection('users')
        .doc(_currentUser!.uid)
        .collection('uploaded_files')
        .snapshots()
        .listen((snapshot) {
      // Only reload data if this isn't the initial load and we're not already refreshing
      if (!_isLoading && !_isRefreshing) {
        print('Files collection changed, refreshing report data...');
        _loadTransactionData(isAutoRefresh: true);
      }
    }, onError: (error) {
      print('Error listening to file changes: $error');
    });
  }

  Future<void> _loadTransactionData({bool isAutoRefresh = false}) async {
    if (_currentUser == null) return;

    setState(() {
      if (!isAutoRefresh) {
        _isLoading = true;
      } else {
        _isRefreshing = true;
      }
    });

    try {
      // Show loading animation
      _fadeController.reset();
      _slideController.reset();

      // Get all analyzed files from Firestore
      final QuerySnapshot filesSnapshot = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .collection('uploaded_files')
          .where('analyzedAt', isNull: false)
          .orderBy('analyzedAt', descending: true)
          .get();

      List<Map<String, dynamic>> allTransactions = [];

      // Extract transaction data from each file
      for (var doc in filesSnapshot.docs) {
        Map<String, dynamic> fileData = doc.data() as Map<String, dynamic>;

        if (fileData['analysisResult'] != null &&
            fileData['analysisResult']['transactions'] != null) {

          List<dynamic> fileTransactions = fileData['analysisResult']['transactions'];
          String? period = fileData['analysisResult']['transactionPeriod'];

          for (var transaction in fileTransactions) {
            DateTime? transactionDate = _parseTransactionDate(transaction['date']);

            if (transactionDate != null) {
              if (transactionDate.isAfter(_startDate.subtract(const Duration(days: 1))) &&
                  transactionDate.isBefore(_endDate.add(const Duration(days: 1)))) {

                allTransactions.add({
                  ...transaction,
                  'parsedDate': transactionDate,
                  'period': period,
                  'fileId': doc.id,
                  'fileName': fileData['name'],
                  'walletType': _extractWalletType(fileData['name']),
                });
              }
            }
          }
        }
      }

      // Sort transactions by date (newest first)
      allTransactions.sort((a, b) => b['parsedDate'].compareTo(a['parsedDate']));

      // Calculate summary data with caching
      await _calculateEnhancedSummary(allTransactions);

      setState(() {
        _transactions = allTransactions;
        _isLoading = false;
        _isRefreshing = false;
      });

      // Start animations - only do full animations on initial load, not on auto-refresh
      if (!isAutoRefresh) {
        _fadeController.forward();
        _slideController.forward();
      } else {
        _fadeController.forward(from: 0.5);
        _slideController.forward(from: 0.5);
      }

    } catch (e) {
      print('Error loading transaction data: $e');
      if (mounted) {
        _showErrorSnackBar('Error loading transaction data: ${e.toString()}');
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  String _extractWalletType(String fileName) {
    String upperName = fileName.toUpperCase();
    if (upperName.contains('TNG') || upperName.contains('TOUCH')) return 'TNG Wallet';
    if (upperName.contains('GRAB')) return 'GrabPay';
    if (upperName.contains('BOOST')) return 'Boost';
    if (upperName.contains('SHOPEE')) return 'ShopeePay';
    if (upperName.contains('BIGPAY')) return 'BigPay';
    if (upperName.contains('MAE')) return 'MAE';
    return 'E-Wallet';
  }

  DateTime? _parseTransactionDate(String dateStr) {
    try {
      List<String> formats = [
        'dd/MM/yyyy',
        'MM/dd/yyyy',
        'yyyy-MM-dd',
        'dd-MM-yyyy',
        'MM-dd-yyyy',
        'dd.MM.yyyy',
        'MM.dd.yyyy',
      ];

      for (String format in formats) {
        try {
          return DateFormat(format).parse(dateStr);
        } catch (e) {
          continue;
        }
      }

      RegExp dateRegex = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})');
      Match? match = dateRegex.firstMatch(dateStr);

      if (match != null) {
        int? day = int.tryParse(match.group(1)!);
        int? month = int.tryParse(match.group(2)!);
        int? year = int.tryParse(match.group(3)!);

        if (day != null && month != null && year != null) {
          if (year < 100) year += 2000;
          if (day > 0 && day <= 31 && month > 0 && month <= 12) {
            return DateTime(year, month, day);
          }
        }
      }
    } catch (e) {
      print('Error parsing date: $e');
    }
    return null;
  }

  Future<void> _calculateEnhancedSummary(List<Map<String, dynamic>> transactions) async {
    if (transactions.isEmpty) {
      _summary = {
        'totalTransactions': 0,
        'totalAmount': 0.0,
        'totalSpending': 0.0,
        'totalTopUps': 0.0,
        'topUpCount': 0,
        'spendingCount': 0,
        'averageAmount': 0.0,
        'averageSpending': 0.0,
        'averageTopUp': 0.0,
        'transactionTypes': {},
        'spendingTypes': {},
        'monthlyTotals': [],
        'dailyTotals': [],
        'walletBreakdown': {},
        'statusBreakdown': {},
      };
      _cachedTypeData = [];
      _cachedMonthlyData = [];
      _cachedDailyData = [];
      return;
    }

    // Perform calculations in a separate isolate for better performance
    await Future.microtask(() {
      double totalAmount = 0.0;
      double totalSpending = 0.0;
      double totalTopUps = 0.0;
      int topUpCount = 0;
      int spendingCount = 0;

      Map<String, double> transactionTypes = {};
      Map<String, double> spendingTypes = {};
      Map<String, double> monthlyTotals = {};
      Map<String, double> dailyTotals = {};
      Map<String, int> walletBreakdown = {};
      Map<String, int> statusBreakdown = {};

      for (var transaction in transactions) {
        double amount = transaction['amount'] ?? 0.0;
        totalAmount += amount;

        String type = transaction['type'] ?? 'Unknown';
        String status = transaction['status'] ?? 'Unknown';
        String description = transaction['description'] ?? '';
        String walletType = transaction['walletType'] ?? 'E-Wallet';

        walletBreakdown[walletType] = (walletBreakdown[walletType] ?? 0) + 1;
        statusBreakdown[status] = (statusBreakdown[status] ?? 0) + 1;

        bool isTopUp = _isTopUpTransaction(type, description);

        if (isTopUp) {
          totalTopUps += amount;
          topUpCount++;
        } else {
          totalSpending += amount;
          spendingCount++;
          spendingTypes[type] = (spendingTypes[type] ?? 0.0) + amount;
        }

        transactionTypes[type] = (transactionTypes[type] ?? 0.0) + amount;

        String monthKey = DateFormat('MMM yyyy').format(transaction['parsedDate']);
        monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0.0) + amount;

        if (transaction['parsedDate'].isAfter(DateTime.now().subtract(const Duration(days: 30)))) {
          String dayKey = DateFormat('dd MMM').format(transaction['parsedDate']);
          dailyTotals[dayKey] = (dailyTotals[dayKey] ?? 0.0) + amount;
        }
      }

      // Cache chart data
      _cachedTypeData = transactionTypes.entries
          .map((e) => ChartData(e.key, e.value))
          .toList();

      _cachedMonthlyData = monthlyTotals.entries
          .map((e) => ChartData(e.key, e.value))
          .toList();

      _cachedMonthlyData.sort((a, b) {
        DateTime dateA = DateFormat('MMM yyyy').parse(a.category);
        DateTime dateB = DateFormat('MMM yyyy').parse(b.category);
        return dateA.compareTo(dateB);
      });

      if (_cachedMonthlyData.length > 6) {
        _cachedMonthlyData = _cachedMonthlyData.sublist(_cachedMonthlyData.length - 6);
      }

      _cachedDailyData = dailyTotals.entries
          .map((e) => ChartData(e.key, e.value))
          .toList();

      _cachedDailyData.sort((a, b) {
        DateTime dateA = DateFormat('dd MMM').parse(a.category);
        DateTime dateB = DateFormat('dd MMM').parse(b.category);
        return dateA.compareTo(dateB);
      });

      if (_cachedDailyData.length > 14) {
        _cachedDailyData = _cachedDailyData.sublist(_cachedDailyData.length - 14);
      }

      List<ChartData> spendingVsTopUpData = [
        ChartData('Spending', totalSpending),
        ChartData('Top Ups', totalTopUps),
      ];

      List<ChartData> walletChartData = walletBreakdown.entries
          .map((e) => ChartData(e.key, e.value.toDouble()))
          .toList();

      _summary = {
        'totalTransactions': transactions.length,
        'totalAmount': totalAmount,
        'totalSpending': totalSpending,
        'totalTopUps': totalTopUps,
        'topUpCount': topUpCount,
        'spendingCount': spendingCount,
        'averageAmount': totalAmount / transactions.length,
        'averageSpending': spendingCount > 0 ? totalSpending / spendingCount : 0.0,
        'averageTopUp': topUpCount > 0 ? totalTopUps / topUpCount : 0.0,
        'transactionTypes': _cachedTypeData,
        'spendingTypes': spendingTypes.entries.map((e) => ChartData(e.key, e.value)).toList(),
        'monthlyTotals': _cachedMonthlyData,
        'dailyTotals': _cachedDailyData,
        'spendingVsTopUps': spendingVsTopUpData,
        'walletBreakdown': walletChartData,
        'statusBreakdown': statusBreakdown,
      };
    });
  }

  bool _isTopUpTransaction(String type, String description) {
    String typeUpper = type.toUpperCase();
    String descUpper = description.toUpperCase();

    List<String> topUpKeywords = [
      'TOP UP', 'TOP-UP', 'RELOAD', 'RECHARGE', 'ADD MONEY', 'DEPOSIT',
      'TRANSFER TO WALLET', 'RECEIVE FROM', 'CREDIT'
    ];

    for (String keyword in topUpKeywords) {
      if (typeUpper.contains(keyword) || descUpper.contains(keyword)) {
        return true;
      }
    }

    return false;
  }

  void _updateDateRange(String period) {
    DateTime now = DateTime.now();
    DateTime start;
    DateTime end = now;

    switch (period) {
      case 'Last 7 days':
        start = now.subtract(const Duration(days: 7));
        break;
      case 'Last 30 days':
        start = now.subtract(const Duration(days: 30));
        break;
      case 'Last 90 days':
        start = now.subtract(const Duration(days: 90));
        break;
      case 'This year':
        start = DateTime(now.year, 1, 1);
        break;
      default:
        start = now.subtract(const Duration(days: 30));
    }

    setState(() {
      _selectedPeriod = period;
      _startDate = start;
      _endDate = end;
    });

    _loadTransactionData();
  }

  Future<void> _selectCustomDateRange(BuildContext context) async {
    DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(
        start: _startDate,
        end: _endDate,
      ),
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: _primaryColor,
              secondary: _secondaryColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
        _selectedPeriod = 'Custom range';
      });

      _loadTransactionData();
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  // Show a subtle notification for auto-refresh
  // Navigation with loading screen
  void _navigateToUploadScreen() async {
    setState(() {
      _isNavigating = true;
    });

    // Add a small delay to show the loading screen
    await Future.delayed(const Duration(milliseconds: 800));

    if (!mounted) return;

    // Navigate to the upload page
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const UploadScreen()),
    ).then((_) {
      // Reset navigation state when returning from the upload page
      if (mounted) {
        setState(() {
          _isNavigating = false;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _backgroundColor,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [
              _buildAppBar(),
              if (_isLoading)
                SliverFillRemaining(child: _buildLoadingState())
              else if (_transactions.isEmpty)
                SliverFillRemaining(child: _buildEmptyState())
              else
                _buildReportContent(),
            ],
          ),
          // Navigation loading overlay
          if (_isNavigating)
            _buildNavigationLoadingOverlay(),
        ],
      ),
    );
  }

  // Navigation loading overlay
  Widget _buildNavigationLoadingOverlay() {
    return Container(
      color: Colors.black.withOpacity(0.5),
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: _primaryColor,
                strokeWidth: 3,
              ),
              const SizedBox(height: 16),
              const Text(
                'Loading...',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      floating: true,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false, // Remove back button
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.only(left: 20, bottom: 16),
        title: const Text(
          'Transaction Insights',
          style: TextStyle(
            color: _textPrimary,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                _primaryColor.withOpacity(0.05),
              ],
            ),
          ),
        ),
      ),
      actions: [
        IconButton(
          icon: Icon(
            _showCharts ? Icons.list : Icons.bar_chart,
            color: _textPrimary,
          ),
          onPressed: () {
            setState(() {
              _showCharts = !_showCharts;
            });
          },
        ),
        IconButton(
          icon: _isRefreshing
              ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          )
              : const Icon(Icons.refresh, color: _textPrimary),
          onPressed: _isRefreshing ? null : () {
            setState(() {
              _isRefreshing = true;
            });
            _loadTransactionData();
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_primaryColor),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Loading your financial insights...',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: _textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_primaryColor.withOpacity(0.2), _secondaryColor.withOpacity(0.2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                Icons.analytics_outlined,
                size: 60,
                color: _primaryColor,
              ),
            ),
            const SizedBox(height: 32),
            const Text(
              'No Transaction Data',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: _textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Upload and analyze your e-wallet statements to get detailed insights about your spending patterns',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: _textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isNavigating ? null : _navigateToUploadScreen,
              icon: const Icon(Icons.upload_file, size: 20),
              label: const Text(
                'Upload Statement',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryColor,
                foregroundColor: _textPrimary,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportContent() {
    return SliverList(
      delegate: SliverChildListDelegate([
        FadeTransition(
          opacity: _fadeAnimation,
          child: SlideTransition(
            position: _slideAnimation,
            child: Column(
              children: [
                _buildDateFilter(),
                const SizedBox(height: 16),
                _buildSummaryCards(),
                const SizedBox(height: 24),
                if (_showCharts) ...[
                  _buildChartsSection(),
                  const SizedBox(height: 24),
                ],
                _buildTransactionsList(),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildDateFilter() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade200),
                borderRadius: BorderRadius.circular(12),
              ),
              child: DropdownButtonFormField<String>(
                decoration: const InputDecoration(
                  contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: InputBorder.none,
                ),
                value: _selectedPeriod,
                items: _periodOptions.map((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontWeight: FontWeight.w500,
                        color: _textPrimary,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: (String? newValue) {
                  if (newValue != null) {
                    _updateDateRange(newValue);
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () => _selectCustomDateRange(context),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _primaryColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                Icons.calendar_today,
                color: _textPrimary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards() {
    NumberFormat currencyFormat = NumberFormat.currency(symbol: 'RM', decimalDigits: 2);

    List<Map<String, dynamic>> cardData = [
      {
        'title': 'Total Amount',
        'value': currencyFormat.format(_summary['totalAmount'] ?? 0),
        'icon': Icons.account_balance_wallet,
        'gradient': [const Color(0xFF6366F1), const Color(0xFF8B5CF6)],
      },
      {
        'title': 'Total Transactions',
        'value': (_summary['totalTransactions'] ?? 0).toString(),
        'icon': Icons.receipt_long,
        'gradient': [const Color(0xFF06B6D4), const Color(0xFF3B82F6)],
      },
      {
        'title': 'Average Amount',
        'value': currencyFormat.format(_summary['averageAmount'] ?? 0),
        'icon': Icons.trending_up,
        'gradient': [const Color(0xFF10B981), const Color(0xFF34D399)],
      },
      {
        'title': 'Top-up Count',
        'value': '${_summary['topUpCount'] ?? 0} times',
        'icon': Icons.add_circle,
        'gradient': [const Color(0xFFF59E0B), const Color(0xFFEAB308)],
      },
    ];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              children: [
                Icon(Icons.insights, color: _primaryColor, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Financial Overview',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
              ],
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1.5,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: cardData.length,
            itemBuilder: (context, index) {
              final data = cardData[index];
              return _buildEnhancedSummaryCard(
                data['title'],
                data['value'],
                data['icon'],
                data['gradient'],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedSummaryCard(
      String title,
      String value,
      IconData icon,
      List<Color> gradientColors,
      ) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.white.withOpacity(0.1),
              Colors.white.withOpacity(0.05),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.trending_up,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: TextStyle(
                fontSize: 13,
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChartsSection() {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(Icons.bar_chart, color: _primaryColor, size: 24),
              const SizedBox(width: 8),
              const Text(
                'Analytics',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildChartTabs(),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: _buildSelectedChart(),
        ),
      ],
    );
  }

  Widget _buildChartTabs() {
    List<String> tabs = ['Monthly', 'Daily', 'Types'];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          int index = entry.key;
          String tab = entry.value;
          bool isSelected = _selectedTabIndex == index;

          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedTabIndex = index;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: isSelected ? [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ] : null,
                ),
                child: Text(
                  tab,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? _primaryColor : _textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSelectedChart() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildMonthlyTrendChart();
      case 1:
        return _buildDailyTrendChart();
      case 2:
        return _buildTransactionTypeChart();
      default:
        return _buildMonthlyTrendChart();
    }
  }

  Widget _buildMonthlyTrendChart() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Monthly Transaction Trends',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 250,
            child: _cachedMonthlyData.isEmpty
                ? _buildEmptyChart('No monthly data available')
                : SfCartesianChart(
              primaryXAxis: CategoryAxis(
                labelStyle: const TextStyle(fontSize: 12, color: _textSecondary),
                majorGridLines: const MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                numberFormat: NumberFormat.currency(symbol: 'RM', decimalDigits: 0),
                labelStyle: const TextStyle(fontSize: 12, color: _textSecondary),
                majorGridLines: MajorGridLines(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
              plotAreaBorderWidth: 0,
              tooltipBehavior: TooltipBehavior(
                enable: true,
                color: _textPrimary,
                textStyle: const TextStyle(color: Colors.white),
              ),
              series: <CartesianSeries<ChartData, String>>[
                ColumnSeries<ChartData, String>(
                  dataSource: _cachedMonthlyData,
                  xValueMapper: (ChartData data, _) => data.category,
                  yValueMapper: (ChartData data, _) => data.value,
                  name: 'Monthly Total',
                  gradient: LinearGradient(
                    colors: [_primaryColor, _primaryColor.withOpacity(0.6)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                  borderRadius: BorderRadius.circular(4),
                  spacing: 0.3,
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyTrendChart() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent Daily Activity',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 250,
            child: _cachedDailyData.isEmpty
                ? _buildEmptyChart('No daily data available')
                : SfCartesianChart(
              primaryXAxis: CategoryAxis(
                labelStyle: const TextStyle(fontSize: 10, color: _textSecondary),
                labelRotation: 45,
                majorGridLines: const MajorGridLines(width: 0),
              ),
              primaryYAxis: NumericAxis(
                numberFormat: NumberFormat.currency(symbol: 'RM', decimalDigits: 0),
                labelStyle: const TextStyle(fontSize: 12, color: _textSecondary),
                majorGridLines: MajorGridLines(
                  color: Colors.grey.shade200,
                  width: 1,
                ),
              ),
              plotAreaBorderWidth: 0,
              tooltipBehavior: TooltipBehavior(
                enable: true,
                color: _secondaryColor,
                textStyle: const TextStyle(color: Colors.white),
              ),
              series: <CartesianSeries<ChartData, String>>[
                LineSeries<ChartData, String>(
                  dataSource: _cachedDailyData,
                  xValueMapper: (ChartData data, _) => data.category,
                  yValueMapper: (ChartData data, _) => data.value,
                  name: 'Daily Amount',
                  color: _secondaryColor,
                  width: 3,
                  markerSettings: MarkerSettings(
                    isVisible: true,
                    color: _secondaryColor,
                    borderColor: Colors.white,
                    borderWidth: 2,
                    height: 8,
                    width: 8,
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionTypeChart() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Transaction Types',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 250,
            child: _cachedTypeData.isEmpty
                ? _buildEmptyChart('No transaction type data available')
                : SfCircularChart(
              legend: Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                overflowMode: LegendItemOverflowMode.wrap,
                textStyle: const TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
              tooltipBehavior: TooltipBehavior(
                enable: true,
                color: _textPrimary,
                textStyle: const TextStyle(color: Colors.white),
              ),
              series: <CircularSeries>[
                DoughnutSeries<ChartData, String>(
                  dataSource: _cachedTypeData,
                  xValueMapper: (ChartData data, _) => data.category,
                  yValueMapper: (ChartData data, _) => data.value,
                  pointColorMapper: (ChartData data, index) {
                    List<Color> colors = [
                      _primaryColor,
                      _secondaryColor,
                      Colors.green.shade400,
                      Colors.orange.shade400,
                      Colors.purple.shade400,
                      Colors.teal.shade400,
                    ];
                    return colors[index % colors.length];
                  },
                  innerRadius: '60%',
                  radius: '90%',
                  explode: true,
                  explodeOffset: '2%',
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    labelPosition: ChartDataLabelPosition.outside,
                    textStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWalletBreakdownChart() {
    List<ChartData> walletData = (_summary['walletBreakdown'] as List<ChartData>?) ?? [];

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'E-Wallet Usage',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: _textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 250,
            child: walletData.isEmpty
                ? _buildEmptyChart('No wallet data available')
                : SfCircularChart(
              legend: Legend(
                isVisible: true,
                position: LegendPosition.bottom,
                textStyle: const TextStyle(
                  fontSize: 12,
                  color: _textSecondary,
                ),
              ),
              tooltipBehavior: TooltipBehavior(
                enable: true,
                color: _textPrimary,
                textStyle: const TextStyle(color: Colors.white),
              ),
              series: <CircularSeries>[
                PieSeries<ChartData, String>(
                  dataSource: walletData,
                  xValueMapper: (ChartData data, _) => data.category,
                  yValueMapper: (ChartData data, _) => data.value,
                  dataLabelMapper: (ChartData data, _) =>
                  '${data.category}\n${data.value.toInt()} txns',
                  pointColorMapper: (ChartData data, index) {
                    List<Color> colors = [
                      _primaryColor,
                      _secondaryColor,
                      Colors.green.shade400,
                      Colors.orange.shade400,
                      Colors.purple.shade400,
                    ];
                    return colors[index % colors.length];
                  },
                  radius: '90%',
                  explode: true,
                  explodeOffset: '3%',
                  dataLabelSettings: const DataLabelSettings(
                    isVisible: true,
                    labelPosition: ChartDataLabelPosition.outside,
                    textStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChart(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.bar_chart_outlined,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Icon(Icons.history, color: _primaryColor, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Recent Transactions',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_transactions.length} total',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_transactions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No transactions found in this date range',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _transactions.length > 10 ? 10 : _transactions.length,
              separatorBuilder: (context, index) => Divider(
                color: Colors.grey.shade100,
                height: 1,
                indent: 20,
                endIndent: 20,
              ),
              itemBuilder: (context, index) {
                return _buildEnhancedTransactionItem(_transactions[index]);
              },
            ),
          if (_transactions.length > 10)
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _showFullTransactionList,
                  icon: const Icon(Icons.visibility),
                  label: Text('View All ${_transactions.length} Transactions'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _primaryColor,
                    side: BorderSide(color: _primaryColor),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEnhancedTransactionItem(Map<String, dynamic> transaction) {
    // Determine transaction icon and color based on type and amount
    IconData typeIcon;
    Color iconColor;
    String category = '';

    String transactionType = transaction['type']?.toLowerCase() ?? '';
    String description = transaction['description']?.toLowerCase() ?? '';

    if (_isTopUpTransaction(transaction['type'] ?? '', transaction['description'] ?? '')) {
      typeIcon = Icons.add_circle;
      iconColor = Colors.green;
      category = 'Top-up';
    } else if (transactionType.contains('payment') || transactionType.contains('purchase')) {
      typeIcon = Icons.shopping_cart;
      iconColor = Colors.red;
      category = 'Payment';
    } else if (transactionType.contains('transfer')) {
      typeIcon = Icons.swap_horiz;
      iconColor = Colors.blue;
      category = 'Transfer';
    } else if (transactionType.contains('duitnow')) {
      typeIcon = Icons.qr_code;
      iconColor = _secondaryColor;
      category = 'DuitNow';
    } else if (transactionType.contains('receive')) {
      typeIcon = Icons.arrow_circle_down;
      iconColor = Colors.green;
      category = 'Receive';
    } else {
      typeIcon = Icons.receipt;
      iconColor = Colors.grey.shade600;
      category = transaction['type'] ?? 'Transaction';
    }

    String formattedAmount = NumberFormat.currency(
      symbol: 'RM',
      decimalDigits: 2,
    ).format(transaction['amount'] ?? 0.0);

    String formattedDate = DateFormat('MMM dd, yyyy').format(transaction['parsedDate']);

    // Get status
    String status = transaction['status'] ?? 'Unknown';
    Color statusColor = status.toLowerCase() == 'success'
        ? Colors.green
        : status.toLowerCase() == 'failed'
        ? Colors.red
        : Colors.orange;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              typeIcon,
              color: iconColor,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      category,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: _textPrimary,
                      ),
                    ),
                    Text(
                      formattedAmount,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: _isTopUpTransaction(transaction['type'] ?? '', transaction['description'] ?? '')
                            ? Colors.green
                            : _textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (transaction['description'] != null &&
                              transaction['description'].toString().isNotEmpty)
                            Text(
                              transaction['description'],
                              style: TextStyle(
                                fontSize: 13,
                                color: _textSecondary,
                                fontWeight: FontWeight.w500,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          Text(
                            formattedDate,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        status,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showFullTransactionList() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.9,
        decoration: const BoxDecoration(
          color: _backgroundColor,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.only(top: 12, bottom: 8),
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                color: _cardColor,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Row(
                children: [
                  const Text(
                    'All Transactions',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: _primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_transactions.length} items',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: _primaryColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                color: _cardColor,
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: _transactions.length,
                  separatorBuilder: (context, index) => Divider(
                    color: Colors.grey.shade100,
                    height: 1,
                    indent: 20,
                    endIndent: 20,
                  ),
                  itemBuilder: (context, index) {
                    return _buildEnhancedTransactionItem(_transactions[index]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ChartData {
  final String category;
  final double value;

  ChartData(this.category, this.value);
}