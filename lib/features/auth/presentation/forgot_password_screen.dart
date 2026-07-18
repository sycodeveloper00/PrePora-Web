import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/services/firebase_service.dart';

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

  Future<void> _sendReset() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Please enter your email.');
      return;
    }
    setState(() { _isLoading = true; _error = null; });
    try {
      await FirebaseService.sendPasswordReset(email);
      if (mounted) setState(() { _sent = true; _isLoading = false; });
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() {
        _error = e.code == 'user-not-found' ? 'No account found with this email.'
            : e.code == 'invalid-email' ? 'Invalid email address.'
            : e.message ?? 'Failed to send reset email.';
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
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
                  const Text('Check your inbox and follow the reset link.',
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
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
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
