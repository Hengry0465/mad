// dept.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dept_model.dart';
import 'dept_service.dart';
import 'add_dept_page.dart';
import 'dept_detail_page.dart';

class DeptPage extends StatefulWidget {
  const DeptPage({Key? key}) : super(key: key);

  @override
  _DeptPageState createState() => _DeptPageState();
}

class _DeptPageState extends State<DeptPage> with SingleTickerProviderStateMixin {
  final DeptService _deptService = DeptService();
  late TabController _tabController;
  int _currentIndex = 0;

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentIndex = _tabController.index;
        });
      }
    });

    // Listen to search query changes
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Show message prompt
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white),
            SizedBox(width: 12),
            Text(message),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: EdgeInsets.only(bottom: 20, left: 20, right: 20),
        duration: Duration(seconds: 2),
      ),
    );
  }

  // Delete record confirmation
  Future<void> _confirmDelete(BuildContext context, DeptRecord record) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: Text('Are you sure you want to delete the record with ${record.personName}?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                try {
                  await _deptService.deleteDeptRecord(record.id!);
                  _showSnackBar('Record deleted');
                } catch (e) {
                  _showSnackBar('Delete failed: $e');
                }
              },
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  // Build single record card
  Widget _buildRecordCard(DeptRecord record) {
    final bool isOverdue = !record.isCompleted && record.dueDate.isBefore(DateTime.now());
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOverdue ? Colors.red.withOpacity(0.5) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => DeptDetailPage(recordId: record.id!),
              ),
            ).then((_) {
              // Refresh state
              setState(() {});
            });
          },
          leading: CircleAvatar(
            backgroundColor: record.deptType == DeptType.borrow
                ? Colors.red[100]
                : Colors.green[100],
            child: Icon(
              record.deptType == DeptType.borrow
                  ? Icons.arrow_back
                  : Icons.arrow_forward,
              color: record.deptType == DeptType.borrow
                  ? Colors.red
                  : Colors.green,
            ),
          ),
          title: Text(
            record.personName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Due: ${DateFormat('yyyy-MM-dd').format(record.dueDate)}'),
            ],
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '\$ ${record.isCompleted ? record.originalAmount.toStringAsFixed(2) : record.amount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: record.deptType == DeptType.borrow
                      ? Colors.red
                      : Colors.green,
                ),
              ),
              const SizedBox(width: 8),
              // Delete button
              if (!record.isCompleted)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.grey),
                  onPressed: () => _confirmDelete(context, record),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // Group records by month and year
  Map<String, List<DeptRecord>> _groupRecordsByMonth(List<DeptRecord> records) {
    // Sort records by date in descending order (newest first)
    records.sort((a, b) => b.dueDate.compareTo(a.dueDate));

    // Group by month and year
    final Map<String, List<DeptRecord>> groupedRecords = {};

    for (final record in records) {
      // Format month and year as a key (e.g., "June 2023")
      final monthYear = DateFormat('MMMM yyyy').format(record.dueDate);

      if (!groupedRecords.containsKey(monthYear)) {
        groupedRecords[monthYear] = [];
      }

      groupedRecords[monthYear]!.add(record);
    }

    return groupedRecords;
  }

  // Filter records by search query
  List<DeptRecord> _filterRecordsBySearch(List<DeptRecord> records, String query) {
    if (query.isEmpty) {
      return records;
    }

    return records.where((record) =>
        record.personName.toLowerCase().contains(query.toLowerCase())
    ).toList();
  }

  // Build record list with month grouping
  Widget _buildRecordList() {
    // Determine the record type to display based on current tab
    DeptType? deptType;
    bool? isCompleted;

    if (_currentIndex == 0) {
      // Borrowed
      deptType = DeptType.borrow;
      isCompleted = false;
    } else if (_currentIndex == 1) {
      // Lent
      deptType = DeptType.lend;
      isCompleted = false;
    } else {
      // History
      isCompleted = true;
    }

    return StreamBuilder<List<DeptRecord>>(
      stream: _deptService.getDeptRecords(
        deptType: deptType,
        isCompleted: isCompleted,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        var records = snapshot.data ?? [];

        // Apply search filter if searching
        if (_searchQuery.isNotEmpty) {
          records = _filterRecordsBySearch(records, _searchQuery);
        }

        if (records.isEmpty) {
          // Show appropriate empty state message
          String message;
          if (_searchQuery.isNotEmpty) {
            message = 'No matches found for "$_searchQuery"';
          } else {
            message = _currentIndex == 0
                ? 'No borrowed records'
                : _currentIndex == 1
                ? 'No lent records'
                : 'No history';
          }

          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.search_off, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          );
        }

        // Group records by month
        final groupedRecords = _groupRecordsByMonth(records);
        final List<String> months = groupedRecords.keys.toList();

        return ListView.builder(
          itemCount: months.length,
          itemBuilder: (context, index) {
            final month = months[index];
            final monthRecords = groupedRecords[month]!;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Month header
                // 月份标题
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          month,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const Divider(thickness: 1.5),
                    ],
                  ),
                ),
                // Month records
                ...monthRecords.map((record) => _buildRecordCard(record)).toList(),

                // Add some space after each month group
                const SizedBox(height: 8),
              ],
            );
          },
        );
      },
    );
  }

  // No longer needed as search is always visible

  // Build a widget that includes the search bar and record list
  Widget _buildTabContent() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by name...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                },
              )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(30),
                borderSide: BorderSide.none,
              ),
              filled: true,
              fillColor: Colors.grey.shade200,
              contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            ),
          ),
        ),

        // Divider between search and records
        Divider(height: 1, thickness: 1, color: Colors.grey.shade300),

        // Expanded list of records
        Expanded(
          child: _buildRecordList(),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Debt Management'),
        bottom: TabBar(
          controller: _tabController,
          indicatorSize: TabBarIndicatorSize.label,
          indicatorWeight: 3,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.normal),
          tabs: const [
            Tab(
              icon: Icon(Icons.arrow_back),
              text: 'Borrowed',
            ),
            Tab(
              icon: Icon(Icons.arrow_forward),
              text: 'Lent',
            ),
            Tab(
              icon: Icon(Icons.history),
              text: 'History',
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildTabContent(),
          _buildTabContent(),
          _buildTabContent(),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AddDeptPage(
                initialType: _currentIndex == 0 ? DeptType.borrow : DeptType.lend,
              ),
            ),
          ).then((result) {
            if (result == true) {
              _showSnackBar('Record added successfully');
            }
          });
        },
        icon: const Icon(Icons.add),
        label: Text(_currentIndex == 0 ? 'Borrow' : _currentIndex == 1 ? 'Lend' : 'Add'),
        backgroundColor: _currentIndex == 0
            ? Colors.red
            : _currentIndex == 1
            ? Colors.green
            : Colors.blue,
      ),
    );
  }
}