import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:mad/addTransaction.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:mad/history.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Initialize Firebase
  runApp(const Overview());
}

class Overview extends StatelessWidget {
  const Overview({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomePage',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellow),
      ),
      home: const MyHomePage(title: ''),
      routes: {
        '/add': (context) => addTransaction(title: ''),
      },
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  double _incomeTotal = 0.0;
  double _expenseTotal = 0.0;
  double _budgetTotal = 0.0; // Store the budget total
  int currentPageIndex = 0;
  final TextEditingController _budgetController = TextEditingController();

  @override
  void initState() {
    super.initState();
    calculateTotals();
    fetchBudget(); // Fetch the budget on startup
  }

  // Fetch the budget from Firestore
  Future<void> fetchBudget() async {
    var snapshot = await FirebaseFirestore.instance.collection('budgets').doc('budget').get();
    if (snapshot.exists) {
      setState(() {
        _budgetTotal = snapshot['amount'] ?? 0.0;
      });
    }
  }

  // Save budget to Firestore
  Future<void> saveBudget(double budget) async {
    await FirebaseFirestore.instance.collection('budgets').doc('budget').set({
      'amount': budget,
    });
    fetchBudget(); // Refresh budget data
  }

  Future<void> calculateTotals() async {
    double income = 0.0;
    double expense = 0.0;

    // Fetch the transactions from Firebase
    var snapshot = await FirebaseFirestore.instance
        .collection('transactions')
        .get();

    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      bool isExpense = data['isExpense'] ?? true; // Default to expense if field is missing
      double amount = data['amount'] ?? 0.0;

      if (isExpense) {
        expense += amount;
      } else {
        income += amount;
      }
    }

    setState(() {
      _incomeTotal = income;
      _expenseTotal = expense;
    });
  }

  String formatCurrency(double amount) {
    final formatter = NumberFormat.simpleCurrency(locale: 'en_MY');
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
    int currentPageIndex = 0;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Hey there!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const Text("Welcome to MoneyPax", style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 20),
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Current Balance", style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text(
                              formatCurrency(_incomeTotal - _expenseTotal),
                              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const Icon(Icons.account_balance_wallet, color: Colors.blue, size: 32),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Icon(Icons.arrow_upward, color: Colors.green),
                            const SizedBox(height: 4),
                            const Text("Income"),
                            Text(
                              formatCurrency(_incomeTotal),
                              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    )),

                    Expanded(child: Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(padding: const EdgeInsets.all(16.0),
                        child: Column(
                          children: [
                            const Icon(Icons.arrow_downward, color: Colors.red),
                            const SizedBox(height: 4),
                            const Text("Expenses"),
                            Text(
                              formatCurrency(_expenseTotal),
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                      ),
                    )),
                  ],
                ),
                const SizedBox(height: 16),

                // In the Card widget for Budget (replace the existing Card widget)
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Budget", style: TextStyle(color: Colors.grey)),
                                const SizedBox(height: 8),
                                Text(
                                  formatCurrency(_budgetTotal),
                                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.blue),
                              onPressed: () {
                                showDialog(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: const Text('Set Budget'),
                                    content: TextField(
                                      controller: _budgetController,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                        labelText: 'Enter Budget',
                                        prefixText: 'RM ',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.pop(context),
                                        child: const Text('Cancel'),
                                      ),
                                      TextButton(
                                        onPressed: () {
                                          if (_budgetController.text.isNotEmpty &&
                                              RegExp(r'^\d+(\.\d+)?$').hasMatch(_budgetController.text)) {
                                            saveBudget(double.parse(_budgetController.text));
                                            Navigator.pop(context);
                                          } else {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              const SnackBar(content: Text('Please enter a valid amount')),
                                            );
                                          }
                                        },
                                        child: const Text('Save'),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Add budget status indicator
                        Builder(
                          builder: (context) {
                            double currentBalance = _incomeTotal - _expenseTotal;
                            double budgetDifference = _budgetTotal - currentBalance;

                            if (_budgetTotal == 0) {
                              return const Text(
                                "No budget set",
                                style: TextStyle(color: Colors.grey),
                              );
                            } else if (budgetDifference >= 0) {
                              return Text(
                                "You have RM${budgetDifference.toStringAsFixed(2)} remaining",
                                style: const TextStyle(color: Colors.green),
                              );
                            } else {
                              return Text(
                                "You exceeded budget by RM${(-budgetDifference).toStringAsFixed(2)}",
                                style: const TextStyle(color: Colors.red),
                              );
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text("Recent Transactions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18 )),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<QuerySnapshot>(
                    stream: FirebaseFirestore.instance
                        .collection('transactions')
                        .orderBy('date', descending: true)
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return const Center(child: Text('Error fetching transactions.'));
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Center(child: Text('No transactions recorded.'));
                      }

                      final transactions = snapshot.data!.docs;

                      return ListView.builder(
                        itemCount: transactions.length,
                        itemBuilder: (context, index) {
                          var transaction = transactions[index];
                          var data = transaction.data() as Map<String, dynamic>;

                          var timestamp = data['date'];
                          DateTime transactionDate = timestamp is Timestamp
                              ? timestamp.toDate()
                              : DateTime.tryParse(timestamp) ?? DateTime.now();
                          String formattedDate = DateFormat('yyyy-MM-dd').format(transactionDate);

                          bool isExpense = data['isExpense'] ?? true;

                          return ListTile(
                            title: Text(data['title'] ?? 'No Title'),
                            subtitle: Text('${data['category'] ?? 'No Category'} - $formattedDate'),
                            trailing: Text(
                              'RM ${data['amount']?.toStringAsFixed(2) ?? '0.00'}',
                              style: TextStyle(
                                color: isExpense ? Colors.red : Colors.green,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            leading: Icon(
                              isExpense ? Icons.remove_circle : Icons.add_circle,
                              color: isExpense ? Colors.red : Colors.green,
                            ),
                          );
                        },
                      );
                    },
                  ),
                )
              ]
          ),
        ),
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
                  context, MaterialPageRoute(builder: (context) => const Overview()),
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
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const History()),
                );
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
