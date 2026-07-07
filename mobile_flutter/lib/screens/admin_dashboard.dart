import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String BASE_URL = 'http://127.0.0.1:8000';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  static const Color vertIAM = Color(0xFF1B5E20);

  Map<String, dynamic>? _fraudeDashboard;
  List<dynamic> _sessionsAujourdhui  = [];
  List<dynamic> _alertesNonTraitees  = [];
  int _totalEtudiants   = 0;
  int _totalModules     = 0;
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
      final results = await Future.wait([
        http.get(Uri.parse('$BASE_URL/api/alertes/dashboard/'),     headers: headers),
        http.get(Uri.parse('$BASE_URL/api/sessions/aujourd-hui/'),  headers: headers),
        http.get(Uri.parse('$BASE_URL/api/alertes/non-traitees/'),  headers: headers),
        http.get(Uri.parse('$BASE_URL/api/utilisateurs/?role=STUDENT'), headers: headers),
        http.get(Uri.parse('$BASE_URL/api/modules/'),               headers: headers),
      ]);

      if (mounted) {
        setState(() {
          if (results[0].statusCode == 200) _fraudeDashboard   = jsonDecode(results[0].body);
          if (results[1].statusCode == 200) _sessionsAujourdhui = jsonDecode(results[1].body)['sessions'] ?? [];
          if (results[2].statusCode == 200) _alertesNonTraitees = jsonDecode(results[2].body)['alertes'] ?? [];
          if (results[3].statusCode == 200) _totalEtudiants    = (jsonDecode(results[3].body) as List).length;
          if (results[4].statusCode == 200) _totalModules      = (jsonDecode(results[4].body) as List).length;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _traiterAlerte(int alerteId, String statut) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    final res = await http.patch(
      Uri.parse('$BASE_URL/api/alertes/$alerteId/traiter/'),
      headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $token'},
      body: jsonEncode({'statut': statut}),
    );

    if (res.statusCode == 200) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Alerte mise à jour → $statut'), backgroundColor: vertIAM),
      );
      _loadData();
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  Widget build(BuildContext context) {
    final nonTraitees = _fraudeDashboard?['non_traitees'] ?? 0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: vertIAM,
        title: const Text('IAMGPS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2)),
        actions: [
          if (nonTraitees > 0)
            Stack(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.notifications, color: Colors.white),
                ),
                Positioned(
                  right: 6,
                  top: 6,
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Center(
                      child: Text('$nonTraitees', style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ),
              ],
            ),
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
                            radius: 20,
                            child: Text(_prenom.isNotEmpty ? _prenom[0].toUpperCase() : 'A',
                                style: const TextStyle(color: vertIAM, fontWeight: FontWeight.bold)),
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('$_prenom $_nom', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                              const Text('Administrateur', style: TextStyle(color: Color(0xFFA5D6A7), fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 1.5,
                      children: [
                        _buildGridStat('Étudiants', '$_totalEtudiants', const Color(0xFFE8F5E9), vertIAM),
                        _buildGridStat('Modules', '$_totalModules', const Color(0xFFE3F2FD), Colors.blue),
                        _buildGridStat('Sessions du jour', '${_sessionsAujourdhui.length}', const Color(0xFFFFF8E1), Colors.orange),
                        _buildGridStat('Alertes fraude', '$nonTraitees', const Color(0xFFFFEBEE), Colors.red),
                      ],
                    ),

                    const SizedBox(height: 16),

                    const Text('Sessions du jour', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    if (_sessionsAujourdhui.isEmpty)
                      const Center(child: Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Aucune session aujourd\'hui', style: TextStyle(color: Colors.grey)),
                      ))
                    else
                      ..._sessionsAujourdhui.map((s) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(s['module'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  Text('${s['heure_debut']} → ${s['heure_fin']} · ${s['zone']}',
                                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                  Text('${s['nb_presences']} présence(s)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                ],
                              ),
                            ),
                            _buildStatutBadge(s['statut'] ?? ''),
                          ],
                        ),
                      )),

                    const SizedBox(height: 16),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Alertes fraude', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        if (nonTraitees > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                            child: Text('$nonTraitees non traitées',
                                style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w500)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (_alertesNonTraitees.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8F5E9),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.check_circle, color: vertIAM),
                            SizedBox(width: 8),
                            Text('Aucune alerte non traitée', style: TextStyle(color: vertIAM)),
                          ],
                        ),
                      )
                    else
                      ..._alertesNonTraitees.take(5).map((alerte) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(alerte['type_fraude'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red)),
                                Text('Score: ${alerte['score_ia'] ?? 'N/A'}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text('${alerte['etudiant']?['nom']} ${alerte['etudiant']?['prenom']} — ${alerte['session']?['module']}',
                                style: const TextStyle(fontSize: 12)),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _traiterAlerte(alerte['alerte_id'], 'FAUSSE_ALERTE'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.grey,
                                      side: const BorderSide(color: Colors.grey),
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    child: const Text('Fausse alerte', style: TextStyle(fontSize: 11)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _traiterAlerte(alerte['alerte_id'], 'FRAUDE_CONFIRMEE'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                    child: const Text('Confirmer', style: TextStyle(fontSize: 11)),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      )),

                    const SizedBox(height: 16),

                    if (_fraudeDashboard != null) ...[
                      const Text('Statistiques fraude', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _buildFraudeStat('Total', '${_fraudeDashboard!['total']}', Colors.grey),
                            _buildFraudeStat('Confirmées', '${_fraudeDashboard!['confirmees']}', Colors.red),
                            _buildFraudeStat('Rejetées', '${_fraudeDashboard!['fausses_alertes']}', Colors.green),
                            _buildFraudeStat('En cours', '${_fraudeDashboard!['en_investigation']}', Colors.orange),
                          ],
                        ),
                      ),
                    ],

                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildGridStat(String label, String value, Color bgColor, Color textColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(10)),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: textColor)),
          Text(label, style: TextStyle(fontSize: 11, color: textColor.withOpacity(0.8)), textAlign: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildStatutBadge(String statut) {
    Color color;
    switch (statut) {
      case 'EN_COURS': color = vertIAM; break;
      case 'PLANIFIE': color = Colors.blue; break;
      case 'TERMINE':  color = Colors.grey; break;
      default:         color = Colors.red;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
      child: Text(statut, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w500)),
    );
  }

  Widget _buildFraudeStat(String label, String value, Color color) {
    return Column(
      children: [
        Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }
}