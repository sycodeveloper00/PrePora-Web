import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/utils.dart';

class AdminFeedbackScreen extends StatefulWidget {
  const AdminFeedbackScreen({super.key});
  @override
  State<AdminFeedbackScreen> createState() => _AdminFeedbackScreenState();
}

class _AdminFeedbackScreenState extends State<AdminFeedbackScreen> {
  List<Map<String, dynamic>>? _students;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    NotificationService.clearBadge();
    _markAllAsViewed();
    _loadStudents();
  }

  Future<void> _markAllAsViewed() async {
    final snap = await FirebaseService.firestore
        .collection('feedbacks')
        .where('status', isEqualTo: 'pending')
        .where('viewed', isEqualTo: false)
        .get();
    final batch = FirebaseService.firestore.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'viewed': true});
    }
    await batch.commit();
  }

  Future<void> _loadStudents() async {
    final students = await FirebaseService.getAllStudents();
    if (mounted) setState(() { _students = students; _loading = false; });
  }

  Future<int> _pendingCount(String uid) async {
    final feedbacks = await FirebaseService.getStudentFeedbacksOnce(uid);
    return feedbacks.where((f) => f['status'] == 'pending').length;
  }

  void _showStudentFeedbacks(String uid, String name, Map<String, dynamic> studentData) async {
    final feedbacks = await FirebaseService.getStudentFeedbacksOnce(uid);
    if (!mounted) return;
    final isBlocked = studentData['blocked'] as bool? ?? false;
    final isVerified = studentData['verified'] as bool? ?? true;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) {
        var items = feedbacks;
        Set<String> updatingIds = {};
        Map<String, String?> selectedStatusPerTicket = {};
        return StatefulBuilder(builder: (ctx, setLocal) {
          final ctxIsDark = Theme.of(ctx).brightness == Brightness.dark;
          return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.85,
          initialChildSize: 0.6,
          builder: (ctx, scrollCtrl) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Text("$name's Feedbacks", style: TextStyle(color: ctxIsDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16)),
                if (isBlocked)
                  const Padding(padding: EdgeInsets.only(left: 8), child: Icon(Icons.block_rounded, color: Colors.redAccent, size: 18)),
                const Spacer(),
                IconButton(icon: Icon(Icons.close, color: ctxIsDark ? Colors.white38 : Colors.black38), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            const Divider(color: Colors.white12),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text('No feedbacks', style: TextStyle(color: ctxIsDark ? Colors.white38 : Colors.black54)))
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final data = items[i];
                        final ticket = data['ticketNo'] as String? ?? '';
                        final msg = data['message'] as String? ?? '';
                        final status = data['status'] as String? ?? 'pending';
                        final time = (data['createdAt'] as Timestamp?)?.toDate();
                        final timeStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';
                        final isUpdating = updatingIds.contains(data['id'] as String);
                        return Card(
                          color: ctxIsDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.shade100,
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Row(children: [
                                  if (isBlocked)
                                    const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.block_rounded, color: Colors.redAccent, size: 14)),
                                  Text('#$ticket', style: const TextStyle(color: Color(0xFF00B8D4), fontWeight: FontWeight.bold, fontSize: 13)),
                                ]),
                                const Spacer(),
                                Text(status.toUpperCase(), style: TextStyle(color: status == 'completed' ? Colors.green : (status == 'rejected' ? Colors.red : (status == 'verified' ? Colors.teal : Colors.orange)), fontSize: 11)),
                              ]),
                              const SizedBox(height: 8),
                              Text(msg, style: TextStyle(color: ctxIsDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                              if (data['reply'] != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: (ctxIsDark ? Colors.white : Colors.black).withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: ctxIsDark ? Colors.white12 : Colors.black12)),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Row(children: [Icon(Icons.reply_rounded, color: Colors.teal, size: 14), SizedBox(width: 4), Text('Admin Reply', style: TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.bold))]),
                                    const SizedBox(height: 4),
                                    Text(data['reply'] as String? ?? '', style: TextStyle(color: ctxIsDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                  ]),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(timeStr, style: TextStyle(color: ctxIsDark ? Colors.white24 : Colors.black38, fontSize: 11)),
                              if (status == 'pending') ...[
                                const SizedBox(height: 10),
                                Row(children: [
                                  IconButton(
                                    icon: const Icon(Icons.reply_rounded, color: Colors.teal, size: 20),
                                    tooltip: 'Reply',
                                    onPressed: () => _showReplyDialog(ctx, setLocal, data, uid, items),
                                  ),
                                  _buildFeedbackActions(ctx, setLocal, data, uid, isUpdating, updatingIds, isBlocked, isVerified, items, selectedStatusPerTicket, data['id'] as String),
                                ]),
                              ],
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
    );
  }

  Widget _buildFeedbackActions(BuildContext ctx, StateSetter setLocal, Map<String, dynamic> data, String uid, bool isUpdating, Set<String> updatingIds, bool isBlocked, bool isVerified, List<Map<String, dynamic>> items, Map<String, String?> selectedStatusPerTicket, String ticketId) {
    final id = data['id'] as String;
    final ticketSelected = selectedStatusPerTicket[ticketId];
    final locked = ticketSelected != null;
    if (isUpdating && updatingIds.contains(id)) {
      return const SizedBox.shrink();
    }
    if (isBlocked) {
      return _buildActionButtonRow(ctx, setLocal, data, uid, isUpdating, updatingIds, items, [
        ('Unblocked', Colors.orange, 'unblocked', () async {
          await FirebaseService.toggleStudentBlocked(uid, false);
        }),
        ('Rejected', Colors.redAccent, 'rejected', null),
      ], selectedStatus: ticketSelected, locked: locked, onSelected: (s) {
        setLocal(() => selectedStatusPerTicket[ticketId] = s);
      }, selectedStatusPerTicket: selectedStatusPerTicket, ticketId: ticketId);
    }
    if (!isVerified) {
      return _buildActionButtonRow(ctx, setLocal, data, uid, isUpdating, updatingIds, items, [
        ('Verified', Colors.teal, 'verified', () async {
          await FirebaseService.toggleStudentVerified(uid, true);
        }),
        ('Rejected', Colors.redAccent, 'rejected', null),
      ], selectedStatus: ticketSelected, locked: locked, onSelected: (s) {
        setLocal(() => selectedStatusPerTicket[ticketId] = s);
      }, selectedStatusPerTicket: selectedStatusPerTicket, ticketId: ticketId);
    }
    return _buildActionButtonRow(ctx, setLocal, data, uid, isUpdating, updatingIds, items, [
      ('Completed', Colors.green, 'completed', null),
      ('Rejected', Colors.redAccent, 'rejected', null),
    ], selectedStatus: ticketSelected, locked: locked, onSelected: (s) {
      setLocal(() => selectedStatusPerTicket[ticketId] = s);
    }, selectedStatusPerTicket: selectedStatusPerTicket, ticketId: ticketId);
  }

  Widget _buildActionButtonRow(BuildContext ctx, StateSetter setLocal, Map<String, dynamic> data, String uid, bool isUpdating, Set<String> updatingIds, List<Map<String, dynamic>> items, List<(String label, Color color, String status, Future<void> Function()? extra)> actions, {String? selectedStatus, bool locked = false, void Function(String)? onSelected, Map<String, String?>? selectedStatusPerTicket, String? ticketId}) {
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: actions.map((a) {
      final (label, color, status, extra) = a;
      final isSelected = selectedStatus == status;
      return Padding(
        padding: const EdgeInsets.only(left: 10),
        child: _buildActionButton(
          label: label, color: color, isUpdating: isUpdating, isSelected: isSelected,
          onPressed: (isUpdating || locked) ? null : () async {
            if (!debounce('fb_action_$status')) return;
            if (onSelected != null) onSelected(status);
            final id = data['id'] as String;
            setLocal(() => updatingIds.add(id));
            await FirebaseService.updateFeedbackStatus(id, status);
            if (extra != null) await extra();
            NotificationService.clearBadge();
            final updated = await FirebaseService.getStudentFeedbacksOnce(uid);
            if (ctx.mounted) setLocal(() { items = updated; updatingIds.remove(id); if (selectedStatusPerTicket != null && ticketId != null) selectedStatusPerTicket[ticketId] = null; });
          },
        ),
      );
    }).toList());
  }

  void _showReplyDialog(BuildContext ctx, StateSetter setLocal, Map<String, dynamic> data, String uid, List<Map<String, dynamic>> items) {
    final ctrl = TextEditingController(text: data['reply'] as String? ?? '');
    final isDark = Theme.of(ctx).brightness == Brightness.dark;
    showDialog(
      context: ctx,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        title: Text('Reply to Feedback', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: TextField(
          controller: ctrl, maxLines: 4,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Write your reply...',
            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(onPressed: () async {
            if (!debounce('fb_reply')) return;
            if (ctrl.text.trim().isEmpty) return;
            final id = data['id'] as String;
            await FirebaseService.updateFeedbackReply(id, ctrl.text.trim());
            await FirebaseService.addTargetedNotification(uid, 'Your feedback has been replied by admin.');
            final updated = await FirebaseService.getStudentFeedbacksOnce(uid);
            if (d.mounted) Navigator.pop(d);
            if (ctx.mounted) setLocal(() { items = updated; });
          }, child: const Text('Send Reply')),
        ],
      ),
    );
  }

  Widget _buildActionButton({required String label, required Color color, required bool isUpdating, bool isSelected = false, VoidCallback? onPressed}) {
    return GestureDetector(
      onTap: (isUpdating || onPressed == null) ? null : onPressed,
      child: AnimatedScale(
        scale: 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: isSelected ? color : null,
            border: Border.all(color: isUpdating ? Colors.grey : (isSelected ? color : color)),
          ),
          child: isUpdating
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey))
              : Text(label, style: TextStyle(color: isSelected ? Colors.white : color, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : null)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Support', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _students == null || _students!.isEmpty
              ? Center(child: Text('No students', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _students!.length,
                  itemBuilder: (context, i) {
                    final s = _students![i];
                    final uid = s['id'] as String;
                    final name = s['name'] as String? ?? 'Unknown';
                    final isBlocked = s['blocked'] as bool? ?? false;
                    return Card(
                      color: isDark ? const Color(0xFF1A0533) : Colors.white,
                      margin: const EdgeInsets.only(bottom: 10),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isBlocked ? Colors.redAccent.withValues(alpha: 0.3) : Colors.white10,
                          child: Icon(isBlocked ? Icons.block_rounded : Icons.person, color: isBlocked ? Colors.redAccent : (isDark ? Colors.white38 : Colors.black54), size: 20),
                        ),
                        title: Text(name, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                        subtitle: FutureBuilder<int>(
                          future: _pendingCount(uid),
                          builder: (ctx, snap) {
                            final count = snap.hasData ? snap.data! : 0;
                            if (count == 0) return const SizedBox.shrink();
                            return Row(children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(10)),
                                child: Text('$count pending', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                              ),
                              if (isBlocked)
                                const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.block_rounded, color: Colors.redAccent, size: 14)),
                            ]);
                          },
                        ),
                        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                          IconButton(
                            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
                                backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
                                title: Text('Clear Feedbacks?', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                                content: Text('Delete all feedback tickets for "$name"?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(d, false), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
                                  ElevatedButton(onPressed: () => Navigator.pop(d, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
                                ],
                              ));
                              if (confirm == true) {
                                final snap = await FirebaseService.firestore.collection('feedbacks').where('uid', isEqualTo: uid).get();
                                final batch = FirebaseService.firestore.batch();
                                for (final d in snap.docs) { batch.delete(d.reference); }
                                await batch.commit();
                                _loadStudents();
                              }
                            },
                          ),
                          Icon(Icons.chevron_right, color: isDark ? Colors.white38 : Colors.black38),
                        ]),
                        onTap: () => _showStudentFeedbacks(uid, name, s),
                      ),
                    );
                  },
                ),
    );
  }
}
