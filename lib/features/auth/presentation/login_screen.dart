import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import '../../../core/widgets/glassmorphic_container.dart';
import '../../../core/services/firebase_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_emailController.text.trim().isEmpty || _passwordController.text.isEmpty) {
      setState(() => _errorMessage = 'Please fill all fields.');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final credential = await FirebaseService.signIn(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (mounted && credential?.user != null) {
        final uid = credential!.user!.uid;
        final role = await FirebaseService.getUserRole(uid);
        if (role != null) {
          FirebaseService.cacheUserRole(uid, role);
          FirebaseService.cachedRole = role;
        }
        if (role == 'admin' || role == 'Assistant') {
          SessionManager.start(onExpiredCallback: () async {
            await FirebaseService.signOut();
            if (context.mounted) context.go('/auth/login');
          });
        }
        if (mounted) {
          if (kIsWeb && role != 'admin' && role != 'Assistant') {
            setState(() => _isLoading = false);
            await FirebaseService.signOut();
            _showUnderDevelopmentDialog();
            return;
          }
          if (role == 'admin') {
            context.go('/admin');
          } else if (role == 'Assistant') {
            final accessDocs = await FirebaseService.getAssistantFolderIds(credential.user!.uid);
            final folderIds = accessDocs.map((e) => e['folderId'] as String?).whereType<String>().toList();
            if (mounted) {
              context.go('/assistant', extra: {'folderIds': folderIds, 'assistantName': credential.user!.displayName});
            }
          } else {
            context.go('/dashboard');
          }
        }
      }
    } catch (e) {
      if (e.toString().contains('BLOCKED')) {
        if (mounted) context.go('/blocked');
        return;
      }
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showUnderDevelopmentDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.construction_rounded, color: Colors.orange, size: 24),
          SizedBox(width: 10),
          Text('Under Development', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: const Text(
          'The portal is under development. A team of developers is working on it. Once it will be complete you will be able to Login/register.',
          style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    ).then((_) {
      setState(() => _isLoading = false);
    });
  }

  void _forgotPassword() {
    context.push('/auth/forgot-password');
  }

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
            padding: const EdgeInsets.all(24.0),
            child: GlassmorphicContainer(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(child: Image.asset('assets/logo.png', height: 80, width: 80)),
                  const SizedBox(height: 16),
                  Text(
                    'Welcome Back',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Login to PrePora',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent),
                      ),
                      child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent)),
                    ),
                  _buildField(_emailController, 'Email Address', Icons.email, false),
                  const SizedBox(height: 16),
                  _buildField(_passwordController, 'Password', Icons.lock, true),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: const Text('Forgot Password?', style: TextStyle(color: Color(0xFF00B8D4))),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4A148C),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Text('Sign In',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text("Don't have an account?", style: TextStyle(color: Colors.white70)),
                      TextButton(
                        onPressed: () => context.push('/auth/signup'),
                        child: const Text('Sign Up', style: TextStyle(color: Color(0xFF00B8D4), fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon, bool isPassword) {
    return TextField(
      controller: ctrl,
      obscureText: isPassword ? _obscurePassword : false,
      style: const TextStyle(color: Colors.white),
      keyboardType: hint.contains('Email') ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white54),
        prefixIcon: Icon(icon, color: Colors.white70),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, color: Colors.white70),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              )
            : null,
        filled: true,
        fillColor: Colors.white10,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      ),
    );
  }
}
