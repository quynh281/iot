import 'package:flutter/material.dart';
import 'dart:io'; 
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'main_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Chỉ khởi tạo FFI trên các nền tảng desktop
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // ✅ THÊM PHẦN NÀY
  final dbPath = await getDatabasesPath();
  final dbFile = join(dbPath, 'iot.db');
  print("📍 DATABASE PATH: $dbFile");

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: MainPage(),
    );
  }
}