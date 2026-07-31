import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/professional_loader.dart';
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
        TextInput.finishAutofillContext(shouldSave: true);
        final uid = credential!.user!.uid;
        final role = await FirebaseService.getUserRole(uid);
        if (role != null) {
          FirebaseService.cacheUserRole(uid, role);
          FirebaseService.cachedRole = role;
          AuthGuard.setUserRole(role);
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
          if (kIsWeb) {
            final host = Uri.base.host;
            if (host.contains('admin-prepora') && role != 'admin') {
              setState(() => _isLoading = false);
              await FirebaseService.signOut();
              _showWrongRoleDialog('admin');
              return;
            }
            if (host.contains('assistant-prepora') && role != 'Assistant') {
              setState(() => _isLoading = false);
              await FirebaseService.signOut();
              _showWrongRoleDialog('assistant');
              return;
            }
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

  void _showWrongRoleDialog(String requiredRole) {
    final title = requiredRole == 'admin' ? 'Admin Access Required' : 'Assistant Access Required';
    final msg = requiredRole == 'admin'
        ? 'This portal is for admin users only. Please use the correct portal for your role.'
        : 'This portal is for assistant users only. Please use the correct portal for your role.';
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A0533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          Icon(requiredRole == 'admin' ? Icons.admin_panel_settings : Icons.person, color: Colors.red, size: 24),
          const SizedBox(width: 10),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
        ]),
        content: Text(msg, style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5)),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
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
            colors: [Color(0xFF0A0118), Color(0xFF0D0D2E), Color(0xFF0A0118)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: _buildDesktopLayout(),
      ),
    );
  }

  Widget _buildDesktopLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(40),
        child: _buildLoginCard(),
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: _buildLoginCard(),
      ),
    );
  }

  Widget _buildLoginCard() {
    final screenWidth = MediaQuery.of(context).size.width;
    final cardWidth = screenWidth > 900 ? 480.0 : (screenWidth > 600 ? 440.0 : 380.0);
    return Container(
      width: cardWidth,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF7C4DFF).withValues(alpha: 0.12),
            blurRadius: 50,
            spreadRadius: -8,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 44),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Image.asset('assets/logo.png', height: 68, width: 68),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Welcome Back',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 26),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Sign in to your admin account',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white54, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          if (_errorMessage != null)
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          AutofillGroup(
            child: Column(
              children: [
                _buildField(_emailController, 'Email Address', Icons.email_rounded, false),
                const SizedBox(height: 18),
                _buildField(_passwordController, 'Password', Icons.lock_rounded, true),
              ],
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _forgotPassword,
              child: const Text('Forgot Password?', style: TextStyle(color: Color(0xFFE040FB), fontSize: 13)),
            ),
          ),
          const SizedBox(height: 4),
          ElevatedButton(
            onPressed: _isLoading ? null : _login,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 18),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 4,
              shadowColor: const Color(0xFFE040FB).withValues(alpha: 0.4),
            ),
            child: _isLoading
                ? const SizedBox(height: 20, width: 20, child: ProfessionalLoader(size: 20))
                : const Text('Sign In',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String hint, IconData icon, bool isPassword) {
    return TextField(
      controller: ctrl,
      obscureText: isPassword ? _obscurePassword : false,
      style: const TextStyle(color: Colors.white),
      keyboardType: hint.contains('Email') ? TextInputType.emailAddress : TextInputType.text,
      autofillHints: isPassword ? [AutofillHints.password] : [AutofillHints.email],
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
        fillColor: Colors.white.withValues(alpha: 0.08),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFF7C4DFF), width: 1.5)),
      ),
    );
  }
}
