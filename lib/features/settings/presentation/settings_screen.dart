import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/theme_provider.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = FirebaseService.currentUser;
    final userName = user?.displayName ?? 'User';
    final userEmail = user?.email ?? '';
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: cardColor,
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: isDark ? Colors.white10 : const Color(0xFF4A148C).withValues(alpha: 0.1),
                child: Text(userName[0].toUpperCase(), style: TextStyle(color: isDark ? Colors.white : const Color(0xFF4A148C), fontWeight: FontWeight.bold)),
              ),
              title: Text(userName, style: TextStyle(color: textColor, fontWeight: FontWeight.bold)),
              subtitle: Text(userEmail, style: TextStyle(color: hintColor, fontSize: 12)),
            ),
          ),
          const SizedBox(height: 16),
          Consumer(builder: (ctx, ref, _) {
            final themeMode = ref.watch(themeModeProvider);
            final icon = themeMode == ThemeMode.light ? Icons.light_mode_rounded : (themeMode == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.settings_brightness_rounded);
            final label = themeMode == ThemeMode.light ? 'Light' : (themeMode == ThemeMode.dark ? 'Dark' : 'System');
            return Card(
              color: cardColor,
              child: ListTile(
                leading: Icon(icon, color: Colors.amber),
                title: Text('Theme', style: TextStyle(color: textColor)),
                subtitle: Text(label, style: TextStyle(color: hintColor, fontSize: 12)),
                trailing: Icon(Icons.chevron_right, color: hintColor, size: 18),
                onTap: () => _showThemeDialog(context, ref),
              ),
            );
          }),
          const SizedBox(height: 16),
          Card(
            color: cardColor,
            child: ListTile(
              leading: const Icon(Icons.support_agent_rounded, color: Colors.orange),
              title: Text('Contact Support', style: TextStyle(color: textColor)),
              subtitle: Text('Need help? Get in touch', style: TextStyle(color: hintColor, fontSize: 12)),
              onTap: () => context.push('/student/feedbacks'),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: cardColor,
            child: ListTile(
              leading: const Icon(Icons.gavel_rounded, color: Colors.teal),
              title: Text('Terms & Conditions', style: TextStyle(color: textColor)),
              subtitle: Text('Usage policy & student agreement', style: TextStyle(color: hintColor, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: hintColor, size: 18),
              onTap: () => _showTermsDialog(context),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            color: cardColor,
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.info_outline_rounded, color: Colors.grey),
                title: Text('Version', style: TextStyle(color: textColor)),
                subtitle: Text('PrePora v1.0.0', style: TextStyle(color: hintColor, fontSize: 12)),
              ),
              Divider(height: 1, color: isDark ? Colors.white12 : Colors.black12),
              ListTile(
                leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
                title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  FirebaseService.signOut();
                  context.go('/auth/login');
                },
              ),
            ]),
          ),
        ],
      ),
    );
  }

  void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(themeModeProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Choose Theme', style: TextStyle(color: textColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.light_mode_rounded, color: Colors.amber),
            title: Text('Light', style: TextStyle(color: textColor)),
            onTap: () { notifier.set(ThemeMode.light); Navigator.pop(d); },
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_rounded, color: Colors.blueGrey),
            title: Text('Dark', style: TextStyle(color: textColor)),
            onTap: () { notifier.set(ThemeMode.dark); Navigator.pop(d); },
          ),
          ListTile(
            leading: const Icon(Icons.settings_brightness_rounded, color: Colors.teal),
            title: Text('System', style: TextStyle(color: textColor)),
            subtitle: Text('Follow device theme', style: TextStyle(color: hintColor, fontSize: 11)),
            onTap: () { notifier.set(ThemeMode.system); Navigator.pop(d); },
          ),
        ]),
      ),
    );
  }

  void _showTermsDialog(BuildContext context) {
    final terms = [
      ('Acceptance of Terms', 'By using PrePora, you agree to these Terms & Conditions. If you do not agree, please discontinue use.', Icons.check_circle_outline_rounded, Colors.teal),
      ('Eligibility', 'PrePora is intended for students preparing for MDCAT, ECAT, NUST, FAST, CSS, IELTS, and similar competitive exams. Users must be 13 years of age or older.', Icons.person_outline_rounded, Colors.blue),
      ('Account Responsibility', 'You are responsible for keeping your login credentials secure. Do not share your account with others. Any activity performed under your account is your responsibility.', Icons.lock_outline_rounded, Colors.orange),
      ('Content & Usage', 'All study material, lectures, notes, and mock tests are provided for personal educational use only. Redistribution, copying, or commercial use of any content without permission is strictly prohibited.', Icons.library_books_rounded, Colors.purple),
      ('Paid Access', 'Some features may require payment or admin verification. Payments made are non-refundable unless otherwise stated by the admin.', Icons.payments_rounded, Colors.green),
      ('AI Assistant', 'The AI tutor is provided as a study aid. Information provided by the AI may contain errors. Always verify critical information with official sources and textbooks.', Icons.smart_toy_rounded, Colors.amber),
      ('Privacy', 'Your personal information (name, email) is used solely for app functionality. We do not sell your data to third parties.', Icons.privacy_tip_rounded, Colors.teal),
      ('Prohibited Conduct', 'Users may not use PrePora to spread misinformation, harass others, or attempt to hack or misuse the platform. Violations may result in account suspension.', Icons.gpp_bad_rounded, Colors.redAccent),
      ('Disclaimer', 'PrePora is not affiliated with any official examination board. Study results depend on the student\'s own effort and dedication.', Icons.warning_amber_rounded, Colors.deepOrange),
      ('Changes to Terms', 'These terms may be updated periodically. Continued use of the app after changes constitutes acceptance.', Icons.update_rounded, Colors.blueGrey),
    ];
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: const Color(0xFF1A0533),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.gavel_rounded, color: Colors.teal, size: 22),
          SizedBox(width: 10),
          Text('Terms & Conditions', style: TextStyle(color: Colors.white, fontSize: 16)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('Welcome to PrePora — Pakistan\'s Smart Study App.', style: TextStyle(color: Colors.white70, fontSize: 13)),
              ),
              ...terms.map((t) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(t.$3, color: t.$4, size: 22),
                title: Text(t.$1, style: TextStyle(color: t.$4, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(t.$2, style: const TextStyle(color: Colors.white70, fontSize: 12, height: 1.3)),
                dense: true,
              )),
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('For questions, contact us through the Feedback section in Settings.', style: TextStyle(color: Colors.white38, fontSize: 11)),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(d),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('I Understand', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}