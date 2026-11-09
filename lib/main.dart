import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:vietnam_provinces/vietnam_provinces.dart';

import 'firebase_options.dart';
import 'screens/login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ==============================
  // KHỞI TẠO FIREBASE
  // ==============================

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ==============================
  // KHỞI TẠO DỮ LIỆU TỈNH / PHƯỜNG
  // ==============================

  await VietnamProvinces.initialize(
    version: AdministrativeDivisionVersion.v2,
  );

  // ==============================
  // CHẠY APP
  // ==============================

  runApp(const VNPTApp());
}

class VNPTApp extends StatelessWidget {
  const VNPTApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,

      title: 'VNPT Đồng Hành Cùng Bạn',

      theme: ThemeData(
        useMaterial3: true,

        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0057B8),
        ),

        fontFamily: 'Roboto',
      ),

      home: const LoginScreen(),
    );
  }
}