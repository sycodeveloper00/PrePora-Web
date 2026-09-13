import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/professional_loader.dart';

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
    final user = FirebaseService.currentUser;
    if (user != null) {
      _checkRoleAndRedirect(user.uid);
    } else {
      _navigateToLogin();
    }
  }

  Future<void> _checkRoleAndRedirect(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedRole = prefs.getString('role_$uid');
      if (cachedRole != null) {
        FirebaseService.cachedRole = cachedRole;
        AuthGuard.setUserRole(cachedRole);
        if (!mounted) return;
        if (cachedRole == 'admin') {
          context.go('/admin');
          return;
        } else if (cachedRole == 'Assistant') {
          final snapshot = await FirebaseService.getUser(uid);
          final data = snapshot?.data() as Map<String, dynamic>?;
          final folderIds = (data?['folderIds'] as List<dynamic>?)?.cast<String>() ?? <String>[];
          final assistantName = data?['name'] as String? ?? 'Assistant';
          if (mounted) context.go('/assistant', extra: {'folderIds': folderIds, 'assistantName': assistantName});
          return;
        } else {
          context.go('/dashboard');
          return;
        }
      }
      final role = await FirebaseService.getUserRole(uid);
      if (role != null) {
        await prefs.setString('role_$uid', role);
        FirebaseService.cachedRole = role;
        AuthGuard.setUserRole(role);
      }
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
              child: ProfessionalLoader(size: 24),
            ),
          ],
        ),
      ),
    );
  }
}
