import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_core/firebase_core.dart';
import '../../../core/services/firebase_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _navigate());
  }

  void _navigate() async {
    for (int i = 0; i < 50; i++) {
      try {
        if (Firebase.apps.isNotEmpty) break;
      } catch (_) {}
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final user = FirebaseService.currentUser;
    if (user != null) {
      _checkRoleAndRedirect(user.uid);
    } else {
      _navigateToLogin();
    }
  }

  Future<void> _checkRoleAndRedirect(String uid) async {
    try {
      String? role = await FirebaseService.getCachedUserRole(uid);
      if (role == null) {
        role = await FirebaseService.getUserRole(uid);
        if (role != null) FirebaseService.cacheUserRole(uid, role);
      }
      FirebaseService.cachedRole = role;
      if (!mounted) return;
      if (role == 'admin') {
        context.go('/admin');
      } else if (role == 'Assistant') {
        final snapshot = await FirebaseService.getUser(uid);
        final data = snapshot?.data() as Map<String, dynamic>?;
        final folderIds = (data?['folderIds'] as List<dynamic>?)?.cast<String>() ?? <String>[];
        final assistantName = data?['name'] as String? ?? 'Assistant';
        context.go('/assistant', extra: {'folderIds': folderIds, 'assistantName': assistantName});
      } else {
        context.go('/dashboard');
      }
    } catch (_) {
      if (mounted) _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    if (mounted) context.go('/auth/login');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D2E),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image.asset('assets/logo.png', height: 140, width: 140),
            const SizedBox(height: 20),
            const Text('PrePora',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 40),
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFB388FF),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
