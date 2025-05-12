// allreport.dart
import 'package:flutter/material.dart';
import 'report_page.dart';
import 'reportpage.dart';

class AllReportPage extends StatefulWidget {
  const AllReportPage({Key? key}) : super(key: key);

  @override
  _AllReportPageState createState() => _AllReportPageState();
}

class _AllReportPageState extends State<AllReportPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Financial Reports'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56.0),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withOpacity(0.2),
                  spreadRadius: 1,
                  blurRadius: 2,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: TabBar(
              controller: _tabController,
              indicatorColor: Colors.amber,
              labelColor: Colors.amber,
              unselectedLabelColor: Colors.grey,
              labelStyle: const TextStyle(fontWeight: FontWeight.bold),
              tabs: const [
                Tab(
                  icon: Icon(Icons.receipt_long),
                  text: "Transaction Report",
                ),
                Tab(
                  icon: Icon(Icons.monetization_on),
                  text: "Debt Report",
                ),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [


          // 已实现的 Dept Report
          const ReportPage(),
          const DeptReportPage(),
        ],
      ),
    );
  }
}