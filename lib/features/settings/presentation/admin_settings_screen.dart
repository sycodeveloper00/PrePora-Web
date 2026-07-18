import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/theme_provider.dart';

class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});
  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  double _price = 0;
  bool _paidAccess = false;
  bool _loading = true;
  String _accountTitle = '';
  String _accountNo = '';
  String _bankName = '';
  String _appVersion = '1.0.0';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await FirebaseService.getSettings();
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() {
      _price = (settings['price'] as num?)?.toDouble() ?? 0;
      _paidAccess = settings['paidAccess'] as bool? ?? false;
      _accountTitle = settings['accountTitle'] as String? ?? '';
      _accountNo = settings['accountNo'] as String? ?? '';
      _bankName = settings['bankName'] as String? ?? '';
      _appVersion = info.version;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                const SizedBox(height: 12),
                Card(
                  color: cardColor,
                  child: Consumer(builder: (ctx, ref, _) {
                    final themeMode = ref.watch(themeModeProvider);
                    final icon = themeMode == ThemeMode.light ? Icons.light_mode_rounded : (themeMode == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.settings_brightness_rounded);
                    final label = themeMode == ThemeMode.light ? 'Light' : (themeMode == ThemeMode.dark ? 'Dark' : 'System');
                    return ListTile(
                      leading: Icon(icon, color: Colors.amber),
                      title: Text('Theme', style: TextStyle(color: textColor)),
                      subtitle: Text(label, style: TextStyle(color: hintColor, fontSize: 12)),
                      trailing: Icon(Icons.chevron_right, color: hintColor, size: 18),
                      onTap: () => _showThemeDialog(context, ref),
                    );
                  }),
                ),
                const SizedBox(height: 12),
                Card(
                  color: cardColor,
                  child: Column(children: [
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded, color: Colors.grey),
                      title: Text('Version', style: TextStyle(color: textColor)),
                      subtitle: Text('PrePora v$_appVersion', style: TextStyle(color: hintColor, fontSize: 12)),
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

  void _showBlockStudents() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final isDarkLocal = Theme.of(ctx).brightness == Brightness.dark;
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: FirebaseService.getAllStudents(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return Padding(padding: const EdgeInsets.all(40), child: Center(child: CircularProgressIndicator(color: isDarkLocal ? Colors.white : Colors.black87)));
            }
            final students = snap.data!;
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.block_rounded, color: Colors.redAccent, size: 22),
                  const SizedBox(width: 10),
                  Text('Block Students (${students.length})', style: TextStyle(color: isDarkLocal ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.close, color: isDarkLocal ? Colors.white38 : Colors.black54), onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),
                if (students.isEmpty)
                  Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No students registered.', style: TextStyle(color: isDarkLocal ? Colors.white38 : Colors.black45))))
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                    child: ListView.separated(
                      itemCount: students.length,
                      separatorBuilder: (_, __) => Divider(color: isDarkLocal ? Colors.white12 : Colors.black12, height: 1),
                      itemBuilder: (_, i) {
                        final s = students[i];
                        final uid = s['id'] as String? ?? '';
                        final name = s['name'] as String? ?? 'Unknown';
                        final email = s['email'] as String? ?? '';
                        final isBlocked = s['blocked'] as bool? ?? false;
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: isBlocked ? Colors.redAccent.withValues(alpha: 0.3) : (isDarkLocal ? Colors.white10 : Colors.black12),
                            child: Icon(Icons.person, color: isBlocked ? Colors.redAccent : (isDarkLocal ? Colors.white38 : Colors.black45)),
                          ),
                          title: Text(name, style: TextStyle(color: isDarkLocal ? Colors.white : Colors.black87, fontWeight: isBlocked ? FontWeight.bold : FontWeight.normal)),
                          subtitle: Text(email, style: TextStyle(color: isBlocked ? Colors.redAccent.withValues(alpha: 0.7) : (isDarkLocal ? Colors.white38 : Colors.black45), fontSize: 12)),
                          trailing: Switch(
                            value: isBlocked,
                            activeColor: Colors.redAccent,
                            onChanged: (v) async {
                              await FirebaseService.toggleStudentBlocked(uid, v);
                              if (ctx.mounted) setLocal(() { s['blocked'] = v; });
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ]),
            );
          },
        );
      }),
    );
  }

  void _showAppUpdates() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.update_rounded, color: Colors.cyanAccent, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text('App Updates', style: TextStyle(color: baseColor, fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(
                icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.cyanAccent, size: 28),
                onPressed: () { Navigator.pop(ctx); _showAddUpdateDialog(); },
              ),
            ]),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.firestore.collection('app_updates').orderBy('createdAt', descending: true).snapshots(),
              builder: (ctx, snap) {
                final updates = snap.data?.docs ?? [];
                if (updates.isEmpty) {
                  return Padding(padding: const EdgeInsets.all(20), child: Center(child: Column(children: [
                    Icon(Icons.update_disabled_rounded, size: 48, color: dimColor),
                    const SizedBox(height: 8),
                    Text('No updates yet', style: TextStyle(color: dimColor)),
                    const SizedBox(height: 4),
                    Text('Tap + to add a new update', style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 12)),
                  ])));
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: updates.length,
                    separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
                    itemBuilder: (_, i) {
                      final d = updates[i].data() as Map<String, dynamic>;
                      final id = updates[i].id;
                      final version = d['version'] as String? ?? '';
                      final link = d['link'] as String? ?? '';
                      final time = (d['createdAt'] as Timestamp?)?.toDate();
                      final timeStr = time != null ? '${time.day}/${time.month}/${time.year}' : '';
                      return ListTile(
                        leading: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                          child: Text('v$version', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        title: Text(link.isNotEmpty ? link : 'No link', style: TextStyle(color: baseColor, fontSize: 13)),
                        subtitle: Text(timeStr, style: TextStyle(color: dimColor, fontSize: 11)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            await FirebaseService.firestore.collection('app_updates').doc(id).delete();
                          },
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ]),
        );
      }),
    );
  }

  void _showAddUpdateDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final versionCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [
          const Icon(Icons.update_rounded, color: Colors.cyanAccent, size: 22),
          const SizedBox(width: 8),
          Text('Add Update', style: TextStyle(color: baseColor)),
        ]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: versionCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(labelText: 'Version (e.g., 1.0.1)', labelStyle: TextStyle(color: dimColor),
              filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: linkCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(labelText: 'Update Link (Google Play URL)', labelStyle: TextStyle(color: dimColor),
              filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: () async {
              final version = versionCtrl.text.trim();
              if (version.isEmpty) return;
              await FirebaseService.firestore.collection('app_updates').add({
                'version': version,
                'link': linkCtrl.text.trim(),
                'createdAt': FieldValue.serverTimestamp(),
              });
              if (d.mounted) Navigator.pop(d);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Add', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editPrice() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final ctrl = TextEditingController(text: _price.toStringAsFixed(0));
    final result = await showDialog<String>(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Text('Set Price', style: TextStyle(color: baseColor)),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, style: TextStyle(color: baseColor),
        decoration: InputDecoration(prefixText: '\$ ', hintText: 'Enter price...', hintStyle: TextStyle(color: dimColor),
          filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
    if (result != null && result.isNotEmpty) {
      final val = double.tryParse(result) ?? 0;
      await FirebaseService.updateSetting('price', val);
      setState(() => _price = val);
    }
  }

  void _editAccountInfo() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final titleCtrl = TextEditingController(text: _accountTitle);
    final noCtrl = TextEditingController(text: _accountNo);
    final bankCtrl = TextEditingController(text: _bankName);
    final saved = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Text('Account Info', style: TextStyle(color: baseColor)),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(labelText: 'Account Title', labelStyle: TextStyle(color: dimColor),
              filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: noCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(labelText: 'Account Number / IBAN', labelStyle: TextStyle(color: dimColor),
              filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: bankCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(labelText: 'Bank Name', labelStyle: TextStyle(color: dimColor),
              filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () => Navigator.pop(d, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
    if (saved == true) {
      await FirebaseService.updateSetting('accountTitle', titleCtrl.text.trim());
      await FirebaseService.updateSetting('accountNo', noCtrl.text.trim());
      await FirebaseService.updateSetting('bankName', bankCtrl.text.trim());
      setState(() { _accountTitle = titleCtrl.text.trim(); _accountNo = noCtrl.text.trim(); _bankName = bankCtrl.text.trim(); });
    }
  }

  void _showTermsDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white70 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final terms = [
      ('Acceptance of Terms', 'By using PrePora, you agree to these Terms & Conditions.', Icons.check_circle_outline_rounded, Colors.teal),
      ('Eligibility', 'PrePora is for students preparing for MDCAT, ECAT, NUST, FAST, CSS, IELTS, etc.', Icons.person_outline_rounded, Colors.blue),
      ('Account Responsibility', 'Keep your credentials secure. You are responsible for all account activity.', Icons.lock_outline_rounded, Colors.orange),
      ('Content & Usage', 'Study material is for personal use only. Redistribution is prohibited.', Icons.library_books_rounded, Colors.purple),
      ('Paid Access', 'Payments are non-refundable unless stated by admin.', Icons.payments_rounded, Colors.green),
      ('AI Assistant', 'AI responses may contain errors. Verify critical info from official sources.', Icons.smart_toy_rounded, Colors.amber),
      ('Privacy', 'Your data is used only for app functionality. Not sold to third parties.', Icons.privacy_tip_rounded, Colors.teal),
      ('Prohibited Conduct', 'Misuse or harassment may result in account suspension.', Icons.gpp_bad_rounded, Colors.redAccent),
      ('Disclaimer', 'PrePora is not affiliated with any official exam board.', Icons.warning_amber_rounded, Colors.deepOrange),
      ('Changes to Terms', 'Terms may be updated. Continued use = acceptance.', Icons.update_rounded, Colors.blueGrey),
    ];
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Icon(Icons.gavel_rounded, color: Colors.teal, size: 22),
          const SizedBox(width: 10),
          Text('Terms & Conditions', style: TextStyle(color: baseColor, fontSize: 16)),
        ]),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('Welcome to PrePora — Pakistan\'s Smart Study App.', style: TextStyle(color: dimColor, fontSize: 13)),
              ),
              ...terms.map((t) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(t.$3, color: t.$4, size: 22),
                title: Text(t.$1, style: TextStyle(color: t.$4, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text(t.$2, style: TextStyle(color: dimColor, fontSize: 12, height: 1.3)),
                dense: true,
              )),
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
}