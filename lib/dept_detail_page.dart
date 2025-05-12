// dept_detail_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dept_model.dart';
import 'dept_service.dart';
import 'add_dept_page.dart';

class DeptDetailPage extends StatefulWidget {
  final String recordId;

  const DeptDetailPage({
    Key? key,
    required this.recordId,
  }) : super(key: key);

  @override
  _DeptDetailPageState createState() => _DeptDetailPageState();
}

class _DeptDetailPageState extends State<DeptDetailPage> {
  final DeptService _deptService = DeptService();
  bool _isLoading = true;
  DeptRecord? _record;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadRecord();
  }

  // Load record details
  Future<void> _loadRecord() async {
    try {
      final record = await _deptService.getDeptRecordById(widget.recordId);
      setState(() {
        _record = record;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load: $e';
        _isLoading = false;
      });
    }
  }

  // Show message
// 显示消息
  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 12),
            Text(message),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.only(bottom: 20, left: 20, right: 20),
        duration: const Duration(seconds: 2),
        backgroundColor: _record?.deptType == DeptType.borrow
            ? Colors.red
            : Colors.green,
      ),
    );
  }

  // Confirm full repayment
  Future<void> _confirmFullRepayment() async {
    if (_record == null) return;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Payment'),
        content: Text(
          _record!.deptType == DeptType.borrow
              ? 'Confirm you have paid \$${_record!.amount.toStringAsFixed(2)} to ${_record!.personName}?'
              : 'Confirm ${_record!.personName} has paid you \$${_record!.amount.toStringAsFixed(2)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (result == true) {
      try {
        await _deptService.completeRepayment(widget.recordId);
        _showSnackBar('Record marked as paid');
        // Return to previous page
        if (mounted) {
          Navigator.pop(context);
        }
      } catch (e) {
        _showSnackBar('Failed: $e');
      }
    }
  }

  // Partial repayment
  Future<void> _showPartialRepaymentDialog() async {
    if (_record == null) return;

    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Partial Payment'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _record!.deptType == DeptType.borrow
                    ? 'How much did you pay to ${_record!.personName}?'
                    : 'How much did ${_record!.personName} pay you?',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Amount',
                  border: OutlineInputBorder(),
                  prefixText: '\$ ',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}$')),
                ],
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter an amount';
                  }
                  try {
                    double amount = double.parse(value);
                    if (amount <= 0) {
                      return 'Amount must be greater than 0';
                    }
                    if (amount > _record!.amount) {
                      return 'Amount cannot exceed remaining amount';
                    }
                  } catch (e) {
                    return 'Please enter a valid amount';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                try {
                  final amount = double.parse(controller.text);
                  Navigator.pop(context, amount);
                } catch (e) {
                  // This should not happen due to validation
                }
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (result != null) {
      try {
        await _deptService.partialRepayment(widget.recordId, result);
        _showSnackBar('Partial payment successful');
        // Reload record
        _loadRecord();
      } catch (e) {
        _showSnackBar('Failed: $e');
      }
    }
  }

  // Navigate to edit page
  void _navigateToEditPage() {
    if (_record == null) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddDeptPage(
          initialType: _record!.deptType,
          recordToEdit: _record,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _showSnackBar('Record updated');
        _loadRecord();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Details')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Details')),
        body: Center(child: Text(_errorMessage!)),
      );
    }

    if (_record == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record Details')),
        body: const Center(child: Text('Record not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Details'),
        actions: [
          if (!_record!.isCompleted)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _navigateToEditPage,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            // 状态卡片改进
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              color: _record!.isCompleted
                  ? Colors.green[50]
                  : _record!.deptType == DeptType.borrow
                  ? Colors.red[50]
                  : Colors.blue[50],
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _record!.isCompleted
                            ? Colors.green.withOpacity(0.2)
                            : _record!.deptType == DeptType.borrow
                            ? Colors.red.withOpacity(0.2)
                            : Colors.blue.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _record!.isCompleted
                            ? Icons.check_circle
                            : _record!.deptType == DeptType.borrow
                            ? Icons.arrow_back
                            : Icons.arrow_forward,
                        size: 48,
                        color: _record!.isCompleted
                            ? Colors.green
                            : _record!.deptType == DeptType.borrow
                            ? Colors.red
                            : Colors.blue,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _record!.isCompleted
                          ? 'Completed'
                          : _record!.deptType == DeptType.borrow
                          ? 'Borrowed (I owe)'
                          : 'Lent (They owe me)',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '\$ ${_record!.isCompleted ? _record!.originalAmount.toStringAsFixed(2) : _record!.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_record!.amount != _record!.originalAmount || _record!.isCompleted)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.grey.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'Original: \$ ${_record!.originalAmount.toStringAsFixed(2)}',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Detailed information
            // 详细信息卡片
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, color: Theme.of(context).primaryColor),
                        const SizedBox(width: 8),
                        const Text(
                          'Details',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    _buildImprovedInfoRow(context, 'Person', _record!.personName, Icons.person),
                    _buildImprovedInfoRow(context, 'Due Date',
                        DateFormat('EEEE, MMMM d, yyyy').format(_record!.dueDate),
                        Icons.calendar_today),
                    if (_record!.description.isNotEmpty)
                      _buildImprovedInfoRow(context, 'Description', _record!.description, Icons.description),
                    _buildImprovedInfoRow(context, 'Created',
                        DateFormat('MMMM d, yyyy').format(_record!.createdAt),
                        Icons.access_time),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Action buttons
// 如果记录未完成，显示操作按钮
            if (!_record!.isCompleted) ...[
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _showPartialRepaymentDialog,
                      icon: const Icon(Icons.payment),
                      label: const Text('Partial Payment'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _confirmFullRepayment,
                      icon: const Icon(Icons.check_circle),
                      label: const Text('Mark as Completed'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // Build info row
// 改进的信息行
  Widget _buildImprovedInfoRow(BuildContext context, String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 20, color: Theme.of(context).primaryColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(fontSize: 16),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}