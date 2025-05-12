import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';

class PermissionDialog {
  // Check if notification permission is granted
  static Future<bool> isNotificationPermissionGranted() async {
    if (!Platform.isAndroid) return true; // Assume iOS has permissions through app settings

    return await Permission.notification.isGranted;
  }

  // Request notification permission directly
  static Future<void> requestNotificationPermission() async {
    if (!Platform.isAndroid) return;

    await Permission.notification.request();
  }

  // Open app notification settings
  static Future<void> openNotificationSettings() async {
    if (Platform.isAndroid) {
      await openAppSettings();
    }
  }

  // 显示解释和请求通知权限的对话框
  static Future<void> showNotificationPermissionDialog(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

    // 检查是否需要显示对话框（Android 13+或权限被拒绝）
    if (androidInfo.version.sdkInt >= 33 &&
        await Permission.notification.isDenied) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Notification Permission'),
            content: const Text(
              'This app needs notification permission to alert you about debt due dates. '
                  'Please grant notification permission in the following dialog.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await Permission.notification.request();
                },
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  // 显示精确闹钟权限的解释和引导对话框
  static Future<void> showScheduleAlarmPermissionDialog(BuildContext context) async {
    if (!Platform.isAndroid) return;

    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    final AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;

    // 仅适用于 Android 12+
    if (androidInfo.version.sdkInt >= 31) {
      try {
        bool hasPermission = await Permission.scheduleExactAlarm.isGranted;

        if (!hasPermission) {
          await showDialog(
            context: context,
            barrierDismissible: false,
            builder: (BuildContext context) {
              return AlertDialog(
                title: const Text('Alarm Permission Needed'),
                content: const Text(
                  'This app needs "Alarms & Reminders" permission to send notifications on debt due dates. '
                      'Without this permission, notifications may be delayed.\n\n'
                      'Please click "Open Settings" and enable "Alarms & Reminders" for this app.',
                ),
                actions: [
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    child: const Text('Later'),
                  ),
                  TextButton(
                    onPressed: () async {
                      Navigator.of(context).pop();

                      // Try to request permission first
                      await Permission.scheduleExactAlarm.request();

                      // If still not granted, open settings
                      if (await Permission.scheduleExactAlarm.isPermanentlyDenied) {
                        await openAppSettings();
                      }
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              );
            },
          );
        }
      } catch (e) {
        print('Error checking alarm permission: $e');
        // If there's an error, we simply skip this permission check
      }
    }
  }

  // 检查并请求所有必需的权限
  static Future<void> checkAndRequestAllPermissions(BuildContext context) async {
    await showNotificationPermissionDialog(context);
    await showScheduleAlarmPermissionDialog(context);
  }
}