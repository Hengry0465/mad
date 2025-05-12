// add_dept_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dept_model.dart';
import 'dept_service.dart';

class AddDeptPage extends StatefulWidget {
  final DeptType initialType;
  final DeptRecord? recordToEdit;

  const AddDeptPage({
    Key? key,
    required this.initialType,
    this.recordToEdit,
  }) : super(key: key);

  @override
  _AddDeptPageState createState() => _AddDeptPageState();
}

class _AddDeptPageState extends State<AddDeptPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  late DeptType _selectedType;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 7));
  final DeptService _deptService = DeptService();
  bool _isLoading = false;
  bool _isEditing = false;

  // Color schemes based on type
  final Map<DeptType, ColorScheme> _typeColorSchemes = {
    DeptType.borrow: ColorScheme.fromSeed(
      seedColor: Colors.red,
      brightness: Brightness.light,
    ),
    DeptType.lend: ColorScheme.fromSeed(
      seedColor: Colors.green,
      brightness: Brightness.light,
    ),
  };

  // Get current color scheme based on selected type
  ColorScheme get _currentColorScheme => _typeColorSchemes[_selectedType]!;

  @override
  void initState() {
    super.initState();
    _selectedType = widget.initialType;

    // If editing mode, populate existing data
    if (widget.recordToEdit != null) {
      _isEditing = true;
      _nameController.text = widget.recordToEdit!.personName;
      _amountController.text = widget.recordToEdit!.amount.toString();
      _descriptionController.text = widget.recordToEdit!.description;
      _selectedType = widget.recordToEdit!.deptType;
      _selectedDate = widget.recordToEdit!.dueDate;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // 选择日期
  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2100),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: _currentColorScheme,
            dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  // Save record
  Future<void> _saveRecord() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final double amount = double.parse(_amountController.text);

        if (_isEditing) {
          // Update existing record
          final updatedRecord = widget.recordToEdit!.copyWith(
            personName: _nameController.text.trim(),
            amount: amount,
            deptType: _selectedType,
            dueDate: _selectedDate,
            description: _descriptionController.text.trim(),
          );

          await _deptService.updateDeptRecord(updatedRecord);
        } else {
          // Create new record
          final newRecord = DeptRecord(
            personName: _nameController.text.trim(),
            amount: amount,
            originalAmount: amount,
            deptType: _selectedType,
            dueDate: _selectedDate,
            description: _descriptionController.text.trim(),
          );

          // Save to database
          await _deptService.addDeptRecord(newRecord);
        }

        // Return to previous page
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        // Show error
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  // Build decorated text field
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? prefixText,
    String? hintText,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
    int maxLines = 1,
    int? maxLength,
    String? Function(String?)? validator,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixText: prefixText,
          prefixIcon: Icon(icon, color: _currentColorScheme.primary),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _currentColorScheme.outline),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _currentColorScheme.outline.withOpacity(0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: _currentColorScheme.primary, width: 2),
          ),
          filled: true,
          fillColor: _currentColorScheme.surface,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
        style: TextStyle(color: _currentColorScheme.onSurface),
        keyboardType: keyboardType,
        inputFormatters: inputFormatters,
        maxLines: maxLines,
        maxLength: maxLength,
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageTitle = _isEditing ? 'Edit Record' : 'Add Record';
    final buttonText = _isEditing ? 'Update' : 'Save';

    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: _currentColorScheme,
        appBarTheme: AppBarTheme(
          backgroundColor: _currentColorScheme.primary,
          foregroundColor: _currentColorScheme.onPrimary,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          labelStyle: TextStyle(color: _currentColorScheme.primary),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(pageTitle),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: SafeArea(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Type selection card
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Select Type',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SegmentedButton<DeptType>(
                            segments: [
                              ButtonSegment<DeptType>(
                                value: DeptType.borrow,
                                label: const Text('Borrowed'),
                                icon: Icon(
                                  Icons.arrow_back,
                                  color: _typeColorSchemes[DeptType.borrow]!.primary,
                                ),
                              ),
                              ButtonSegment<DeptType>(
                                value: DeptType.lend,
                                label: const Text('Lent'),
                                icon: Icon(
                                  Icons.arrow_forward,
                                  color: _typeColorSchemes[DeptType.lend]!.primary,
                                ),
                              ),
                            ],
                            selected: {_selectedType},
                            onSelectionChanged: (Set<DeptType> newSelection) {
                              setState(() {
                                _selectedType = newSelection.first;
                              });
                            },
                            style: ButtonStyle(
                              backgroundColor: MaterialStateProperty.resolveWith<Color?>(
                                    (Set<MaterialState> states) {
                                  if (states.contains(MaterialState.selected)) {
                                    return _currentColorScheme.primaryContainer;
                                  }
                                  return null;
                                },
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Description of the selected type
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _currentColorScheme.primaryContainer.withOpacity(0.3),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  _selectedType == DeptType.borrow
                                      ? Icons.info_outline
                                      : Icons.info_outline,
                                  color: _currentColorScheme.primary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _selectedType == DeptType.borrow
                                        ? 'You borrowed money and need to pay it back'
                                        : 'You lent money and expect to be paid back',
                                    style: TextStyle(
                                      color: _currentColorScheme.onSurface,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Person name field
                  _buildTextField(
                    controller: _nameController,
                    label: 'Person Name',
                    hintText: 'Who is involved in this transaction?',
                    icon: Icons.person,
                    maxLength: 50,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Please enter a name';
                      }
                      if (value.trim().length > 50) {
                        return 'Name cannot exceed 50 characters';
                      }
                      return null;
                    },
                  ),

                  // Amount field
                  _buildTextField(
                    controller: _amountController,
                    label: 'Amount',
                    hintText: 'Enter the amount',
                    prefixText: '\$ ',
                    icon: Icons.attach_money,
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
                        if (amount.isNaN || amount.isInfinite) {
                          return 'Please enter a valid amount';
                        }
                      } catch (e) {
                        return 'Please enter a valid amount';
                      }
                      return null;
                    },
                  ),

                  // Due date field
                  Container(
                    margin: const EdgeInsets.only(bottom: 20),
                    child: InkWell(
                      onTap: () => _selectDate(context),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: _currentColorScheme.outline.withOpacity(0.5),
                          ),
                          borderRadius: BorderRadius.circular(12),
                          color: _currentColorScheme.surface,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              color: _currentColorScheme.primary,
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Due Date',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: _currentColorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w500,
                                    color: _currentColorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            Icon(
                              Icons.arrow_drop_down,
                              color: _currentColorScheme.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Description field
                  _buildTextField(
                    controller: _descriptionController,
                    label: 'Description (Optional)',
                    hintText: 'Add more details about this transaction',
                    icon: Icons.description,
                    maxLines: 3,
                    maxLength: 200,
                    validator: (value) {
                      if (value != null && value.length > 200) {
                        return 'Description cannot exceed 200 characters';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 24),

                  // Buttons
                  Row(
                    children: [
                      // Cancel button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : () => Navigator.pop(context),
                          icon: const Icon(Icons.cancel),
                          label: const Text('Cancel'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[300],
                            foregroundColor: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),

                      // Save/Update button
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isLoading ? null : _saveRecord,
                          icon: Icon(_isEditing ? Icons.update : Icons.save),
                          label: _isLoading
                              ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                _currentColorScheme.onPrimary,
                              ),
                            ),
                          )
                              : Text(buttonText),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _currentColorScheme.primary,
                            foregroundColor: _currentColorScheme.onPrimary,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}