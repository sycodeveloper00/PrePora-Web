import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF0D0D1A), Color(0xFF1A0533)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 64),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Account Blocked',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
                  ),
                  child: const Text(
                    'Our system detected suspicious activity from your account',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.redAccent, fontSize: 15, height: 1.5),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'If you believe this is a mistake, please contact the admin to restore access.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () => context.go('/auth/login'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back to Login', style: TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
