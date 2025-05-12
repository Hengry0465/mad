// dept_model.dart
import 'package:cloud_firestore/cloud_firestore.dart';

enum DeptType {
  borrow, // 借入(我欠别人的)
  lend,   // 借出(别人欠我的)
}

class DeptRecord {
  String? id;
  String? userId;
  String personName;
  double amount;
  double originalAmount; // 原始金额
  DeptType deptType;
  DateTime dueDate;
  String description;
  bool isCompleted;
  DateTime createdAt;
  DateTime? updatedAt;

  DeptRecord({
    this.id,
    this.userId,
    required this.personName,
    required this.amount,
    required this.deptType,
    required this.dueDate,
    this.description = '',
    this.isCompleted = false,
    required this.originalAmount,
    DateTime? createdAt,
    this.updatedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  // 从Firestore文档转换为DeptRecord对象
  factory DeptRecord.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return DeptRecord(
      id: doc.id,
      userId: data['userId'],
      personName: data['personName'],
      amount: data['amount'].toDouble(),
      originalAmount: data['originalAmount'].toDouble(),
      deptType: DeptType.values.firstWhere(
            (e) => e.toString() == data['deptType'],
        orElse: () => DeptType.borrow,
      ),
      dueDate: (data['dueDate'] as Timestamp).toDate(),
      description: data['description'] ?? '',
      isCompleted: data['isCompleted'] ?? false,
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      updatedAt: data['updatedAt'] != null
          ? (data['updatedAt'] as Timestamp).toDate()
          : null,
    );
  }

  // 转换为可以存储在Firestore的Map
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'personName': personName,
      'amount': amount,
      'originalAmount': originalAmount,
      'deptType': deptType.toString(),
      'dueDate': Timestamp.fromDate(dueDate),
      'description': description,
      'isCompleted': isCompleted,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
    };
  }

  // 创建更新后的记录副本
  DeptRecord copyWith({
    String? id,
    String? userId,
    String? personName,
    double? amount,
    double? originalAmount,
    DeptType? deptType,
    DateTime? dueDate,
    String? description,
    bool? isCompleted,
    DateTime? updatedAt,
  }) {
    return DeptRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      personName: personName ?? this.personName,
      amount: amount ?? this.amount,
      originalAmount: originalAmount ?? this.originalAmount,
      deptType: deptType ?? this.deptType,
      dueDate: dueDate ?? this.dueDate,
      description: description ?? this.description,
      isCompleted: isCompleted ?? this.isCompleted,
      createdAt: this.createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }
}