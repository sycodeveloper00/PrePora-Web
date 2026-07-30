import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../core/widgets/professional_loader.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});
  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailCtrl = TextEditingController();
  bool _isLoading = false;
  bool _sent = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  String get _apiBase => kIsWeb ? '' : 'https://prepora-web.vercel.app';

  void _showAssistantDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black54,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF1A0533),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF7B2FF7).withValues(alpha: 0.3)),
            boxShadow: [BoxShadow(color: const Color(0xFF7B2FF7).withValues(alpha: 0.15), blurRadius: 24, spreadRadius: 2)],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFFFF6F00), Color(0xFFFFB300)]),
                boxShadow: [BoxShadow(color: const Color(0xFFFF6F00).withValues(alpha: 0.3), blurRadius: 12)],
              ),
              child: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 32),
            ),
            const SizedBox(height: 20),
            const Text('Assistant Account',
                style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(
              'You are an Assistant.\nPlease contact the Admin to reset your password.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14, height: 1.5),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFF7B2FF7).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF7B2FF7).withValues(alpha: 0.3)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.info_outline_rounded, color: const Color(0xFFC084FC), size: 16),
                const SizedBox(width: 8),
                Text('Admin can change your password from\nthe Control Panel.',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 12)),
              ]),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7B2FF7),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Got It', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter a valid email.');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      final q = await FirebaseFirestore.instance
          .collection('users')
          .where('email', isEqualTo: email)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        final role = q.docs.first.data()['role'] as String?;
        if (role == 'Assistant') {
          if (mounted) setState(() { _isLoading = false; });
          _showAssistantDialog();
          return;
        }
      }
      final res = await http.post(
        Uri.parse('$_apiBase/api/send-reset-email'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );
      if (res.statusCode == 200) {
        if (mounted) setState(() { _sent = true; _isLoading = false; });
      } else {
        final data = jsonDecode(res.body);
        if (mounted) setState(() { _error = data['error'] ?? 'Failed to send email.'; _isLoading = false; });
      }
    } catch (e) {
      if (mounted) setState(() { _error = 'Network error. Please try again.'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        width: double.infinity, height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF0D0D1A), Color(0xFF1A0533)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
              ),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(_sent ? Icons.mark_email_read_rounded : Icons.lock_reset_rounded,
                    size: 64, color: isDark ? Colors.white70 : Colors.white),
                const SizedBox(height: 16),
                Text(_sent ? 'Email Sent' : 'Forgot Password',
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(_sent
                    ? 'A password reset link has been sent to\n${_emailCtrl.text.trim()}\n\nCheck your email and follow the link to reset your password.'
                    : 'Enter your email address to receive\na password reset link.',
                    style: const TextStyle(color: Colors.white60, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                if (!_sent)
                  TextField(controller: _emailCtrl, style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Email Address', hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.email, color: Colors.white70),
                      filled: true, fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                if (_sent) ...[
                  const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 48),
                  const SizedBox(height: 12),
                  const Text('Check your inbox and follow the reset link.\n\nIf you don\'t see the email, check your\nSpam/Junk folder and mark it as "Not Spam".',
                      style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
                ],
                if (_error != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _sent ? () => setState(() { _sent = false; _error = null; }) : _sendReset,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A148C),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: ProfessionalLoader(size: 20))
                        : Text(_sent ? 'Send Again' : 'Send Reset Link',
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => context.go('/auth/login'),
                  child: const Text('Back to Login', style: TextStyle(color: Color(0xFF00B8D4))),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
