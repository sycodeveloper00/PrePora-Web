import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/firebase_service.dart';

class StudentNoticeScreen extends StatelessWidget {
  const StudentNoticeScreen({super.key});

  String? _extractBase64(String url) {
    final idx = url.indexOf('base64,');
    if (idx == -1) return null;
    return url.substring(idx + 7);
  }

  Future<void> _openFile(BuildContext context, Map<String, dynamic> data) async {
    final url = data['fileUrl'] as String?;
    final title = data['title'] as String? ?? '';
    final fileType = data['fileType'] as String? ?? 'text';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (fileType == 'text' || url == null) {
      if (!context.mounted) return;
      _showTextBoard(context, title, data);
      return;
    }

    final ext = title.split('.').last.toLowerCase();
    final urlExt = Uri.tryParse(url)?.path.split('.').last.split('?').first.split('#').first.toLowerCase() ?? '';
    final fileExt = (urlExt.isNotEmpty && urlExt.length < 12) ? urlExt : ext;

    if (url.startsWith('data:')) {
      final b64 = _extractBase64(url);
      if (b64 == null) {
        if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid file data')));
        return;
      }
      final bytes = base64Decode(b64);

      if (['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(fileExt)) {
        if (!context.mounted) return;
        showDialog(context: context, builder: (_) => AlertDialog(
          backgroundColor: isDark ? const Color(0xFF0D0D2E) : Colors.white,
          contentPadding: EdgeInsets.zero,
          content: InteractiveViewer(child: Image.memory(bytes, fit: BoxFit.contain)),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)))],
        ));
      } else if (fileExt == 'pdf') {
        if (!context.mounted) return;
        if (kIsWeb) {
          final blobUrl = 'data:application/pdf;base64,$b64';
          context.push('/pdf_reader/view', extra: {'url': blobUrl});
        } else {
          final dir = await getTemporaryDirectory();
          final tempFile = File('${dir.path}/$title');
          await tempFile.writeAsBytes(bytes);
          if (!context.mounted) return;
          context.push('/pdf_reader/view', extra: {'url': tempFile.path});
        }
      } else if (!kIsWeb) {
        final dir = await getTemporaryDirectory();
        final tempFile = File('${dir.path}/$title');
        await tempFile.writeAsBytes(bytes);
        await OpenFilex.open(tempFile.path);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('File type not supported on web')));
        }
      }
      return;
    }

    if (['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(fileExt)) {
      if (!context.mounted) return;
      context.push('/image_viewer', extra: {'url': url, 'title': title});
    } else if (fileExt == 'pdf') {
      if (!context.mounted) return;
      context.push('/pdf_reader/view', extra: {'url': url, 'folderId': null});
    } else if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm'].contains(fileExt)) {
      if (!context.mounted) return;
      context.push('/media_player', extra: {'url': url, 'title': title, 'isAudio': false});
    } else if (['mp3', 'wav', 'aac', 'ogg', 'flac', 'wma', 'm4a', 'opus'].contains(fileExt)) {
      if (!context.mounted) return;
      context.push('/media_player', extra: {'url': url, 'title': title, 'isAudio': true});
    } else if (url.startsWith('http://') || url.startsWith('https://')) {
      if (!context.mounted) return;
      context.push('/webview', extra: {'url': url, 'title': title});
    } else {
      launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  void _showTextBoard(BuildContext context, String content, Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final addedBy = data['addedBy'] as String? ?? 'Admin';
    final time = (data['createdAt'] as Timestamp?)?.toDate();
    final timeStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';

    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.75),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A0533) : const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: isDark ? Colors.white12 : Colors.amber.withValues(alpha: 0.5)),
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.amber.withValues(alpha: 0.3))),
                ),
                child: Row(children: [
                  Icon(Icons.push_pin_rounded, size: 20, color: isDark ? Colors.amber.shade300 : Colors.amber.shade700),
                  const SizedBox(width: 10),
                  Text('NOTICE', style: TextStyle(
                    color: isDark ? Colors.amber.shade300 : Colors.amber.shade700,
                    fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 2,
                  )),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: isDark ? Colors.white54 : Colors.black54),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ]),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: SelectableText(
                    content,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15, height: 1.7),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: isDark ? Colors.white12 : Colors.amber.withValues(alpha: 0.3))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(addedBy, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 12)),
                    Text(timeStr, style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 11)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notice Board', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseService.getNotices(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
          if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Text('No notices', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38)));
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snap.data!.docs.length,
            itemBuilder: (context, i) {
              final d = snap.data!.docs[i].data() as Map<String, dynamic>;
              final title = d['title'] as String? ?? '';
              final type = d['fileType'] as String? ?? 'text';
              final time = (d['createdAt'] as Timestamp?)?.toDate();
              final timeStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';
              final addedBy = d['addedBy'] as String? ?? 'Admin';

              if (type == 'text') {
                final preview = title.length > 80 ? '${title.substring(0, 80)}...' : title;
                return GestureDetector(
                  onTap: () => _openFile(context, d),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A0533) : const Color(0xFFFFF8E1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: isDark ? Colors.white12 : Colors.amber.withValues(alpha: 0.4)),
                      boxShadow: [
                        BoxShadow(
                          color: isDark ? Colors.black26 : Colors.black.withValues(alpha: 0.08),
                          blurRadius: 6, offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.push_pin_rounded, size: 18, color: isDark ? Colors.amber.shade300 : Colors.amber.shade700),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text('Notice', style: TextStyle(
                              color: isDark ? Colors.amber.shade300 : Colors.amber.shade700,
                              fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1,
                            )),
                          ),
                          Text(addedBy, style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11)),
                        ]),
                        const SizedBox(height: 10),
                        Text(preview, style: TextStyle(
                          color: isDark ? Colors.white : Colors.black87,
                          fontSize: 14, height: 1.5,
                        )),
                        if (title.length > 80)
                          Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('Tap to read more', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12, fontStyle: FontStyle.italic)),
                          ),
                        const SizedBox(height: 8),
                        Text(timeStr, style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 11)),
                      ],
                    ),
                  ),
                );
              }

              final icon = _iconForType(type, title);
              return Card(
                color: isDark ? const Color(0xFF1A0533) : Colors.white,
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  leading: Icon(icon, color: const Color(0xFF00B8D4)),
                  title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                  subtitle: Text(timeStr, style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 12)),
                  onTap: () => _openFile(context, d),
                ),
              );
            },
          );
        },
      ),
    );
  }

  IconData _iconForType(String type, String title) {
    if (type == 'file') {
      final ext = title.split('.').last.toLowerCase();
      if (['png', 'jpg', 'jpeg', 'gif', 'webp'].contains(ext)) return Icons.image_rounded;
      if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
      if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm'].contains(ext)) return Icons.videocam_rounded;
      if (['mp3', 'wav', 'aac', 'ogg', 'flac', 'wma', 'm4a', 'opus'].contains(ext)) return Icons.audiotrack_rounded;
      if (['doc', 'docx'].contains(ext)) return Icons.description_rounded;
      if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_rounded;
      if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_rounded;
      if (['zip', 'rar', '7z'].contains(ext)) return Icons.folder_zip_rounded;
      return Icons.attachment_rounded;
    }
    return Icons.article_rounded;
  }
}
