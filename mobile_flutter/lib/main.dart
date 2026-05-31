import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';

void main() {
  runApp(const IAMGPSApp());
}

class IAMGPSApp extends StatelessWidget {
  const IAMGPSApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'IAMGPS',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
        ),
        useMaterial3: true,
      ),
      home: SplashScreen(),
    );
  }
}