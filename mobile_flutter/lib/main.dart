import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';
import 'screens/login_screen.dart';
import 'screens/etudiant_dashboard.dart';
import 'screens/enseignant_dashboard.dart';
import 'screens/admin_dashboard.dart';
import 'screens/pointage_screen.dart';

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
      initialRoute: '/',
      routes: {
        '/':           (_) => SplashScreen(),
        '/login':      (_) => const LoginScreen(),
        '/etudiant':   (_) => const EtudiantDashboard(),
        '/enseignant': (_) => const EnseignantDashboard(),
        '/admin':      (_) => const AdminDashboard(),
        '/pointage':   (_) => const PointageScreen(),
      },
    );
  }
}