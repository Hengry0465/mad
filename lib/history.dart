import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:mad/addTransaction.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(); // Initialize Firebase
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'HomePage',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.yellow),
      ),
      home: const MyHomePage(title: ''),
      routes: {
        '/add': (context) => addTransaction(title: '',),
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
  final List<Map<String, dynamic>> transactions = [
    // Empty for now. Add example data if needed.
  ];

  final double incomeTotal = 0.00;
  final double expenseTotal = 0.00;

  String formatCurrency(double amount) {
    return 'RM ${amount.toStringAsFixed(2)}';
  }

  @override
  void initState() {
    super.initState();
    calculateTotals();
  }

  Future<void> calculateTotals() async {
    final snapshot = await FirebaseFirestore.instance.collection('transactions').get();
    double income = 0.0;
    double expenses = 0.0;

    for (var doc in snapshot.docs) {
      final data = doc.data();
      final type = data['type'];
      final amount = data['amount'] ?? 0.0;

      if (type == 'Income') {
        income += amount;
      } else if (type == 'Expense') {
        expenses += amount;
      }
    }

  }

  @override
  Widget build(BuildContext context) {
    final double balance = incomeTotal - expenseTotal;
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
                  child: Padding(padding: const EdgeInsets.all(16.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text("Current Balance", style: TextStyle(color: Colors.grey)),
                            const SizedBox(height: 8),
                            Text(
                              formatCurrency(balance),
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
                              formatCurrency(incomeTotal),
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
                                formatCurrency(expenseTotal),
                                style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ],
                          ),
                        ))
                    ),
                  ],
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

                          // Retrieve the transaction date
                          var timestamp = data['date'];
                          DateTime transactionDate = timestamp is Timestamp
                              ? timestamp.toDate()
                              : DateTime.tryParse(timestamp) ?? DateTime.now();
                          String formattedDate = DateFormat('yyyy-MM-dd').format(transactionDate);

                          // Determine if the transaction is an expense or income
                          bool isExpense = data['isExpense'] ?? true; // Default to expense if field is missing

                          return ListTile(
                            title: Text(data['title'] ?? 'No Title'),
                            subtitle: Text(
                                '${data['category'] ?? 'No Category'} - $formattedDate'),
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
