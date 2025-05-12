// dept_service.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dept_model.dart';
import 'notification_service.dart';

class DeptService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Get current user ID
  String? get currentUserId => _auth.currentUser?.uid;

  // Add new debt record
  Future<String> addDeptRecord(DeptRecord record) async {
    try {
      if (currentUserId == null) {
        throw Exception('User not logged in');
      }

      // Set user ID
      record = record.copyWith(userId: currentUserId);

      // Add to Firestore
      DocumentReference docRef = await _firestore
          .collection('dept_records')
          .add(record.toFirestore());

      return docRef.id;
    } catch (e) {
      throw Exception('Failed to add record: $e');
    }
  }

  // Update debt record
  Future<void> updateDeptRecord(DeptRecord record) async {
    try {
      if (record.id == null) {
        throw Exception('Record ID cannot be null');
      }

      await _firestore
          .collection('dept_records')
          .doc(record.id)
          .update(record.toFirestore());
    } catch (e) {
      throw Exception('Failed to update record: $e');
    }
  }

  // Partial repayment
  Future<void> partialRepayment(String recordId, double repayAmount) async {
    try {
      // Start transaction
      return _firestore.runTransaction((transaction) async {
        // Get current record
        DocumentReference recordRef = _firestore.collection('dept_records').doc(recordId);
        DocumentSnapshot snapshot = await transaction.get(recordRef);

        if (!snapshot.exists) {
          throw Exception('Record does not exist');
        }

        DeptRecord record = DeptRecord.fromFirestore(snapshot);

        if (repayAmount > record.amount) {
          throw Exception('Repayment amount cannot exceed remaining amount');
        }

        // Calculate remaining amount
        double remainingAmount = record.amount - repayAmount;

        // If remaining amount is 0, mark as completed
        bool isCompleted = remainingAmount <= 0;

        // Update record
        transaction.update(recordRef, {
          'amount': remainingAmount,
          'isCompleted': isCompleted,
          'updatedAt': Timestamp.now(),
        });
      });
    } catch (e) {
      throw Exception('Partial repayment failed: $e');
    }
  }

  // Complete repayment
  Future<void> completeRepayment(String recordId) async {
    try {
      // Cancel notifications for this record
      await NotificationService.cancelNotification(recordId);

      await _firestore
          .collection('dept_records')
          .doc(recordId)
          .update({
        'isCompleted': true,
        'amount': 0,
        'updatedAt': Timestamp.now(),
      });
    } catch (e) {
      throw Exception('Complete repayment failed: $e');
    }
  }

  // Delete debt record
  Future<void> deleteDeptRecord(String recordId) async {
    try {
      // Cancel notifications for this record
      await NotificationService.cancelNotification(recordId);

      // Delete record from Firestore
      await _firestore
          .collection('dept_records')
          .doc(recordId)
          .delete();
    } catch (e) {
      throw Exception('Failed to delete record: $e');
    }
  }


  // Get all debt records (filtered by type and completion status)
  Stream<List<DeptRecord>> getDeptRecords({
    DeptType? deptType,
    bool? isCompleted,
  }) {
    if (currentUserId == null) {
      return Stream.value([]);
    }

    Query query = _firestore
        .collection('dept_records')
        .where('userId', isEqualTo: currentUserId);

    if (deptType != null) {
      query = query.where('deptType', isEqualTo: deptType.toString());
    }

    if (isCompleted != null) {
      query = query.where('isCompleted', isEqualTo: isCompleted);
    }

    return query
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs
          .map((doc) => DeptRecord.fromFirestore(doc))
          .toList();
    });
  }

  // Get single debt record by ID
  Future<DeptRecord?> getDeptRecordById(String recordId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('dept_records')
          .doc(recordId)
          .get();

      if (doc.exists) {
        return DeptRecord.fromFirestore(doc);
      } else {
        return null;
      }
    } catch (e) {
      throw Exception('Failed to get record: $e');
    }
  }

  // Improved method to check and send due notifications
  Future<void> checkAndSendDueNotifications() async {
    if (currentUserId == null) return;

    try {
      print('Checking for due and overdue records...');
      // Get all uncompleted records
      final snapshot = await _firestore
          .collection('dept_records')
          .where('userId', isEqualTo: currentUserId)
          .where('isCompleted', isEqualTo: false)
          .get();

      final records = snapshot.docs
          .map((doc) => DeptRecord.fromFirestore(doc))
          .toList();

      // Check for today's and overdue records
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      // Find records due today, tomorrow or already overdue
      final dueRecords = records.where((record) {
        final dueDate = DateTime(
          record.dueDate.year,
          record.dueDate.month,
          record.dueDate.day,
        );

        // Due today, tomorrow or overdue
        return dueDate.compareTo(tomorrow) <= 0;
      }).toList();

      print('Found ${dueRecords.length} records due today/tomorrow or overdue');

      // Send notifications for all due records
      for (final record in dueRecords) {
        final dueDate = DateTime(
            record.dueDate.year,
            record.dueDate.month,
            record.dueDate.day
        );

        final isOverdue = dueDate.isBefore(today);
        final isDueToday = dueDate.isAtSameMomentAs(today);
        final isDueTomorrow = dueDate.isAtSameMomentAs(tomorrow);

        await NotificationService.sendDueNotification(
            record,
            isOverdue: isOverdue,
            isDueToday: isDueToday,
            isDueTomorrow: isDueTomorrow
        );
      }

      return;
    } catch (e) {
      print('Error checking due notifications: $e');
      throw Exception('Failed to check due notifications: $e');
    }
  }

  // Get all records that are due or overdue
  Future<List<DeptRecord>> getDueRecords() async {
    if (currentUserId == null) {
      return [];
    }

    try {
      final snapshot = await _firestore
          .collection('dept_records')
          .where('userId', isEqualTo: currentUserId)
          .where('isCompleted', isEqualTo: false)
          .get();

      final allRecords = snapshot.docs
          .map((doc) => DeptRecord.fromFirestore(doc))
          .toList();

      // Filter for records due today or overdue
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));

      return allRecords.where((record) {
        final dueDate = DateTime(
          record.dueDate.year,
          record.dueDate.month,
          record.dueDate.day,
        );
        return dueDate.compareTo(tomorrow) <= 0;
      }).toList();
    } catch (e) {
      print('Failed to get due records: $e');
      return [];
    }
  }
}