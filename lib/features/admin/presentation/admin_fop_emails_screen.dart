import 'package:flutter/material.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/supabase_read_service.dart';

class AdminFopEmailsScreen extends StatefulWidget {
  const AdminFopEmailsScreen({super.key});
  @override
  State<AdminFopEmailsScreen> createState() => _AdminFopEmailsScreenState();
}

class _AdminFopEmailsScreenState extends State<AdminFopEmailsScreen> {
  Set<String> _emails = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final emails = await FirebaseService.getFopAllowedEmails();
    if (mounted) setState(() { _emails = emails; _loading = false; });
  }

  void _showAddEmailDialog() {
    final ctrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Text('Add FOP Email', style: TextStyle(color: baseColor, fontSize: 16)),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.emailAddress,
        style: TextStyle(color: baseColor),
        decoration: InputDecoration(
          hintText: 'student@example.com',
          hintStyle: TextStyle(color: dimColor),
          filled: true,
          fillColor: isDark ? Colors.white10 : Colors.black12,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(
          onPressed: _saving ? null : () async {
            final email = ctrl.text.trim();
            if (email.isEmpty || !email.contains('@')) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter valid email'), backgroundColor: Colors.red));
              return;
            }
            if (_emails.contains(email.toLowerCase())) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Email already added'), backgroundColor: Colors.orange));
              return;
            }
            setState(() => _saving = true);
            final ok = await SupabaseReadService.addFopEmail(email);
            FirebaseService.invalidateFopEmailsCache();
            setState(() { _saving = false; });
            if (ok) {
              _emails.add(email.toLowerCase());
              if (mounted) setState(() {});
              if (d.mounted) Navigator.pop(d);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$email authorized for FOP'), backgroundColor: Colors.green));
            } else {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to add email'), backgroundColor: Colors.red));
            }
          },
          child: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Add'),
        ),
      ],
    ));
  }

  Future<void> _removeEmail(String email) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove Email'),
        content: Text('Remove "$email" from FOP access?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(d, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _saving = true);
    final ok = await SupabaseReadService.removeFopEmail(email);
    FirebaseService.invalidateFopEmailsCache();
    setState(() { _saving = false; });
    if (ok) {
      _emails.remove(email.toLowerCase());
      if (mounted) setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$email removed from FOP'), backgroundColor: Colors.orange));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to remove email'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return Scaffold(
      appBar: AppBar(
        title: const Text('FOP Emails', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, color: Colors.orange),
            tooltip: 'Add Email',
            onPressed: _showAddEmailDialog,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _emails.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.school_rounded, size: 64, color: dimColor),
                      const SizedBox(height: 16),
                      Text('No FOP emails yet', style: TextStyle(color: dimColor, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Tap + to add authorized emails', style: TextStyle(color: dimColor, fontSize: 12)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _emails.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) {
                    final email = _emails.elementAt(i);
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: baseColor.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.person_rounded, color: Colors.orange, size: 20),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(email, style: TextStyle(color: baseColor, fontWeight: FontWeight.w600, fontSize: 14)),
                                const SizedBox(height: 2),
                                Text('FOP Authorized', style: TextStyle(color: Colors.green, fontSize: 11)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_rounded, color: Colors.red.withValues(alpha: 0.7), size: 20),
                            tooltip: 'Remove',
                            onPressed: _saving ? null : () => _removeEmail(email),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}
