import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

const String BASE_URL = 'http://127.0.0.1:8000';

class PointageScreen extends StatefulWidget {
  const PointageScreen({super.key});

  @override
  State<PointageScreen> createState() => _PointageScreenState();
}

class _PointageScreenState extends State<PointageScreen>
    with SingleTickerProviderStateMixin {
  static const Color kBg = Color(0xFF0F172A);
  static const Color kPanel = Color(0xFF122433);
  static const Color kPanelSoft = Color(0xFF172C3D);
  static const Color kGreen = Color(0xFF22C55E);
  static const Color kRed = Color(0xFFEF4444);
  static const Color kMuted = Color(0xFF7C8CA3);

  late final AnimationController _radarCtrl;

  List<dynamic> _sessions = [];
  dynamic _sessionSelectionnee;
  Position? _positionActuelle;
  bool _isLoadingSessions = true;
  bool _isLocating = false;
  bool _isPointing = false;
  String? _messageResultat;
  bool? _pointageValide;
  String _userId = '';
  Map<String, dynamic>? _dernierResultat;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _loadUserId();
    _loadSessions();
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUserId() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _userId = prefs.getString('user_id') ?? '');
  }

  Future<void> _loadSessions() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    setState(() => _isLoadingSessions = true);

    try {
      final res = await http.get(
        Uri.parse('$BASE_URL/api/sessions/aujourd-hui/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final sessions = (data['sessions'] as List)
            .where(
                (s) => s['statut'] == 'EN_COURS' || s['statut'] == 'PLANIFIE')
            .toList();

        setState(() {
          _sessions = sessions;
          _sessionSelectionnee = sessions.isNotEmpty ? sessions.first : null;
          _isLoadingSessions = false;
        });
      } else {
        setState(() => _isLoadingSessions = false);
      }
    } catch (_) {
      setState(() {
        _messageResultat = 'Impossible de charger les sessions du jour.';
        _pointageValide = false;
        _isLoadingSessions = false;
      });
    }
  }

  Future<Position?> _obtenirPosition() async {
    setState(() {
      _isLocating = true;
      _messageResultat = null;
      _pointageValide = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied) {
        setState(() {
          _messageResultat = 'Permission de localisation refusee.';
          _pointageValide = false;
          _isLocating = false;
        });
        return null;
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _messageResultat = 'Activez la localisation dans les parametres.';
          _pointageValide = false;
          _isLocating = false;
        });
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _positionActuelle = position;
        _isLocating = false;
      });
      return position;
    } catch (_) {
      setState(() {
        _messageResultat = 'Erreur pendant la localisation GPS.';
        _pointageValide = false;
        _isLocating = false;
      });
      return null;
    }
  }

  Future<void> _pointerMaintenant() async {
    if (_sessionSelectionnee == null) {
      setState(() {
        _messageResultat = 'Aucune session disponible aujourd hui.';
        _pointageValide = false;
      });
      return;
    }

    final position = await _obtenirPosition();
    if (position == null) return;

    setState(() {
      _isPointing = true;
      _messageResultat = 'Analyse IA en cours...';
    });

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token') ?? '';

    try {
      final res = await http.post(
        Uri.parse('$BASE_URL/api/pointages/valider/'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'utilisateur_id': _userId,
          'session_id': _sessionSelectionnee['id'],
          'latitude': position.latitude,
          'longitude': position.longitude,
          'precision_gps_m': position.accuracy,
        }),
      );

      final data = jsonDecode(res.body);

      if (res.statusCode == 201) {
        final dansZone = data['dans_zone'] == true;
        setState(() {
          _pointageValide = dansZone;
          _messageResultat =
              dansZone ? 'Position dans la zone' : 'Position hors zone';
          _dernierResultat = data;
        });
      } else {
        setState(() {
          _pointageValide = false;
          _messageResultat = data['error'] ?? 'Erreur lors du pointage.';
        });
      }
    } catch (_) {
      setState(() {
        _pointageValide = false;
        _messageResultat = 'Impossible de contacter le serveur.';
      });
    } finally {
      setState(() => _isPointing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionTitle = _sessionSelectionnee?['intitule'] ??
        _sessionSelectionnee?['module'] ??
        'Pointage GPS';
    final sessionPlace = _sessionSelectionnee?['zone'] ?? 'Zone de presence';
    final statusColor = _pointageValide == false ? kRed : kGreen;

    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadSessions,
          color: kGreen,
          backgroundColor: kPanel,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(),
                const SizedBox(height: 28),
                Text(
                  'Pointage GPS',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 6),
                Text(
                  '$sessionTitle\n$sessionPlace',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: kMuted,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                _buildGpsPanel(statusColor),
                const SizedBox(height: 18),
                _buildSessionSelector(),
                const SizedBox(height: 18),
                _buildDetailsPanel(),
                const SizedBox(height: 20),
                _buildPointageButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withOpacity(0.08),
          ),
        ),
        const Spacer(),
        Row(
          children: [
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
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGpsPanel(Color statusColor) {
    return Container(
      height: 276,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kPanel,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: statusColor.withOpacity(0.35), width: 1.4),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 24,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _radarCtrl,
              builder: (_, __) {
                return CustomPaint(
                  painter: _RadarPainter(
                    progress: _radarCtrl.value,
                    color: statusColor,
                    isActive: _isLocating || _isPointing,
                  ),
                  child: Center(
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.95),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withOpacity(0.28),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: const Text(
                        'GPS',
                        style: TextStyle(
                          color: kBg,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _statusTitle(),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: statusColor,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _isPointing
                ? 'Analyse IA en cours...'
                : _isLocating
                    ? 'Localisation GPS en cours...'
                    : _statusSubtitle(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _statusTitle() {
    if (_isLocating) return 'Recherche de position';
    if (_isPointing) return 'Verification en cours';
    if (_pointageValide == true) return 'Position dans la zone';
    if (_pointageValide == false) return 'Alerte de position';
    return 'Pret pour le pointage';
  }

  String _statusSubtitle() {
    if (_dernierResultat != null) {
      return 'Distance: ${_dernierResultat!['distance_m']}m / ${_dernierResultat!['rayon_zone_m']}m autorises';
    }
    return 'Selectionnez une session puis lancez le pointage';
  }

  Widget _buildSessionSelector() {
    if (_isLoadingSessions) {
      return const Center(child: CircularProgressIndicator(color: kGreen));
    }

    if (_sessions.isEmpty) {
      return _buildInfoTile(
        icon: Icons.event_busy_rounded,
        title: 'Aucune session disponible',
        subtitle: 'Demandez a l enseignant de demarrer une session.',
        color: kRed,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Seances du jour',
          style: TextStyle(
            color: kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        ..._sessions.map((session) {
          final selected = _sessionSelectionnee?['id'] == session['id'];
          return GestureDetector(
            onTap: () => setState(() {
              _sessionSelectionnee = session;
              _messageResultat = null;
              _pointageValide = null;
              _dernierResultat = null;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: selected ? kPanelSoft : Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected ? kGreen.withOpacity(0.45) : Colors.white10,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: selected
                          ? kGreen.withOpacity(0.16)
                          : Colors.white.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      selected
                          ? Icons.check_rounded
                          : Icons.radio_button_unchecked_rounded,
                      color: selected ? kGreen : kMuted,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session['intitule'] ?? session['module'] ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: kGreen,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Pointer',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDetailsPanel() {
    if (_messageResultat == null && _positionActuelle == null) {
      return _buildInfoTile(
        icon: Icons.shield_outlined,
        title: 'Controle GPS et IA',
        subtitle: 'La position, la precision et la zone seront verifiees.',
        color: kGreen,
      );
    }

    return _buildInfoTile(
      icon: _pointageValide == false
          ? Icons.warning_amber_rounded
          : Icons.verified_rounded,
      title: _messageResultat ?? 'Position obtenue',
      subtitle: _positionActuelle == null
          ? 'En attente de localisation.'
          : 'Precision GPS: ${_positionActuelle!.accuracy.toStringAsFixed(1)}m',
      color: _pointageValide == false ? kRed : kGreen,
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
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
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
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

  Widget _buildPointageButton() {
    final disabled = _isPointing ||
        _isLocating ||
        _isLoadingSessions ||
        _sessionSelectionnee == null;

    return SizedBox(
      height: 54,
      child: ElevatedButton.icon(
        onPressed: disabled ? null : _pointerMaintenant,
        icon: (_isPointing || _isLocating)
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.fingerprint_rounded),
        label: Text(
          _isPointing
              ? 'Analyse en cours...'
              : _isLocating
                  ? 'Localisation...'
                  : 'Pointer maintenant',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: kGreen,
          disabledBackgroundColor: kGreen.withOpacity(0.45),
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({
    required this.progress,
    required this.color,
    required this.isActive,
  });

  final double progress;
  final Color color;
  final bool isActive;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.36;
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withOpacity(0.14);

    for (var i = 1; i <= 4; i++) {
      canvas.drawCircle(center, radius * i / 4, ringPaint);
    }

    final mainRing = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = color.withOpacity(0.65);
    canvas.drawCircle(center, radius * 0.52, mainRing);

    final sweepPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: 0,
        endAngle: math.pi * 2,
        colors: [
          color.withOpacity(0),
          color.withOpacity(isActive ? 0.25 : 0.12),
          color,
        ],
        stops: const [0.0, 0.72, 1.0],
        transform: GradientRotation(progress * math.pi * 2),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius * 0.88),
      -math.pi / 2,
      math.pi * 0.9,
      false,
      sweepPaint,
    );

    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(isActive ? 0.07 : 0.04);
    canvas.drawCircle(center, radius * (0.72 + progress * 0.18), glowPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.isActive != isActive;
  }
}
