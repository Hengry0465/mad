import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'accountmodule/welcome_screen.dart';
import 'accountmodule/profile_screen.dart';
import 'firebase_options.dart';
import 'overview.dart';
import 'notification_service.dart';
import 'permission_dialog.dart';
import 'dept.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化通知服务
  await NotificationService.initialize();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoneyPax',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.amber), // 使用黄色主题
        useMaterial3: true,
      ),
      home: StreamBuilder<User?>(
        stream: FirebaseAuth.instance.authStateChanges(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          if (snapshot.hasData) {
            // 用户已登录，返回导航控制器
            return const MainNavigationScreen();
          }

          return const WelcomeScreen();
        },
      ),
    );
  }
}