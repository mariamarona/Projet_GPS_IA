import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// ── Remplace par l'IP de ton PC si tu testes sur téléphone physique
// Ex: 'http://192.168.1.X:8000'
const String BASE_URL = 'http://127.0.0.1:8000';  // émulateur Android
// const String BASE_URL = 'http://127.0.0.1:8000'; // Chrome/Web

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {

  final _formKey             = GlobalKey<FormState>();
  final _emailController     = TextEditingController();
  final _passwordController  = TextEditingController();
  bool _isLoading            = false;
  bool _obscurePassword      = true;
  String? _errorMessage;

  static const Color vertIAM = Color(0xFF1B5E20);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ── Appel API Django JWT ─────────────────────────────────
  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading    = true;
      _errorMessage = null;
    });

    try {
      final response = await http.post(
        Uri.parse('$BASE_URL/api/auth/login/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'email':        _emailController.text.trim(),
          'mot_de_passe': _passwordController.text,
        }),
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);

      if (response.statusCode == 200) {
        // ── Sauvegarde des tokens ──────────────────────────
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('access_token',  data['access']);
        await prefs.setString('refresh_token', data['refresh']);
        await prefs.setString('user_role',     data['utilisateur']['role']);
        await prefs.setString('user_id',       data['utilisateur']['id']);
        await prefs.setString('user_nom',      data['utilisateur']['nom']);
        await prefs.setString('user_prenom',   data['utilisateur']['prenom']);
        await prefs.setString('user_matricule',data['utilisateur']['matricule']);

        if (!mounted) return;

        // ── Navigation selon le rôle ───────────────────────
        final role = data['utilisateur']['role'];
        _naviguerSelonRole(role);

      } else {
        setState(() {
          _errorMessage = data['error'] ?? 'Erreur de connexion';
        });
      }

    } catch (e) {
      setState(() {
        _errorMessage = 'Impossible de contacter le serveur. Vérifiez votre connexion.';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _naviguerSelonRole(String role) {
    // TODO: remplacer par tes vrais écrans
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Connecté en tant que $role'),
        backgroundColor: vertIAM,
      ),
    );
    // Exemple:
    // if (role == 'ADMIN') Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const AdminDashboard()));
    // if (role == 'STUDENT') Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EtudiantDashboard()));
    // if (role == 'TEACHER') Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const EnseignantDashboard()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [

                const SizedBox(height: 40),

                // ── Logo IAM ──────────────────────────────
                Image.asset('assets/images/logo.jpeg', width: 140, height: 140),

                const SizedBox(height: 16),

                const Text(
                  'IAMGPS',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: vertIAM,
                    letterSpacing: 3,
                  ),
                ),

                const SizedBox(height: 4),

                const Text(
                  'Connectez-vous à votre compte',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),

                const SizedBox(height: 32),

                // ── Message d'erreur ──────────────────────
                if (_errorMessage != null)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                    ),
                  ),

                // ── Champ Email ───────────────────────────
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email',
                    prefixIcon: const Icon(Icons.email_outlined, color: vertIAM),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: vertIAM, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Email requis';
                    if (!value.contains('@')) return 'Email invalide';
                    return null;
                  },
                ),

                const SizedBox(height: 16),

                // ── Champ Mot de passe ────────────────────
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Mot de passe',
                    prefixIcon: const Icon(Icons.lock_outline, color: vertIAM),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility_off : Icons.visibility,
                        color: Colors.grey,
                      ),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: vertIAM, width: 2),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Mot de passe requis';
                    if (value.length < 6) return 'Minimum 6 caractères';
                    return null;
                  },
                ),

                const SizedBox(height: 28),

                // ── Bouton Connexion ──────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: vertIAM,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                        : const Text(
                            'Se connecter',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                ),

                const SizedBox(height: 40),

                const Text(
                  'Institut Africain de Management — Bamako',
                  style: TextStyle(fontSize: 11, color: Colors.grey),
                  textAlign: TextAlign.center,
                ),

              ],
            ),
          ),
        ),
      ),
    );
  }
}