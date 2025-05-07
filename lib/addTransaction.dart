import 'package:flutter/material.dart';
import 'dart:async';
import 'package:mad/main.dart';

void main() {
  runApp(const AddTransaction());
}

class AddTransaction extends StatelessWidget {
  const AddTransaction({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AddTransaction',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber),
      ),
      home: addTransaction(title: 'AddTransaction'),
      routes: {
        '/add': (context) => addTransaction(title: '',),
      },
    );
  }
}

class addTransaction extends StatefulWidget {
  const addTransaction({super.key, required this.title});

  final String title;

  @override
  State<addTransaction> createState() => _addTransaction();
}

class _addTransaction extends State<addTransaction> {
  bool isExpense = true;
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  String _selectedCategory = "";
  DateTime _selectedDate = DateTime.now();
  int currentPageIndex = 0;

  final List<Map<String, dynamic>> _transactions = [];

  final List<String> expenseCategories = [
    "Food",
    "Shopping",
    "Grocery",
    "Transportation",
    "Entertainment",
    "Housing",
    "Medical",
    "Car",
    "Other"
  ];
  final List<String> incomeCategories = [
    "Salary",
    "Part Time",
    "Financial Management",
    "Gift Money",
    "Other"
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = expenseCategories.first;
  }

  void main() {
    var obj = _addTransaction; // Calls the default constructor
  }

  // Function to pick a date
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: _selectedDate,
        firstDate: DateTime(2015, 8),
        lastDate: DateTime(2101));
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  void addTransaction() {
    String title = _titleController.text.trim();
    String amountText = _amountController.text.trim();
    String description = _descriptionController.text.trim();
    String category = _selectedCategory;

    if (title.isEmpty || amountText.isEmpty) {
      // Validation: Title and Amount are required
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter both title and amount.'),
        ),
      );
      return;
    }

    double? amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      // Validation: Amount must be a positive number
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid amount.'),
        ),
      );
      return;
    }

    // Add transaction to the simulated database
    _transactions.add({
      'title': title,
      'amount': amount,
      'category': category,
      'description': description.isNotEmpty ? description : "No description",
      'date': _selectedDate,
      'type': isExpense ? "Expense" : "Income",
    });

    // Sort the transactions by date (latest first)
    _transactions.sort((a, b) => b['date'].compareTo(a['date']));

    print("Transactions Database: $_transactions");

    // Clear form fields after adding
    _titleController.clear();
    _amountController.clear();
    _descriptionController.clear();
    setState(() {
      _selectedCategory = isExpense ? expenseCategories.first : incomeCategories.first;
      _selectedDate = DateTime.now();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$title added successfully!'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Transaction'),
        backgroundColor: Colors.amber,
      ),
      body: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Record a new expense or income:',
                  style: TextStyle(fontSize: 20, color: Colors.black),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child:
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          isExpense = true;
                          _selectedCategory = expenseCategories.first;
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: isExpense ? Colors.red : Colors.grey.shade300,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(8),
                            bottomLeft: Radius.circular(8),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: const Center(
                          child: Text(
                            'Expense',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    )
                    ),
                    Expanded(child:
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          isExpense = false;
                          _selectedCategory = incomeCategories.first;
                        });
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: !isExpense ? Colors.green : Colors.grey.shade300,
                          borderRadius: const BorderRadius.only(
                            topRight: Radius.circular(8),
                            bottomRight: Radius.circular(8),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: const Center(
                          child: Text(
                            'Income',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    )
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Title Field
                TextField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                // Amount Field
                TextField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixText: 'RM ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                // Category Dropdown
                DropdownButtonFormField<String>(
                  value: _selectedCategory,
                  items: (isExpense ? expenseCategories : incomeCategories)
                      .map((String category) {
                    return DropdownMenuItem<String>(
                      value: category,
                      child: Text(category),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedCategory = newValue!;
                    });
                  },
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),

                // Description Field (Optional)
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),

                // Date Picker
                Text("${_selectedDate.toLocal()}".split(' ')[0]),
                ElevatedButton(
                  onPressed: () => _selectDate(context),
                  child: const Text('Select date'),
                ),
                const SizedBox(height: 8),

                // Add Transaction Button
                ElevatedButton(
                  onPressed: addTransaction,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size.fromHeight(50),
                  ),
                  child: Text(isExpense ? "Add Expense" : "Add Income"),
                ),
              ])
      ),
      bottomNavigationBar: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () {
                Navigator.push(
                  context, MaterialPageRoute(builder: (context) => const MyApp()),
                );
              },
              color: currentPageIndex == 0 ? Colors.amber : Colors.grey,
            ),
            IconButton(
              icon: const Icon(Icons.add_outlined),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const AddTransaction()),
                );
              },
              color: currentPageIndex == 1 ? Colors.amber : Colors.grey,
            ),
            IconButton(
              icon: const Icon(Icons.wallet),
              onPressed: () {
                setState(() {
                  currentPageIndex = 2;
                });
              },
              color: currentPageIndex == 2 ? Colors.amber : Colors.grey,
            ),
            IconButton(
              icon: const Icon(Icons.report),
              onPressed: () {
                setState(() {
                  currentPageIndex = 3;
                });
              },
              color: currentPageIndex == 3 ? Colors.amber : Colors.grey,
            ),
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () {
                setState(() {
                  currentPageIndex = 4;
                });
              },
              color: currentPageIndex == 4 ? Colors.amber : Colors.grey,
            ),
          ],
        ),
      ),
    );
  }
}
