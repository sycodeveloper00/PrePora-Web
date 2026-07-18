import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils.dart';

class AdminControlPanelScreen extends StatefulWidget {
  const AdminControlPanelScreen({super.key});
  @override
  State<AdminControlPanelScreen> createState() => _AdminControlPanelScreenState();
}

class _AdminControlPanelScreenState extends State<AdminControlPanelScreen> {
  double _price = 0;
  bool _paidAccess = false;
  bool _loading = true;
  String _accountTitle = '';
  String _accountNo = '';
  String _bankName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await FirebaseService.getSettings();
    if (mounted) setState(() {
      _price = (settings['price'] as num?)?.toDouble() ?? 0;
      _paidAccess = settings['paidAccess'] as bool? ?? false;
      _accountTitle = settings['accountTitle'] as String? ?? '';
      _accountNo = settings['accountNo'] as String? ?? '';
      _bankName = settings['bankName'] as String? ?? '';
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Control Panel', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ctrlSection(context, 'Paid Access', [
                  _ctrlTile(context, Icons.verified_user_rounded, Colors.blue, 'Student Paid Access', _paidAccess ? 'ON - Manual verification' : 'OFF - Auto verify', trailing: Switch(
                    value: _paidAccess, activeColor: Colors.blue,
                    onChanged: (v) async { await FirebaseService.updateSetting('paidAccess', v); if (mounted) setState(() => _paidAccess = v); },
                  )),
                  _ctrlTile(context, Icons.attach_money_rounded, Colors.green, 'Set Price', 'Current: Rs.${_price.toStringAsFixed(0)}', onTap: () => _showSetPriceDialog(context)),
                  _ctrlTile(context, Icons.account_balance_rounded, Colors.teal, 'Account Info', _accountTitle.isNotEmpty ? '$_accountTitle - $_bankName' : 'Add bank details', onTap: () => _showAccountInfoDialog(context)),
                ]),
                const SizedBox(height: 8),
                _ctrlSection(context, 'Student Management', [
                  _ctrlTile(context, Icons.admin_panel_settings_rounded, Colors.cyan, 'Control Student Panel', 'Open full admin panel for a student', onTap: () => _showStudentListForPanel(context)),
                  _ctrlTile(context, Icons.history_rounded, Colors.lime, 'Student Activity', 'Login history & device info', onTap: () => _showStudentActivity(context)),
                  _ctrlTile(context, Icons.school_rounded, Colors.blue, 'Students', 'View registered students', onTap: () => _showAllStudents(context)),
                ]),
                const SizedBox(height: 8),
                _ctrlSection(context, 'Restrictions', [
                  _ctrlTile(context, Icons.block_rounded, Colors.redAccent, 'Block Students', 'Manage blocked student accounts', onTap: () => _showBlockStudents(context)),
                  _ctrlTile(context, Icons.people_alt_rounded, Colors.teal, 'Assistant', 'Create & manage Assistant accounts', onTap: () => _showAllAssistant(context)),
                ]),
                const SizedBox(height: 8),
                _ctrlSection(context, 'App', [
                  _ctrlTile(context, Icons.update_rounded, Colors.cyanAccent, 'App Updates', 'Manage version & update banner', onTap: () => _showAppUpdates(context)),
                ]),
              ],
            ),
    );
  }

  // ─── UI Helpers ─────────────────────────────────────────────────────────

  Widget _ctrlSection(BuildContext context, String title, List<Widget> tiles) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 6),
        child: Text(title, style: TextStyle(color: baseColor.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
      ),
      Container(
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.05 : 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.08 : 0.06)),
        ),
        child: Column(children: tiles),
      ),
    ]);
  }

  Widget _ctrlTile(BuildContext context, IconData icon, Color iconColor, String title, String subtitle, {Widget? trailing, VoidCallback? onTap}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 22),
      title: Text(title, style: TextStyle(color: baseColor, fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: Text(subtitle, style: TextStyle(color: dimColor, fontSize: 11)),
      trailing: trailing ?? Icon(Icons.chevron_right, color: dimColor, size: 18),
      onTap: onTap,
      dense: true,
    );
  }

  // ─── Set Price Dialog ─────────────────────────────────────────────────

  void _showSetPriceDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final ctrl = TextEditingController(text: _price.toStringAsFixed(0));
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, title: Text('Set Price', style: TextStyle(color: baseColor)),
      content: TextField(controller: ctrl, keyboardType: TextInputType.number, style: TextStyle(color: baseColor), decoration: InputDecoration(filled: true, fillColor: isDark ? Colors.white10 : Colors.black12, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))), ElevatedButton(onPressed: () async {
        final result = ctrl.text.trim();
        if (result.isNotEmpty) { final p = double.tryParse(result) ?? 0; await FirebaseService.updateSetting('price', p); if (mounted) setState(() => _price = p); }
        if (d.mounted) Navigator.pop(d);
      }, child: const Text('Save'))],
    ));
  }

  // ─── Account Info Dialog ──────────────────────────────────────────────

  void _showAccountInfoDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final titleCtrl = TextEditingController(text: _accountTitle);
    final noCtrl = TextEditingController(text: _accountNo);
    final bankCtrl = TextEditingController(text: _bankName);
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, title: Text('Account Info', style: TextStyle(color: baseColor)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Account Title', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        TextField(controller: noCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Account Number', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        TextField(controller: bankCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Bank Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.updateSetting('accountTitle', titleCtrl.text.trim());
          await FirebaseService.updateSetting('accountNo', noCtrl.text.trim());
          await FirebaseService.updateSetting('bankName', bankCtrl.text.trim());
          if (mounted) setState(() { _accountTitle = titleCtrl.text.trim(); _accountNo = noCtrl.text.trim(); _bankName = bankCtrl.text.trim(); });
          if (d.mounted) Navigator.pop(d);
        }, child: const Text('Save')),
      ],
    ));
  }

  // ─── Student List for Panel ───────────────────────────────────────────

  void _showStudentListForPanel(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0D0D2E) : Colors.grey.shade50;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: FirebaseService.getAllStudents(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return SizedBox(height: 300, child: Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black87)));
          final students = snap.data ?? [];
          return StatefulBuilder(builder: (ctx, setLocal) {
            if (students.isEmpty) return SizedBox(height: 200, child: Center(child: Text('No students registered', style: TextStyle(color: dimColor))));
            return DraggableScrollableSheet(
              expand: false, maxChildSize: 0.85, initialChildSize: 0.5,
              builder: (ctx, scrollCtrl) => Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(children: [
                    const Icon(Icons.admin_panel_settings_rounded, color: Colors.cyan, size: 22),
                    const SizedBox(width: 8),
                    Text('Select Student', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(icon: Icon(Icons.close, color: dimColor), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl, padding: const EdgeInsets.all(16),
                    itemCount: students.length,
                    itemBuilder: (context, i) {
                      final s = students[i];
                      final uid = s['id'] as String;
                      final name = s['name'] as String? ?? 'Unknown';
                      final email = s['email'] as String? ?? '';
                      return Card(
                        color: cardBg, margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: Colors.cyan.shade700, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                          title: Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold)),
                          subtitle: Text(email, style: TextStyle(color: dimColor, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.cyan, size: 20),
                          onTap: () { Navigator.pop(ctx); context.push('/admin', extra: {'studentUid': uid, 'studentName': name}); },
                        ),
                      );
                    },
                  ),
                ),
              ]),
            );
          });
        },
      ),
    );
  }

  // ─── Student Activity ─────────────────────────────────────────────────

  void _showStudentActivity(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0D0D2E) : Colors.grey.shade50;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.9,
        child: StudentActivityPage(
          isDark: isDark, baseColor: baseColor, dimColor: dimColor, bgColor: bgColor, cardBg: cardBg,
        ),
      ),
    );
  }

  // ─── All Students ─────────────────────────────────────────────────────

  void _showAllStudents(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0D0D2E) : Colors.grey.shade50;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: FirebaseService.getAllStudents(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return SizedBox(height: 300, child: Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black87)));
          final students = snap.data ?? [];
          return StatefulBuilder(builder: (ctx, setLocal) {
            if (students.isEmpty) return SizedBox(height: 200, child: Center(child: Text('No students registered', style: TextStyle(color: dimColor))));
            return DraggableScrollableSheet(
              expand: false, maxChildSize: 0.85, initialChildSize: 0.7,
              builder: (ctx, scrollCtrl) => Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(children: [
                    Icon(Icons.school_rounded, color: Colors.blue, size: 22),
                    const SizedBox(width: 8),
                    Text('All Students (${students.length})', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(icon: Icon(Icons.close, color: dimColor), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl, padding: const EdgeInsets.all(16),
                    itemCount: students.length,
                    itemBuilder: (context, i) {
                      final s = students[i];
                      final name = s['name'] as String? ?? 'Unknown';
                      final email = s['email'] as String? ?? '';
                      final blocked = s['blocked'] == true;
                      final verified = s['verified'] == true;
                      return Card(
                        color: cardBg, margin: const EdgeInsets.only(bottom: 6),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: blocked ? Colors.red.shade700 : Colors.blue.shade700, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                          title: Row(children: [
                            Flexible(child: Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                            if (blocked) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.redAccent, borderRadius: BorderRadius.circular(4)), child: const Text('BLOCKED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))],
                            if (!verified) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(4)), child: const Text('UNVERIFIED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)))],
                          ]),
                          subtitle: Text(email, style: TextStyle(color: dimColor, fontSize: 12)),
                          trailing: IconButton(
                            icon: Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            onPressed: () async {
                              final uid = s['id'] as String? ?? '';
                              final confirm = await showDialog<bool>(
                                context: ctx,
                                builder: (d) => AlertDialog(
                                  backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
                                  title: Text('Delete Student?', style: TextStyle(color: baseColor)),
                                  content: Text('Delete "$name"? This cannot be undone.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
                                    ElevatedButton(onPressed: () => Navigator.pop(d, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
                                  ],
                                ),
                              );
                              if (confirm == true && uid.isNotEmpty) {
                                await FirebaseService.firestore.collection('users').doc(uid).delete();
                                await FirebaseService.deleteUserFromAuth(uid);
                                if (ctx.mounted) Navigator.pop(ctx);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            );
          });
        },
      ),
    );
  }

  // ─── Block Students ───────────────────────────────────────────────────

  void _showBlockStudents(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0D0D2E) : Colors.grey.shade50;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: FirebaseService.getAllStudents(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return SizedBox(height: 300, child: Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black87)));
          final allStudents = snap.data ?? [];
          return StatefulBuilder(builder: (ctx, setLocal) {
            final students = allStudents.where((s) => s['blocked'] == true || s['blocked'] == null || s['blocked'] == false).toList();
            if (students.isEmpty) return SizedBox(height: 200, child: Center(child: Text('No students', style: TextStyle(color: dimColor))));
            return DraggableScrollableSheet(
              expand: false, maxChildSize: 0.85, initialChildSize: 0.6,
              builder: (ctx, scrollCtrl) => Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text('Manage Blocked Students', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
                ),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl, padding: const EdgeInsets.all(16),
                    itemCount: students.length,
                    itemBuilder: (context, i) {
                      final s = students[i];
                      final uid = s['id'] as String;
                      final name = s['name'] as String? ?? 'Unknown';
                      final email = s['email'] as String? ?? '';
                      final blocked = s['blocked'] == true;
                      final verified = s['verified'] == true;
                      return Card(
                        color: cardBg, margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              CircleAvatar(backgroundColor: blocked ? Colors.red : Colors.green, child: Icon(blocked ? Icons.block_rounded : Icons.check_circle_outline_rounded, color: Colors.white, size: 20)),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold)),
                                Text(email, style: TextStyle(color: dimColor, fontSize: 12)),
                              ])),
                            ]),
                            const SizedBox(height: 8),
                            Row(children: [
                              Expanded(
                                child: SizedBox(
                                  height: 32,
                                  child: TextButton(
                                    onPressed: () async {
                                      if (!debounce('ctrl_block_$uid')) return;
                                      await FirebaseService.firestore.collection('users').doc(uid).update({'blocked': !blocked});
                                      if (ctx.mounted) setLocal(() => s['blocked'] = !blocked);
                                    },
                                    style: TextButton.styleFrom(backgroundColor: blocked ? Colors.green : Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                                    child: Text(blocked ? 'Unblock' : 'Block', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: SizedBox(
                                  height: 32,
                                  child: TextButton(
                                    onPressed: () async {
                                      if (!debounce('ctrl_verify_$uid')) return;
                                      await FirebaseService.firestore.collection('users').doc(uid).update({'verified': !verified});
                                      if (ctx.mounted) setLocal(() => s['verified'] = !verified);
                                    },
                                    style: TextButton.styleFrom(backgroundColor: verified ? Colors.orange : Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8)),
                                    child: Text(verified ? 'Unverify' : 'Verify', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
              ]),
            );
          });
        },
      ),
    );
  }

  // ─── All Assistant ───────────────────────────────────────────────────────

  void _showAllAssistant(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false, maxChildSize: 0.85, initialChildSize: 0.6,
        builder: (ctx, scrollCtrl) => Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.people_alt_rounded, color: Colors.teal, size: 22),
              const SizedBox(width: 8),
              Expanded(child: Text('Assistant', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(icon: const Icon(Icons.person_add_rounded, color: Colors.orange, size: 26), onPressed: () { Navigator.pop(ctx); _showCreateAssistantDialog(context); }),
            ]),
          ),
          Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getAllAssistant(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.person_off_rounded, size: 50, color: isDark ? Colors.white12 : Colors.black12),
                    const SizedBox(height: 12),
                    Text('No Assistant yet', style: TextStyle(color: dimColor, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Tap + to create an Assistant account', style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 12)),
                  ]));
                }
                final docs = snap.data!.docs;
                return ListView.builder(
                  controller: scrollCtrl, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final data = docs[i].data() as Map<String, dynamic>;
                    final name = data['name'] as String? ?? 'Unknown';
                    final email = data['email'] as String? ?? '';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.05 : 0.03),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.1 : 0.08)),
                      ),
                      child: Row(children: [
                        CircleAvatar(backgroundColor: Colors.teal.withValues(alpha: isDark ? 0.2 : 0.1), child: const Icon(Icons.person, color: Colors.teal, size: 20)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(email, style: const TextStyle(color: Colors.teal, fontSize: 12)),
                        ])),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            final uid = docs[i].id;
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (d) => AlertDialog(
                                backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
                                title: Text('Delete Assistant?', style: TextStyle(color: baseColor)),
                                content: Text('Delete "$name"? This removes all folder access.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
                                  ElevatedButton(onPressed: () => Navigator.pop(d, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
                                ],
                              ),
                            );
                            if (confirm == true) {
                              await FirebaseService.deleteAssistantAccount(uid);
                              await FirebaseService.deleteUserFromAuth(uid);
                            }
                          },
                        ),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
        ]),
      ),
    );
  }

  void _showCreateAssistantDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController();
    Map<String, String>? creds;
    bool loading = false;
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          backgroundColor: bgColor,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [const Icon(Icons.person_add_rounded, color: Colors.orange), const SizedBox(width: 8), Text('New Assistant Account', style: TextStyle(color: baseColor, fontSize: 15))]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (creds == null)
              TextField(
                controller: nameCtrl, style: TextStyle(color: baseColor),
                decoration: InputDecoration(
                  hintText: 'Assistant name...', hintStyle: TextStyle(color: dimColor),
                  filled: true, fillColor: fillColor,
                  prefixIcon: const Icon(Icons.person, color: Colors.orange),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            if (creds != null)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withValues(alpha: 0.4))),
                child: Column(children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 28),
                  const SizedBox(height: 8),
                  Text('Email: ${creds!['email']}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Password: ${creds!['password']}', style: const TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('Share these credentials with the Assistant', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 11)),
                ]),
              ),
            if (error != null) ...[const SizedBox(height: 12), Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 13))],
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Close', style: TextStyle(color: baseColor))),
            if (creds == null)
              ElevatedButton(
                onPressed: loading ? null : () async {
                  if (nameCtrl.text.trim().isEmpty) return;
                  setLocal(() { loading = true; error = null; });
                  try {
                    final result = await FirebaseService.createAssistantAccount(nameCtrl.text.trim());
                    setLocal(() { creds = result; loading = false; });
                  } catch (e) {
                    setLocal(() { error = e.toString(); loading = false; });
                  }
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                child: const Text('Create', style: TextStyle(color: Colors.white)),
              ),
          ],
        );
      }),
    );
  }

  // ─── App Updates ──────────────────────────────────────────────────────

  void _showAppUpdates(BuildContext context) {
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
              IconButton(icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.cyanAccent, size: 28), onPressed: () { Navigator.pop(ctx); _showAddUpdateDialog(context); }),
            ]),
            const SizedBox(height: 16),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.firestore.collection('app_updates').orderBy('createdAt', descending: true).snapshots(),
              builder: (ctx, snap) {
                final updates = snap.data?.docs ?? [];
                if (updates.isEmpty) {
                  return Padding(padding: const EdgeInsets.all(20), child: Center(child: Column(children: [
                    Icon(Icons.update_disabled_rounded, size: 48, color: dimColor),
                    const SizedBox(height: 8), Text('No updates yet', style: TextStyle(color: dimColor)),
                    const SizedBox(height: 4), Text('Tap + to add', style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 12)),
                  ])));
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                  child: ListView.separated(shrinkWrap: true, itemCount: updates.length,
                    separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
                    itemBuilder: (_, i) {
                      final d = updates[i].data() as Map<String, dynamic>;
                      final id = updates[i].id;
                      final version = d['version'] as String? ?? '';
                      final link = d['link'] as String? ?? '';
                      final time = (d['createdAt'] as Timestamp?)?.toDate();
                      final timeStr = time != null ? '${time.day}/${time.month}/${time.year}' : '';
                      return ListTile(
                        leading: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                          child: Text('v$version', style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 12))),
                        title: Text(link.isNotEmpty ? link : 'No link', style: TextStyle(color: baseColor, fontSize: 13)),
                        subtitle: Text(timeStr, style: TextStyle(color: dimColor, fontSize: 11)),
                        trailing: IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          onPressed: () async { await FirebaseService.firestore.collection('app_updates').doc(id).delete(); }),
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

  void _showAddUpdateDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final versionCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.update_rounded, color: Colors.cyanAccent, size: 22), const SizedBox(width: 8), Text('Add Update', style: TextStyle(color: baseColor))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: versionCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Version (e.g., 1.0.1)', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        TextField(controller: linkCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Update Link', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          final version = versionCtrl.text.trim();
          if (version.isEmpty) return;
          await FirebaseService.firestore.collection('app_updates').add({'version': version, 'link': linkCtrl.text.trim(), 'createdAt': FieldValue.serverTimestamp()});
          if (d.mounted) Navigator.pop(d);
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Add', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
}

class StudentActivityPage extends StatefulWidget {
  final bool isDark;
  final Color baseColor, dimColor, bgColor, cardBg;
  const StudentActivityPage({super.key, required this.isDark, required this.baseColor, required this.dimColor, required this.bgColor, required this.cardBg});
  @override
  State<StudentActivityPage> createState() => _StudentActivityPageState();
}

class _StudentActivityPageState extends State<StudentActivityPage> {
  List<Map<String, dynamic>>? _students;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final students = await FirebaseService.getAllStudents();
      if (mounted) setState(() => _students = students);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child: Row(children: [
            const Icon(Icons.history_rounded, color: Colors.lime, size: 22),
            const SizedBox(width: 8),
            Text('Student Activity', style: TextStyle(color: widget.baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
            const Spacer(),
            IconButton(icon: Icon(Icons.close, color: widget.dimColor), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Divider(color: widget.isDark ? Colors.white12 : Colors.black12),
        Expanded(
          child: _error != null
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 12),
                  Text('Error loading activity', style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(_error!, style: TextStyle(color: widget.dimColor, fontSize: 12), textAlign: TextAlign.center),
                ]))
              : _students == null
              ? const Center(child: CircularProgressIndicator())
              : _students!.isEmpty
                  ? Center(child: Text('No students registered', style: TextStyle(color: widget.dimColor)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _students!.length,
                      itemBuilder: (context, i) {
                        final s = _students![i];
                        final uid = s['id'] as String? ?? '';
                        final name = s['name'] as String? ?? 'Unknown';
                        final email = s['email'] as String? ?? '';
                        return Card(
                          color: widget.cardBg, margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: Colors.lime.shade800, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                            title: Text(name, style: TextStyle(color: widget.baseColor, fontWeight: FontWeight.bold)),
                            subtitle: Text(email, style: TextStyle(color: widget.dimColor, fontSize: 12)),
                            trailing: const Icon(Icons.chevron_right, color: Colors.lime, size: 20),
                            onTap: () => _showStudentLoginHistory(uid, name),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  void _showStudentLoginHistory(String uid, String name) {
    final isDark = widget.isDark;
    final baseColor = widget.baseColor;
    final dimColor = widget.dimColor;
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: widget.bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: Colors.lime.shade800, child: Text(name[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Login Activity', style: TextStyle(color: dimColor, fontSize: 12)),
            ])),
            IconButton(icon: Icon(Icons.close, color: dimColor), onPressed: () => Navigator.pop(ctx)),
          ]),
          const SizedBox(height: 16),
          SizedBox(
            height: 300,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.firestore.collection('login_attempts')
                  .where('uid', isEqualTo: uid)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.hasError) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
                    const SizedBox(height: 8),
                    Text('Could not load history', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('${snap.error}', style: TextStyle(color: dimColor, fontSize: 10), textAlign: TextAlign.center)),
                  ]));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator(strokeWidth: 2));
                }
                final logs = snap.data!.docs.toList();
                logs.sort((a, b) {
                  final aTime = (a.data() as Map<String, dynamic>)['timestamp'] as String? ?? '';
                  final bTime = (b.data() as Map<String, dynamic>)['timestamp'] as String? ?? '';
                  return bTime.compareTo(aTime);
                });
                if (logs.isEmpty) {
                  return Center(child: Text('No login history yet', style: TextStyle(color: dimColor)));
                }
                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: logs.length,
                  separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
                  itemBuilder: (_, i) {
                    final d = logs[i].data() as Map<String, dynamic>;
                    final timeStr = d['timestamp'] as String? ?? '';
                    final deviceModel = d['deviceModel'] as String? ?? 'Unknown device';
                    final deviceId = d['deviceId'] as String? ?? '';
                    final timeDisplay = timeStr.isNotEmpty ? timeStr.replaceFirst('T', ' ').substring(0, 19) : 'N/A';
                    return ListTile(
                      leading: const Icon(Icons.login_rounded, color: Colors.green, size: 20),
                      title: Text(deviceModel, style: TextStyle(color: baseColor, fontSize: 13, fontWeight: FontWeight.bold)),
                      subtitle: Text('$timeDisplay • ${deviceId.isNotEmpty ? deviceId.substring(0, 8) : "?"}', style: TextStyle(color: dimColor, fontSize: 11)),
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () { Navigator.pop(ctx); _showSendNotificationDialog(uid, name); },
              icon: const Icon(Icons.notifications_active_rounded, size: 18),
              label: const Text('Send Notification'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ]),
      ),
    );
  }

  void _showSendNotificationDialog(String uid, String name) {
    final msgCtrl = TextEditingController();
    final isDark = widget.isDark;
    final baseColor = widget.baseColor;
    final dimColor = widget.dimColor;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: widget.bgColor,
        title: Text('Notify $name', style: TextStyle(color: baseColor, fontSize: 16)),
        content: TextField(
          controller: msgCtrl, maxLines: 3,
          style: TextStyle(color: baseColor),
          decoration: InputDecoration(
            hintText: 'Type your notification message...', hintStyle: TextStyle(color: dimColor),
            filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: () async {
              if (!debounce('ctrl_notif_send')) return;
              final msg = msgCtrl.text.trim();
              if (msg.isEmpty) return;
              await FirebaseService.addTargetedNotification(uid, msg);
              if (d.mounted) Navigator.pop(d);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notification sent to $name')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
