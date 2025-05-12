import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:mad/history.dart';
import 'package:mad/overview.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Initialize Firebase
  runApp(const AddTransaction());
}

class AddTransaction extends StatelessWidget {
  const AddTransaction({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AddTransaction',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellow),
      ),
      home: addTransaction(title: 'AddTransaction'),
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
  int currentPageIndex = 1;
  DateTime? _selectedDate = DateTime.now(); // Set the default date to current date

  final List<String> expenseCategories = [
    "Food", "Shopping", "Grocery", "Transportation", "Entertainment",
    "Housing", "Medical", "Car", "Other"
  ];
  final List<String> incomeCategories = [
    "Salary", "Part Time", "Financial Management", "Gift Money", "Other"
  ];

  @override
  void initState() {
    super.initState();
    _selectedCategory = expenseCategories.first;
  }

  Future<void> addTransaction() async {
    String title = _titleController.text.trim();
    String amountText = _amountController.text.trim();
    String description = _descriptionController.text.trim();
    String category = _selectedCategory;

    if (title.isEmpty || amountText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter both title and amount.')),
      );
      return;
    }

    double? amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount.')),
      );
      return;
    }

    // Clear the input fields after successful validation
    _titleController.clear();
    _amountController.clear();
    _descriptionController.clear();

    // Store the data in Firestore
    try {
      await FirebaseFirestore.instance.collection('transactions').add({
        'title': title,
        'amount': amount,
        'description': description,
        'category': category,
        'date': _selectedDate?.toIso8601String(),
        'isExpense': isExpense,
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$title added successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to add transaction: $e')),
      );
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    DateTime currentDate = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: currentDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
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
        child: Column(children: [
          Row(children: [
            Expanded(
              child: GestureDetector(
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
                    child: Text('Expense', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: GestureDetector(
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
                    child: Text('Income', style: TextStyle(color: Colors.white)),
                  ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: TextEditingController(
                    text: DateFormat('yyyy-MM-dd').format(_selectedDate!),
                  ),
                  readOnly: true,  // Make the text field non-editable
                  decoration: InputDecoration(
                    labelText: 'Date',
                    hintText: 'Select a date',
                    prefixIcon: Icon(Icons.calendar_today), // Add a calendar icon
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(vertical: 15.0, horizontal: 10.0), // Add padding for better visual
                  ),
                  onTap: () => _selectDate(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _amountController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount',
              prefixText: 'RM ',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: _selectedCategory,
            items: (isExpense ? expenseCategories : incomeCategories).map((String category) {
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
          const SizedBox(height: 10),
          TextField(
            controller: _descriptionController,
            decoration: const InputDecoration(
              labelText: 'Description (Optional)',
              border: OutlineInputBorder(),
            ),
            maxLines: 2,
          ),
          const SizedBox(height: 10),
          ElevatedButton(
            onPressed: addTransaction,
            child: Text(isExpense ? "Add Expense" : "Add Income"),
          ),
          const SizedBox(height: 20),
        ]),
      ),
    );
  }
}
