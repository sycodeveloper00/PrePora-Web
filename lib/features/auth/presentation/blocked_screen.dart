import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isPC = screenWidth > 900;
    final cardWidth = isPC ? 500.0 : (screenWidth > 600 ? 440.0 : double.infinity);
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
            padding: EdgeInsets.symmetric(horizontal: isPC ? 0 : 24, vertical: 24),
            child: Container(
              width: cardWidth,
              padding: EdgeInsets.all(isPC ? 40 : 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.all(isPC ? 24 : 20),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: isPC ? 72 : 64),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Account Blocked',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: isPC ? 28 : 24,
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
                    child: Text(
                      'Our system detected suspicious activity from your account',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.redAccent, fontSize: isPC ? 16 : 15, height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'If you believe this is a mistake, please contact the admin to restore access.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: isPC ? 14 : 13, height: 1.4),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: isPC ? 240 : double.infinity,
                    height: isPC ? 50 : 46,
                    child: ElevatedButton(
                      onPressed: () => context.go('/auth/login'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Back to Login', style: TextStyle(color: Colors.white, fontSize: isPC ? 17 : 16)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
