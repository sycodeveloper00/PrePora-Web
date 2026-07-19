import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils.dart';

class StudentFeedbackScreen extends StatefulWidget {
  const StudentFeedbackScreen({super.key});
  @override
  State<StudentFeedbackScreen> createState() => _StudentFeedbackScreenState();
}

class _StudentFeedbackScreenState extends State<StudentFeedbackScreen> {
  final String? _uid = FirebaseService.currentUser?.uid;
  List<Map<String, dynamic>>? _feedbacks;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = _uid;
    if (uid == null) { if (mounted) setState(() => _loading = false); return; }
    try {
      final list = await FirebaseService.getStudentFeedbacksOnce(uid);
      if (mounted) setState(() { _feedbacks = list; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contact Support', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: () => _showAddDialog(context)),
        ],
      ),
      body: _uid == null
          ? Center(child: Text('Not logged in', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54)))
          : _loading
              ? const Center(child: CircularProgressIndicator())
              : _feedbacks == null || _feedbacks!.isEmpty
                  ? Center(child: Text('No feedbacks', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54)))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _feedbacks!.length,
                      itemBuilder: (context, i) {
                        final d = _feedbacks![i];
                        final ticket = d['ticketNo'] as String? ?? '';
                        final msg = d['message'] as String? ?? '';
                        final status = d['status'] as String? ?? 'pending';
                        final time = (d['createdAt'] as Timestamp?)?.toDate();
                        final timeStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';
                        final statusColor = status == 'completed' ? Colors.green : (status == 'rejected' ? Colors.red : Colors.orange);
                        return Card(
                          color: isDark ? const Color(0xFF1A0533) : Colors.white,
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: const Color(0xFF4A148C), borderRadius: BorderRadius.circular(6)),
                                  child: Text('#$ticket', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                                  child: Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              Text(msg, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                              if (d['reply'] != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05), borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? Colors.white12 : Colors.black12)),
                                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    const Row(children: [Icon(Icons.reply_rounded, color: Colors.teal, size: 14), SizedBox(width: 4), Text('Admin Reply', style: TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.bold))]),
                                    const SizedBox(height: 4),
                                    Text(d['reply'] as String? ?? '', style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                                  ]),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(timeStr, style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 11)),
                            ]),
                          ),
                        );
                      },
                    ),
    );
  }

  void _showAddDialog(BuildContext context) {
    final ctrl = TextEditingController();
    bool sending = false;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (d, setLocal) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
          title: Text('Send Message', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: SingleChildScrollView(child: TextField(
            controller: ctrl, maxLines: 4, style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Write your feedback...', hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          )),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
            ElevatedButton(
              onPressed: sending ? null : () async {
                if (sending) return;
                if (ctrl.text.trim().isEmpty) return;
                setLocal(() => sending = true);
                await FirebaseService.submitFeedback(ctrl.text.trim());
                if (d.mounted) Navigator.pop(d);
                _load();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4A148C),
                foregroundColor: Colors.white,
              ),
              child: Text(sending ? 'Sending...' : 'Send'),
            ),
          ],
        ),
      ),
    );
  }
}
