// report_page.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart';
import 'dept_model.dart';
import 'dept_service.dart';

class ReportPage extends StatefulWidget {
  const ReportPage({Key? key}) : super(key: key);

  @override
  _ReportPageState createState() => _ReportPageState();
}

class _ReportPageState extends State<ReportPage> {
  final DeptService _deptService = DeptService();

  // Initialize with default values immediately
  final DateTime _now = DateTime.now();
  // Selected month and year (default to current)
  int _selectedMonth = DateTime.now().month;
  int _selectedYear = DateTime.now().year;

  // Available months and years for dropdown
  final List<int> _months = List.generate(12, (index) => index + 1);
  late List<int> _years;

  // Report data
  double _totalBorrowed = 0;
  double _totalLent = 0;
  double _totalPaid = 0;
  double _totalUnpaid = 0;

  // Loading state
  bool _isLoading = true;  // Start with loading
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    // Generate years list (from 2020 to current year + 2)
    _years = List.generate(_now.year - 2020 + 3, (index) => 2020 + index);

    // Load data after widget is built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReportData();
    });
  }

  // Get month name from month number
  String _getMonthName(int month) {
    return DateFormat('MMMM').format(DateTime(2022, month, 1));
  }

  // Load report data for selected month
  Future<void> _loadReportData() async {
    try {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });

      // Validate user is logged in
      final String? userId = _deptService.currentUserId;
      if (userId == null) {
        setState(() {
          _errorMessage = 'Please login to view reports';
          _isLoading = false;
        });
        return;
      }

      // Calculate start and end of month
      final DateTime startOfMonth = DateTime(_selectedYear, _selectedMonth, 1);
      final DateTime endOfMonth = (_selectedMonth < 12)
          ? DateTime(_selectedYear, _selectedMonth + 1, 0, 23, 59, 59)
          : DateTime(_selectedYear + 1, 1, 0, 23, 59, 59);

      // Get all records
      final QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection('dept_records')
          .where('userId', isEqualTo: userId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
          .get();

      // Process data
      final List<DeptRecord> records = snapshot.docs
          .map((doc) => DeptRecord.fromFirestore(doc))
          .toList();

      double borrowed = 0;
      double lent = 0;
      double paid = 0;
      double unpaid = 0;

      for (final record in records) {
        if (record.deptType == DeptType.borrow) {
          // Borrowing (I owe)
          borrowed += record.originalAmount;
          if (record.isCompleted) {
            paid += record.originalAmount;
          } else {
            unpaid += record.amount;
          }
        } else {
          // Lending (They owe me)
          lent += record.originalAmount;
          if (record.isCompleted) {
            paid += record.originalAmount;
          } else {
            unpaid += record.amount;
          }
        }
      }

      setState(() {
        _totalBorrowed = borrowed;
        _totalLent = lent;
        _totalPaid = paid;
        _totalUnpaid = unpaid;
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load report data: $e';
        _isLoading = false;
      });
      print('Error loading report data: $e');
    }
  }

  // Build stat card
  Widget _buildStatCard(String title, double amount, Color color, IconData icon) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[700],
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '\$${amount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Build bar chart
  Widget _buildBarChart() {
    const double barWidth = 40;
    const double barSpacing = 24;
    const double maxHeight = 200;

    // Safely find the maximum value, handling empty array case
    final List<double> values = [_totalBorrowed, _totalLent, _totalPaid, _totalUnpaid];
    final double maxAmount = values.isEmpty ? 0 : values.reduce((max, value) => max > value ? max : value);

    // Guard against division by zero
    final double scale = maxAmount > 0 ? maxHeight / maxAmount : 0;

    return SizedBox(
      height: maxHeight + 60, // Add space for labels
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Borrowed bar
            _buildBar(
              'Borrowed',
              _totalBorrowed,
              Colors.red[400]!,
              maxHeight,
              scale,
              barWidth,
              Icons.arrow_back,
            ),
            SizedBox(width: barSpacing),

            // Lent bar
            _buildBar(
              'Lent',
              _totalLent,
              Colors.green[400]!,
              maxHeight,
              scale,
              barWidth,
              Icons.arrow_forward,
            ),
            SizedBox(width: barSpacing),

            // Paid bar
            _buildBar(
              'Paid',
              _totalPaid,
              Colors.blue[400]!,
              maxHeight,
              scale,
              barWidth,
              Icons.check_circle,
            ),
            SizedBox(width: barSpacing),

            // Unpaid bar
            _buildBar(
              'Unpaid',
              _totalUnpaid,
              Colors.orange[400]!,
              maxHeight,
              scale,
              barWidth,
              Icons.warning,
            ),
          ],
        ),
      ),
    );
  }

  // Build individual bar
  Widget _buildBar(
      String label,
      double value,
      Color color,
      double maxHeight,
      double scale,
      double width,
      IconData icon,
      ) {
    // Calculate height based on value
    final double height = value * scale;

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        // Value at top of bar
        Text(
          '\$${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
            color: color,
          ),
        ),
        const SizedBox(height: 4),

        // The bar
        AnimatedContainer(
          duration: const Duration(milliseconds: 500),
          width: width,
          height: height > 0 ? height : 2, // Minimum visible height
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
          child: value > 0
              ? Center(
            child: Icon(icon, color: Colors.white, size: 16),
          )
              : null,
        ),
        const SizedBox(height: 8),

        // Label below bar
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  // Build month and year dropdown selectors
  Widget _buildDateSelectors() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today, color: Colors.blue),
          const SizedBox(width: 12),

          // Month dropdown
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _selectedMonth,
              decoration: const InputDecoration(
                labelText: 'Month',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              items: _months.map((month) {
                return DropdownMenuItem<int>(
                  value: month,
                  child: Text(_getMonthName(month)),
                );
              }).toList(),
              onChanged: (month) {
                if (month != null && month != _selectedMonth) {
                  setState(() {
                    _selectedMonth = month;
                  });
                  _loadReportData();
                }
              },
            ),
          ),

          const SizedBox(width: 12),

          // Year dropdown
          Expanded(
            child: DropdownButtonFormField<int>(
              value: _selectedYear,
              decoration: const InputDecoration(
                labelText: 'Year',
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
              items: _years.map((year) {
                return DropdownMenuItem<int>(
                  value: year,
                  child: Text(year.toString()),
                );
              }).toList(),
              onChanged: (year) {
                if (year != null && year != _selectedYear) {
                  setState(() {
                    _selectedYear = year;
                  });
                  _loadReportData();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dept Monthly Report'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadReportData,
            tooltip: 'Refresh data',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadReportData,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      )
          : RefreshIndicator(
        onRefresh: _loadReportData,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month and year dropdown selectors
              _buildDateSelectors(),
              const SizedBox(height: 24),

              // Stats cards in a grid
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildStatCard('Borrowed (I owe)', _totalBorrowed, Colors.red, Icons.arrow_back),
                  _buildStatCard('Lent (They owe)', _totalLent, Colors.green, Icons.arrow_forward),
                  _buildStatCard('Total Paid', _totalPaid, Colors.blue, Icons.check_circle),
                  _buildStatCard('Total Unpaid', _totalUnpaid, Colors.orange, Icons.warning),
                ],
              ),
              const SizedBox(height: 32),

              // Bar chart
              const Center(
                child: Text(
                  'Monthly Summary',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _buildBarChart(),

              // No data message if all zeros
              if (_totalBorrowed == 0 && _totalLent == 0)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Icon(Icons.info_outline, size: 48, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        Text(
                          'No transactions found for ${_getMonthName(_selectedMonth)} $_selectedYear',
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 16,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}