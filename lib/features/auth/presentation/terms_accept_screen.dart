import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';

class TermsAcceptScreen extends StatefulWidget {
  const TermsAcceptScreen({super.key});
  @override
  State<TermsAcceptScreen> createState() => _TermsAcceptScreenState();
}

class _TermsAcceptScreenState extends State<TermsAcceptScreen> {
  bool _agreed = false;

  final _terms = [
    ('Acceptance', 'By creating an account, you agree to these Terms & Conditions. If you do not agree, do not use the app.'),
    ('Eligibility', 'You must be at least 13 years old. Students preparing for MDCAT, ECAT, NUST, FAST, CSS, IELTS, and other exams are welcome.'),
    ('Account Responsibility', 'You are responsible for all activity under your account. Keep your credentials secure.'),
    ('Content & Usage', 'All study content is for personal use only. Redistribution, resale, or sharing of paid content is strictly prohibited.'),
    ('Paid Access', 'Payment is required for full access. Fees are non-refundable unless specified otherwise.'),
    ('AI Assistant', 'The AI tutor provides study assistance only. Always verify critical information from official sources.'),
    ('Privacy', 'We collect minimal data (name, email, study progress). We do not share your data with third parties.'),
    ('Prohibited Conduct', 'Sharing accounts, uploading harmful content, or misusing the platform may result in account termination.'),
    ('PDF & Notes', 'You can annotate PDFs, save notes, and manage them in the Notes tab. Saved notes can be renamed or deleted.'),
    ('In-App Browser', 'All links (YouTube, Google Drive, websites) open inside the app for a seamless experience.'),
    ('App Updates', 'The app may show update banners for new versions. You are encouraged to update for the best experience.'),
    ('Security', 'Login activity is monitored. Suspicious activity across multiple devices may result in account warnings or blocks.'),
    ('Disclaimer', 'PrePora is an educational support tool. We do not guarantee exam results or admission success.'),
    ('Changes', 'We may update these terms. Continued use after changes means you accept the new terms.'),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark ? [const Color(0xFF0D0D1A), const Color(0xFF1A0533)] : [const Color(0xFFF5F0FF), const Color(0xFFE8D5F5)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      const SizedBox(height: 20),
                      Icon(Icons.description_rounded, size: 64, color: isDark ? const Color(0xFFB388FF) : const Color(0xFF4A148C)),
                      const SizedBox(height: 16),
                      Text('Terms & Conditions',
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold,
                              color: isDark ? Colors.white : const Color(0xFF1A0533))),
                      const SizedBox(height: 8),
                      Text('Please read and accept to continue',
                          style: TextStyle(color: isDark ? Colors.white54 : Colors.black54)),
                      const SizedBox(height: 24),
                      ..._terms.map((t) => Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.check_circle_outline_rounded, size: 18,
                                  color: isDark ? const Color(0xFFB388FF) : const Color(0xFF4A148C)),
                              const SizedBox(width: 8),
                              Text(t.$1,
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15,
                                      color: isDark ? Colors.white : const Color(0xFF1A0533))),
                            ]),
                            const SizedBox(height: 6),
                            Text(t.$2, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13)),
                          ],
                        ),
                      )),
                    ],
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black26 : Colors.white.withValues(alpha: 0.9),
                  border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                ),
                child: Column(
                  children: [
                    InkWell(
                      onTap: () => setState(() => _agreed = !_agreed),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: _agreed ? (isDark ? const Color(0xFFB388FF) : const Color(0xFF4A148C)) : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: _agreed ? Colors.transparent : (isDark ? Colors.white38 : Colors.black38)),
                            ),
                            child: _agreed ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                          ),
                          const SizedBox(width: 12),
                          Text('I agree and continue',
                              style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _agreed ? () async {
                          await FirebaseService.firestore.collection('users').doc(FirebaseService.currentUser?.uid)
                              .set({'termsAccepted': true, 'termsAcceptedAt': FieldValue.serverTimestamp()}, SetOptions(merge: true));
                          if (context.mounted) context.go('/dashboard');
                        } : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isDark ? const Color(0xFF4A148C) : const Color(0xFF4A148C),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          disabledBackgroundColor: isDark ? Colors.white12 : Colors.black12,
                        ),
                        child: const Text('Continue', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
