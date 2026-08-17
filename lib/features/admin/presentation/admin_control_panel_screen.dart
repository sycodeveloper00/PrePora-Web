import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../../core/utils.dart';
import '../../../core/widgets/professional_loader.dart';
import '../../student/presentation/student_progress_screen.dart';
import '../../../core/widgets/gender_badge.dart';

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
  DateTime? _trialEnd;
  bool _trialLoading = true;
  Timer? _trialTimer;
  Duration _remaining = Duration.zero;

  @override
  void initState() {
    super.initState();
    _load();
    _loadTrial();
    _trialTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        if (_trialEnd != null) {
          _remaining = _trialEnd!.difference(DateTime.now());
          if (_remaining.isNegative) _remaining = Duration.zero;
        }
      });
    });
  }

  @override
  void dispose() {
    _trialTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadTrial() async {
    final end = await FirebaseService.getActiveTrialEndTime();
    if (mounted) setState(() {
      _trialEnd = end;
      _trialLoading = false;
    });
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

  String _trialSubtitle() {
    if (_paidAccess) return 'Turn OFF Paid Access to enable';
    if (_trialLoading) return 'Checking trial status...';
    final end = _trialEnd;
    if (end == null) return 'Give unverified students free trial';
    if (!end.isAfter(DateTime.now())) return 'Trial ended - Give free trial';
    return 'Active - Ends: ${_formatTrialEndDate(end)}';
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
          ? const Center(child: ProfessionalLoader())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ctrlSection(context, 'Paid Access', [
                  _ctrlTile(context, Icons.verified_user_rounded, Colors.blue, 'Student Paid Access', _paidAccess ? 'ON - Manual verification' : 'OFF - Auto verify', trailing: Switch(
                    value: _paidAccess, activeColor: Colors.blue,
                    onChanged: (v) async { await FirebaseService.updateSetting('paidAccess', v); if (mounted) setState(() => _paidAccess = v); },
                  )),
                  _ctrlTile(context, Icons.timer_rounded, Colors.orange, 'Free Trial', _trialSubtitle(), onTap: _paidAccess || _trialLoading ? null : () => _showFreeTrialDialog(context)),
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
                  _ctrlTile(context, Icons.cloud_upload_rounded, Colors.deepPurple, 'Storage Settings', 'Manage Supabase, Cloudinary & upload providers', onTap: () => context.push('/admin/storage-settings')),
                  _ctrlTile(context, Icons.auto_awesome_rounded, Colors.indigo, 'AI API Keys', 'Add & manage AI provider keys (BazaarLink, Groq, Gemini)', onTap: () => context.push('/admin/ai-api-keys')),
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
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Text(title, style: TextStyle(color: baseColor.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
      ),
      Container(
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.05 : 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.08 : 0.06)),
          boxShadow: [
            BoxShadow(
              color: (isDark ? Colors.black : Colors.grey).withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
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
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: isDark ? 0.2 : 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 20),
      ),
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

  // ─── Free Trial Dialog ────────────────────────────────────────────────

  void _showFreeTrialDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    bool hasActiveTrial = _trialEnd != null && _trialEnd!.isAfter(DateTime.now());
    DateTime selectedEnd = DateTime.now().add(const Duration(days: 3));

    Future<void> _pickDateTime() async {
      final date = await showDatePicker(
        context: context,
        initialDate: selectedEnd,
        firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 365)),
        builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(primary: Colors.orange, surface: bgColor, onSurface: baseColor),
          dialogBackgroundColor: bgColor,
        ), child: child!),
      );
      if (date == null) return;
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(selectedEnd),
        builder: (ctx, child) => Theme(data: Theme.of(ctx).copyWith(
          colorScheme: ColorScheme.dark(primary: Colors.orange, surface: bgColor, onSurface: baseColor),
          dialogBackgroundColor: bgColor,
        ), child: child!),
      );
      if (time != null) {
        selectedEnd = DateTime(date.year, date.month, date.day, time.hour, time.minute);
        // The dialog will show the selected date via StatefulBuilder
      }
    }

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Text('Free Trial', style: TextStyle(color: baseColor)),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasActiveTrial) ...[
            Text('Free trial is active for unverified students.', style: TextStyle(color: dimColor, fontSize: 12)),
            const SizedBox(height: 8),
            Text('Ends: ${_formatTrialEndDate(_trialEnd!)}', style: TextStyle(color: Colors.orange, fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Remaining: ${_trialRemainingText()}', style: TextStyle(color: baseColor, fontSize: 12)),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
          ],
          Text(hasActiveTrial
              ? 'Extend the current trial by selecting a new end date/time below.'
              : 'Give unverified students free access until the selected date/time. When the trial ends, Paid Access turns ON automatically.',
              style: TextStyle(color: dimColor, fontSize: 12)),
          const SizedBox(height: 16),
          InkWell(
            onTap: () async {
              await _pickDateTime();
              setDialog(() {});
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: fillColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: isDark ? Colors.white24 : Colors.black12),
              ),
              child: Row(children: [
                Icon(Icons.calendar_today_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text('End: ${_formatTrialEndDate(selectedEnd)}', style: TextStyle(color: baseColor, fontSize: 14, fontWeight: FontWeight.w500))),
                Icon(Icons.edit_rounded, color: dimColor, size: 18),
              ]),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Close', style: TextStyle(color: dimColor))),
          ElevatedButton(onPressed: () async {
            final now = DateTime.now();
            if (!selectedEnd.isAfter(now)) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('End date/time must be in the future'), backgroundColor: Colors.orange));
              return;
            }
            // Auto-set Paid Access OFF when trial starts
            await FirebaseService.updateSetting('paidAccess', false);
            if (mounted) setState(() => _paidAccess = false);
            final count = await FirebaseService.startFreeTrialForAll(end: selectedEnd);
            if (d.mounted) Navigator.pop(d);
            await _loadTrial();
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(count > 0 ? 'Free trial started for $count student(s) — Paid Access turned OFF' : 'No unverified students found'),
                backgroundColor: Colors.green,
              ));
            }
          }, child: Text(hasActiveTrial ? 'Extend Trial' : 'Start Trial')),
        ],
      );
    }));
  }

  String _formatTrialEndDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final month = months[dt.month - 1];
    final day = dt.day;
    final year = dt.year;
    final hour = dt.hour;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = hour >= 12 ? 'PM' : 'AM';
    final hour12 = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour);
    return '$day $month $year, $hour12:$minute $period';
  }

  String _trialRemainingText() {
    final r = _remaining;
    if (r.inSeconds <= 0) return '0s';
    final d = r.inDays;
    final h = r.inHours % 24;
    final m = r.inMinutes % 60;
    final s = r.inSeconds % 60;
    final parts = <String>[
      if (d > 0) '$d d',
      if (h > 0) '$h h',
      if (m > 0) '$m m',
      if (s > 0) '$s s',
    ];
    return parts.join(' ');
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
          if (snap.connectionState == ConnectionState.waiting) return SizedBox(height: 300, child: Center(child: ProfessionalLoader()));
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
    final baseColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cardBg = isDark ? const Color(0xFF0D0D2E) : Colors.grey.shade50;
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => StudentActivityPage(
        isDark: isDark, baseColor: baseColor, dimColor: dimColor, bgColor: bgColor, cardBg: cardBg,
      ),
    ));
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
          if (snap.connectionState == ConnectionState.waiting) return SizedBox(height: 300, child: Center(child: ProfessionalLoader()));
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
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            IconButton(
                              icon: Icon(Icons.password_rounded, color: Colors.cyan, size: 20),
                              tooltip: 'Change Password',
                              onPressed: () => _showStudentPasswordDialog(ctx, s['id'] as String? ?? '', name),
                            ),
                            IconButton(
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
          if (snap.connectionState == ConnectionState.waiting) return SizedBox(height: 300, child: Center(child: ProfessionalLoader()));
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
                if (snap.connectionState == ConnectionState.waiting) return const Center(child: ProfessionalLoader());
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
                          icon: const Icon(Icons.password_rounded, color: Colors.cyan, size: 20),
                          tooltip: 'Change Password',
                          onPressed: () => _showAssistantPasswordDialog(context, name, docs[i].id),
                        ),
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

  void _showAssistantPasswordDialog(BuildContext context, String name, String uid) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final ctrl = TextEditingController();
    bool saving = false;
    String? error;
    showDialog(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setLocal) {
        Future<void> prefill() async {
          final old = await FirebaseService.getUserStoredPassword(uid);
          if (old.isNotEmpty && ctrl.text.isEmpty && d.mounted) {
            setLocal(() => ctrl.text = old);
          }
        }
        prefill();
        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Change Password - $name', style: TextStyle(color: baseColor)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (error != null) ...[
              Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: ctrl, obscureText: true,
              style: TextStyle(color: baseColor),
              decoration: InputDecoration(
                labelText: 'Old Password (overtype to change)', labelStyle: TextStyle(color: dimColor),
                hintText: ctrl.text.isEmpty ? 'No stored password - enter new' : null,
                hintStyle: TextStyle(color: dimColor),
                filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final pwd = ctrl.text.trim();
                      if (pwd.length < 6) {
                        setLocal(() => error = 'Password must be at least 6 characters');
                        return;
                      }
                      setLocal(() { saving = true; error = null; });
                      final ok = await FirebaseService.updateUserPassword(uid, pwd);
                      if (!d.mounted) return;
                      setLocal(() => saving = false);
                      if (ok) {
                        Navigator.pop(d);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated'), backgroundColor: Colors.green));
                        }
                      } else {
                        setLocal(() => error = 'Failed to update password. Try again.');
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
    );
  }

  void _showStudentPasswordDialog(BuildContext context, String uid, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final ctrl = TextEditingController();
    bool saving = false;
    String? error;
    showDialog(
      context: context,
      builder: (d) => StatefulBuilder(builder: (d, setLocal) {
        Future<void> prefill() async {
          final old = await FirebaseService.getUserStoredPassword(uid);
          if (old.isNotEmpty && ctrl.text.isEmpty && d.mounted) {
            setLocal(() => ctrl.text = old);
          }
        }
        prefill();
        return AlertDialog(
          backgroundColor: bgColor,
          title: Text('Change Password - $name', style: TextStyle(color: baseColor)),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (error != null) ...[
              Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: ctrl, obscureText: true,
              style: TextStyle(color: baseColor),
              decoration: InputDecoration(
                labelText: 'Old Password (overtype to change)', labelStyle: TextStyle(color: dimColor),
                hintText: ctrl.text.isEmpty ? 'No stored password - enter new' : null,
                hintStyle: TextStyle(color: dimColor),
                filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      final pwd = ctrl.text.trim();
                      if (pwd.length < 6) {
                        setLocal(() => error = 'Password must be at least 6 characters');
                        return;
                      }
                      setLocal(() { saving = true; error = null; });
                      final ok = await FirebaseService.updateUserPassword(uid, pwd);
                      if (!d.mounted) return;
                      setLocal(() => saving = false);
                      if (ok) {
                        Navigator.pop(d);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Password updated'), backgroundColor: Colors.green));
                        }
                      } else {
                        setLocal(() => error = 'Failed to update password. Try again.');
                      }
                    },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
              child: const Text('Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      }),
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
    return Scaffold(
      backgroundColor: widget.bgColor,
      appBar: AppBar(
        backgroundColor: widget.bgColor,
        foregroundColor: widget.baseColor,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: widget.baseColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          const Icon(Icons.history_rounded, color: Colors.lime, size: 22),
          const SizedBox(width: 8),
          Text('Student Activity', style: TextStyle(color: widget.baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.campaign_rounded, color: Colors.orange),
            tooltip: 'Send Notification to All Students',
            onPressed: () => _showSendToAllDialog(context),
          ),
        ],
      ),
      body: Column(
      children: [
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
              ? const Center(child: ProfessionalLoader())
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
                        final gender = s['gender'] as String? ?? '';
                        return Card(
                          color: widget.cardBg, margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(backgroundColor: Colors.lime.shade800, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                            title: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Flexible(child: Text(name, style: TextStyle(color: widget.baseColor, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                                if (gender.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  GenderBadge(gender: gender, size: 16),
                                ],
                              ],
                            ),
                            subtitle: Text(email, style: TextStyle(color: widget.dimColor, fontSize: 12)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.insights_rounded, color: Colors.cyan, size: 20),
                                tooltip: 'View Progress',
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) => StudentProgressScreen(targetUid: uid),
                                  ));
                                },
                              ),
                              const Icon(Icons.chevron_right, color: Colors.lime, size: 20),
                            ],
                          ),
                          onTap: () => _showStudentLoginHistory(uid, name),
                          ),
                        );
                      },
                    ),
        ),
      ],
    ),
    );
  }

  void _showStudentLoginHistory(String uid, String name) {
    Navigator.push(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _StudentDevicePage(
        uid: uid, name: name,
        isDark: widget.isDark, baseColor: widget.baseColor, dimColor: widget.dimColor,
        bgColor: widget.bgColor, cardBg: widget.cardBg,
      ),
    ));
  }

  void _showSendToAllDialog(BuildContext context) {
    final msgCtrl = TextEditingController();
    final baseColor = widget.baseColor;
    final dimColor = widget.dimColor;
    final fillColor = widget.isDark ? Colors.white10 : Colors.black12;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: widget.bgColor,
        title: Text('Notify All Students', style: TextStyle(color: baseColor, fontSize: 16)),
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
              final msg = msgCtrl.text.trim();
              if (msg.isEmpty) return;
              final count = await FirebaseService.addNotificationToAllStudents(msg);
              if (d.mounted) Navigator.pop(d);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Notification sent to $count student(s)'),
                  backgroundColor: Colors.green,
                ));
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Send to All', style: TextStyle(color: Colors.white)),
          ),
        ],
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

class _StudentDevicePage extends StatefulWidget {
  final String uid, name;
  final bool isDark;
  final Color baseColor, dimColor, bgColor, cardBg;
  const _StudentDevicePage({required this.uid, required this.name, required this.isDark, required this.baseColor, required this.dimColor, required this.bgColor, required this.cardBg});
  @override
  State<_StudentDevicePage> createState() => _StudentDevicePageState();
}

class _StudentDevicePageState extends State<_StudentDevicePage> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) {
        setState(() => _currentTabIndex = _tabCtrl.index);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.bgColor,
      appBar: AppBar(
        backgroundColor: widget.bgColor,
        foregroundColor: widget.baseColor,
        elevation: 0,
        title: Row(children: [
          CircleAvatar(backgroundColor: Colors.lime.shade800, radius: 16, child: Text(widget.name[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 14))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.name, style: TextStyle(color: widget.baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
            Text('Student Overview', style: TextStyle(color: widget.dimColor, fontSize: 11)),
          ])),
        ]),
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.cyan,
          labelColor: widget.baseColor,
          unselectedLabelColor: widget.dimColor,
          tabs: const [
            Tab(text: 'Devices', icon: Icon(Icons.phone_android_rounded, size: 18)),
            Tab(text: 'Progress', icon: Icon(Icons.insights_rounded, size: 18)),
            Tab(text: 'Notifications', icon: Icon(Icons.notifications_rounded, size: 18)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildDevicesTab(),
          _buildProgressTab(),
          _buildNotificationsTab(),
        ],
      ),
      floatingActionButton: _currentTabIndex == 2
          ? FloatingActionButton(
              onPressed: () => _showSendNotificationDialog(),
              backgroundColor: Colors.orange,
              child: const Icon(Icons.send_rounded, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildDevicesTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.firestore.collection('login_attempts')
          .where('uid', isEqualTo: widget.uid)
          .snapshots(),
      builder: (ctx, loginSnap) {
        if (loginSnap.hasError) {
          if (FirebaseService.currentUser == null) {
            ctx.go('/auth/login');
          }
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
            const SizedBox(height: 8),
            Text('Could not load devices', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
          ]));
        }
        if (!loginSnap.hasData) return const Center(child: ProfessionalLoader());
        final loginLogs = loginSnap.data!.docs.toList();
        loginLogs.sort((a, b) {
          final aT = (a.data() as Map<String, dynamic>)['timestamp'] as String? ?? '';
          final bT = (b.data() as Map<String, dynamic>)['timestamp'] as String? ?? '';
          return bT.compareTo(aT);
        });
        if (loginLogs.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.phone_android_rounded, size: 48, color: widget.dimColor.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('No devices yet', style: TextStyle(color: widget.dimColor, fontSize: 14)),
          ]));
        }
        final now = DateTime.now();
        final latestTime = loginLogs.isNotEmpty ? (() {
          final ts = (loginLogs.first.data() as Map<String, dynamic>)['timestamp'] as String? ?? '';
          if (ts.isNotEmpty) { try { return DateTime.parse(ts); } catch (_) {} }
          return null;
        })() : null;
        final latestDeviceId = latestTime != null && now.difference(latestTime).inMinutes < 5
            ? (loginLogs.first.data() as Map<String, dynamic>)['deviceId'] as String?
            : null;
        return StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.firestore.collection('web_sessions')
              .where('uid', isEqualTo: widget.uid)
              .snapshots(),
          builder: (ctx, webSnap) {
            final allWebSessions = webSnap.hasData ? webSnap.data!.docs : [];
            final activeWebSessions = allWebSessions
                .where((doc) => (doc.data() as Map<String, dynamic>)['status'] == 'connected')
                .toList();
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: loginLogs.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: widget.isDark ? Colors.white10 : Colors.black12),
              itemBuilder: (_, i) {
                final d = loginLogs[i].data() as Map<String, dynamic>;
                final deviceModel = d['deviceModel'] as String? ?? 'Unknown device';
                final deviceId = d['deviceId'] as String? ?? '';
                final ts = d['timestamp'] as String? ?? '';
                final timeDisplay = ts.isNotEmpty ? ts.replaceFirst('T', ' ').substring(0, 19) : 'N/A';
                final isLatestActive = latestDeviceId != null && deviceId == latestDeviceId;
                final totalDeviceWebSessions = activeWebSessions.length;
                return ListTile(
                  contentPadding: const EdgeInsets.symmetric(vertical: 4),
                  leading: Stack(
                    children: [
                      Icon(Icons.phone_android_rounded, color: isLatestActive ? Colors.green : Colors.lime.shade700, size: 24),
                      if (isLatestActive)
                        Positioned(right: -2, top: -2, child: Container(
                          width: 10, height: 10,
                          decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle,
                            border: Border.all(color: widget.bgColor, width: 2)),
                        )),
                    ],
                  ),
                  title: Row(children: [
                    Flexible(child: Text(deviceModel, style: TextStyle(color: widget.baseColor, fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    if (isLatestActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: const Text('Active', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                    if (totalDeviceWebSessions > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: const Color(0xFF00E5FF).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.language_rounded, size: 10, color: Color(0xFF00E5FF)),
                          const SizedBox(width: 3),
                          Text('$totalDeviceWebSessions', style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 10, fontWeight: FontWeight.bold)),
                        ]),
                      ),
                    ],
                  ]),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(timeDisplay, style: TextStyle(color: widget.dimColor, fontSize: 12)),
                      if (isLatestActive && activeWebSessions.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        ...activeWebSessions.map((w) {
                          final wd = w.data() as Map<String, dynamic>;
                          final webBrowser = wd['webBrowser'] as String? ?? 'Web Browser';
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Row(children: [
                              Container(width: 6, height: 6, decoration: const BoxDecoration(color: Color(0xFF00E5FF), shape: BoxShape.circle)),
                              const SizedBox(width: 6),
                              Text(webBrowser, style: const TextStyle(color: Color(0xFF00E5FF), fontSize: 11, fontWeight: FontWeight.w600)),
                            ]),
                          );
                        }),
                      ],
                    ],
                  ),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(
                      fullscreenDialog: true,
                      builder: (_) => _AdminLinkHistoryScreen(
                        uid: widget.uid, studentName: widget.name, deviceName: deviceModel,
                        deviceId: deviceId, isWeb: false, isDark: widget.isDark, baseColor: widget.baseColor,
                        dimColor: widget.dimColor, bgColor: widget.bgColor, cardBg: widget.cardBg,
                      ),
                    ));
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildProgressTab() {
    return StudentProgressScreen(targetUid: widget.uid, embedded: true);
  }

  Widget _buildNotificationsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseService.firestore.collection('notifications')
          .where('uid', isEqualTo: widget.uid)
          .where('type', isEqualTo: 'targeted')
          .snapshots(),
      builder: (ctx, snap) {
        if (snap.hasError) {
          if (FirebaseService.currentUser == null) {
            ctx.go('/auth/login');
          }
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
            const SizedBox(height: 8),
            Text('Could not load notifications', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('${snap.error}', style: TextStyle(color: widget.dimColor, fontSize: 10), textAlign: TextAlign.center)),
          ]));
        }
        if (!snap.hasData) return const Center(child: ProfessionalLoader());
        final notifications = snap.data!.docs.toList();
        notifications.sort((a, b) {
          final aT = (a.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          final bT = (b.data() as Map<String, dynamic>)['createdAt'] as Timestamp?;
          if (aT == null && bT == null) return 0;
          if (aT == null) return 1;
          if (bT == null) return -1;
          return bT.compareTo(aT);
        });
        if (notifications.isEmpty) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.notifications_none_rounded, size: 48, color: widget.dimColor.withValues(alpha: 0.3)),
            const SizedBox(height: 12),
            Text('No notifications yet', style: TextStyle(color: widget.dimColor, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Tap the send button to notify this student', style: TextStyle(color: widget.dimColor.withValues(alpha: 0.5), fontSize: 12)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: notifications.length,
          itemBuilder: (_, i) {
            final d = notifications[i].data() as Map<String, dynamic>;
            final message = d['message'] as String? ?? '';
            final createdAt = (d['createdAt'] as Timestamp?)?.toDate();
            final timeStr = createdAt != null
                ? '${createdAt.day}/${createdAt.month}/${createdAt.year} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}'
                : 'N/A';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: widget.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: widget.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.notifications_rounded, color: Colors.orange, size: 16),
                  const SizedBox(width: 6),
                  Expanded(child: Text(message, style: TextStyle(color: widget.baseColor, fontSize: 13))),
                ]),
                const SizedBox(height: 6),
                Text(timeStr, style: TextStyle(color: widget.dimColor.withValues(alpha: 0.6), fontSize: 11)),
              ]),
            );
          },
        );
      },
    );
  }

  void _showSendNotificationDialog() {
    final msgCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: widget.bgColor,
        title: Text('Notify ${widget.name}', style: TextStyle(color: widget.baseColor, fontSize: 16)),
        content: TextField(
          controller: msgCtrl, maxLines: 3,
          style: TextStyle(color: widget.baseColor),
          decoration: InputDecoration(
            hintText: 'Type your notification message...', hintStyle: TextStyle(color: widget.dimColor),
            filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: widget.dimColor))),
          ElevatedButton(
            onPressed: () async {
              final msg = msgCtrl.text.trim();
              if (msg.isEmpty) return;
              await FirebaseService.addTargetedNotification(widget.uid, msg);
              if (d.mounted) Navigator.pop(d);
              if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Notification sent to ${widget.name}')));
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Send', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  bool get isDark => widget.isDark;
}

class _AdminLinkHistoryScreen extends StatefulWidget {
  final String uid;
  final String studentName;
  final String deviceName;
  final String deviceId;
  final bool isWeb;
  final bool isDark;
  final Color baseColor, dimColor, bgColor, cardBg;
  const _AdminLinkHistoryScreen({
    required this.uid, required this.studentName, required this.deviceName,
    required this.deviceId, required this.isWeb, required this.isDark,
    required this.baseColor, required this.dimColor, required this.bgColor, required this.cardBg,
  });
  @override
  State<_AdminLinkHistoryScreen> createState() => _AdminLinkHistoryScreenState();
}

class _AdminLinkHistoryScreenState extends State<_AdminLinkHistoryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.bgColor,
      appBar: AppBar(
        backgroundColor: widget.bgColor,
        foregroundColor: widget.baseColor,
        elevation: 0,
        title: Text(widget.studentName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Icon(Icons.shield_rounded, color: widget.dimColor.withValues(alpha: 0.4), size: 18),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            decoration: BoxDecoration(
              color: widget.isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
              border: Border(bottom: BorderSide(color: widget.isDark ? Colors.white10 : Colors.black12)),
            ),
            child: Row(children: [
              Icon(widget.isWeb ? Icons.language_rounded : Icons.phone_android_rounded,
                color: Colors.cyan, size: 18),
              const SizedBox(width: 8),
              Text(widget.deviceName, style: TextStyle(color: widget.baseColor, fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Admin View', style: TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ]),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.firestore.collection('web_sessions')
                  .where('uid', isEqualTo: widget.uid)
                  .snapshots(),
              builder: (ctx, snap) {
                if (snap.hasError) {
                  if (FirebaseService.currentUser == null) {
                    ctx.go('/auth/login');
                  }
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 32),
                    const SizedBox(height: 8),
                    Text('Could not load history', style: TextStyle(color: Colors.redAccent, fontSize: 13)),
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('${snap.error}', style: TextStyle(color: widget.dimColor, fontSize: 10), textAlign: TextAlign.center)),
                  ]));
                }
                if (!snap.hasData) {
                  return const Center(child: ProfessionalLoader());
                }
                var sessions = snap.data!.docs.toList();
                sessions.sort((a, b) {
                  final aT = (a.data() as Map<String, dynamic>)['connectedAt'] as Timestamp?;
                  final bT = (b.data() as Map<String, dynamic>)['connectedAt'] as Timestamp?;
                  if (aT == null && bT == null) return 0;
                  if (aT == null) return 1;
                  if (bT == null) return -1;
                  return bT.compareTo(aT);
                });
                sessions = sessions.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final devId = data['androidDeviceId'] as String? ?? '';
                  return devId == widget.deviceId;
                }).toList();
                if (sessions.isEmpty) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.language_rounded, size: 48, color: widget.dimColor.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text('No web link history', style: TextStyle(color: widget.dimColor, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('This student has not linked any web sessions', style: TextStyle(color: widget.dimColor.withValues(alpha: 0.5), fontSize: 12)),
                  ]));
                }
                return ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: sessions.length,
                  itemBuilder: (_, i) {
                    final d = sessions[i].data() as Map<String, dynamic>;
                    final connectedAt = (d['connectedAt'] as Timestamp?)?.toDate();
                    final disconnectedAt = (d['disconnectedAt'] as Timestamp?)?.toDate();
                    final status = d['status'] ?? 'disconnected';
                    final isActive = status == 'connected';
                    final deviceInfo = (d['webBrowser'] as String?) ?? 'Web Browser';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: widget.cardBg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: isActive ? Colors.green.withValues(alpha: 0.3) : widget.isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Stack(
                                children: [
                                  Icon(Icons.language_rounded, color: isActive ? Colors.green : widget.dimColor, size: 22),
                                  if (isActive)
                                    Positioned(right: -2, top: -2, child: Container(
                                      width: 10, height: 10,
                                      decoration: BoxDecoration(color: Colors.green, shape: BoxShape.circle,
                                        border: Border.all(color: widget.cardBg, width: 2)),
                                    )),
                                ],
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(deviceInfo, style: TextStyle(color: widget.baseColor, fontWeight: FontWeight.bold, fontSize: 14)),
                                  const SizedBox(height: 2),
                                  Text(d['sessionId']?.toString().substring(0, (d['sessionId']?.toString().length ?? 0).clamp(0, 20)) ?? '', style: TextStyle(color: widget.dimColor, fontSize: 10, fontFamily: 'monospace')),
                                ],
                              )),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: isActive ? Colors.green.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(isActive ? 'Active' : 'Ended',
                                  style: TextStyle(color: isActive ? Colors.green : Colors.grey, fontSize: 11, fontWeight: FontWeight.bold)),
                              ),
                            ]),
                            const SizedBox(height: 12),
                            _buildInfoRow(Icons.access_time_rounded, 'Connected',
                              connectedAt != null ? '${connectedAt.year}-${connectedAt.month.toString().padLeft(2, '0')}-${connectedAt.day.toString().padLeft(2, '0')} ${connectedAt.hour.toString().padLeft(2, '0')}:${connectedAt.minute.toString().padLeft(2, '0')}' : 'N/A',
                              widget.dimColor),
                            if (disconnectedAt != null)
                              _buildInfoRow(Icons.link_off_rounded, 'Disconnected',
                                '${disconnectedAt.year}-${disconnectedAt.month.toString().padLeft(2, '0')}-${disconnectedAt.day.toString().padLeft(2, '0')} ${disconnectedAt.hour.toString().padLeft(2, '0')}:${disconnectedAt.minute.toString().padLeft(2, '0')}',
                                widget.dimColor),
                            if (!isActive && connectedAt != null) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(children: [
                                  Icon(Icons.timer_off_rounded, size: 14, color: widget.dimColor.withValues(alpha: 0.6)),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Duration: ${_formatDuration(connectedAt, disconnectedAt)}',
                                    style: TextStyle(color: widget.dimColor.withValues(alpha: 0.7), fontSize: 11),
                                  ),
                                ]),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String label, String value, Color dimColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 14, color: dimColor.withValues(alpha: 0.5)),
        const SizedBox(width: 6),
        Text('$label: ', style: TextStyle(color: dimColor.withValues(alpha: 0.5), fontSize: 12)),
        Expanded(child: Text(value, style: TextStyle(color: dimColor, fontSize: 12))),
      ]),
    );
  }

  String _formatDuration(DateTime start, DateTime? end) {
    final diff = (end ?? DateTime.now()).difference(start);
    if (diff.inDays > 0) return '${diff.inDays}d ${diff.inHours % 24}h';
    if (diff.inHours > 0) return '${diff.inHours}h ${diff.inMinutes % 60}m';
    return '${diff.inMinutes}m';
  }
}
