import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import '../../../core/widgets/glassmorphic_container.dart';
import '../../../core/widgets/animated_pressable.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/theme/theme_provider.dart';
import '../../folders/presentation/folder_details_screen.dart' show GroupLinkDialog;
import '../../../core/utils.dart';

class AdminDashboardScreen extends StatefulWidget {
  final String? studentUid;
  final String? studentName;
  const AdminDashboardScreen({super.key, this.studentUid, this.studentName});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  final _folderNameController = TextEditingController();
  int _pendingFeedbackCount = 0;
  StreamSubscription? _feedbackSub;
  // Cached stream to prevent folder list from blinking on each rebuild
  late final Stream<QuerySnapshot> _folderStream;
  // Local docs for optimistic reorder — avoids snap-back on drag
  List<QueryDocumentSnapshot>? _localDocs;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _folderStream = FirebaseService.getAllFolders();
    _loadPendingCount();
    _listenNewFeedbacks();
  }

  void _markAllFeedbacksViewed() async {
    final snap = await FirebaseService.firestore
        .collection('feedbacks')
        .where('status', isEqualTo: 'pending')
        .where('viewed', isEqualTo: false)
        .get();
    if (snap.docs.isEmpty) return;
    final batch = FirebaseService.firestore.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'viewed': true});
    }
    await batch.commit();
  }

  void _loadPendingCount() async {
    final count = await FirebaseService.getPendingFeedbackCount();
    if (mounted) setState(() => _pendingFeedbackCount = count);
  }

  void _listenNewFeedbacks() {
    _feedbackSub = FirebaseService.firestore
        .collection('feedbacks')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snap) {
      final all = snap.docs.where((d) {
        final data = d.data() as Map<String, dynamic>;
        return data['viewed'] != true;
      }).toList();
      final count = all.length;
      if (mounted) setState(() => _pendingFeedbackCount = count);
      NotificationService.setBadgeCount(count);
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data() as Map<String, dynamic>;
          final time = (data['createdAt'] as Timestamp?)?.toDate();
          if (time != null && DateTime.now().difference(time).inSeconds < 10) {
            NotificationService.showFeedbackNotification(
              data['name'] as String? ?? 'Student',
              data['message'] as String? ?? '',
            );
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _feedbackSub?.cancel();
    _folderNameController.dispose();
    super.dispose();
  }

  void _showCreateFolderDialog() {
    _folderNameController.text = '';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('New Folder', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: TextField(
          controller: _folderNameController, style: TextStyle(color: isDark ? Colors.white : Colors.black87), autofocus: true,
          decoration: InputDecoration(
            hintText: 'Folder name...', hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
            prefixIcon: const Icon(Icons.folder, color: Color(0xFF00B8D4)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (!debounce('folder_create')) return;
              final name = _folderNameController.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx);
              await FirebaseService.createRootFolder(name: name, color: '#4A148C');
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ─── Assistant Management ───────────────────────────────────────────────────────

  void _showAllAssistant() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.7, minChildSize: 0.3, maxChildSize: 0.9, expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.people_alt_rounded, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('All Assistant', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(
                icon: const Icon(Icons.person_add_rounded, color: Colors.orange, size: 28),
                onPressed: () { Navigator.pop(ctx); _showCreateAssistantDialog(); },
              ),
            ]),
          ),
          Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getAllAssistant(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.person_off_rounded, size: 50, color: isDark ? Colors.white12 : Colors.black12),
                    const SizedBox(height: 12),
                    Text('No Assistant yet', style: TextStyle(color: dimColor, fontSize: 14)),
                    const SizedBox(height: 4),
                    Text('Tap + to create an Assistant account', style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 12)),
                  ]));
                }
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final uid = docs[index].id;
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
                        CircleAvatar(
                          backgroundColor: Colors.orange.withValues(alpha: isDark ? 0.2 : 0.1),
                          child: const Icon(Icons.person, color: Colors.orange, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 2),
                          Text(email, style: const TextStyle(color: Colors.orange, fontSize: 12)),
                          const SizedBox(height: 2),
                          Text('Password: Assistant123', style: TextStyle(color: dimColor, fontSize: 11)),
                        ])),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (d) => AlertDialog(
                                backgroundColor: bgColor,
                                title: Text('Delete Assistant?', style: TextStyle(color: baseColor)),
                                content: Text('Delete "$name"? This removes all folder access.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
                                  ElevatedButton(onPressed: () => Navigator.pop(d, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
                                ],
                              ),
                            );
                            if (confirm == true) await FirebaseService.deleteAssistantAccount(uid);
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

  void _showAllStudents() {
    bool paidAccess = false;
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
      builder: (ctx) => FutureBuilder<List<Map<String, dynamic>>>(
        future: FirebaseService.getAllStudents(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return SizedBox(height: 300, child: Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black87)));
          final students = snap.data ?? [];
          return StatefulBuilder(builder: (ctx, setLocal) {
            if (students.isEmpty) return SizedBox(height: 200, child: Center(child: Text('No students registered', style: TextStyle(color: dimColor))));
            return DraggableScrollableSheet(
              expand: false,
              maxChildSize: 0.85,
              initialChildSize: 0.5,
              builder: (ctx, scrollCtrl) => Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Row(children: [
                    const Icon(Icons.school_rounded, color: Colors.blue, size: 22),
                    const SizedBox(width: 8),
                    Text('Registered Students', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    IconButton(icon: Icon(Icons.close, color: dimColor), onPressed: () => Navigator.pop(ctx)),
                  ]),
                ),
                Divider(color: isDark ? Colors.white12 : Colors.black12),
                Expanded(
                  child: ListView.builder(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.all(16),
                    itemCount: students.length,
                    itemBuilder: (context, i) {
                      final s = students[i];
                      final uid = s['id'] as String;
                      final name = s['name'] as String? ?? 'Unknown';
                      final email = s['email'] as String? ?? '';
                      final verified = s['verified'] as bool? ?? true;
                      return Card(
                        color: cardBg,
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: verified ? Colors.green.shade700 : Colors.grey.shade700,
                            child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white)),
                          ),
                          title: Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold)),
                          subtitle: Text(email, style: TextStyle(color: dimColor, fontSize: 12)),
                          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                            GestureDetector(
                              onTap: () async {
                                if (!debounce('verify_stud_$uid')) return;
                                final settings = await FirebaseService.getSettings();
                                final isPaid = settings['paidAccess'] as bool? ?? false;
                                if (!isPaid) return;
                                await FirebaseService.toggleStudentVerified(uid, !verified);
                                if (ctx.mounted) setLocal(() => s['verified'] = !verified);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: verified ? Colors.green : Colors.grey.shade700,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.check_circle, size: 14, color: verified ? Colors.white : Colors.white38),
                                  const SizedBox(width: 4),
                                  Text('Verified', style: TextStyle(color: verified ? Colors.white : Colors.white38, fontSize: 11)),
                                ]),
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                              onPressed: () async {
                                final confirm = await showDialog<bool>(context: ctx, builder: (d) => AlertDialog(
                                  backgroundColor: bgColor,
                                  title: Text('Delete Student?', style: TextStyle(color: baseColor)),
                                  content: Text('Remove "$name"?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
                                    ElevatedButton(onPressed: () => Navigator.pop(d, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
                                  ],
                                ));
                                if (confirm == true) {
                                  await FirebaseService.deleteStudentCompletely(uid);
                                  if (ctx.mounted) Navigator.pop(ctx);
                                  _showAllStudents();
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

  void _showControlPanel() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    double price = 0;
    bool paidAccess = false;
    bool loading = true;
    String accountTitle = '', accountNo = '', bankName = '';
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        if (loading) {
          FirebaseService.getSettings().then((s) {
            if (ctx.mounted) setLocal(() { price = (s['price'] as num?)?.toDouble() ?? 0; paidAccess = s['paidAccess'] as bool? ?? false; accountTitle = s['accountTitle'] as String? ?? ''; accountNo = s['accountNo'] as String? ?? ''; bankName = s['bankName'] as String? ?? ''; loading = false; });
          });
        }
        return Container(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.admin_panel_settings_rounded, color: Colors.cyan, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text('Control Panel', style: TextStyle(color: baseColor, fontSize: 18, fontWeight: FontWeight.bold))),
              IconButton(icon: Icon(Icons.close, color: dimColor), onPressed: () => Navigator.pop(ctx)),
            ]),
            const SizedBox(height: 16),
            if (loading)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(children: [
                  _ctrlSection('Paid Access', [
                    _ctrlTile(Icons.verified_user_rounded, Colors.blue, 'Student Paid Access', paidAccess ? 'ON - Manual verification' : 'OFF - Auto verify', trailing: Switch(
                      value: paidAccess, activeColor: Colors.blue,
                      onChanged: (v) async { await FirebaseService.updateSetting('paidAccess', v); if (ctx.mounted) setLocal(() => paidAccess = v); },
                    )),
                    _ctrlTile(Icons.attach_money_rounded, Colors.green, 'Set Price', 'Current: Rs.${price.toStringAsFixed(0)}', onTap: () async {
                      final ctrl = TextEditingController(text: price.toStringAsFixed(0));
                      final result = await showDialog<String>(context: ctx, builder: (d) => AlertDialog(
                        backgroundColor: bgColor, title: Text('Set Price', style: TextStyle(color: baseColor)),
                        content: TextField(controller: ctrl, keyboardType: TextInputType.number, style: TextStyle(color: baseColor), decoration: InputDecoration(filled: true, fillColor: isDark ? Colors.white10 : Colors.black12, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
                        actions: [TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))), ElevatedButton(onPressed: () => Navigator.pop(d, ctrl.text.trim()), child: const Text('Save'))],
                      ));
                      if (result != null && result.isNotEmpty) { final p = double.tryParse(result) ?? 0; await FirebaseService.updateSetting('price', p); if (ctx.mounted) setLocal(() => price = p); }
                    }),
                    _ctrlTile(Icons.account_balance_rounded, Colors.teal, 'Account Info', accountTitle.isNotEmpty ? '$accountTitle - $bankName' : 'Add bank details', onTap: () => _showAccountInfoDialog(ctx, setLocal, accountTitle, accountNo, bankName)),
                  ]),
                  const SizedBox(height: 8),
                  _ctrlSection('Student Management', [
                    _ctrlTile(Icons.admin_panel_settings_rounded, Colors.cyan, 'Control Student Panel', 'Open full admin panel for a student', onTap: () { Navigator.pop(ctx); Future.delayed(const Duration(milliseconds: 300), () => _showStudentListForPanel()); }),
                    _ctrlTile(Icons.history_rounded, Colors.lime, 'Student Activity', 'Login history & send notifications', onTap: () { Navigator.pop(ctx); Future.delayed(const Duration(milliseconds: 300), () => _showStudentActivity()); }),
                    _ctrlTile(Icons.school_rounded, Colors.blue, 'Students', 'View registered students', onTap: () { Navigator.pop(ctx); Future.delayed(const Duration(milliseconds: 300), () => _showAllStudents()); }),
                  ]),
                  const SizedBox(height: 8),
                  _ctrlSection('Restrictions', [
                    _ctrlTile(Icons.block_rounded, Colors.redAccent, 'Block Students', 'Manage blocked student accounts', onTap: () { Navigator.pop(ctx); Future.delayed(const Duration(milliseconds: 300), () => _showBlockStudents(context)); }),
                    _ctrlTile(Icons.people_alt_rounded, Colors.teal, 'Assistant', 'Create & manage Assistant accounts', onTap: () { Navigator.pop(ctx); Future.delayed(const Duration(milliseconds: 300), () => _showAllAssistant()); }),
                  ]),
                  const SizedBox(height: 8),
                  _ctrlSection('App', [
                    _ctrlTile(Icons.update_rounded, Colors.cyanAccent, 'App Updates', 'Manage version & update banner', onTap: () { Navigator.pop(ctx); Future.delayed(const Duration(milliseconds: 300), () => _showAppUpdates()); }),
                  ]),
                ]),
              ),
          ]),
        );
      }),
    );
  }

  void _showStudentListForPanel() {
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

  Widget _ctrlSection(String title, List<Widget> tiles) {
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

  Widget _ctrlTile(IconData icon, Color iconColor, String title, String subtitle, {Widget? trailing, VoidCallback? onTap}) {
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

  void _showStudentActivity() {
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
                    const Icon(Icons.history_rounded, color: Colors.lime, size: 22),
                    const SizedBox(width: 8),
                    Text('Student Activity', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
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
                          leading: CircleAvatar(backgroundColor: Colors.lime.shade800, child: Text(name.isNotEmpty ? name[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
                          title: Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold)),
                          subtitle: Text(email, style: TextStyle(color: dimColor, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right, color: Colors.lime, size: 20),
                          onTap: () => _showStudentActivityDetail(ctx, uid, name),
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

  void _showStudentActivityDetail(BuildContext parentCtx, String uid, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showModalBottomSheet(
      context: parentCtx, isScrollControlled: true, backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return Container(
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
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.firestore.collection('login_history').doc(uid).collection('logins').orderBy('timestamp', descending: true).limit(20).snapshots(),
              builder: (ctx, snap) {
                final logs = snap.data?.docs ?? [];
                if (logs.isEmpty) {
                  return Padding(padding: const EdgeInsets.all(20), child: Center(child: Text('No login history yet', style: TextStyle(color: dimColor))));
                }
                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.4),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12),
                    itemBuilder: (_, i) {
                      final d = logs[i].data() as Map<String, dynamic>;
                      final time = (d['timestamp'] as Timestamp?)?.toDate();
                      final device = d['device'] as String? ?? 'Unknown device';
                      final ip = d['ip'] as String? ?? '';
                      final timeStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}' : 'N/A';
                      return ListTile(
                        leading: const Icon(Icons.login_rounded, color: Colors.green, size: 20),
                        title: Text(device, style: TextStyle(color: baseColor, fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Text('$timeStr${ip.isNotEmpty ? ' • $ip' : ''}', style: TextStyle(color: dimColor, fontSize: 11)),
                      );
                    },
                  ),
                );
              },
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
        );
      }),
    );
  }

  void _showSendNotificationDialog(String uid, String name) {
    final msgCtrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
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
              if (!debounce('notif_send')) return;
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
              IconButton(icon: const Icon(Icons.add_circle_outline_rounded, color: Colors.cyanAccent, size: 28), onPressed: () { Navigator.pop(ctx); _showAddUpdateDialog(); }),
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

  void _showAddUpdateDialog() {
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

  void _showCreateAssistantDialog() {
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

  // ─── Assistant Access Per Folder ────────────────────────────────────────────────

  void _showFolderAssistantAccess(String folderId, String folderName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0533),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.3, maxChildSize: 0.85, expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.vpn_key_rounded, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Assistant Access — $folderName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getAssistantLoginsForFolder(folderId),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.vpn_key_off_rounded, size: 50, color: Colors.white12),
                    SizedBox(height: 12),
                    Text('No Assistant have access to this folder', style: TextStyle(color: Colors.white38, fontSize: 14)),
                    SizedBox(height: 4),
                    Text('Use "Assistant" button to grant access', style: TextStyle(color: Colors.white24, fontSize: 12)),
                  ]));
                }
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final uid = data['uid'] as String? ?? '';
                    final name = data['name'] as String? ?? 'Unknown';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white.withValues(alpha: 0.1))),
                      child: Row(children: [
                        const Icon(Icons.person, color: Colors.orange, size: 20),
                        const SizedBox(width: 12),
                        Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14))),
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded, color: Colors.redAccent, size: 22),
                          onPressed: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (d) => AlertDialog(
                                backgroundColor: const Color(0xFF1A0533),
                                title: const Text('Revoke Access?', style: TextStyle(color: Colors.white)),
                                content: Text('Remove $name\'s access to this folder?', style: const TextStyle(color: Colors.white70)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancel')),
                                  ElevatedButton(onPressed: () => Navigator.pop(d, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Revoke', style: TextStyle(color: Colors.white))),
                                ],
                              ),
                            );
                            if (confirm == true) await FirebaseService.revokeAssistantAccess(uid, folderId);
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

  void _showGrantAccessDialog(String folderId, String folderName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A0533),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.5, minChildSize: 0.3, maxChildSize: 0.7, expand: false,
        builder: (ctx, scrollCtrl) => Column(children: [
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.person_add_rounded, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text('Grant Access — $folderName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16))),
              IconButton(
                icon: const Icon(Icons.person_add_rounded, color: Colors.orange, size: 28),
                tooltip: 'Add Assistant',
                onPressed: () { Navigator.pop(ctx); _showCreateAssistantDialog(); },
              ),
            ]),
          ),
          const Divider(color: Colors.white12, height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getAllAssistant(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.person_off_rounded, size: 48, color: Colors.white12),
                        const SizedBox(height: 12),
                        const Text('No Assistant yet', style: TextStyle(color: Colors.white38, fontSize: 14)),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          icon: const Icon(Icons.person_add_rounded, size: 18),
                          label: const Text('Create Assistant'),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                          onPressed: () { Navigator.pop(ctx); _showCreateAssistantDialog(); },
                        ),
                      ],
                    ),
                  );
                }
                final docs = snapshot.data!.docs;
                return ListView.builder(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final data = docs[index].data() as Map<String, dynamic>;
                    final uid = docs[index].id;
                    final name = data['name'] as String? ?? 'Unknown';
                    final email = data['email'] as String? ?? '';
                    final folderIds = (data['folderIds'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
                    final hasAccess = folderIds.contains(folderId);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: hasAccess ? Colors.green.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: hasAccess ? Colors.green.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.1)),
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          backgroundColor: hasAccess ? Colors.green.withValues(alpha: 0.2) : Colors.white10,
                          child: Icon(hasAccess ? Icons.check : Icons.person, color: hasAccess ? Colors.green : Colors.white54, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                          Text(email, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ])),
                        if (hasAccess)
                          ElevatedButton(
                            onPressed: () async => await FirebaseService.revokeAssistantAccess(uid, folderId),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                            child: const Text('Revoke', style: TextStyle(color: Colors.white, fontSize: 12)),
                          )
                        else
                          ElevatedButton(
                            onPressed: () async => await FirebaseService.grantAssistantAccess(uid, folderId, name),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                            child: const Text('Grant', style: TextStyle(color: Colors.white, fontSize: 12)),
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

  // ─── Folder Lock ─────────────────────────────────────────────────────────────

  void _showFolderLockSheet(String folderId, String folderName, bool locked, bool updating, bool invisible) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [const Icon(Icons.lock_outline_rounded, color: Colors.orange, size: 20), const SizedBox(width: 8), Expanded(child: Text(folderName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)))]),
            const SizedBox(height: 20),
            _buildToggleRow('Lock Folder', 'Students cannot see this folder', Icons.lock_rounded, Colors.redAccent, locked, (val) async {
              await FirebaseService.toggleFolderLock(folderId, 'locked', val);
              if (val) {
                await FirebaseService.toggleFolderLock(folderId, 'updating', false);
                await FirebaseService.toggleFolderLock(folderId, 'invisible', false);
                setLocal(() { locked = val; updating = false; invisible = false; });
              } else {
                setLocal(() => locked = val);
              }
            }),
            const SizedBox(height: 12),
            _buildToggleRow('Show "Updating..."', 'Folder visible but shows Updating message', Icons.update_rounded, Colors.orange, updating, (val) async {
              await FirebaseService.toggleFolderLock(folderId, 'updating', val);
              if (val) {
                await FirebaseService.toggleFolderLock(folderId, 'locked', false);
                await FirebaseService.toggleFolderLock(folderId, 'invisible', false);
                setLocal(() { updating = val; locked = false; invisible = false; });
              } else {
                setLocal(() => updating = val);
              }
            }),
            const SizedBox(height: 12),
            _buildToggleRow('Invisible', 'Hide from students & Assistant', Icons.visibility_off_rounded, Colors.purple, invisible, (val) async {
              await FirebaseService.toggleFolderLock(folderId, 'invisible', val);
              if (val) {
                await FirebaseService.toggleFolderLock(folderId, 'locked', false);
                await FirebaseService.toggleFolderLock(folderId, 'updating', false);
                setLocal(() { invisible = val; locked = false; updating = false; });
              } else {
                setLocal(() => invisible = val);
              }
            }),
            const SizedBox(height: 16),
          ]);
        }),
      ),
    );
  }

  String _formatTimestamp(dynamic ts) {
    if (ts is Timestamp) {
      final dt = ts.toDate();
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
      if (diff.inHours < 24) return '${diff.inHours}h ago';
      if (diff.inDays < 7) return '${diff.inDays}d ago';
      return '${dt.day}/${dt.month}/${dt.year}';
    }
    return '';
  }

  void _showAdminNotifications(BuildContext ctx, List<QueryDocumentSnapshot> docs) async {
    await FirebaseService.markAdminNotificationsRead();
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.9,
        expand: false,
        builder: (__, scrollCtrl) => Padding(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Row(children: [
              Icon(Icons.notifications_none_rounded, color: isDark ? Colors.white70 : Colors.black54),
              const SizedBox(width: 8),
              Text('Notifications', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
              const Spacer(),
              if (docs.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.clear_all_rounded, color: isDark ? Colors.white54 : Colors.black45, size: 20),
                  tooltip: 'Clear all',
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await FirebaseService.clearAdminNotifications();
                    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All notifications cleared')));
                  },
                ),
              IconButton(icon: Icon(Icons.close, color: isDark ? Colors.white54 : Colors.black45), onPressed: () => Navigator.pop(ctx)),
            ]),
            const Divider(),
            Expanded(
              child: docs.isEmpty
                  ? Center(child: Text('No notifications', style: TextStyle(color: isDark ? Colors.white38 : Colors.black45)))
                  : ListView.separated(
                      controller: scrollCtrl,
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        final type = d['type'] as String? ?? '';
                        final msg = d['message'] as String? ?? '';
                        IconData icon;
                        Color color;
                        switch (type) {
                          case 'registration': icon = Icons.person_add_rounded; color = Colors.green; break;
                          case 'feedback': icon = Icons.support_agent_rounded; color = Colors.orange; break;
                          case 'login': icon = Icons.login_rounded; color = Colors.blue; break;
                          case 'logout': icon = Icons.logout_rounded; color = Colors.blueGrey; break;
                          case 'auto_block': icon = Icons.block_rounded; color = Colors.red; break;
                          case 'blocked': icon = Icons.block_rounded; color = Colors.red; break;
                          default: icon = Icons.circle_rounded; color = Colors.grey;
                        }
                        return ListTile(
                          leading: Icon(icon, color: color, size: 28),
                          title: Text(msg, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14)),
                          subtitle: d['createdAt'] != null
                              ? Text(_formatTimestamp(d['createdAt']), style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 11))
                              : null,
                          dense: true,
                          onTap: () {
                            Navigator.pop(ctx);
                            switch (type) {
                              case 'feedback': context.push('/admin/feedbacks'); break;
                              case 'blocked': case 'auto_block': context.push('/admin', extra: {'studentUid': d['relatedUid']}); break;
                              case 'registration': context.push('/admin/control-panel'); break;
                              default: break;
                            }
                          },
                        );
                      },
                    ),
            ),
          ]),
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchContentMatches(String query) async {
    final q = query.toLowerCase();
    final results = <Map<String, dynamic>>[];
    final foldersSnap = await FirebaseService.firestore.collection('folders').get();
    for (final folderDoc in foldersSnap.docs) {
      final data = folderDoc.data() as Map<String, dynamic>;
      if (data['invisible'] == true) continue;
      final folderName = data['name'] as String? ?? '';
      final folderId = folderDoc.id;
      if (folderName.toLowerCase().contains(q)) continue;
      final contentsSnap = await FirebaseService.firestore.collection('folders').doc(folderId).collection('contents').get();
      for (final contentDoc in contentsSnap.docs) {
        final cData = contentDoc.data() as Map<String, dynamic>;
        final contentName = cData['name'] as String? ?? cData['title'] as String? ?? '';
        if (contentName.toLowerCase().contains(q)) {
          final type = cData['type'] as String?;
          results.add({'folderId': folderId, 'folderName': folderName, 'contentName': contentName, 'contentId': contentDoc.id, 'type': type ?? ''});
        }
      }
      if (results.length >= 50) break;
    }
    return results;
  }

  Widget _buildAdminSearchResults(List<QueryDocumentSnapshot> filteredFolders, List<QueryDocumentSnapshot> allDocs, List<Color> colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _fetchContentMatches(_searchQuery),
      builder: (context, snap) {
        final contentMatches = snap.data ?? [];
        final totalItems = filteredFolders.length + contentMatches.length;
        if (totalItems == 0) {
          return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.search_off_rounded, size: 60, color: Colors.white12),
            const SizedBox(height: 16),
            const Text('No results found', style: TextStyle(color: Colors.white38, fontSize: 16)),
          ]));
        }
        return ListView.builder(
          padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
          itemCount: totalItems,
          itemBuilder: (context, index) {
            if (index < filteredFolders.length) {
              final d = filteredFolders[index];
              final data = d.data() as Map<String, dynamic>;
              final folderId = d.id;
              final folderName = data['name'] as String? ?? 'Folder';
              final color = colors[index % colors.length];
              return Card(
                color: isDark ? const Color(0xFF1A0533) : Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(Icons.folder_rounded, color: color, size: 32),
                  title: Text(folderName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                  subtitle: Text('Folder match', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => context.push('/folders/$folderId', extra: {'canEdit': true, 'canManage': true, 'isAdmin': true}),
                ),
              );
            } else {
              final m = contentMatches[index - filteredFolders.length];
              final isSubfolder = m['type'] == 'subfolder';
              final path = isSubfolder
                  ? '/folders/${m['folderId']}/sub/${m['contentId']}'
                  : '/folders/${m['folderId']}';
              final label = isSubfolder ? 'subfolder' : 'file';
              return Card(
                color: isDark ? const Color(0xFF1A0533) : Colors.white,
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: Icon(isSubfolder ? Icons.folder_rounded : Icons.insert_drive_file_rounded, color: isSubfolder ? Colors.amber : Colors.teal, size: 28),
                  title: Text(m['contentName'] as String? ?? '', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text('${m['folderName']} › $label', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () => context.push(path, extra: {'canEdit': true, 'canManage': true, 'isAdmin': true}),
                ),
              );
            }
          },
        );
      },
    );
  }

  Widget _buildAdminSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white38 : Colors.black45;
    final fillColor = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search folders...',
          hintStyle: TextStyle(color: hintColor, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: hintColor, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: hintColor, size: 18),
                  onPressed: () { _searchController.clear(); setState(() => _searchQuery = ''); },
                )
              : null,
          filled: true, fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  Widget _buildToggleRow(String title, String subtitle, IconData icon, Color color, bool value, Function(bool) onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(children: [
        Icon(icon, color: color, size: 22),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
          Text(subtitle, style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 11)),
        ])),
        Switch(value: value, onChanged: onChanged, activeColor: color),
      ]),
    );
  }

  // ─── Content Methods ─────────────────────────────────────────────────────────

  void _showAddContentSheet(String folderId, String folderName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Add to: $folderName', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 20),
            _buildContentOption(ctx, Icons.folder_rounded, Colors.blue, 'Sub-Folder', 'Create a sub-folder', () => _addSubFolder(ctx, folderId)),
            const SizedBox(height: 12),
            _buildContentOption(ctx, Icons.play_circle_fill_rounded, Colors.red, 'Recorded Lecture', 'Add YouTube video link', () => _addYouTubeLecture(ctx, folderId)),
            const SizedBox(height: 12),
            _buildContentOption(ctx, Icons.assignment_rounded, Colors.orange, 'Mock Test', 'Add URL or paste code', () => _addMockTest(ctx, folderId)),
            const SizedBox(height: 12),
            _buildContentOption(ctx, Icons.upload_file_rounded, Colors.teal, 'Upload File', 'Add file name and link', () => _addUploadFile(ctx, folderId)),
            const SizedBox(height: 16),
          ]),
        ),
      ),
    );
  }

  Widget _buildContentOption(BuildContext ctx, IconData icon, Color color, String title, String subtitle, VoidCallback onTap) {
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14), border: Border.all(color: color.withValues(alpha: 0.3))),
        child: Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: 0.2), shape: BoxShape.circle), child: Icon(icon, color: color, size: 22)),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)), Text(subtitle, style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12))]),
          const Spacer(),
          Icon(Icons.chevron_right, color: color.withValues(alpha: 0.6)),
        ]),
      ),
    );
  }

  void _addMockTest(BuildContext ctx, String folderId) {
    Navigator.pop(ctx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context, backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Add Mock Test', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 20),
          ListTile(leading: const Icon(Icons.link, color: Colors.orange), title: Text('Add URL', style: TextStyle(color: isDark ? Colors.white : Colors.black87)), onTap: () { Navigator.pop(ctx); _addMockTestUrl(folderId); }),
          const Divider(color: Colors.white12),
          ListTile(leading: const Icon(Icons.code, color: Colors.orange), title: Text('Paste a Code', style: TextStyle(color: isDark ? Colors.white : Colors.black87)), onTap: () { Navigator.pop(ctx); _addMockTestCode(folderId); }),
        ])),
      ),
    );
  }

  void _addMockTestUrl(String folderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController(text: 'Mock Test');
    final urlCtrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [const Icon(Icons.link, color: Colors.orange), const SizedBox(width: 8), Text('Mock Test URL', style: TextStyle(color: baseColor))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Test name...', Icons.title, isDark: isDark)),
        const SizedBox(height: 12),
        TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Paste URL...', Icons.link, isDark: isDark)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('save_mock_url')) return;
          if (nameCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.addFolderContent(folderId, {'type': 'mocktest_url', 'name': nameCtrl.text.trim(), 'url': urlCtrl.text.trim()});
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _addMockTestCode(String folderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController(text: 'Mock Test');
    final codeCtrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [const Icon(Icons.code, color: Colors.orange), const SizedBox(width: 8), Text('Mock Test Code', style: TextStyle(color: baseColor))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Test name...', Icons.title, isDark: isDark)),
        const SizedBox(height: 12),
        TextField(controller: codeCtrl, maxLines: 5, style: TextStyle(color: baseColor, fontFamily: 'monospace', fontSize: 13), decoration: InputDecoration(hintText: 'Paste code...', hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('save_mock_code')) return;
          if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.addFolderContent(folderId, {'type': 'mocktest_code', 'name': nameCtrl.text.trim(), 'code': codeCtrl.text.trim()});
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _addUploadFile(BuildContext ctx, String folderId) {
    Navigator.pop(ctx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Upload File', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.phone_android, color: Colors.blue),
              title: Text('Internal Storage', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text('Pick file from device', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
              onTap: () { Navigator.pop(context); _pickFileFromStorage(folderId); },
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            ListTile(
              leading: const Icon(Icons.cloud_upload_rounded, color: Colors.amber),
              title: Text('Google Drive', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text('Import from Google Drive', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
              onTap: () { Navigator.pop(context); _pickFileFromDrive(folderId); },
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            ListTile(
              leading: const Icon(Icons.link, color: Colors.teal),
              title: Text('Paste URL', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              subtitle: Text('Enter file link manually', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
              onTap: () { Navigator.pop(context); _addUploadFileUrl(folderId); },
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }

  void _pickFileFromStorage(String folderId) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: false);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        await FirebaseService.addFolderContent(folderId, {'type': 'file', 'name': file.name, 'url': file.path ?? '', 'source': 'internal_storage'});
        await FirebaseService.addNotification('Uploaded file: ${file.name}', folderId: folderId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error picking file: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _pickFileFromDrive(String folderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.cloud_upload_rounded, color: Colors.amber), const SizedBox(width: 8), Text('Google Drive', style: TextStyle(color: baseColor))]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('File name...', Icons.title, isDark: isDark)),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Paste Drive link...', Icons.cloud, isDark: isDark)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (!debounce('save_drive')) return;
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              await FirebaseService.addFolderContent(folderId, {'type': 'file', 'name': nameCtrl.text.trim(), 'url': urlCtrl.text.trim(), 'source': 'google_drive'});
              await FirebaseService.addNotification('Uploaded from Drive: ${nameCtrl.text.trim()}', folderId: folderId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addUploadFileUrl(String folderId) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.link, color: Colors.teal), const SizedBox(width: 8), Text('Paste URL', style: TextStyle(color: baseColor))]),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('File name...', Icons.title, isDark: isDark)),
          const SizedBox(height: 12),
          TextField(controller: linkCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('File URL or link...', Icons.link, isDark: isDark)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (!debounce('save_url_file')) return;
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              await FirebaseService.addFolderContent(folderId, {'type': 'file', 'name': nameCtrl.text.trim(), 'url': linkCtrl.text.trim(), 'source': 'url'});
              await FirebaseService.addNotification('Uploaded file: ${nameCtrl.text.trim()}', folderId: folderId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addGroupLink(BuildContext ctx, String folderId) {
    Navigator.pop(ctx);
    showDialog(
      context: context,
      builder: (d) => GroupLinkDialog(
        folderId: folderId,
        parentContentId: 'root',
      ),
    );
  }

  void _groupLinkForFolder(BuildContext ctx, String folderId) {
    showDialog(
      context: ctx,
      builder: (d) => GroupLinkDialog(
        folderId: folderId,
        parentContentId: 'root',
      ),
    );
  }

  void _addSubFolder(BuildContext ctx, String parentFolderId) {
    Navigator.pop(ctx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('New Sub-Folder', style: TextStyle(color: baseColor)),
      content: TextField(controller: ctrl, autofocus: true, style: TextStyle(color: baseColor), decoration: _inputDec('Sub-folder name...', Icons.folder, isDark: isDark)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('create_subfolder')) return;
          if (ctrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.addFolderContent(parentFolderId, {'type': 'subfolder', 'name': ctrl.text.trim()});
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Create', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _addYouTubeLecture(BuildContext ctx, String folderId) {
    Navigator.pop(ctx);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [const Icon(Icons.play_circle_fill_rounded, color: Colors.red), const SizedBox(width: 8), Text('Add Lecture', style: TextStyle(color: baseColor))]),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: titleCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Lecture title...', Icons.title, isDark: isDark)),
        const SizedBox(height: 12),
        TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: _inputDec('Paste YouTube link...', Icons.link, isDark: isDark)),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('save_lecture')) return;
          if (titleCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.addFolderContent(folderId, {'type': 'lecture', 'name': titleCtrl.text.trim(), 'youtubeUrl': urlCtrl.text.trim()});
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  InputDecoration _inputDec(String hint, IconData icon, {bool isDark = true}) => InputDecoration(
    hintText: hint, hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38), prefixIcon: Icon(icon, color: isDark ? Colors.white54 : Colors.black54),
    filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
  );

  void _showRenameDialog(String folderId, String currentName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final ctrl = TextEditingController(text: currentName);
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text('Rename Folder', style: TextStyle(color: baseColor)),
      content: TextField(controller: ctrl, autofocus: true, style: TextStyle(color: baseColor), decoration: _inputDec('New name...', Icons.edit, isDark: isDark)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
        ElevatedButton(onPressed: () async {
          if (ctrl.text.trim().isEmpty) return;
          Navigator.pop(d);
          await FirebaseService.renameRootFolder(folderId, ctrl.text.trim());
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Rename', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 48, 12, 12),
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Row(children: [
            Image.asset('assets/logo.png', height: 36, width: 36),
            const SizedBox(width: 12),
            if (widget.studentUid != null)
              IconButton(
                icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white70 : const Color(0xFF1A0533), size: 20),
                onPressed: () => context.go('/admin'),
              ),
            Expanded(
              child: Text(
                widget.studentUid != null ? '${widget.studentName ?? 'Student'}\'s Panel' : 'Admin Console',
                style: TextStyle(fontSize: widget.studentUid != null ? 16 : 20, fontWeight: FontWeight.bold, color: isDark ? Colors.white : const Color(0xFF1A0533)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.getAdminNotifications(),
              builder: (context, snap) {
                final unread = snap.hasData ? snap.data!.docs.where((d) => (d.data() as Map<String, dynamic>)['read'] == false).length : 0;
                return IconButton(
                  icon: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(Icons.notifications_none_rounded, color: isDark ? Colors.white70 : const Color(0xFF1A0533), size: 26),
                      if (unread > 0)
                        Positioned(
                          right: -4, top: -2,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                            child: Text('$unread', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                          ),
                        ),
                    ],
                  ),
                  onPressed: () => _showAdminNotifications(this.context, snap.data?.docs ?? []),
                  tooltip: 'Notifications',
                );
              },
            ),
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : const Color(0xFF1A0533), size: 28),
              color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              onOpened: () { _loadPendingCount(); _markAllFeedbacksViewed(); },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'notices', child: Row(children: [Icon(Icons.campaign_rounded, size: 18, color: Colors.amber), SizedBox(width: 10), Text('Notice Board', style: TextStyle(color: isDark ? Colors.white : Colors.black87))])),
                PopupMenuItem(value: 'control_panel', child: Row(children: [Icon(Icons.admin_panel_settings_rounded, size: 18, color: Colors.cyan), SizedBox(width: 10), Text('Control Panel', style: TextStyle(color: isDark ? Colors.white : Colors.black87))])),
                    PopupMenuItem(value: 'feedbacks', child: Row(children: [Icon(Icons.support_agent_rounded, size: 18, color: Colors.orange), SizedBox(width: 10), Text('Contact Support', style: TextStyle(color: isDark ? Colors.white : Colors.black87))])),
                PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, size: 18, color: isDark ? Colors.white70 : Colors.black87), SizedBox(width: 10), Text('Settings', style: TextStyle(color: isDark ? Colors.white : Colors.black87))])),
              ],
              onSelected: (val) {
                switch (val) {
                  case 'notices': context.push('/admin/notices'); break;
                  case 'control_panel': context.push('/admin/control-panel'); break;
                  case 'feedbacks': context.push('/admin/feedbacks'); break;
                  case 'settings': context.push('/admin/settings'); break;
                }
              },
            ),
          ]),
        ),
        _buildAdminSearchBar(),
        const Divider(height: 1, color: Colors.white12),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: _folderStream,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.folder_open_rounded, size: 80, color: Colors.white12),
                  const SizedBox(height: 16),
                  const Text('No folders yet', style: TextStyle(color: Colors.white38, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text('Tap + to create your first folder', style: TextStyle(color: Colors.white24, fontSize: 13)),
                ]));
              }
              // Use optimistic local state if available, else sort from snapshot
              final rawDocs = snapshot.data!.docs;
              // Always re-sort from stream data (fixes rename not reflecting)
              _localDocs = List<QueryDocumentSnapshot>.from(rawDocs)
                ..sort((a, b) {
                  final aData = a.data() as Map<String, dynamic>;
                  final bData = b.data() as Map<String, dynamic>;
                  final aOrder = (aData['sortOrder'] as num?)?.toInt() ?? 9999;
                  final bOrder = (bData['sortOrder'] as num?)?.toInt() ?? 9999;
                  return aOrder.compareTo(bOrder);
                });
              final docs = _localDocs!;
              final colors = [Colors.purple, Colors.teal, Colors.blue, Colors.orange, Colors.pink, Colors.indigo];
              final filtered = _searchQuery.isNotEmpty
                  ? docs.where((d) {
                      final data = d.data() as Map<String, dynamic>;
                      final name = (data['name'] as String? ?? '').toLowerCase();
                      return name.contains(_searchQuery.toLowerCase());
                    }).toList()
                  : docs;
              if (_searchQuery.isNotEmpty) {
                return _buildAdminSearchResults(filtered, snapshot.data!.docs, colors);
              }
              return ReorderableListView.builder(
                padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 120),
                itemCount: filtered.length,
                onReorder: (oldIndex, newIndex) async {
                  if (newIndex > oldIndex) newIndex--;
                  final reordered = List<QueryDocumentSnapshot>.from(docs);
                  final moved = reordered.removeAt(oldIndex);
                  reordered.insert(newIndex, moved);
                  // Optimistic local update
                  setState(() => _localDocs = reordered);
                  // Save to Firestore
                  for (int i = 0; i < reordered.length; i++) {
                    await FirebaseService.firestore
                        .collection('folders')
                        .doc(reordered[i].id)
                        .update({'sortOrder': i}).catchError((_) {});
                  }
                },
                buildDefaultDragHandles: false,
                itemBuilder: (context, index) {
                  final isDark = Theme.of(context).brightness == Brightness.dark;
                  final data = filtered[index].data() as Map<String, dynamic>;
                  final folderId = filtered[index].id;
                  final folderName = data['name'] as String? ?? 'Folder';
                  final locked = data['locked'] as bool? ?? false;
                  final updating = data['updating'] as bool? ?? false;
                  final invisible = data['invisible'] as bool? ?? false;
                  final color = colors[index % colors.length];
                  return AnimatedPressable(
                    key: ValueKey(folderId),
                    onTap: () => context.push('/folders/$folderId', extra: {'canEdit': true, 'canManage': true, 'isAdmin': true}),
                    child: GestureDetector(
                      onLongPress: () {
                        showModalBottomSheet(
                          context: context, backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
                          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
                          builder: (_) => Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Text(folderName, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            ListTile(leading: const Icon(Icons.drive_file_rename_outline_rounded, color: Colors.blue), title: Text('Rename', style: TextStyle(color: isDark ? Colors.white : Colors.black87)), onTap: () { Navigator.pop(context); _showRenameDialog(folderId, folderName); }),
                            ListTile(leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), title: const Text('Delete', style: TextStyle(color: Colors.redAccent)), onTap: () { Navigator.pop(context); _confirmDelete(folderId, folderName); }),
                          ])),
                        );
                      },
                      child: GlassmorphicContainer(
                        padding: const EdgeInsets.all(0), margin: const EdgeInsets.only(bottom: 14),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
                            child: Row(children: [
                              // 6-dot drag handle
                              ReorderableDragStartListener(
                                index: index,
                                child: Padding(
                                  padding: const EdgeInsets.only(right: 10),
                                  child: Icon(Icons.drag_indicator_rounded, color: isDark ? Colors.white38 : Colors.black38, size: 22),
                                ),
                              ),
                              Icon(Icons.folder_rounded, color: locked ? Colors.grey : color, size: 28),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(folderName, style: TextStyle(color: (locked || invisible) ? (isDark ? Colors.white38 : Colors.black45) : (isDark ? Colors.white : Colors.black87), fontWeight: FontWeight.bold, fontSize: 16)),
                                if (locked || updating || invisible)
                                  Text(locked ? '🔒 Locked' : (updating ? '🔄 Updating...' : '👻 Hidden'),
                                    style: TextStyle(
                                      color: locked ? Colors.redAccent : (updating ? Colors.orange : Colors.purple),
                                      fontSize: 11, fontWeight: FontWeight.bold,
                                    )),
                              ])),
                            ]),
                          ),
                          const Divider(color: Colors.white12, height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                            child: Row(children: [
                              _actionBtn(Icons.add_circle_outline, color, 'Add', () => _showAddContentSheet(folderId, folderName)),
                              _actionBtn(Icons.people_alt_rounded, Colors.orange, 'Assistant', () => _showGrantAccessDialog(folderId, folderName)),
                              _actionBtn(Icons.lock_outline_rounded, Colors.amber, 'Lock', () => _showFolderLockSheet(folderId, folderName, locked, updating, invisible)),
                              _actionBtn(Icons.groups_rounded, Colors.green, 'Group', () => _groupLinkForFolder(context, folderId)),
                              _actionBtn(Icons.open_in_new_rounded, Colors.blue, 'Open', () => context.push('/folders/$folderId', extra: {'canEdit': true, 'canManage': true, 'isAdmin': true})),
                              const Spacer(),
                              IconButton(icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent), onPressed: () => _confirmDelete(folderId, folderName), tooltip: 'Delete'),
                            ]),
                          ),
                        ]),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
      floatingActionButton: Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton(
          heroTag: 'ai_chat_admin', onPressed: () => context.push('/ai_tutor'),
          backgroundColor: Colors.transparent, elevation: 0,
          child: Container(width: 56, height: 56, decoration: BoxDecoration(shape: BoxShape.circle, gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)], begin: Alignment.topLeft, end: Alignment.bottomRight), boxShadow: [BoxShadow(color: const Color(0xFF00B8D4).withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 2)]), child: ClipOval(child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover))),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(
          heroTag: 'create_folder', onPressed: _showCreateFolderDialog,
          backgroundColor: const Color(0xFF4A148C),
          child: const Icon(Icons.create_new_folder_rounded, color: Colors.white),
        ),
      ]),
    );
  }

  void _showSettings() {
    final container = ProviderScope.containerOf(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    double price = 0;
    bool paidAccess = false;
    bool loadingSettings = true;
    String accountTitle = '';
    String accountNo = '';
    String bankName = '';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        if (loadingSettings) {
          FirebaseService.getSettings().then((s) {
            if (ctx.mounted) setLocal(() { price = (s['price'] as num?)?.toDouble() ?? 0; paidAccess = s['paidAccess'] as bool? ?? false; accountTitle = s['accountTitle'] as String? ?? ''; accountNo = s['accountNo'] as String? ?? ''; bankName = s['bankName'] as String? ?? ''; loadingSettings = false; });
          });
        }
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final baseColor = isDark ? Colors.white : Colors.black87;
        final dimColor = isDark ? Colors.white38 : Colors.black54;
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.settings_outlined, color: baseColor, size: 22), SizedBox(width: 10), Text('Settings', style: TextStyle(color: baseColor, fontSize: 18, fontWeight: FontWeight.bold))]),
            const SizedBox(height: 12),
            Builder(builder: (ctx) {
              final u = FirebaseService.currentUser;
              return ListTile(
                leading: CircleAvatar(child: Text((u?.displayName ?? 'A')[0].toUpperCase(), style: const TextStyle(color: Colors.white))),
                title: Text(u?.displayName ?? 'Admin', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold)),
                subtitle: Text(u?.email ?? '', style: TextStyle(color: dimColor, fontSize: 12)),
              );
            }),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            const SizedBox(height: 8),
            if (loadingSettings)
              const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
            else ...[
              Divider(color: isDark ? Colors.white12 : Colors.black12, height: 24),
            ],
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Colors.grey),
              title: Text('Version', style: TextStyle(color: baseColor)),
              subtitle: Text('PrePora v1.0.0', style: TextStyle(color: dimColor, fontSize: 12)),
            ),
            ListTile(
              leading: const Icon(Icons.palette_outlined, color: Colors.amber),
              title: Text('Theme', style: TextStyle(color: baseColor)),
              subtitle: Text(() {
                final tm = container.read(themeModeProvider);
                return tm == ThemeMode.light ? 'Light' : (tm == ThemeMode.dark ? 'Dark' : 'System');
              }(), style: TextStyle(color: dimColor, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: dimColor, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                _showThemeDialog(context);
              },
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12, height: 24),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Logout', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                FirebaseService.signOut();
                this.context.go('/auth/login');
              },
            ),
          ]),
        );
      }),
    );
  }

  void _showThemeDialog(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final themeMode = container.read(themeModeProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        title: Text('Choose Theme', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.light_mode_rounded, color: Colors.amber),
            title: Text('Light', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            onTap: () { themeMode.set(ThemeMode.light); Navigator.pop(d); },
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_rounded, color: Colors.blueGrey),
            title: Text('Dark', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            onTap: () { themeMode.set(ThemeMode.dark); Navigator.pop(d); },
          ),
          ListTile(
            leading: const Icon(Icons.settings_brightness_rounded, color: Colors.teal),
            title: Text('System', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
            subtitle: Text('Follow device theme', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 11)),
            onTap: () { themeMode.set(ThemeMode.system); Navigator.pop(d); },
          ),
        ]),
      ),
    );
  }

  void _showBlockStudents(BuildContext parentCtx) {
    showModalBottomSheet(
      context: parentCtx,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return FutureBuilder<List<Map<String, dynamic>>>(
          future: FirebaseService.getAllStudents(),
          builder: (ctx, snap) {
            if (!snap.hasData) {
              return Padding(
                padding: const EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator(color: isDark ? Colors.white : Colors.black87)),
              );
            }
            final students = snap.data!;
            return Container(
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1A0533) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.block_rounded, color: Colors.redAccent, size: 22),
                  const SizedBox(width: 10),
                  Text('Block Students (${students.length})', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(icon: Icon(Icons.close, color: isDark ? Colors.white38 : Colors.black54), onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),
                if (students.isEmpty)
                  Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('No students registered.', style: TextStyle(color: isDark ? Colors.white38 : Colors.black45))))
                else
                  ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.5),
                    child: ListView.separated(
                      itemCount: students.length,
                      separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
                      itemBuilder: (_, i) {
                        final s = students[i];
                        final uid = s['id'] as String? ?? '';
                        final name = s['name'] as String? ?? 'Unknown';
                        final email = s['email'] as String? ?? '';
                        final isBlocked = s['blocked'] as bool? ?? false;
                        final isVerified = s['verified'] as bool? ?? false;
                        return Card(
                          color: isDark ? const Color(0xFF0D0D2E) : Colors.grey.shade50,
                          margin: const EdgeInsets.only(bottom: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                CircleAvatar(
                                  backgroundColor: isBlocked ? Colors.redAccent.withValues(alpha: 0.3) : Colors.green.withValues(alpha: 0.3),
                                  child: Icon(isBlocked ? Icons.block_rounded : Icons.check_circle_outline_rounded, color: isBlocked ? Colors.redAccent : Colors.green, size: 18),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
                                  Text(email, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 11)),
                                ])),
                              ]),
                              const SizedBox(height: 6),
                              Row(children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 30,
                                    child: TextButton(
                                      onPressed: () async {
                                        if (!debounce('block_$uid')) return;
                                        await FirebaseService.toggleStudentBlocked(uid, !isBlocked);
                                        if (ctx.mounted) setLocal(() { s['blocked'] = !isBlocked; });
                                      },
                                      style: TextButton.styleFrom(backgroundColor: isBlocked ? Colors.green : Colors.redAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 6)),
                                      child: Text(isBlocked ? 'Unblock' : 'Block', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: SizedBox(
                                    height: 30,
                                    child: TextButton(
                                      onPressed: () async {
                                        if (!debounce('verify_$uid')) return;
                                        await FirebaseService.toggleStudentVerified(uid, !isVerified);
                                        if (ctx.mounted) setLocal(() { s['verified'] = !isVerified; });
                                      },
                                      style: TextButton.styleFrom(backgroundColor: isVerified ? Colors.orange : Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 6)),
                                      child: Text(isVerified ? 'Unverify' : 'Verify', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
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
          },
        );
      }),
    );
  }

  void _showAccountInfoDialog(BuildContext parentCtx, StateSetter setLocal, String currentTitle, String currentNo, String currentBank) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final titleCtrl = TextEditingController(text: currentTitle);
    final noCtrl = TextEditingController(text: currentNo);
    final bankCtrl = TextEditingController(text: currentBank);
    showDialog(
      context: parentCtx,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Account Info', style: TextStyle(color: baseColor)),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: titleCtrl, style: TextStyle(color: baseColor),
              decoration: InputDecoration(labelText: 'Account Title', labelStyle: TextStyle(color: dimColor),
                filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
            const SizedBox(height: 12),
            TextField(controller: noCtrl, style: TextStyle(color: baseColor),
              decoration: InputDecoration(labelText: 'Account No', labelStyle: TextStyle(color: dimColor),
                filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
            const SizedBox(height: 12),
            TextField(controller: bankCtrl, style: TextStyle(color: baseColor),
              decoration: InputDecoration(labelText: 'Bank Name', labelStyle: TextStyle(color: dimColor),
                filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(onPressed: () async {
            await FirebaseService.updateSetting('accountTitle', titleCtrl.text.trim());
            await FirebaseService.updateSetting('accountNo', noCtrl.text.trim());
            await FirebaseService.updateSetting('bankName', bankCtrl.text.trim());
            if (parentCtx.mounted) {
              setLocal(() { /* parent will refresh on next open */ });
            }
            Navigator.pop(d);
          }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Column(children: [Icon(icon, color: color, size: 22), Text(label, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold))])),
    );
  }

  void _confirmDelete(String folderId, String name) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      title: Text('Delete Folder?', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
      content: Text('Delete "$name"? This cannot be undone.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async { Navigator.pop(d); await FirebaseService.deleteRootFolder(folderId); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
}
