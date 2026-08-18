import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:http/http.dart' as http;
import 'dart:html' as html;
import '../../../core/router/app_router.dart';
import '../../../core/services/firebase_service.dart';

class LinkWebScreen extends StatefulWidget {
  const LinkWebScreen({super.key});
  @override
  State<LinkWebScreen> createState() => _LinkWebScreenState();
}

class _LinkWebScreenState extends State<LinkWebScreen> {
  String _sessionId = '';
  String _status = 'waiting';
  Map<String, dynamic>? _sessionData;
  Timer? _refreshTimer;
  Timer? _expireTimer;
  Timer? _redirectTimer;
  StreamSubscription? _sessionSub;
  DateTime? _createdAt;
  int _countdown = 3;
  DateTime? _lastUserActivity;
  Timer? _activityCheckTimer;
  Timer? _heartbeatTimer;
  html.EventListener? _beforeUnloadHandler;

  static const String _sessionKey = 'prepora_web_session';

  @override
  void initState() {
    super.initState();
    _checkExistingSession();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _expireTimer?.cancel();
    _redirectTimer?.cancel();
    _sessionSub?.cancel();
    _activityCheckTimer?.cancel();
    _stopHeartbeat();
    _stopBeforeUnloadListener();
    if (_status != 'connected') {
      _cleanupSession();
    }
    html.window.removeEventListener('mousemove', _onUserActivity);
    html.window.removeEventListener('click', _onUserActivity);
    html.window.removeEventListener('keydown', _onUserActivity);
    super.dispose();
  }

  void _onUserActivity(html.Event? e) {
    _lastUserActivity = DateTime.now();
  }

  void _startActivityTracking() {
    _lastUserActivity = DateTime.now();
    html.window.addEventListener('mousemove', _onUserActivity);
    html.window.addEventListener('click', _onUserActivity);
    html.window.addEventListener('keydown', _onUserActivity);
    _activityCheckTimer?.cancel();
    _activityCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_lastUserActivity == null) return;
      final inactive = DateTime.now().difference(_lastUserActivity!);
      if (inactive.inMinutes >= 30) {
        _disconnectSession();
      }
    });
  }

  void _stopActivityTracking() {
    _activityCheckTimer?.cancel();
    html.window.removeEventListener('mousemove', _onUserActivity);
    html.window.removeEventListener('click', _onUserActivity);
    html.window.removeEventListener('keydown', _onUserActivity);
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    // 5-minute heartbeat (was 30s) — every write triggers re-reads on active
    // web_sessions collection listeners, which burned the free-tier read quota.
    _heartbeatTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (_sessionId.isEmpty || _status != 'connected') return;
      final now = DateTime.now();
      FirebaseFirestore.instance.collection('web_sessions').doc(_sessionId).update({
        'lastActive': FieldValue.serverTimestamp(),
      }).catchError((_) {});
      FirebaseService.mirrorWebSession(_sessionId, {'lastActive': now.toIso8601String()});
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }

  /// Best-effort cleanup of stale waiting/disconnected sessions older than
  /// 2 hours. Runs once per session creation and never throws.
  Future<void> _cleanupStaleSessions() async {
    try {
      final cutoff = Timestamp.fromDate(DateTime.now().subtract(const Duration(hours: 2)));
      final stale = await FirebaseFirestore.instance
          .collection('web_sessions')
          .where('createdAt', isLessThan: cutoff)
          .limit(50)
          .get();
      for (final doc in stale.docs) {
        try {
          final data = doc.data();
          final status = data['status'] as String?;
          if (status == 'waiting' || status == 'disconnected') {
            await doc.reference.delete();
          }
        } catch (_) {}
      }
    } catch (_) {}
  }

  void _startBeforeUnloadListener() {
    if (_beforeUnloadHandler != null) return;
    _beforeUnloadHandler = (html.Event e) {
      _cleanupSession();
    };
    html.window.addEventListener('beforeunload', _beforeUnloadHandler!);
  }

  void _stopBeforeUnloadListener() {
    if (_beforeUnloadHandler != null) {
      html.window.removeEventListener('beforeunload', _beforeUnloadHandler!);
      _beforeUnloadHandler = null;
    }
  }

  String _detectBrowser() {
    final ua = html.window.navigator.userAgent.toLowerCase();
    if (ua.contains('edg/')) return 'Edge';
    if (ua.contains('opr') || ua.contains('opera')) return 'Opera';
    if (ua.contains('brave')) return 'Brave';
    if (ua.contains('baiduboxapp') || ua.contains('baidubrowser') || ua.contains('baidu')) return 'Baidu';
    if (ua.contains('ucbrowser')) return 'UC Browser';
    if (ua.contains('samsungbrowser')) return 'Samsung Internet';
    if (ua.contains('chrome') && !ua.contains('edg/')) return 'Chrome';
    if (ua.contains('firefox')) return 'Firefox';
    if (ua.contains('safari') && !ua.contains('chrome')) return 'Safari';
    return 'Other';
  }

  void _checkExistingSession() {
    final saved = html.window.localStorage[_sessionKey];
    if (saved != null && saved.isNotEmpty) {
      try {
        final data = json.decode(saved) as Map<String, dynamic>;
        final sid = data['sessionId'] as String?;
        if (sid != null && sid.isNotEmpty) {
          _sessionId = sid;
          _status = 'checking';
          if (mounted) setState(() {});
          _verifyExistingSession(sid);
          return;
        }
      } catch (_) {}
    }
    _generateSession();
  }

  Future<void> _verifyExistingSession(String sessionId) async {
    try {
      Map<String, dynamic>? data;
      try {
        data = await FirebaseService.getWebSessionDoc(sessionId);
      } catch (_) {}
      if (data == null) {
        final doc = await FirebaseFirestore.instance.collection('web_sessions').doc(sessionId).get();
        if (doc.exists) data = doc.data();
      }
      if (data != null) {
        final status = data['status'];
        if (status == 'connected') {
          final uid = data['uid'];
          if (uid != null) {
            _LinkedWebSession.instance.setSession(
              uid: uid,
              name: data['userName'] ?? 'Student',
              email: data['userEmail'] ?? '',
              role: data['userRole'] ?? 'student',
            );
            bool signedIn = false;
            try {
              final response = await http.post(
                Uri.parse('/api/generate-token'),
                headers: {'Content-Type': 'application/json'},
                body: json.encode({'sessionId': sessionId, 'uid': uid}),
              );
              if (response.statusCode == 200) {
                final body = json.decode(response.body) as Map<String, dynamic>;
                final customToken = body['customToken'] as String?;
                if (customToken != null) {
                  await fb_auth.FirebaseAuth.instance.signInWithCustomToken(customToken);
                  signedIn = true;
                }
              } else {
                print('[generate-token restore] Failed: ${response.statusCode}');
              }
            } catch (e) {
              print('[generate-token restore] Error: $e');
            }

            if (!signedIn) {
              html.window.localStorage.remove(_sessionKey);
              _generateSession();
              return;
            }

            final role = data['userRole'] ?? 'student';
            FirebaseService.cachedRole = role;

            _sessionSub = FirebaseService.streamWebSessionDoc(sessionId).listen((sData) {
              if (sData == null) return;
              if (sData['status'] == 'disconnected' && mounted) {
                html.window.localStorage.remove(_sessionKey);
                setState(() {
                  _status = 'waiting';
                  _sessionData = null;
                });
                _stopActivityTracking();
                _expireTimer?.cancel();
                _generateSession();
              }
            });
            _LinkedWebSession.instance.startMonitoring(sessionId, () {
              html.window.localStorage.remove(_sessionKey);
              _LinkedWebSession.instance.clear();
              _stopActivityTracking();
              fb_auth.FirebaseAuth.instance.signOut().then((_) {
                final navCtx = AppRouter.rootNavigatorKey.currentContext;
                if (navCtx != null) {
                  GoRouter.of(navCtx).go('/link-web');
                }
              });
            });
            _startActivityTracking();
            if (mounted) {
              context.go('/dashboard');
            }
            return;
          }
        }
      }
    } catch (_) {}
    html.window.localStorage.remove(_sessionKey);
    _generateSession();
  }

  Future<void> _generateSession() async {
    if (fb_auth.FirebaseAuth.instance.currentUser == null) {
      try {
        await fb_auth.FirebaseAuth.instance.signInAnonymously();
      } catch (_) {}
    }

    final rng = Random.secure();
    final token = List.generate(32, (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    _sessionId = 'web-$token';
    _createdAt = DateTime.now();

    // Clean up stale waiting/disconnected sessions older than 2 hours so the
    // web_sessions collection doesn't grow unbounded (each QR page load used
    // to create a permanent doc, inflating collection reads).
    _cleanupStaleSessions();

    try {
      await FirebaseFirestore.instance.collection('web_sessions').doc(_sessionId).set({
        'sessionId': _sessionId,
        'status': 'waiting',
        'createdAt': Timestamp.fromDate(_createdAt!),
        'lastActive': Timestamp.fromDate(_createdAt!),
        'webBrowser': _detectBrowser(),
      });
    } catch (e) {
      print('[generateSession] Firestore write failed: $e');
    }
    await FirebaseService.mirrorWebSession(_sessionId, {
      'sessionId': _sessionId,
      'status': 'waiting',
      'createdAt': _createdAt!.toIso8601String(),
      'lastActive': _createdAt!.toIso8601String(),
      'webBrowser': _detectBrowser(),
    });

    _sessionSub = FirebaseService.streamWebSessionDoc(_sessionId).listen((sData) {
      if (sData == null) return;
      final status = sData['status'] ?? 'waiting';

      if (status == 'connected' && mounted) {
        setState(() {
          _status = 'connected';
          _sessionData = sData;
          _countdown = 3;
        });
        _startRedirectTimer();
        _startHeartbeat();
        _startBeforeUnloadListener();
      } else if (status == 'disconnected' && mounted) {
        setState(() {
          _status = 'waiting';
          _sessionData = null;
        });
        _expireTimer?.cancel();
        _stopHeartbeat();
        _stopBeforeUnloadListener();
        _generateSession();
      }
    });

    _expireTimer = Timer(const Duration(minutes: 5), () {
      if (_status == 'waiting' && mounted) {
        setState(() => _status = 'expired');
      }
    });

    // Refresh timer removed — 5-min expiry is sufficient

    if (mounted) setState(() {});
  }

  void _startRedirectTimer() {
    _redirectTimer?.cancel();
    _redirectTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) { timer.cancel(); return; }
      setState(() { _countdown--; });
      if (_countdown <= 0) {
        timer.cancel();
        _redirectToDashboard();
      }
    });
  }

  void _redirectToDashboard() async {
    final uid = _sessionData?['uid'];
    final role = _sessionData?['userRole'] ?? 'student';
    if (uid == null) return;

    _LinkedWebSession.instance.setSession(
      uid: uid,
      name: _sessionData?['userName'] ?? 'Student',
      email: _sessionData?['userEmail'] ?? '',
      role: role,
    );

    bool signedIn = false;
    try {
      final response = await http.post(
        Uri.parse('/api/generate-token'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'sessionId': _sessionId, 'uid': uid}),
      );
      if (response.statusCode == 200) {
        final body = json.decode(response.body) as Map<String, dynamic>;
        final customToken = body['customToken'] as String?;
        if (customToken != null) {
          await fb_auth.FirebaseAuth.instance.signInWithCustomToken(customToken);
          signedIn = true;
        }
      } else {
        print('[generate-token] Failed: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('[generate-token] Error: $e');
    }

    if (!signedIn) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to connect. Please scan QR again.'), backgroundColor: Colors.redAccent),
        );
      }
      return;
    }

    FirebaseService.cachedRole = role;

    html.window.localStorage[_sessionKey] = json.encode({'sessionId': _sessionId});
    _startActivityTracking();

    // Keep listening for Android-side disconnect even after this screen is
    // disposed on navigation.
    _LinkedWebSession.instance.startMonitoring(_sessionId, () {
      html.window.localStorage.remove(_sessionKey);
      _LinkedWebSession.instance.clear();
      _stopActivityTracking();
      fb_auth.FirebaseAuth.instance.signOut().then((_) {
        final navCtx = AppRouter.rootNavigatorKey.currentContext;
        if (navCtx != null) {
          GoRouter.of(navCtx).go('/link-web');
        }
      });
    });
    _listenToSessionStatus();

    if (mounted) {
      context.go('/dashboard');
    }
  }

  void _listenToSessionStatus() {
    _sessionSub?.cancel();
    _sessionSub = FirebaseService.streamWebSessionDoc(_sessionId).listen((sData) {
      if (sData == null) return;
      if (sData['status'] == 'disconnected' && mounted) {
        html.window.localStorage.remove(_sessionKey);
        _stopActivityTracking();
        _expireTimer?.cancel();
        setState(() {
          _status = 'waiting';
          _sessionData = null;
        });
        _generateSession();
      }
    });
  }

  Future<void> _disconnectSession() async {
    if (_sessionId.isEmpty) return;
    final now = DateTime.now();
    try {
      await FirebaseFirestore.instance.collection('web_sessions').doc(_sessionId).update({
        'status': 'disconnected',
        'disconnectedAt': Timestamp.fromDate(now),
      });
    } catch (_) {}
    await FirebaseService.mirrorWebSession(_sessionId, {
      'status': 'disconnected',
      'disconnectedAt': now.toIso8601String(),
    });
    html.window.localStorage.remove(_sessionKey);
    _expireTimer?.cancel();
    _refreshTimer?.cancel();
    _sessionSub?.cancel();
    _stopActivityTracking();
    _LinkedWebSession.instance.clear();
    await fb_auth.FirebaseAuth.instance.signOut();
    if (mounted) {
      setState(() {
        _status = 'waiting';
        _sessionData = null;
      });
      _generateSession();
    }
  }

  Future<void> _cleanupSession() async {
    if (_sessionId.isEmpty) return;
    final now = DateTime.now();
    try {
      final docRef = FirebaseFirestore.instance.collection('web_sessions').doc(_sessionId);
      final snap = await docRef.get();
      final data = snap.data();
      final hadUid = data?['uid'] is String && (data?['uid'] as String? ?? '').isNotEmpty;
      if (hadUid) {
        await docRef.update({
          'status': 'disconnected',
          'disconnectedAt': Timestamp.fromDate(now),
        });
        await FirebaseService.mirrorWebSession(_sessionId, {
          'status': 'disconnected',
          'disconnectedAt': now.toIso8601String(),
        });
      } else {
        await docRef.delete();
        await FirebaseService.mirrorWebSession(_sessionId, const {}, delete: true);
      }
    } catch (_) {}
  }

  Future<void> _refreshSession() async {
    _expireTimer?.cancel();
    _refreshTimer?.cancel();
    _sessionSub?.cancel();
    await _cleanupSession();
    await _generateSession();
  }

  String get _qrData => 'prepora-web-link:$_sessionId';

  Widget _buildLogo({double size = 64, bool light = true}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.28),
      child: Image.asset(
        'assets/logo.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: light
                  ? [Colors.white.withValues(alpha: 0.25), Colors.white.withValues(alpha: 0.10)]
                  : const [Color(0xFF7C4DFF), Color(0xFF536DFE)],
            ),
            borderRadius: BorderRadius.circular(size * 0.28),
          ),
          child: Center(
            child: Text('P', style: TextStyle(
              color: light ? Colors.white : Colors.white,
              fontSize: size * 0.45,
              fontWeight: FontWeight.bold,
            )),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = Colors.white;
    final cardColor = Colors.white.withValues(alpha: 0.06);
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 800;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0118),
      body: SafeArea(
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0A0118), Color(0xFF120226), Color(0xFF0A0118)],
            ),
          ),
          child: _status == 'connected'
              ? _buildConnectedView(cardColor, textColor)
              : isCompact
                  ? _buildMobileLayout(cardColor, textColor)
                  : _buildDesktopLayout(cardColor, textColor),
        ),
      ),
    );
  }

  Widget _buildDesktopLayout(Color cardColor, Color textColor) {
    return Row(
      children: [
        Expanded(
          flex: 5,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildLogo(size: 52),
                      const SizedBox(width: 14),
                      const Text(
                        'PrePora',
                        style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Web Version',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 40),
                  Text(
                    'CONNECT YOUR DEVICE',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 11, letterSpacing: 2, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 20),
                  _buildStep(1, 'Open PrePora app on your phone'),
                  const SizedBox(height: 14),
                  _buildStep(2, 'Tap the menu button (three dots)'),
                  const SizedBox(height: 14),
                  _buildStep(3, 'Select "Link with Web Version"'),
                  const SizedBox(height: 14),
                  _buildStep(4, 'Scan the QR code on the right'),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Center(
            child: _buildQRSection(cardColor, textColor),
          ),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(Color cardColor, Color textColor) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLogo(size: 48),
              const SizedBox(width: 12),
              Text('PrePora', style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 32),
          _buildQRSection(cardColor, textColor),
          const SizedBox(height: 24),
          _buildMobileStep(1, 'Open PrePora app', textColor),
          const SizedBox(height: 10),
          _buildMobileStep(2, 'Tap menu → Link with Web Version', textColor),
          const SizedBox(height: 10),
          _buildMobileStep(3, 'Scan this QR code', textColor),
        ],
      ),
    );
  }

  Widget _buildQRSection(Color cardColor, Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _status == 'expired' ? 'QR Code Expired' : 'Scan to Connect',
          style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        const SizedBox(height: 8),
        Text(
          _status == 'expired' ? 'Tap Refresh to generate a new code' : 'Use your phone\'s camera to scan',
          style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
        ),
        const SizedBox(height: 32),
        Container(
          width: 280, height: 280,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF9C27B0).withValues(alpha: 0.35),
                blurRadius: 50,
                spreadRadius: -10,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
                blurRadius: 80,
                spreadRadius: -15,
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: Center(
            child: _status == 'expired'
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.qr_code_scanner_rounded, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text('Expired', style: TextStyle(color: Colors.grey.shade500, fontSize: 16)),
                    ],
                  )
                : QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    size: 252,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Color(0xFF7C4DFF),
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Color(0xFF0A0118),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 20),
        ElevatedButton.icon(
          onPressed: _refreshSession,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Refresh'),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF7C4DFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 3,
            shadowColor: const Color(0xFF7C4DFF).withValues(alpha: 0.3),
          ),
        ),
      ],
    );
  }

  Widget _buildStep(int number, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF7C4DFF).withValues(alpha: 0.2)),
          ),
          child: Center(
            child: Text(
              '$number',
              style: const TextStyle(color: Color(0xFFB388FF), fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ),
        const SizedBox(width: 14),
        Text(text, style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, height: 1.3)),
      ],
    );
  }

  Widget _buildMobileStep(int number, String text, Color textColor) {
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text('$number', style: const TextStyle(color: Color(0xFF7C4DFF), fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 14))),
      ],
    );
  }

  Widget _buildConnectedView(Color cardColor, Color textColor) {
    final userName = _sessionData?['userName'] ?? 'Student';
    final userEmail = _sessionData?['userEmail'] ?? '';
    final connectedAt = (_sessionData?['connectedAt'] as Timestamp?)?.toDate();

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Container(
          width: 480,
          constraints: const BoxConstraints(maxWidth: 480),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00E676).withValues(alpha: 0.08),
                blurRadius: 60,
                spreadRadius: -10,
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 44, vertical: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFF00E676), Color(0xFF00C853)],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00E676).withValues(alpha: 0.3),
                      blurRadius: 24,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Icon(Icons.check_rounded, size: 40, color: Colors.white),
              ),
              const SizedBox(height: 20),
              Text('Connected!', style: TextStyle(color: textColor, fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text('Linked to PrePora mobile app', style: TextStyle(color: textColor.withValues(alpha: 0.45), fontSize: 13)),
              const SizedBox(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0xFF7C4DFF), Color(0xFF536DFE)]),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(userName[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(userName, style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Text(userEmail, style: TextStyle(color: textColor.withValues(alpha: 0.4), fontSize: 12)),
                        ],
                      ),
                    ),
                    if (connectedAt != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00E676).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${connectedAt.hour}:${connectedAt.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _disconnectSession,
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: const Text('Disconnect', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: BorderSide(color: Colors.redAccent.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      value: _countdown / 3,
                      color: const Color(0xFF00E676),
                      backgroundColor: Colors.white.withValues(alpha: 0.1),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Redirecting in $_countdown...',
                    style: TextStyle(color: textColor.withValues(alpha: 0.45), fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LinkedWebSession {
  static final _LinkedWebSession instance = _LinkedWebSession._();
  _LinkedWebSession._();

  String uid = '';
  String name = '';
  String email = '';
  String role = 'student';

  /// Global session-status listener that survives navigation so the web app
  /// reacts to an Android-side disconnect even after the LinkWebScreen is
  /// disposed.
  StreamSubscription? _globalSessionSub;
  void Function()? _onDisconnected;

  void setSession({required String uid, required String name, required String email, required String role}) {
    this.uid = uid;
    this.name = name;
    this.email = email;
    this.role = role;
  }

  /// Starts a persistent listener on the given session doc. When the session
  /// becomes 'disconnected', [onDisconnected] is invoked once and the
  /// listener stops.
  void startMonitoring(String sessionId, void Function() onDisconnected) {
    stopMonitoring();
    _onDisconnected = onDisconnected;
    _globalSessionSub = FirebaseService.streamWebSessionDoc(sessionId).listen((sData) {
      if (sData == null) return;
      if (sData['status'] == 'disconnected') {
        stopMonitoring();
        _onDisconnected?.call();
      }
    });
  }

  void stopMonitoring() {
    _globalSessionSub?.cancel();
    _globalSessionSub = null;
    _onDisconnected = null;
  }

  void clear() {
    stopMonitoring();
    uid = '';
    name = '';
    email = '';
    role = 'student';
  }

  bool get isActive => uid.isNotEmpty;
}
