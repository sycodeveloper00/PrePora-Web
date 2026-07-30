import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import '../../../core/widgets/professional_loader.dart';

class ResetPasswordScreen extends StatefulWidget {
  final String? token;
  const ResetPasswordScreen({super.key, this.token});
  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _isLoading = false;
  bool _success = false;
  String? _error;
  bool _obscure1 = true;
  bool _obscure2 = true;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String get _apiBase => kIsWeb ? '' : 'https://prepora-web.vercel.app';

  bool get _isValidToken => widget.token != null && widget.token!.isNotEmpty;

  Future<void> _resetPassword() async {
    final email = _emailCtrl.text.trim();
    final pass = _passCtrl.text;
    final confirm = _confirmCtrl.text;

    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Please enter your email.');
      return;
    }
    if (pass.length < 6) {
      setState(() => _error = 'Password must be at least 6 characters.');
      return;
    }
    if (pass != confirm) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }

    setState(() { _isLoading = true; _error = null; });
    try {
      final res = await http.post(
        Uri.parse('$_apiBase/api/reset-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'token': widget.token,
          'email': email,
          'newPassword': pass,
        }),
      );
      if (res.statusCode == 200) {
        if (mounted) setState(() { _success = true; _isLoading = false; });
      } else {
        final data = jsonDecode(res.body);
        if (mounted) setState(() { _error = data['error'] ?? 'Failed to reset password.'; _isLoading = false; });
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
                Icon(_success ? Icons.check_circle_rounded : Icons.lock_reset_rounded,
                    size: 64, color: _success ? Colors.greenAccent : (isDark ? Colors.white70 : Colors.white)),
                const SizedBox(height: 16),
                Text(_success ? 'Password Reset!' : 'Create New Password',
                    style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(_success
                    ? 'Your password has been reset successfully.\nYou can now log in with your new password.'
                    : !_isValidToken
                        ? 'Invalid or expired reset link.\nPlease request a new one.'
                        : 'Enter your email and new password below.',
                    style: const TextStyle(color: Colors.white60, fontSize: 13), textAlign: TextAlign.center),
                const SizedBox(height: 28),
                if (!_success && _isValidToken) ...[
                  TextField(controller: _emailCtrl, style: const TextStyle(color: Colors.white),
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Email Address', hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.email, color: Colors.white70),
                      filled: true, fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: _passCtrl, style: const TextStyle(color: Colors.white),
                    obscureText: _obscure1,
                    decoration: InputDecoration(
                      hintText: 'New Password', hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure1 ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                        onPressed: () => setState(() => _obscure1 = !_obscure1),
                      ),
                      filled: true, fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(controller: _confirmCtrl, style: const TextStyle(color: Colors.white),
                    obscureText: _obscure2,
                    decoration: InputDecoration(
                      hintText: 'Confirm Password', hintStyle: const TextStyle(color: Colors.white54),
                      prefixIcon: const Icon(Icons.lock_outline, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility, color: Colors.white54),
                        onPressed: () => setState(() => _obscure2 = !_obscure2),
                      ),
                      filled: true, fillColor: Colors.white10,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                ],
                if (_success) ...[
                  const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 48),
                  const SizedBox(height: 12),
                  const Text('You can now log in with your new password.',
                      style: TextStyle(color: Colors.white70, fontSize: 13), textAlign: TextAlign.center),
                ],
                if (_error != null) Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
                const SizedBox(height: 20),
                if (_isValidToken || _success)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _success ? () => context.go('/auth/login') : _resetPassword,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4A148C),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: ProfessionalLoader(size: 20))
                          : Text(_success ? 'Go to Login' : 'Reset Password',
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
