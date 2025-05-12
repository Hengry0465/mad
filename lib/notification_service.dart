// notification_service.dart
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tzdata;
import 'dart:io' show Platform;
import 'dept_model.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:ui';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _notifications =
  FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  // Initialize notification service
  static Future<void> initialize() async {
    if (_initialized) return;

    // Initialize timezone data
    tzdata.initializeTimeZones();

    print('Initializing notification service...');

    // Android settings
    const AndroidInitializationSettings androidSettings =
    AndroidInitializationSettings('@mipmap/ic_launcher');

    // iOS settings
    const DarwinInitializationSettings iosSettings =
    DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      settings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        print('Received notification response: ${response.payload}');
      },
    );

    // Create notification channel
    await _createNotificationChannel();

    _initialized = true;
    print('Notification service initialized');
  }

  // Create notification channel
  static Future<void> _createNotificationChannel() async {
    if (Platform.isAndroid) {
      const AndroidNotificationChannel channel = AndroidNotificationChannel(
        'debt_due_channel',
        'Debt Due Reminders',
        description: 'Notifications for due debts',
        importance: Importance.high,
        playSound: true,
        enableVibration: true,
      );

      await _notifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);

      print('Notification channel created');
    }
  }

  // Check if notification permission is granted
  static Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      return await Permission.notification.isGranted;
    }
    return true; // Assume enabled on iOS for simplicity
  }

  // Send notification for due record
  static Future<void> sendDueNotification(
      DeptRecord record, {
        bool isOverdue = false,
        bool isDueToday = false,
        bool isDueTomorrow = false,
      }) async {
    if (record.id == null) return;

    if (!await areNotificationsEnabled()) {
      print('Notifications disabled. Skipping notification for record ${record.id}');
      return;
    }

    await initialize();

    try {
      final androidDetails = AndroidNotificationDetails(
        'debt_due_channel',
        'Debt Due Reminders',
        channelDescription: 'Notifications for due debts',
        importance: Importance.max,
        priority: Priority.high,
        color: record.deptType == DeptType.borrow ?
        const Color.fromARGB(255, 244, 67, 54) :  // Red for borrow
        const Color.fromARGB(255, 76, 175, 80),   // Green for lend
        styleInformation: BigTextStyleInformation(''),
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Set notification content based on status and type
      String title;
      String body;

      final isBorrowed = record.deptType == DeptType.borrow;
      final formattedAmount = record.amount.toStringAsFixed(2);

      if (isOverdue) {
        title = isBorrowed ? 'Overdue Payment' : 'Overdue Collection';
        body = isBorrowed
            ? 'Your payment of \$${formattedAmount} to ${record.personName} is overdue'
            : '${record.personName} owes you \$${formattedAmount} and payment is overdue';
      } else if (isDueToday) {
        title = isBorrowed ? 'Payment Due Today' : 'Collection Due Today';
        body = isBorrowed
            ? 'Your payment of \$${formattedAmount} to ${record.personName} is due today'
            : '${record.personName} owes you \$${formattedAmount} due today';
      } else {
        title = isBorrowed ? 'Payment Due Tomorrow' : 'Collection Due Tomorrow';
        body = isBorrowed
            ? 'Your payment of \$${formattedAmount} to ${record.personName} is due tomorrow'
            : '${record.personName} owes you \$${formattedAmount} due tomorrow';
      }

      // Add description if available
      if (record.description.isNotEmpty) {
        body += '\nDetails: ${record.description}';
      }

      // Show notification immediately
      await _notifications.show(
        record.id.hashCode,
        title,
        body,
        platformDetails,
        payload: record.id,
      );

      print('Notification sent for record: ${record.id}');
    } catch (e) {
      print('Failed to send notification: $e');
    }
  }

  // Schedule due notification for a record
  static Future<void> scheduleDueNotification(DeptRecord record) async {
    if (record.id == null) return;

    if (!await areNotificationsEnabled()) {
      print('Notifications disabled. Skipping scheduled notification for record ${record.id}');
      return;
    }

    await initialize();

    try {
      final androidDetails = AndroidNotificationDetails(
        'debt_due_channel',
        'Debt Due Reminders',
        channelDescription: 'Notifications for due debts',
        importance: Importance.max,
        priority: Priority.high,
        color: record.deptType == DeptType.borrow ?
        const Color.fromARGB(255, 244, 67, 54) :  // Red for borrow
        const Color.fromARGB(255, 76, 175, 80),   // Green for lend
      );

      final iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      );

      final platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Get current time
      final now = tz.TZDateTime.now(tz.local);

      // Schedule for 9:00 AM on due date
      final scheduledDate = tz.TZDateTime(
          tz.local,
          record.dueDate.year,
          record.dueDate.month,
          record.dueDate.day,
          9, 0, 0  // 9:00 AM
      );

      // If due date has passed, don't schedule
      if (scheduledDate.isBefore(now)) {
        print('Due date ${record.dueDate} has already passed. Not scheduling future notification.');
        return;
      }

      // Set notification content
      final bool isBorrowed = record.deptType == DeptType.borrow;
      final title = isBorrowed ? 'Payment Due Today' : 'Collection Due Today';
      final body = isBorrowed
          ? 'Your payment of \$${record.amount.toStringAsFixed(2)} to ${record.personName} is due today'
          : '${record.personName} owes you \$${record.amount.toStringAsFixed(2)} due today';

      // Schedule notification
      await _notifications.zonedSchedule(
        record.id.hashCode,
        title,
        body,
        scheduledDate,
        platformDetails,
        androidAllowWhileIdle: true,
        uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
        payload: record.id,
      );

      print('Notification scheduled for ${scheduledDate}');
    } catch (e) {
      print('Failed to schedule notification: $e');
    }
  }

  // Cancel notification
  static Future<void> cancelNotification(String recordId) async {
    try {
      await _notifications.cancel(recordId.hashCode);
      print('Notification cancelled for ID: $recordId');
    } catch (e) {
      print('Failed to cancel notification: $e');
    }
  }

  // Send test notification
  static Future<void> sendTestNotification() async {
    await initialize();

    try {
      final androidDetails = AndroidNotificationDetails(
        'debt_due_channel',
        'Debt Due Reminders',
        channelDescription: 'Notifications for due debts',
        importance: Importance.max,
        priority: Priority.high,
      );

      final platformDetails = NotificationDetails(
        android: androidDetails,
      );

      await _notifications.show(
        999999,
        'Test Notification',
        'If you see this, notifications are working correctly',
        platformDetails,
      );

      print('Test notification sent');
    } catch (e) {
      print('Failed to send test notification: $e');
    }
  }
}