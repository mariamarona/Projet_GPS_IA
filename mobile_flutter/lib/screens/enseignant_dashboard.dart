import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String BASE_URL = 'http://127.0.0.1:8000';

class EnseignantDashboard extends StatefulWidget {
  const EnseignantDashboard({super.key});

  @override
  State<EnseignantDashboard> createState() => _EnseignantDashboardState();
}

class _EnseignantDashboardState extends State<EnseignantDashboard> {
  static const Color vertIAM = Color(0xFF1B5E20);

  List<dynamic> _sessionsAujourdhui = [];
  List<dynamic> _modules            = [];
  bool _isLoading = true;
  String _nom     = '';
  String _prenom  = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _nom    = prefs.getString('user_nom') ?? '';
    _prenom = prefs.getString('user_prenom') ?? '';
    final token = prefs.getString('access_token') ?? '';

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    try {
      final sessionRes = await http.get(
        Uri.parse('$BASE_URL/api/sessions/aujourd-hui/'),
        headers: headers,
      );
      final modulesRes = await http.get(
        Uri.parse('$BASE_URL/api/modules/'),
        headers: headers,
      );

      if (mounted) {
        setState(() {
          if (sessionRes.statusCode == 200) {
            _sessionsAujourdhui = jsonDecode(sessionRes.body)['sessions'] ?? [];
          }
          if (modulesRes.statusCode == 200) {
            _modules = jsonDecode(modulesRes.body);
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _demarrerSession(int sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    final res = await http.post(
      Uri.parse('$BASE_URL/api/sessions/$sessionId/demarrer/'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
    );

    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Session démarrée ✅'), backgroundColor: vertIAM),
      );
      _loadData();
    } else {
      final data = jsonDecode(res.body);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(data['error'] ?? 'Erreur'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _terminerSession(int sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    final res = await http.post(
      Uri.parse('$BASE_URL/api/sessions/$sessionId/terminer/'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
    );

    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      final resume = data['resume'];
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session terminée — Présence: ${resume['taux_presence']}'),
          backgroundColor: vertIAM,
        ),
      );
      _loadData();
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  Color _getStatutColor(String statut) {
    switch (statut) {
      case 'EN_COURS':  return vertIAM;
      case 'PLANIFIE':  return Colors.blue;
      case 'TERMINE':   return Colors.grey;
      case 'ANNULEE':   return Colors.red;
      default:          return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: vertIAM,
        title: const Text('IAMGPS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          IconButton(icon: const Icon(Icons.logout, color: Colors.white), onPressed: _logout),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: vertIAM))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: vertIAM,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: vertIAM, borderRadius: BorderRadius.circular(12)),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white,
                            radius: 24,
                            child: Text(_prenom.isNotEmpty ? _prenom[0].toUpperCase() : 'E',
                                style: const TextStyle(color: vertIAM, fontWeight: FontWeight.bold, fontSize: 18)),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$_prenom $_nom', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                              const Text('Enseignant', style: TextStyle(color: Color(0xFFA5D6A7), fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    Row(
                      children: [
                        Expanded(child: _buildStatCard('Modules', '${_modules.length}', Icons.book, Colors.blue)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildStatCard('Sessions du jour', '${_sessionsAujourdhui.length}', Icons.today, vertIAM)),
                        const SizedBox(width: 8),
                        Expanded(child: _buildStatCard('En cours',
                            '${_sessionsAujourdhui.where((s) => s['statut'] == 'EN_COURS').length}',
                            Icons.play_circle, Colors.orange)),
                      ],
                    ),

                    const SizedBox(height: 16),

                    const Text('Sessions du jour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    if (_sessionsAujourdhui.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucune session aujourd\'hui', style: TextStyle(color: Colors.grey)),
                      ))
                    else
                      ..._sessionsAujourdhui.map((session) {
                        final statut = session['statut'] ?? '';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(session['module'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: _getStatutColor(statut).withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(statut, style: TextStyle(fontSize: 10, color: _getStatutColor(statut), fontWeight: FontWeight.w500)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(session['intitule'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                              Text('${session['heure_debut']} → ${session['heure_fin']} · ${session['zone']}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              Text('${session['nb_presences']} présence(s)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (statut == 'PLANIFIE')
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _demarrerSession(session['id']),
                                        icon: const Icon(Icons.play_arrow, size: 16),
                                        label: const Text('Démarrer', style: TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: vertIAM,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  if (statut == 'EN_COURS') ...[
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: () => _terminerSession(session['id']),
                                        icon: const Icon(Icons.stop, size: 16),
                                        label: const Text('Terminer', style: TextStyle(fontSize: 12)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(vertical: 6),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      }),

                    const SizedBox(height: 16),

                    const Text('Mes modules', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    ..._modules.map((module) => Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(8)),
                            child: const Icon(Icons.book, color: vertIAM, size: 20),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(module['code'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text(module['intitule'] ?? '', style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                              ],
                            ),
                          ),
                          Text('Seuil: ${module['seuil_presence_pct']}%',
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    )),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
        ],
      ),
    );
  }
}