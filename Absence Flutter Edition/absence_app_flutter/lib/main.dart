import 'package:flutter/material.dart';

import 'modules/auth/login_page.dart';

void main() {
  // Εξασφάλιση αρχικοποίησης των Flutter Bindings
  WidgetsFlutterBinding.ensureInitialized();

  // Εκκίνηση της εφαρμογής Flutter
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Σύστημα Απουσιών',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const LoginPage(),
    );
  }
}
