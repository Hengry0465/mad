import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:mad/addTransaction.dart';
import 'package:mad/overview.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const History());
}

class History extends StatelessWidget {
  const History({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Transaction History',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
      ),
      home: const TransactionHistoryScreen(),
    );
  }
}

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  String _searchQuery = '';
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Income', 'Expense'];
  int currentPageIndex = 2;

  // Month/year dropdown variables
  final List<String> _months = [
    'January', 'February', 'March', 'April',
    'May', 'June', 'July', 'August',
    'September', 'October', 'November', 'December'
  ];
  final List<int> _years = List.generate(5, (index) => DateTime.now().year - index);
  String? _selectedMonth;
  int? _selectedYear;
  DateTime? _selectedMonthYear;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(''),
        centerTitle: true,
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Transaction History",
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
            ),
            const Text(
              'View and manage your past transactions',
              style: TextStyle(
                color: Colors.grey,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            _buildSearchBar(),
            const SizedBox(height: 20),
            _buildCombinedFilterRow(),
            const SizedBox(height: 20),
            Expanded(
              child: _buildTransactionList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        onChanged: (value) => setState(() => _searchQuery = value),
        decoration: InputDecoration(
          hintText: 'Search transactions...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => setState(() => _searchQuery = ''),
          )
              : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildCombinedFilterRow() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Row(
          children: [
            // Filter chips on the left
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: _filters.map((filter) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: ChoiceChip(
                        label: Text(filter),
                        selected: _selectedFilter == filter,
                        onSelected: (selected) => setState(() => _selectedFilter = filter),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),

            // Month/Year dropdowns on the right
            Row(
              children: [
                // Month dropdown
                Container(
                  width: 100,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<String>(
                    isExpanded: true,
                    value: _selectedMonth,
                    hint: const Text('Month', style: TextStyle(fontSize: 12)),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                    ),
                    items: _months.map((String month) {
                      return DropdownMenuItem<String>(
                        value: month,
                        child: Text(month, style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedMonth = newValue;
                        if (_selectedMonth != null && _selectedYear != null) {
                          _selectedMonthYear = DateTime(
                              _selectedYear!,
                              _months.indexOf(_selectedMonth!) + 1
                          );
                        }
                      });
                    },
                  ),
                ),
                if (_selectedMonth != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      setState(() {
                        _selectedMonth = null;
                        _selectedMonthYear = null;
                      });
                    },
                  ),

                const SizedBox(width: 8),

                // Year dropdown
                Container(
                  width: 80,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButton<int>(
                    isExpanded: true,
                    value: _selectedYear,
                    hint: const Text('Year', style: TextStyle(fontSize: 12)),
                    underline: const SizedBox(),
                    icon: const Icon(Icons.arrow_drop_down, size: 20),
                    style: const TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                    ),
                    items: _years.map((int year) {
                      return DropdownMenuItem<int>(
                        value: year,
                        child: Text(year.toString(), style: const TextStyle(fontSize: 12)),
                      );
                    }).toList(),
                    onChanged: (int? newValue) {
                      setState(() {
                        _selectedYear = newValue;
                        if (_selectedMonth != null && _selectedYear != null) {
                          _selectedMonthYear = DateTime(
                              _selectedYear!,
                              _months.indexOf(_selectedMonth!) + 1
                          );
                        }
                      });
                    },
                  ),
                ),
                if (_selectedYear != null)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 16),
                    onPressed: () {
                      setState(() {
                        _selectedYear = null;
                        _selectedMonthYear = null;
                      });
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('transactions')
          .orderBy('date', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Text('No transactions recorded.'));
        }

        final transactions = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>;
          final title = data['title']?.toString().toLowerCase() ?? '';
          final isExpense = data['isExpense'] ?? true;

          // Handle date formats
          DateTime date;
          if (data['date'] is Timestamp) {
            date = (data['date'] as Timestamp).toDate();
          } else if (data['date'] is String) {
            date = DateTime.tryParse(data['date']) ?? DateTime.now();
          } else {
            date = DateTime.now();
          }

          // Search filter
          final matchesSearch = _searchQuery.isEmpty ||
              title.contains(_searchQuery.toLowerCase());

          // Type filter
          final matchesType = _selectedFilter == 'All' ||
              (_selectedFilter == 'Income' && !isExpense) ||
              (_selectedFilter == 'Expense' && isExpense);

          // Month filter
          final matchesMonth = _selectedMonthYear == null ||
              (date.year == _selectedMonthYear!.year &&
                  date.month == _selectedMonthYear!.month);

          return matchesSearch && matchesType && matchesMonth;
        }).toList();

        if (transactions.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _searchQuery.isEmpty
                      ? 'No transactions in ${_selectedMonthYear != null ? DateFormat('MMMM yyyy').format(_selectedMonthYear!) : 'selected month'}'
                      : 'No transactions found for "$_searchQuery"',
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          );
        }

        return Column(
          children: [
            if (_selectedMonthYear != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'Showing transactions for ${DateFormat('MMMM yyyy').format(_selectedMonthYear!)}',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: transactions.length,
                itemBuilder: (context, index) {
                  final transaction = transactions[index];
                  final data = transaction.data() as Map<String, dynamic>;
                  final docId = transaction.id;
                  final title = data['title']?.toString() ?? 'No Title';
                  final isExpense = data['isExpense'] ?? true;
                  final amount = (data['amount'] ?? 0.0).toDouble();
                  final category = data['category']?.toString() ?? 'No Category';

                  // Handle date formats
                  DateTime transactionDate;
                  if (data['date'] is Timestamp) {
                    transactionDate = (data['date'] as Timestamp).toDate();
                  } else if (data['date'] is String) {
                    transactionDate = DateTime.tryParse(data['date']) ?? DateTime.now();
                  } else {
                    transactionDate = DateTime.now();
                  }

                  final formattedDate = DateFormat('MMM d, yyyy').format(transactionDate);

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      title: Text(title),
                      subtitle: Text('$category • $formattedDate'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'RM ${amount.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: isExpense ? Colors.red : Colors.green,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                            onPressed: () => _deleteTransaction(docId),
                          ),
                        ],
                      ),
                      leading: Icon(
                        isExpense ? Icons.arrow_downward : Icons.arrow_upward,
                        color: isExpense ? Colors.red : Colors.green,
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _deleteTransaction(String docId) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Transaction'),
          content: const Text('Are you sure you want to delete this transaction?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                FirebaseFirestore.instance
                    .collection('transactions')
                    .doc(docId)
                    .delete();
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Transaction deleted')),
                );
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }
}