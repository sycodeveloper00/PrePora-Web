import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/firebase_service.dart';
import '../../../core/utils.dart';

class AdminNoticeScreen extends StatefulWidget {
  const AdminNoticeScreen({super.key});
  @override
  State<AdminNoticeScreen> createState() => _AdminNoticeScreenState();
}

class _AdminNoticeScreenState extends State<AdminNoticeScreen> {
  String? _extractBase64(String url) {
    final idx = url.indexOf('base64,');
    if (idx == -1) return null;
    return url.substring(idx + 7);
  }

  Future<void> _openFile(Map<String, dynamic> data) async {
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
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
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
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(children: [
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(Icons.text_fields_rounded, size: 18, color: isDark ? Colors.white : Colors.black87),
                label: Text('Text', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C), padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => _showTextDialog(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                icon: Icon(Icons.file_upload_rounded, size: 18, color: isDark ? Colors.white : Colors.black87),
                label: Text('File', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A148C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => _pickFile(),
              ),
            ),
          ]),
        ),
        Divider(color: isDark ? Colors.white12 : Colors.black12),
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getNotices(),
            builder: (context, snap) {
              final listDark = Theme.of(context).brightness == Brightness.dark;
              if (snap.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
              if (!snap.hasData || snap.data!.docs.isEmpty) return Center(child: Text('No notices', style: TextStyle(color: listDark ? Colors.white38 : Colors.black54)));
              final now = DateTime.now();
              return ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: snap.data!.docs.length,
                itemBuilder: (context, i) {
                  final doc = snap.data!.docs[i];
                  final data = doc.data() as Map<String, dynamic>;
                  final title = data['title'] as String? ?? '';
                  final type = data['fileType'] as String? ?? 'text';
                  final time = (data['createdAt'] as Timestamp?)?.toDate();
                  if (time != null && now.difference(time).inHours >= 24) {
                    FirebaseService.firestore.collection('notices').doc(doc.id).delete();
                    return const SizedBox.shrink();
                  }
                  final timeStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';

                  if (type == 'text') {
                    final preview = title.length > 80 ? '${title.substring(0, 80)}...' : title;
                    return GestureDetector(
                      onLongPress: () => _showNoticeOptions(doc.id, title),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: listDark ? const Color(0xFF1A0533) : const Color(0xFFFFF8E1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: listDark ? Colors.white12 : Colors.amber.withValues(alpha: 0.4)),
                          boxShadow: [
                            BoxShadow(
                              color: listDark ? Colors.black26 : Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6, offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(Icons.push_pin_rounded, size: 18, color: listDark ? Colors.amber.shade300 : Colors.amber.shade700),
                              const SizedBox(width: 8),
                              Text('NOTICE', style: TextStyle(
                                color: listDark ? Colors.amber.shade300 : Colors.amber.shade700,
                                fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1,
                              )),
                            ]),
                            const SizedBox(height: 10),
                            Text(preview, style: TextStyle(
                              color: listDark ? Colors.white : Colors.black87,
                              fontSize: 14, height: 1.5,
                            )),
                            if (title.length > 80)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('Tap to read more', style: TextStyle(color: listDark ? Colors.white38 : Colors.black38, fontSize: 12, fontStyle: FontStyle.italic)),
                              ),
                            const SizedBox(height: 8),
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Text(timeStr, style: TextStyle(color: listDark ? Colors.white24 : Colors.black26, fontSize: 11)),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                onPressed: () => FirebaseService.firestore.collection('notices').doc(doc.id).delete(),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    );
                  }

                  final icon = _iconForType(type, title);
                  return Card(
                    color: listDark ? const Color(0xFF1A0533) : Colors.white,
                    margin: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      onLongPress: () => _showNoticeOptions(doc.id, title),
                      child: ListTile(
                        leading: Icon(icon, color: const Color(0xFF00B8D4)),
                        title: Text(title, style: TextStyle(color: listDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold)),
                        subtitle: Text(timeStr, style: TextStyle(color: listDark ? Colors.white38 : Colors.black54, fontSize: 12)),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                          onPressed: () => FirebaseService.firestore.collection('notices').doc(doc.id).delete(),
                        ),
                        onTap: () => _openFile(data),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ]),
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

  void _showTextDialog() {
    final ctrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      title: Text('Add Notice', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
      content: SingleChildScrollView(child: TextField(controller: ctrl, maxLines: 5, style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(hintText: 'Write notice...', hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
          filled: true, fillColor: isDark ? Colors.white10 : Colors.black12, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (!debounce('notice_add')) return;
          if (ctrl.text.trim().isEmpty) return;
          await FirebaseService.addNotice(ctrl.text.trim(), null, 'text');
          if (d.mounted) Navigator.pop(d);
        }, child: const Text('Add')),
      ],
    ));
  }

  Future<void> _pickFile() async {
    final maxSize = 50 * 1024 * 1024;
    final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true, withData: true);
    if (result != null && result.files.isNotEmpty) {
      int count = 0;
      for (final file in result.files) {
        final bytes = file.bytes ?? (!kIsWeb && file.path != null ? File(file.path!).readAsBytesSync() : null);
        if (bytes == null) continue;
        if (bytes.length > maxSize) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${file.name} too large (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB). Max: 10MB'), backgroundColor: Colors.redAccent),
          );
          continue;
        }
        try {
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          final ref = FirebaseService.storage.ref('notices/$fileName');
          await ref.putData(bytes, metadata: SettableMetadata(contentDisposition: 'inline; filename="${file.name}"'));
          final downloadUrl = await ref.getDownloadURL();
          await FirebaseService.addNotice(file.name, downloadUrl, 'file');
          count++;
        } catch (e) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${file.name} failed: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
      if (mounted && count > 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count notice(s) added!'), backgroundColor: Colors.green));
      }
    }
  }

  String _mimeForExt(String ext) {
    switch (ext) {
      case 'png': return 'image/png';
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'gif': return 'image/gif';
      case 'webp': return 'image/webp';
      case 'pdf': return 'application/pdf';
      case 'doc': case 'docx': return 'application/msword';
      case 'xls': case 'xlsx': case 'csv': return 'application/vnd.ms-excel';
      case 'ppt': case 'pptx': return 'application/vnd.ms-powerpoint';
      case 'mp4': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }

  void _showNoticeOptions(String docId, String currentTitle) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Color(0xFF00B8D4)),
              title: Text('Edit', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(docId, currentTitle);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded, color: Color(0xFF00B8D4)),
              title: Text('Rename', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
              onTap: () {
                Navigator.pop(context);
                _showEditDialog(docId, currentTitle, isRename: true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(context);
                FirebaseService.firestore.collection('notices').doc(docId).delete();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(String docId, String currentTitle, {bool isRename = false}) {
    final ctrl = TextEditingController(text: currentTitle);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      title: Text(isRename ? 'Rename Notice' : 'Edit Notice', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
      content: SingleChildScrollView(child: TextField(controller: ctrl, maxLines: 1, style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(hintText: 'Notice title...', hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
          filled: true, fillColor: isDark ? Colors.white10 : Colors.black12, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
        ElevatedButton(onPressed: () async {
          if (ctrl.text.trim().isEmpty) return;
          await FirebaseService.firestore.collection('notices').doc(docId).update({'title': ctrl.text.trim()});
          if (d.mounted) Navigator.pop(d);
        }, child: const Text('Save')),
      ],
    ));
  }
}
