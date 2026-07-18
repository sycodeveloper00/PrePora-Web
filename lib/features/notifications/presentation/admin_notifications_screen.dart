import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';

class AdminNotificationsScreen extends StatefulWidget {
  const AdminNotificationsScreen({super.key});
  @override
  State<AdminNotificationsScreen> createState() => _AdminNotificationsScreenState();
}

class _AdminNotificationsScreenState extends State<AdminNotificationsScreen> {
  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
        actions: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.firestore.collection('admin_notifications')
                .where('read', isEqualTo: false).snapshots(),
            builder: (context, snap) {
              final unread = snap.hasData ? snap.data!.docs.length : 0;
              if (unread == 0) return const SizedBox();
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: () => _markAllRead(context),
                  child: Text('Mark all read', style: TextStyle(color: Colors.cyanAccent, fontSize: 12)),
                ),
              );
            },
          ),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert, color: isDark ? Colors.white70 : Colors.black87),
            color: isDark ? const Color(0xFF2D2D2D) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'clear', child: Row(children: [const Icon(Icons.clear_all_rounded, color: Colors.redAccent, size: 18), const SizedBox(width: 8), Text('Clear All', style: TextStyle(color: baseColor))])),
            ],
            onSelected: (val) async {
              if (val == 'clear') {
                await FirebaseService.clearAdminNotifications();
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All notifications cleared')));
              }
            },
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getAdminNotifications(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? [];
          if (docs.isEmpty) {
            return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.notifications_off_rounded, size: 80, color: isDark ? Colors.white12 : Colors.black12),
              const SizedBox(height: 16),
              Text('No notifications', style: TextStyle(color: dimColor, fontSize: 18)),
            ]));
          }
          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            itemCount: docs.length,
            itemBuilder: (context, i) {
              final d = docs[i].data() as Map<String, dynamic>;
              final id = docs[i].id;
              final type = d['type'] as String? ?? '';
              final msg = d['message'] as String? ?? '';
              final isRead = d['read'] as bool? ?? false;
              final time = (d['createdAt'] as Timestamp?)?.toDate();
              final timeStr = time != null ? _formatTime(time) : '';
              IconData icon;
              Color iconColor;
              switch (type) {
                case 'registration': icon = Icons.person_add_rounded; iconColor = Colors.green; break;
                case 'feedback': icon = Icons.support_agent_rounded; iconColor = Colors.orange; break;
                case 'login': icon = Icons.login_rounded; iconColor = Colors.blue; break;
                case 'auto_block': icon = Icons.block_rounded; iconColor = Colors.red; break;
                default: icon = Icons.circle_rounded; iconColor = Colors.grey;
              }
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isRead
                      ? (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02))
                      : (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.04)),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isRead
                        ? (isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06))
                        : (isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.1)),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon, color: iconColor, size: 24),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(msg, style: TextStyle(color: baseColor, fontSize: 13, fontWeight: isRead ? FontWeight.normal : FontWeight.w600)),
                      const SizedBox(height: 4),
                      Text(timeStr, style: TextStyle(color: dimColor, fontSize: 11)),
                    ])),
                    if (!isRead)
                      GestureDetector(
                        onTap: () async {
                          await FirebaseService.firestore.collection('admin_notifications').doc(id).update({'read': true});
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.cyanAccent.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                          child: const Text('NEW', style: TextStyle(color: Colors.cyanAccent, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _markAllRead(BuildContext context) async {
    await FirebaseService.markAdminNotificationsRead();
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All marked as read')));
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
