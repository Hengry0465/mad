import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:mad/addTransaction.dart';
import 'package:mad/history.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'accountmodule/profile_screen.dart';
import 'all_report.dart';
import 'dept.dart';
import 'dept_service.dart';
import 'permission_dialog.dart';
import 'notification_service.dart';
import 'report_page.dart';

// 主导航控制器
class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  _MainNavigationScreenState createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();

    // 初始化页面列表
    _pages = [
      const MyHomePage(title: ''),
      const addTransaction(title: ''),
      const History(),
      DeptPage(),
      const AllReportPage(),
    ];

    // 应用启动时直接请求权限
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await PermissionDialog.requestNotificationPermission();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        selectedItemColor: Colors.amber,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_outlined),
            label: 'Add',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.wallet),
            label: 'History',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.monetization_on), // 修改为money图标
            label: 'Dept', // 修改为Dept文本
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.bar_chart), // 交换位置到最后
            label: 'Report',
          ),
        ],
      ),
    );
  }
}

// 简化后的Overview类
class Overview extends StatelessWidget {
  const Overview({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // 直接返回MyHomePage
    return const MyHomePage(title: '');
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  double _incomeTotal = 0.0;
  double _expenseTotal = 0.0;
  double _budgetTotal = 0.0;
  final TextEditingController _budgetController = TextEditingController();
  User? _user;
  final DeptService _deptService = DeptService();
  bool _notificationsEnabled = false;

  // 跟踪是否已经检查过通知
  static bool _hasCheckedNotifications = false;

  @override
  void initState() {
    super.initState();
    calculateTotals();
    fetchBudget();
    _user = FirebaseAuth.instance.currentUser;

    // 仅在首次加载时执行通知检查
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_hasCheckedNotifications) {
        await _checkNotificationStatus();

        // 只在首次检查时发送到期通知
        if (_user != null && _notificationsEnabled) {
          await _checkAndSendDueNotifications();
        }

        _hasCheckedNotifications = true;
      }
    });
  }

  // 检查通知权限状态
  Future<void> _checkNotificationStatus() async {
    final status = await PermissionDialog.isNotificationPermissionGranted();
    setState(() {
      _notificationsEnabled = status;
    });
  }

  // 检查并发送到期通知
  Future<void> _checkAndSendDueNotifications() async {
    try {
      print('Checking for due records...');
      await _deptService.checkAndSendDueNotifications();
      print('Due record check completed');
    } catch (e) {
      print('Failed to check due records: $e');
    }
  }

  // 获取预算
  Future<void> fetchBudget() async {
    try {
      var snapshot = await FirebaseFirestore.instance.collection('budgets').doc('budget').get();
      if (snapshot.exists) {
        setState(() {
          _budgetTotal = snapshot['amount'] ?? 0.0;
        });
      }
    } catch (e) {
      print('Error fetching budget: $e');
    }
  }

  // 保存预算
  Future<void> saveBudget(double budget) async {
    try {
      await FirebaseFirestore.instance.collection('budgets').doc('budget').set({
        'amount': budget,
      });
      fetchBudget();
    } catch (e) {
      print('Error saving budget: $e');
    }
  }

  // 计算总额
  Future<void> calculateTotals() async {
    try {
      double income = 0.0;
      double expense = 0.0;

      var snapshot = await FirebaseFirestore.instance
          .collection('transactions')
          .get();

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        bool isExpense = data['isExpense'] ?? true;
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
    } catch (e) {
      print('Error calculating totals: $e');
    }
  }

  String formatCurrency(double amount) {
    final formatter = NumberFormat.simpleCurrency(locale: 'en_MY');
    return formatter.format(amount);
  }

  @override
  Widget build(BuildContext context) {
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
                // 顶部行：问候语和两个导航按钮
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // 左侧问候语
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text("Hey there!", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                        Text("Welcome to MoneyPax", style: TextStyle(fontSize: 16, color: Colors.grey)),
                      ],
                    ),
                    // 右侧两个导航按钮
                    Row(
                      children: [
                        // 上传按钮
                        IconButton(
                          icon: const Icon(Icons.cloud_upload, color: Colors.blue),
                          onPressed: () {
                            // 导航到上传页面的占位
                          },
                        ),
                        // 个人资料按钮
                        IconButton(
                          icon: const Icon(Icons.person, color: Colors.blue),
                          onPressed: () {
                            Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const ProfileScreen()),);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
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

                // 预算卡片
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
                        // 预算状态指示器
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
                const Text("Recent Transactions", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
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
    );
  }
}