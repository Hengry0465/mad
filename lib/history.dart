import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

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
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellow),
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
  DateTimeRange? _dateRange;
  final List<String> _filters = ['All', 'Income', 'Expense'];
  int currentPageIndex = 2;

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
            _buildFilterTabs(),
            const SizedBox(height: 20),
            _buildDateRangeSelector(context),
            const SizedBox(height: 20),
            Expanded(
              child: _buildTransactionList(),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentPageIndex,
        onTap: (index) {
          // Handle navigation based on index
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Overview',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add),
            label: 'Add',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.history),
            label: 'History',
          ),
        ],
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

  Widget _buildFilterTabs() {
    return Row(
      children: _filters.map((filter) {
        return Padding(
          padding: const EdgeInsets.only(right: 16.0),
          child: ChoiceChip(
            label: Text(filter),
            selected: _selectedFilter == filter,
            onSelected: (selected) => setState(() => _selectedFilter = filter),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateRangeSelector(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Date range',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.calendar_today, size: 20),
          onPressed: () async {
            final picked = await showDateRangePicker(
              context: context,
              firstDate: DateTime(2020),
              lastDate: DateTime.now(),
            );
            if (picked != null) {
              setState(() => _dateRange = picked);
            }
          },
        ),
        const SizedBox(width: 8),
        Text(
          _dateRange == null
              ? 'Select range'
              : '${DateFormat('MMM d').format(_dateRange!.start)} - '
              '${DateFormat('MMM d').format(_dateRange!.end)}',
          style: const TextStyle(
            color: Colors.black,
          ),
        ),
      ],
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

          // Search filter - matches if search query is empty or title contains query
          final matchesSearch = _searchQuery.isEmpty ||
              title.contains(_searchQuery.toLowerCase());

          // Type filter
          final matchesType = _selectedFilter == 'All' ||
              (_selectedFilter == 'Income' && !isExpense) ||
              (_selectedFilter == 'Expense' && isExpense);

          // Date filter
          final matchesDate = _dateRange == null ||
              (date.isAfter(_dateRange!.start) &&
                  date.isBefore(_dateRange!.end));

          return matchesSearch && matchesType && matchesDate;
        }).toList();

        if (transactions.isEmpty) {
          return Center(
            child: Text(
              _searchQuery.isEmpty
                  ? 'No transactions match your filters'
                  : 'No transactions found for "$_searchQuery"',
              style: const TextStyle(fontSize: 16),
            ),
          );
        }

        return ListView.builder(
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final transaction = transactions[index];
            final data = transaction.data() as Map<String, dynamic>;
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

            final formattedDate = DateFormat('yyyy-MM-dd').format(transactionDate);

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(title),
                subtitle: Text('$category • $formattedDate'),
                trailing: Text(
                  'RM ${amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: isExpense ? Colors.red : Colors.green,
                  ),
                ),
                leading: Icon(
                  isExpense ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isExpense ? Colors.red : Colors.green,
                ),
              ),
            );
          },
        );
      },
    );
  }
}