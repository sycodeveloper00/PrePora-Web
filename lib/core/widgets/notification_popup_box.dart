import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/firebase_service.dart';

enum NotificationPanelType { student, admin, assistant }

class NotificationPopupBox extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final NotificationPanelType panelType;
  final VoidCallback? onDismiss;

  const NotificationPopupBox({
    super.key,
    required this.docs,
    required this.panelType,
    this.onDismiss,
  });

  static void show({
    required BuildContext context,
    required List<QueryDocumentSnapshot> docs,
    required NotificationPanelType panelType,
    VoidCallback? onDismiss,
    VoidCallback? onRead,
  }) {
    if (panelType == NotificationPanelType.student) {
      final uid = FirebaseService.currentUser?.uid ?? '';
      FirebaseService.markStudentNotificationsRead(uid);
    } else if (panelType == NotificationPanelType.admin) {
      FirebaseService.markAdminNotificationsRead();
    }
    onRead?.call();

    showDialog(
      context: context,
      barrierColor: Colors.black26,
      builder: (_) => _NotificationPopupDialog(
        docs: docs,
        panelType: panelType,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _NotificationPopupDialog extends StatelessWidget {
  final List<QueryDocumentSnapshot> docs;
  final NotificationPanelType panelType;
  final VoidCallback? onDismiss;

  const _NotificationPopupDialog({
    required this.docs,
    required this.panelType,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.white70 : Colors.black54;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03);

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.of(context).size.height * 0.7,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 16, 0),
              child: Row(
                children: [
                  Icon(Icons.notifications_none_rounded, color: mutedColor, size: 22),
                  const SizedBox(width: 8),
                  Text('Notifications', style: TextStyle(color: baseColor, fontSize: 17, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (docs.isNotEmpty && panelType == NotificationPanelType.admin)
                    IconButton(
                      icon: Icon(Icons.delete_sweep_rounded, color: dimColor, size: 20),
                      tooltip: 'Clear all',
                      onPressed: () async {
                        await FirebaseService.clearAdminNotifications();
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('All notifications cleared')));
                        }
                      },
                    ),
                  IconButton(
                    icon: Icon(Icons.close, color: dimColor, size: 20),
                    onPressed: () {
                      onDismiss?.call();
                      Navigator.pop(context);
                    },
                  ),
                ],
              ),
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
            Flexible(
              child: docs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.notifications_off_rounded, size: 50, color: isDark ? Colors.white12 : Colors.black12),
                          const SizedBox(height: 12),
                          Text('No notifications', style: TextStyle(color: dimColor, fontSize: 14)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      itemCount: docs.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final d = docs[i].data() as Map<String, dynamic>;
                        return _buildNotificationCard(d, isDark, baseColor, dimColor, cardBg, context);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    Map<String, dynamic> d, bool isDark, Color baseColor, Color dimColor, Color cardBg, BuildContext context,
  ) {
    final type = d['type'] as String? ?? '';
    final msg = d['message'] as String? ?? '';
    final userName = d['userName'] as String? ?? '';
    final role = d['role'] as String? ?? '';
    final time = d['createdAt'] as Timestamp?;
    final timeStr = time != null ? _formatTimestamp(time) : '';

    IconData icon;
    Color color;
    if (panelType == NotificationPanelType.admin) {
      switch (type) {
        case 'registration': icon = Icons.person_add_rounded; color = Colors.green; break;
        case 'feedback': icon = Icons.support_agent_rounded; color = Colors.orange; break;
        case 'login': icon = Icons.login_rounded; color = Colors.blue; break;
        case 'logout': icon = Icons.logout_rounded; color = Colors.blueGrey; break;
        case 'auto_block': case 'blocked': icon = Icons.block_rounded; color = Colors.red; break;
        default: icon = Icons.circle_rounded; color = Colors.grey;
      }
    } else {
      icon = role == 'admin' ? Icons.admin_panel_settings : Icons.workspace_premium;
      color = role == 'admin' ? Colors.redAccent : Colors.orange;
    }

    final subtitleParts = <String>[];
    if (userName.isNotEmpty) subtitleParts.add(userName);
    if (timeStr.isNotEmpty) subtitleParts.add(timeStr);

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        Navigator.pop(context);
        _handleTap(type, d, context);
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: baseColor.withValues(alpha: 0.06)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(msg, style: TextStyle(color: baseColor, fontSize: 13)),
                  if (subtitleParts.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(subtitleParts.join(' • '), style: TextStyle(color: dimColor, fontSize: 11)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleTap(String type, Map<String, dynamic> d, BuildContext context) {
    if (panelType == NotificationPanelType.admin) {
      switch (type) {
        case 'feedback': context.push('/admin/feedbacks'); break;
        case 'blocked': case 'auto_block': context.push('/admin', extra: {'studentUid': d['relatedUid']}); break;
        case 'registration': context.push('/admin/control-panel'); break;
        default: break;
      }
    } else {
      final folderId = d['folderId'] as String?;
      if (folderId != null && folderId.isNotEmpty) {
        context.push('/folders/$folderId');
      }
    }
  }

  static String _formatTimestamp(Timestamp ts) {
    final diff = DateTime.now().difference(ts.toDate());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${(diff.inDays / 7).floor()}w ago';
  }
}
