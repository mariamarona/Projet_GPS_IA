import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String BASE_URL = 'http://127.0.0.1:8000';

class EtudiantDashboard extends StatefulWidget {
  const EtudiantDashboard({super.key});

  @override
  State<EtudiantDashboard> createState() => _EtudiantDashboardState();
}

class _EtudiantDashboardState extends State<EtudiantDashboard> {
  static const Color kBg = Color(0xFF0F172A);
  static const Color kPanel = Color(0xFF132335);
  static const Color kPanelSoft = Color(0xFF172C3D);
  static const Color kGreen = Color(0xFF22C55E);
  static const Color kGreenDark = Color(0xFF15803D);
  static const Color kOrange = Color(0xFFF59E0B);
  static const Color kRed = Color(0xFFFB7185);
  static const Color kMuted = Color(0xFF7C8CA3);

  Map<String, dynamic>? _presence;
  List<dynamic> _historique = [];
  List<dynamic> _sessions = [];
  bool _isLoading = true;
  String _nom = '';
  String _prenom = '';
  String _userId = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    _userId = prefs.getString('user_id') ?? '';
    _nom = prefs.getString('user_nom') ?? '';
    _prenom = prefs.getString('user_prenom') ?? '';
    final token = prefs.getString('access_token') ?? '';

    final headers = {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };

    try {
      final presenceRes = await http.get(
        Uri.parse('$BASE_URL/api/utilisateurs/$_userId/presence/'),
        headers: headers,
      );
      final historiqueRes = await http.get(
        Uri.parse('$BASE_URL/api/utilisateurs/$_userId/historique/'),
        headers: headers,
      );
      final sessionsRes = await http.get(
        Uri.parse('$BASE_URL/api/sessions/aujourd-hui/'),
        headers: headers,
      );

      if (!mounted) return;

      setState(() {
        if (presenceRes.statusCode == 200) {
          _presence = jsonDecode(presenceRes.body);
        }
        if (historiqueRes.statusCode == 200) {
          _historique = jsonDecode(historiqueRes.body)['pointages'] ?? [];
        }
        if (sessionsRes.statusCode == 200) {
          final data = jsonDecode(sessionsRes.body);
          _sessions = (data['sessions'] as List? ?? [])
              .where(
                  (s) => s['statut'] == 'EN_COURS' || s['statut'] == 'PLANIFIE')
              .toList();
        }
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    if (mounted) {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: kGreen))
                : RefreshIndicator(
                    onRefresh: _loadData,
                    color: kGreen,
                    backgroundColor: kPanel,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTopBar(),
                          const SizedBox(height: 28),
                          _buildHeader(),
                          const SizedBox(height: 22),
                          _buildPresenceCard(),
                          const SizedBox(height: 18),
                          _buildSessionsSection(),
                          const SizedBox(height: 18),
                          _buildRecentHistory(),
                        ],
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        const Text(
          '9:41',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const Spacer(),
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: kGreen,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'GPS actif',
          style: TextStyle(
            color: kGreen,
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          onPressed: _logout,
          icon: const Icon(Icons.logout_rounded, color: Colors.white),
          tooltip: 'Deconnexion',
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.08),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bonjour',
                style: TextStyle(color: kMuted, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '${_prenom.isEmpty ? 'Etudiant' : _prenom} $_nom'.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 23,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        CircleAvatar(
          radius: 26,
          backgroundColor: kGreen,
          child: Text(
            _initials(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPresenceCard() {
    final totalSessions = _presence?['total_sessions'] ?? 0;
    final totalPresences = _presence?['total_presences'] ?? 0;
    final absences = (totalSessions - totalPresences).clamp(0, 9999);
    final fraudes = _historique
        .where((p) => p['est_fraude'] == true || p['statut'] == 'HORS_ZONE')
        .length;
    final taux = _parsePercent(_presence?['taux_global'] ?? '0%');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: kGreenDark,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TAUX DE PRESENCE',
            style: TextStyle(
              color: Color(0xFFD7FBE5),
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: taux.toStringAsFixed(0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const TextSpan(
                  text: ' %',
                  style: TextStyle(
                    color: Color(0xFFD7FBE5),
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: (taux / 100).clamp(0, 1),
              backgroundColor: Colors.white.withOpacity(0.18),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFA7F3D0),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              _buildPresenceMetric('Validees', '$totalPresences', Colors.white),
              _buildPresenceMetric('Absences', '$absences', kRed),
              _buildPresenceMetric('Fraudes', '$fraudes', kOrange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPresenceMetric(String label, String value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFB7E9C7),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'SEANCES DU JOUR',
          style: TextStyle(
            color: kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        if (_sessions.isEmpty)
          _buildEmptyPanel(
            icon: Icons.event_busy_rounded,
            title: 'Aucune seance disponible',
            subtitle: 'Les seances demarrees apparaitront ici.',
          )
        else
          ..._sessions.map((session) => _buildSessionCard(session)),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/pointage'),
            icon: const Icon(Icons.fingerprint_rounded),
            label: const Text(
              'Pointer ma presence',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSessionCard(dynamic session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kPanelSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: const Color(0xFF052E16),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.check_rounded, color: kGreen, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  session['intitule'] ?? session['module'] ?? 'Session',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${session['heure_debut']} - ${session['heure_fin']} · ${session['zone']}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: kMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, '/pointage'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              'Pointer',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentHistory() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'HISTORIQUE RECENT',
          style: TextStyle(
            color: kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.3,
          ),
        ),
        const SizedBox(height: 12),
        if (_historique.isEmpty)
          _buildEmptyPanel(
            icon: Icons.history_rounded,
            title: 'Aucun pointage',
            subtitle: 'Vos derniers pointages apparaitront ici.',
          )
        else
          ..._historique.take(5).map((pointage) {
            final estValide = pointage['statut'] == 'VALIDE';
            return Container(
              margin: const EdgeInsets.only(bottom: 9),
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Row(
                children: [
                  Icon(
                    estValide
                        ? Icons.check_circle_rounded
                        : Icons.warning_rounded,
                    color: estValide ? kGreen : kRed,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          pointage['module'] ?? 'Module',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          pointage['date'] ?? '',
                          style: const TextStyle(color: kMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    pointage['statut'] ?? '',
                    style: TextStyle(
                      color: estValide ? kGreen : kRed,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  Widget _buildEmptyPanel({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: kMuted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: kMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _initials() {
    final p = _prenom.trim();
    final n = _nom.trim();
    final first = p.isNotEmpty ? p[0] : 'E';
    final second = n.isNotEmpty ? n[0] : '';
    return '$first$second'.toUpperCase();
  }

  double _parsePercent(dynamic value) {
    final text = value.toString().replaceAll('%', '').trim();
    return double.tryParse(text) ?? 0;
  }
}
