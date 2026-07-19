import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../../../core/widgets/glassmorphic_container.dart';
import '../../../core/services/firebase_service.dart';
import 'folder_browser_screen.dart';

class FolderDetailsScreen extends StatefulWidget {
  final String folderId;
  final bool canEdit;
  final bool canManage;
  final bool isAdmin;
  final Set<String>? assistantContentAccess;
  final String? parentContentId;

  const FolderDetailsScreen({
    super.key,
    required this.folderId,
    this.canEdit = false,
    this.canManage = false,
    this.isAdmin = false,
    this.assistantContentAccess,
    this.parentContentId,
  });

  @override
  State<FolderDetailsScreen> createState() => _FolderDetailsScreenState();
}

class _FolderDetailsScreenState extends State<FolderDetailsScreen> {
  String _searchQuery = '';
  String _folderName = '';
  String _subfolderName = '';
  Set<String> _assistantAccess = {};
  Set<String> _pendingOptimistic = {};
  bool _isBlocked = false;
  bool _isVerified = true;
  bool _isPaidAccess = false;
  final Map<String, int> _localOrderMap = {};
  bool _hasLocalOrder = false;
  Set<String> _selectedIds = {};
  bool _isSelectMode = false;
  String? _groupLink;

  // ─── Cached futures & streams to prevent blinking rebuild loops ───
  late Future<DocumentSnapshot> _folderFuture;
  late Stream<QuerySnapshot> _contentsStream;

  @override
  void initState() {
    super.initState();
    if (widget.assistantContentAccess != null) {
      _assistantAccess = widget.assistantContentAccess!;
    }
    _folderFuture = FirebaseService.firestore.collection('folders').doc(widget.folderId).get();
    _contentsStream = FirebaseService.firestore
        .collection('folders')
        .doc(widget.folderId)
        .collection('contents')
        .snapshots();
    _refreshAssistantAccess();
    _checkStatus();
    _loadSubfolderName();
    _loadGroupLink();
  }

  void _loadSubfolderName() async {
    if (widget.parentContentId == null) return;
    try {
      final snap = await FirebaseService.firestore
          .collection('folders').doc(widget.folderId)
          .collection('contents').doc(widget.parentContentId!).get();
      if (snap.exists && mounted) {
        setState(() {
          _subfolderName = (snap.data() as Map<String, dynamic>)['name'] as String? ?? '';
        });
      }
    } catch (_) {}
  }

  void _checkStatus() async {
    final uid = FirebaseService.currentUser?.uid;
    if (uid != null) {
      final blocked = await FirebaseService.isStudentBlocked(uid);
      final settings = await FirebaseService.getSettings();
      final paidAccess = settings['paidAccess'] as bool? ?? false;
      final verified = paidAccess ? await FirebaseService.isStudentVerified(uid) : true;
      if (mounted) setState(() {
        _isBlocked = blocked;
        _isVerified = verified;
        _isPaidAccess = paidAccess;
      });
    }
  }

  void _refreshAssistantAccess() async {
    if (!widget.isAdmin) {
      final uid = FirebaseService.currentUser?.uid;
      if (uid != null) {
        final access = await FirebaseService.getContentAccess(uid);
        final ids = access[widget.folderId] ?? [];
        if (mounted) {
          setState(() {
            _assistantAccess = ids.toSet();
            _assistantAccess.addAll(_pendingOptimistic);
          });
        }
      }
    }
  }

  List<DocumentSnapshot> _filterDocs(List<DocumentSnapshot> docs, String query) {
    if (query.isEmpty) return docs;
    final q = query.toLowerCase();
    return docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>;
      final name = (data['name'] as String? ?? '').toLowerCase();
      return name.contains(q);
    }).toList();
  }

  // ─── Lock Sheet (3 toggles) ────────────────────────────────────────────────

  void _showContentLockSheet(String contentId, String contentName, bool locked, bool updating, bool invisible) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: StatefulBuilder(builder: (ctx, setLocal) {
          return Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.orange, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(contentName, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 16))),
            ]),
            const SizedBox(height: 20),
            _buildToggleRow('Lock Content', 'Students cannot see this', Icons.lock_rounded, Colors.redAccent, locked, (val) async {
              await FirebaseService.updateContentField(widget.folderId, contentId, 'locked', val);
              if (val) {
                await FirebaseService.updateContentField(widget.folderId, contentId, 'updating', false);
                await FirebaseService.updateContentField(widget.folderId, contentId, 'invisible', false);
                setLocal(() { locked = val; updating = false; invisible = false; });
                await FirebaseService.addNotification('Locked: $contentName', folderId: widget.folderId, contentData: {'locked': true});
              } else {
                setLocal(() => locked = val);
                await FirebaseService.addNotification('Unlocked: $contentName', folderId: widget.folderId);
              }
            }),
            const SizedBox(height: 12),
            _buildToggleRow('Show "Updating..."', 'Visible but shows Updating message', Icons.update_rounded, Colors.orange, updating, (val) async {
              await FirebaseService.updateContentField(widget.folderId, contentId, 'updating', val);
              if (val) {
                await FirebaseService.updateContentField(widget.folderId, contentId, 'locked', false);
                await FirebaseService.updateContentField(widget.folderId, contentId, 'invisible', false);
                setLocal(() { updating = val; locked = false; invisible = false; });
                await FirebaseService.addNotification('Updating: $contentName', folderId: widget.folderId, contentData: {'updating': true});
              } else {
                setLocal(() => updating = val);
                await FirebaseService.addNotification('Updating removed: $contentName', folderId: widget.folderId);
              }
            }),
            const SizedBox(height: 12),
            _buildToggleRow('Invisible', 'Hide from students & Assistant', Icons.visibility_off_rounded, Colors.purple, invisible, (val) async {
              await FirebaseService.updateContentField(widget.folderId, contentId, 'invisible', val);
              if (val) {
                await FirebaseService.updateContentField(widget.folderId, contentId, 'locked', false);
                await FirebaseService.updateContentField(widget.folderId, contentId, 'updating', false);
                setLocal(() { invisible = val; locked = false; updating = false; });
                await FirebaseService.addNotification('Hidden: $contentName', folderId: widget.folderId, contentData: {'invisible': true});
              } else {
                setLocal(() => invisible = val);
                await FirebaseService.addNotification('Visible: $contentName', folderId: widget.folderId);
              }
            }),
            const SizedBox(height: 16),
          ]);
        }),
      ),
    );
  }

  Widget _buildToggleRow(String title, String subtitle, IconData icon, Color color, bool value, ValueChanged<bool> onChanged) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(width: 12),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14)),
        Text(subtitle, style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 11)),
      ])),
      Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: color,
      ),
    ]);
  }

  // ─── Assistant Access Sheet for Content ────────────────────────────────────────

  void _showContentAssistantSheet(String contentId, String contentName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          Set<String> grantedUids = {};
          List<Map<String, dynamic>> assistants = [];
          bool loading = true;
          Future<void> load() async {
            final results = await Future.wait([
              FirebaseService.getAllAssistant().first,
              FirebaseService.getUidsWithContentAccess(widget.folderId, contentId),
            ]);
            final assistantSnap = results[0] as QuerySnapshot;
            final uids = results[1] as Set<String>;
            assistants = assistantSnap.docs.map((d) => {
              'uid': d.id,
              'name': ((d.data() as Map<String, dynamic>)['name'] as String?) ?? 'Unknown',
              'email': ((d.data() as Map<String, dynamic>)['email'] as String?) ?? '',
            }).toList();
            grantedUids = uids;
            loading = false;
            if (ctx.mounted) setLocal(() {});
          }
          load();
          return DraggableScrollableSheet(
            initialChildSize: 0.5, minChildSize: 0.3, maxChildSize: 0.7, expand: false,
            builder: (scrollCtx, scrollCtrl) => Column(children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const Icon(Icons.person_add_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Grant Access — $contentName', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16))),
                  IconButton(
                    icon: const Icon(Icons.add_circle_rounded, color: Colors.orange, size: 28),
                    onPressed: () { Navigator.pop(ctx); _showCreateAssistantDialog(); },
                  ),
                ]),
              ),
              Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
              Expanded(
                child: loading
                    ? const Center(child: CircularProgressIndicator())
                    : assistants.isEmpty
                        ? Center(child: Text('No Assistant accounts.', style: TextStyle(color: dimColor)))
                        : ListView.builder(
                            controller: scrollCtrl,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: assistants.length,
                            itemBuilder: (context, index) {
                              final data = assistants[index];
                              final uid = data['uid'] as String;
                              final name = data['name'] as String;
                              final email = data['email'] as String;
                              final hasAccess = grantedUids.contains(uid);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: hasAccess ? Colors.green.withValues(alpha: 0.08) : (isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03)),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: hasAccess ? Colors.green.withValues(alpha: 0.3) : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08))),
                                ),
                                child: Row(children: [
                                  CircleAvatar(
                                    backgroundColor: hasAccess ? Colors.green.withValues(alpha: 0.2) : (isDark ? Colors.white10 : Colors.black12),
                                    child: Icon(hasAccess ? Icons.check : Icons.person, color: hasAccess ? Colors.green : (isDark ? Colors.white54 : Colors.black45), size: 18),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(name, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 14)),
                                    Text(email, style: TextStyle(color: dimColor, fontSize: 11)),
                                  ])),
                                  if (hasAccess)
                                    ElevatedButton(
                                      onPressed: () async {
                                        await FirebaseService.revokeContentAccess(uid, widget.folderId, contentId);
                                        if (ctx.mounted) setLocal(() { grantedUids.remove(uid); });
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                                      child: const Text('Denied', style: TextStyle(color: Colors.white, fontSize: 12)),
                                    )
                                  else
                                    ElevatedButton(
                                      onPressed: () async {
                                        await FirebaseService.grantContentAccess(uid, widget.folderId, contentId, name);
                                        if (ctx.mounted) setLocal(() { grantedUids.add(uid); });
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                                      child: const Text('Grant', style: TextStyle(color: Colors.white, fontSize: 12)),
                                    ),
                                ]),
                              );
                            },
                          ),
              ),
            ]),
          );
        },
      ),
    );
  }

  void _showCreateAssistantDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final nameCtrl = TextEditingController();
    Map<String, String>? creds;
    bool loading = false;
    String? error;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(children: [const Icon(Icons.person_add_rounded, color: Colors.orange), const SizedBox(width: 8), Text('New Assistant Account', style: TextStyle(color: baseColor, fontSize: 15))]),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (creds == null)
              TextField(
                controller: nameCtrl, style: TextStyle(color: baseColor),
                decoration: InputDecoration(
                  hintText: 'Assistant name...', hintStyle: TextStyle(color: dimColor),
                  filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
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
          ])),
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

  // ─── Add Content Methods ─────────────────────────────────────────────────────

  void _addSubFolder(BuildContext ctx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('New Sub-Folder', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: SingleChildScrollView(child: TextField(
          controller: ctrl, autofocus: true,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
          decoration: InputDecoration(
            hintText: 'Sub-folder name...', hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
            filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              final data = {'type': 'subfolder', 'name': ctrl.text.trim(), 'level': (widget.parentContentId != null) ? 1 : 0};
              if (widget.parentContentId != null) data['parentContentId'] = widget.parentContentId!;
              final newId = await FirebaseService.addFolderContent(widget.folderId, data);
              if (newId != null && !widget.isAdmin) { _assistantAccess.add(newId); _pendingOptimistic.add(newId); }
              await FirebaseService.addNotification('Created sub-folder: ${ctrl.text.trim()}', folderId: widget.folderId);
              _refreshAssistantAccess();
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Create', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addYouTubeLecture(BuildContext ctx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final titleCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.play_circle_fill_rounded, color: Colors.red), const SizedBox(width: 8), Text('Add Lecture', style: TextStyle(color: baseColor))]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titleCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'Lecture title...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.title, color: Colors.white54), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'Paste YouTube link...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.link, color: Colors.red), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (titleCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
               final data = {'type': 'lecture', 'name': titleCtrl.text.trim(), 'youtubeUrl': urlCtrl.text.trim()};
              if (widget.parentContentId != null) data['parentContentId'] = widget.parentContentId!;
              final newId = await FirebaseService.addFolderContent(widget.folderId, data);
              if (newId != null && !widget.isAdmin) { _assistantAccess.add(newId); _pendingOptimistic.add(newId); }
              await FirebaseService.addNotification('Added lecture: ${titleCtrl.text.trim()}', folderId: widget.folderId);
              _refreshAssistantAccess();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addUploadFile(BuildContext ctx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Upload File', style: TextStyle(color: dimColor, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 20),
          ListTile(
            leading: const Icon(Icons.phone_android, color: Colors.blue),
            title: Text('Internal Storage', style: TextStyle(color: baseColor)),
            subtitle: Text('Pick file from device', style: TextStyle(color: dimColor, fontSize: 12)),
            onTap: () { Navigator.pop(context); _pickFileFromStorage(ctx); },
          ),
          Divider(color: isDark ? Colors.white12 : Colors.black12),
          ListTile(
            leading: const Icon(Icons.cloud_upload_rounded, color: Colors.amber),
            title: Text('Google Drive', style: TextStyle(color: baseColor)),
            subtitle: Text('Import from Google Drive', style: TextStyle(color: dimColor, fontSize: 12)),
            onTap: () { Navigator.pop(context); _pickFileFromDrive(ctx); },
          ),
          Divider(color: isDark ? Colors.white12 : Colors.black12),
          ListTile(
            leading: const Icon(Icons.link, color: Colors.teal),
            title: Text('Paste URL', style: TextStyle(color: baseColor)),
            subtitle: Text('Enter file link manually', style: TextStyle(color: dimColor, fontSize: 12)),
            onTap: () { Navigator.pop(context); _addUploadFileUrl(ctx); },
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
  }

  void _pickFileFromStorage(BuildContext ctx) async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true, withData: true);
      if (result != null && result.files.isNotEmpty) {
        int count = 0;
        for (final file in result.files) {
          final bytes = file.bytes ?? (!kIsWeb && file.path != null ? File(file.path!).readAsBytesSync() : null);
          if (bytes == null) continue;
          if (bytes.length > 50 * 1024 * 1024) {
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: Text('${file.name} too large (${(bytes.length / 1024 / 1024).toStringAsFixed(1)}MB). Max: 50MB'),
                backgroundColor: Colors.redAccent,
              ));
            }
            continue;
          }
          if (ctx.mounted) {
            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Uploading ${file.name}...'), backgroundColor: Colors.orange, duration: const Duration(seconds: 1)));
          }
          final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.name}';
          final ref = FirebaseService.storage.ref('folder_files/$fileName');
          await ref.putData(bytes, metadata: SettableMetadata(contentDisposition: 'inline; filename="${file.name}"'));
          final downloadUrl = await ref.getDownloadURL();
          final data = <String, dynamic>{'type': 'file', 'name': file.name, 'url': downloadUrl, 'source': 'supabase_storage'};
          if (widget.parentContentId != null) data['parentContentId'] = widget.parentContentId!;
          final newId = await FirebaseService.addFolderContent(widget.folderId, data);
          if (newId != null && !widget.isAdmin) { _assistantAccess.add(newId); _pendingOptimistic.add(newId); }
          await FirebaseService.addNotification('Uploaded file: ${file.name}', folderId: widget.folderId);
          count++;
        }
        _refreshAssistantAccess();
        if (ctx.mounted && count > 0) {
          ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('$count file(s) uploaded!'), backgroundColor: Colors.green));
        }
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent, duration: const Duration(seconds: 5)));
      }
    }
  }

  void _pickFileFromDrive(BuildContext ctx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.cloud_upload_rounded, color: Colors.amber), const SizedBox(width: 8), Text('Google Drive', style: TextStyle(color: baseColor))]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'File name...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.title, color: Colors.white54), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'Paste Drive link...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.cloud, color: Colors.amber), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              final data = {'type': 'file', 'name': nameCtrl.text.trim(), 'url': urlCtrl.text.trim(), 'source': 'google_drive'};
              if (widget.parentContentId != null) data['parentContentId'] = widget.parentContentId!;
              final newId = await FirebaseService.addFolderContent(widget.folderId, data);
              if (newId != null && !widget.isAdmin) { _assistantAccess.add(newId); _pendingOptimistic.add(newId); }
              await FirebaseService.addNotification('Uploaded from Drive: ${nameCtrl.text.trim()}', folderId: widget.folderId);
              _refreshAssistantAccess();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade800),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addUploadFileUrl(BuildContext ctx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final nameCtrl = TextEditingController();
    final linkCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.link, color: Colors.teal), const SizedBox(width: 8), Text('Paste URL', style: TextStyle(color: baseColor))]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'File name...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.title, color: Colors.white54), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          const SizedBox(height: 12),
          TextField(controller: linkCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'File URL or link...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.link, color: Colors.teal), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              final data = {'type': 'file', 'name': nameCtrl.text.trim(), 'url': linkCtrl.text.trim(), 'source': 'url'};
              if (widget.parentContentId != null) data['parentContentId'] = widget.parentContentId!;
              final newId = await FirebaseService.addFolderContent(widget.folderId, data);
              if (newId != null && !widget.isAdmin) { _assistantAccess.add(newId); _pendingOptimistic.add(newId); }
              await FirebaseService.addNotification('Uploaded file: ${nameCtrl.text.trim()}', folderId: widget.folderId);
              _refreshAssistantAccess();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addMockTestUrl(BuildContext ctx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final nameCtrl = TextEditingController(text: 'Mock Test');
    final urlCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.link, color: Colors.orange), const SizedBox(width: 8), Text('Mock Test URL', style: TextStyle(color: baseColor))]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'Test name...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.title, color: Colors.white54), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          const SizedBox(height: 12),
          TextField(controller: urlCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'Paste URL...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.link, color: Colors.orange), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || urlCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              final data = {'type': 'mocktest_url', 'name': nameCtrl.text.trim(), 'url': urlCtrl.text.trim()};
              if (widget.parentContentId != null) data['parentContentId'] = widget.parentContentId!;
              final newId = await FirebaseService.addFolderContent(widget.folderId, data);
              if (newId != null && !widget.isAdmin) { _assistantAccess.add(newId); _pendingOptimistic.add(newId); }
              await FirebaseService.addNotification('Added Mock Test URL: ${nameCtrl.text.trim()}', folderId: widget.folderId);
              _refreshAssistantAccess();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _addMockTestCode(BuildContext ctx) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final nameCtrl = TextEditingController(text: 'Mock Test');
    final codeCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [const Icon(Icons.code, color: Colors.orange), const SizedBox(width: 8), Text('Mock Test Code', style: TextStyle(color: baseColor))]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'Test name...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.title, color: Colors.white54), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          const SizedBox(height: 12),
          TextField(controller: codeCtrl, maxLines: 5, style: TextStyle(color: baseColor, fontFamily: 'monospace', fontSize: 13),
            decoration: InputDecoration(hintText: 'Paste your code here...', hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty || codeCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              final data = {'type': 'mocktest_code', 'name': nameCtrl.text.trim(), 'code': codeCtrl.text.trim()};
              if (widget.parentContentId != null) data['parentContentId'] = widget.parentContentId!;
              final newId = await FirebaseService.addFolderContent(widget.folderId, data);
              if (newId != null && !widget.isAdmin) { _assistantAccess.add(newId); _pendingOptimistic.add(newId); }
              await FirebaseService.addNotification('Added Mock Test Code: ${nameCtrl.text.trim()}', folderId: widget.folderId);
              _refreshAssistantAccess();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadGroupLink() async {
    final link = await FirebaseService.getGroupLinkForLevel(widget.folderId, parentContentId: widget.parentContentId ?? 'root');
    if (mounted) setState(() => _groupLink = link);
  }

  void _showGroupLinkDialog() {
    showDialog(
      context: context,
      builder: (d) => GroupLinkDialog(
        folderId: widget.folderId,
        parentContentId: widget.parentContentId ?? 'root',
      ),
    ).then((_) => _loadGroupLink());
  }

  void _showGroupLinkDialogForContent(String contentId) {
    showDialog(
      context: context,
      builder: (d) => GroupLinkDialog(
        folderId: widget.folderId,
        parentContentId: contentId,
      ),
    ).then((_) => _loadGroupLink());
  }
  // ─── Content Actions ─────────────────────────────────────────────────────────

  void _confirmDeleteContent(String contentId, String contentName, [Map<String, dynamic>? data]) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        title: Text('Delete Content?', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text('Are you sure you want to delete "$contentName"?', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(d);
              await FirebaseService.deleteFolderContent(widget.folderId, contentId);
              await FirebaseService.addNotification('Deleted: $contentName', folderId: widget.folderId, contentData: data);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showRenameContentDialog(String contentId, String currentName) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final ctrl = TextEditingController(text: currentName);
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Rename', style: TextStyle(color: baseColor)),
        content: SingleChildScrollView(child: TextField(controller: ctrl, autofocus: true, style: TextStyle(color: baseColor),
          decoration: InputDecoration(hintText: 'New name...', hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (ctrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              await FirebaseService.renameFolderContent(widget.folderId, contentId, ctrl.text.trim());
              await FirebaseService.addNotification('Renamed "$currentName" to "${ctrl.text.trim()}"', folderId: widget.folderId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Rename', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showEditContentDialog(String contentId, String currentName, String type, Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final nameCtrl = TextEditingController(text: currentName);
    final urlCtrl = TextEditingController(text: data['youtubeUrl'] as String? ?? data['url'] as String? ?? data['code'] as String? ?? '');
    final isCode = type == 'mocktest_code';
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Edit $type', style: TextStyle(color: baseColor)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, style: TextStyle(color: baseColor),
            decoration: InputDecoration(hintText: 'Name...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.title, color: Colors.white54), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
          const SizedBox(height: 12),
          if (isCode)
            TextField(controller: urlCtrl, maxLines: 5, style: TextStyle(color: baseColor, fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(hintText: 'Code/HTML...', hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)))
          else
            TextField(controller: urlCtrl, style: TextStyle(color: baseColor),
              decoration: InputDecoration(hintText: 'URL...', hintStyle: TextStyle(color: dimColor), prefixIcon: const Icon(Icons.link, color: Colors.teal), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              Navigator.pop(d);
              await FirebaseService.renameFolderContent(widget.folderId, contentId, nameCtrl.text.trim());
              if (type == 'lecture') {
                await FirebaseService.updateContentField(widget.folderId, contentId, 'youtubeUrl', urlCtrl.text.trim());
              } else if (type == 'mocktest_url' || type == 'file') {
                await FirebaseService.updateContentField(widget.folderId, contentId, 'url', urlCtrl.text.trim());
              } else if (type == 'mocktest_code') {
                await FirebaseService.updateContentField(widget.folderId, contentId, 'code', urlCtrl.text.trim());
              }
              await FirebaseService.addNotification('Updated: ${nameCtrl.text.trim()}', folderId: widget.folderId, contentData: data);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            child: const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showContentOptions(String contentId, String contentName, String type, bool locked, Map<String, dynamic> data) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(contentName, style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded, color: Colors.blue),
              title: Text('Rename', style: TextStyle(color: baseColor)),
              onTap: () { Navigator.pop(context); _showRenameContentDialog(contentId, contentName); },
            ),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.green),
              title: Text('Edit', style: TextStyle(color: baseColor)),
              onTap: () { Navigator.pop(context); _showEditContentDialog(contentId, contentName, type, data); },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
              title: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
              onTap: () { Navigator.pop(context); _confirmDeleteContent(contentId, contentName, data); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  bool _isDisabled(Map<String, dynamic> data, String contentId) {
    final locked = data['locked'] as bool? ?? false;
    final updating = data['updating'] as bool? ?? false;
    final invisible = data['invisible'] as bool? ?? false;
    if (!widget.isAdmin && locked) return true;
    if (!widget.isAdmin && updating) return true;
    if (!widget.isAdmin && invisible) return true;
    if (widget.assistantContentAccess != null && _assistantAccess.isNotEmpty && !_assistantAccess.contains(contentId)) return true;
    return false;
  }

  // ─── Selection (long-press multi-select) ──────────────────────────────────────

  void _onContentSelect(String id) {
    setState(() {
      if (!_isSelectMode) _isSelectMode = true;
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        if (_selectedIds.isEmpty) _isSelectMode = false;
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _isSelectMode = false;
    });
  }

  Future<void> _deleteSelected() async {
    final count = _selectedIds.length;
    for (final id in _selectedIds) {
      await FirebaseService.deleteFolderContent(widget.folderId, id);
    }
    await FirebaseService.addNotification('Deleted $count item(s)', folderId: widget.folderId);
    _clearSelection();
  }

  void _confirmDeleteSelected() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        title: Text('Delete ${_selectedIds.length} item(s)?', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        content: Text('This cannot be undone.', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54))),
          ElevatedButton(
            onPressed: () { Navigator.pop(d); _deleteSelected(); },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showCopyMoveDialog(bool isMove) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => FolderBrowserScreen(
        sourceFolderId: widget.folderId,
        isMove: isMove,
        selectedIds: _selectedIds.toList(),
      ),
    )).then((result) {
      if (result == true) _clearSelection();
    });
  }

  // ─── Content Tap Handlers ────────────────────────────────────────────────────

  String _extractYoutubeId(String url) {
    final patterns = [
      RegExp(r'youtube\.com/watch\?v=([^&]+)'),
      RegExp(r'youtu\.be/([^?]+)'),
      RegExp(r'youtube\.com/embed/([^?]+)'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(url);
      if (m != null) return m.group(1) ?? '';
    }
    return '';
  }

  void _openContent(Map<String, dynamic> data, {String? folderName}) {
    folderName ??= _folderName;
    final type = data['type'] as String? ?? 'file';
    final name = data['name'] as String? ?? '';
    final locked = data['locked'] as bool? ?? false;
    final updating = data['updating'] as bool? ?? false;

    if (!widget.isAdmin) {
      if (locked) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This content is locked'), backgroundColor: Colors.redAccent));
        return;
      }
      if (updating) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This content is being updated'), backgroundColor: Colors.orange));
        return;
      }
    }

    switch (type) {
      case 'lecture':
        final url = data['youtubeUrl'] as String? ?? '';
        final videoId = _extractYoutubeId(url);
        if (videoId.isNotEmpty) {
          context.push('/lectures/$videoId', extra: {'name': name, 'folderId': widget.folderId, 'folderName': folderName, 'parentContentId': widget.parentContentId});
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid YouTube URL')));
        }
        break;
      case 'mocktest_url':
        final url = data['url'] as String? ?? '';
        if (url.isNotEmpty) {
          context.push('/webview', extra: {'url': url, 'title': name, 'folderId': widget.folderId, 'parentContentId': widget.parentContentId, 'isMockTest': true});
        }
        break;
      case 'mocktest_code':
        final code = data['code'] as String? ?? '';
        if (code.isNotEmpty) {
          context.push('/webview', extra: {'html': code, 'title': name, 'folderId': widget.folderId, 'parentContentId': widget.parentContentId, 'isMockTest': true});
        }
        break;
      case 'file':
        _openFile(data);
        break;
      default:
        break;
    }
  }

  void _openFile(Map<String, dynamic> data) async {
    final url = data['url'] as String? ?? '';
    final source = data['source'] as String? ?? 'url';
    final name = data['name'] as String? ?? 'File';

    if (url.isEmpty) return;

    String ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    if (ext.isEmpty) {
      final urlName = url.split('/').last.split('?').first.split('#').first;
      ext = urlName.contains('.') ? urlName.split('.').last.toLowerCase() : '';
    }
    final displayTitle = name.replaceFirst(RegExp(r'^\d+_'), '');

    if (kIsWeb && source == 'internal_storage' && !url.startsWith('http://') && !url.startsWith('https://') && !url.startsWith('blob:')) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This file is stored on device, cannot open on web'),
        backgroundColor: Colors.redAccent,
        duration: Duration(seconds: 4),
      ));
      return;
    }

    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      context.push('/image_viewer', extra: {'url': url, 'title': displayTitle});
    } else if (ext == 'pdf') {
      context.push('/pdf_reader/view', extra: {'url': url, 'folderId': widget.folderId, 'parentContentId': widget.parentContentId});
    } else if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm'].contains(ext)) {
      context.push('/media_player', extra: {'url': url, 'title': displayTitle, 'isAudio': false});
    } else if (['mp3', 'wav', 'aac', 'ogg', 'flac', 'wma', 'm4a', 'opus'].contains(ext)) {
      context.push('/media_player', extra: {'url': url, 'title': displayTitle, 'isAudio': true});
    } else if (source == 'internal_storage' && !url.startsWith('http://') && !url.startsWith('https://')) {
      if (kIsWeb) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('This file is stored on device, cannot open on web'),
          backgroundColor: Colors.redAccent,
        ));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Opening $name...')));
        final result = await OpenFilex.open(url);
        if (result.type != ResultType.done && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Cannot open file: ${result.message}'), backgroundColor: Colors.redAccent));
        }
      }
    } else if (url.isNotEmpty) {
      context.push('/webview', extra: {'url': url, 'title': displayTitle, 'folderId': widget.folderId, 'parentContentId': widget.parentContentId});
    }
  }

  // ─── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentSnapshot>(
      future: _folderFuture,
      builder: (context, folderSnap) {
        _folderName = folderSnap.hasData && folderSnap.data!.exists
            ? (folderSnap.data!.data() as Map<String, dynamic>)['name'] as String? ?? 'Folder'
            : 'Folder';
        final folderName = _folderName;

        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.parentContentId != null && _subfolderName.isNotEmpty ? _subfolderName : folderName,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              if (widget.parentContentId != null && _subfolderName.isNotEmpty)
                Text('in $folderName', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.black45, fontSize: 11)),
            ]),
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
child: TextField(
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Search content...', hintStyle: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white38 : Colors.black38),
                      prefixIcon: Icon(Icons.search, color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(icon: Icon(Icons.clear, color: Theme.of(context).brightness == Brightness.dark ? Colors.white54 : Colors.black54), onPressed: () => setState(() => _searchQuery = ''))
                          : null,
                      filled: true, fillColor: Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.black12,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
              ),
              _buildSelectionToolbar(),
              Expanded(
                child: StreamBuilder<QuerySnapshot>(
                  stream: _contentsStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.folder_open_rounded, size: 80, color: Colors.white12),
                        const SizedBox(height: 16),
                        const Text('No content yet', style: TextStyle(color: Colors.white38, fontSize: 16)),
                        if (widget.canEdit) ...[const SizedBox(height: 8), const Text('Tap + to add content', style: TextStyle(color: Colors.white24, fontSize: 13))],
                      ]));
                    }

                    final docs = snapshot.data!.docs;
                    final parentFiltered = docs.where((doc) {
                      final data = doc.data() as Map<String, dynamic>;
                      final docParentId = data['parentContentId'] as String?;
                      if (widget.parentContentId != null) {
                        if (docParentId != widget.parentContentId) return false;
                      } else {
                        if (docParentId != null) return false;
                      }
                      return true;
                    }).toList();

                    final filteredDocs = _searchQuery.isNotEmpty ? _filterDocs(parentFiltered, _searchQuery) : parentFiltered;
                    final visibleDocs = widget.isAdmin
                        ? filteredDocs
                        : filteredDocs.where((doc) {
                            final d = doc.data() as Map<String, dynamic>;
                            return d['invisible'] != true && d['locked'] != true && d['updating'] != true;
                          }).toList();

                    // If local order has missing or extra IDs vs stream, reset local order
                    if (_hasLocalOrder && _searchQuery.isEmpty) {
                      final streamIds = visibleDocs.map((d) => d.id).toSet();
                      final localIds = _localOrderMap.keys.toSet();
                      if (!localIds.containsAll(streamIds) || localIds.length != streamIds.length) {
                        _hasLocalOrder = false;
                      }
                    }
                    // Initialize local order map from stream if not yet set
                    if (!_hasLocalOrder && visibleDocs.isNotEmpty) {
                      _localOrderMap.clear();
                      // Sort by stored order field first (for persistence across app restarts)
                      visibleDocs.sort((a, b) {
                        final aOrder = (a.data() as Map<String, dynamic>)['order'] as num? ?? 999999;
                        final bOrder = (b.data() as Map<String, dynamic>)['order'] as num? ?? 999999;
                        return aOrder.compareTo(bOrder);
                      });
                      for (int i = 0; i < visibleDocs.length; i++) {
                        _localOrderMap[visibleDocs[i].id] = i;
                      }
                    }

                    // Sort visibleDocs by local order map when local order is active
                    if (_hasLocalOrder && _searchQuery.isEmpty) {
                      visibleDocs.sort((a, b) => (_localOrderMap[a.id] ?? 9999).compareTo(_localOrderMap[b.id] ?? 9999));
                    }

                    if (visibleDocs.isEmpty && _groupLink == null) {
                      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.folder_open_rounded, size: 80, color: Colors.white12),
                        const SizedBox(height: 16),
                        Text(_searchQuery.isNotEmpty ? 'No matching content' : 'No content here', style: const TextStyle(color: Colors.white38, fontSize: 16)),
                        if (widget.canEdit) ...[const SizedBox(height: 8), const Text('Tap + to add content', style: TextStyle(color: Colors.white24, fontSize: 13))],
                      ]));
                    }

                    final listWidget = widget.isAdmin
                        ? ReorderableListView.builder(
                            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
                            itemCount: visibleDocs.length,
                            buildDefaultDragHandles: false,
                            onReorderItem: (int oldIndex, int newIndex) async {
                              final ids = _localOrderMap.keys.toList();
                              if (oldIndex >= ids.length || newIndex >= ids.length) return;
                              final id = ids.removeAt(oldIndex);
                              ids.insert(newIndex, id);
                              _localOrderMap.clear();
                              for (int i = 0; i < ids.length; i++) {
                                _localOrderMap[ids[i]] = i;
                              }
                              _hasLocalOrder = true;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                if (mounted) setState(() {});
                              });
                              final allDocs = snapshot.data!.docs.toList();
                              final reordered = allDocs.where((doc) {
                                final d = doc.data() as Map<String, dynamic>;
                                final pid = d['parentContentId'] as String?;
                                if (widget.parentContentId != null) {
                                  return pid == widget.parentContentId;
                                }
                                return pid == null;
                              }).toList();
                              reordered.sort((a, b) => (_localOrderMap[a.id] ?? 9999).compareTo(_localOrderMap[b.id] ?? 9999));
                              final batch = FirebaseService.firestore.batch();
                              for (int i = 0; i < reordered.length; i++) {
                                batch.update(reordered[i].reference, {'order': i});
                              }
                              await batch.commit();
                            },
                            proxyDecorator: (child, index, animation) {
                              return AnimatedBuilder(
                                animation: animation,
                                builder: (context, child) => Material(
                                  elevation: 4,
                                  color: Colors.transparent,
                                  child: child,
                                ),
                                child: child,
                              );
                            },
                            itemBuilder: (context, index) {
                              final data = visibleDocs[index].data() as Map<String, dynamic>;
                              final type = data['type'] as String? ?? 'file';
                              final docId = visibleDocs[index].id;
                              return Container(
                                key: ValueKey(docId),
                                child: _buildContentCard(context, docId, data, type, index),
                              );
                            },
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(left: 16, right: 16, top: 16, bottom: 100),
                            itemCount: visibleDocs.length,
                            itemBuilder: (context, index) {
                              final data = visibleDocs[index].data() as Map<String, dynamic>;
                              final type = data['type'] as String? ?? 'file';
                              final docId = visibleDocs[index].id;
                              return _buildContentCard(context, docId, data, type, index);
                            },
                          );

                    if (_groupLink == null || _groupLink!.isEmpty || !widget.isAdmin) return listWidget;
                    return Column(children: [_buildGroupBanner(), Expanded(child: listWidget)]);
                  },
                ),
              ),
            ],
          ),
          floatingActionButton: widget.canEdit
              ? FloatingActionButton(
                  heroTag: 'add_content_${widget.parentContentId ?? "root"}',
                  backgroundColor: const Color(0xFF4A148C),
                  onPressed: () => _showUploadOptions(context),
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : (_isBlocked || (_isPaidAccess && !_isVerified))
                  ? const SizedBox.shrink()
                  : FutureBuilder<String?>(
                      future: FirebaseService.getGroupLinkForLevel(widget.folderId, parentContentId: widget.parentContentId ?? 'root'),
                      builder: (context, snap) {
                        final link = snap.data;
                        final hasGroup = link != null && link.isNotEmpty;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildAiFab(context),
                            if (hasGroup) ...[
                              const SizedBox(height: 16),
                              _buildGroupFab(context, link),
                            ],
                          ],
                        );
                      },
                    ),
        );
      },
    );
  }

  Future<String> _buildFolderContext() async {
    final folderDoc = await FirebaseService.firestore.collection('folders').doc(widget.folderId).get();
    final folderName = folderDoc.exists
        ? (folderDoc.data()?['name'] as String? ?? 'Unnamed Folder')
        : 'Unnamed Folder';

    final contentsSnap = await FirebaseService.firestore
        .collection('folders').doc(widget.folderId)
        .collection('contents').orderBy('createdAt', descending: false).get();

    if (contentsSnap.docs.isEmpty) {
      return 'User is viewing folder "$folderName" (ID: ${widget.folderId}). The folder is empty.';
    }

    final buffer = StringBuffer('User is viewing folder "$folderName". '
        'Below is a list of all items in this folder. Use this information to help the user with their studies:\n\n');

    for (final doc in contentsSnap.docs) {
      final data = doc.data();
      final type = data['type'] as String? ?? 'file';
      final name = data['name'] as String? ?? 'Unnamed';
      final locked = data['locked'] as bool? ?? false;
      final updating = data['updating'] as bool? ?? false;
      final invisible = data['invisible'] as bool? ?? false;

      buffer.write('- "$name" (type: $type)');
      if (locked) buffer.write(' [LOCKED]');
      if (updating) buffer.write(' [UPDATING]');
      if (invisible) buffer.write(' [HIDDEN]');

      if (type == 'lecture') {
        final url = data['youtubeUrl'] as String?;
        if (url != null && url.isNotEmpty) buffer.write(' — YouTube: $url');
      } else if (type == 'file') {
        final url = data['url'] as String?;
        final source = data['source'] as String?;
        if (url != null && url.isNotEmpty) buffer.write(' — URL: $url');
        if (source != null) buffer.write(' (source: $source)');
      } else if (type == 'mocktest_url') {
        final url = data['url'] as String?;
        if (url != null && url.isNotEmpty) buffer.write(' — URL: $url');
      } else if (type == 'mocktest_code') {
        final code = data['code'] as String?;
        if (code != null && code.isNotEmpty) buffer.write(' — Code: $code');
      }

      buffer.write('\n');
    }

    return buffer.toString();
  }

  Widget _buildAiFab(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'ai_chat_folder_${widget.folderId}',
        onPressed: () async {
          final contextStr = await _buildFolderContext();
          if (context.mounted) {
            context.push('/ai_tutor', extra: {'folderContext': contextStr});
          }
        },
        backgroundColor: Colors.transparent, elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: const Color(0xFF00B8D4).withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 2)],
          ),
          child: ClipOval(child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover)),
        ),
      ),
    );
  }

  Widget _buildGroupFab(BuildContext context, String link) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'group_${widget.folderId}',
        onPressed: () async {
          final uri = Uri.tryParse(link);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        backgroundColor: Colors.transparent, elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.amber.shade700,
            boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)],
          ),
          child: const Icon(Icons.groups_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildGroupBanner() {
    if (_groupLink == null || _groupLink!.isEmpty) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.groups_rounded, color: Colors.amber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _groupLink!,
              style: const TextStyle(color: Colors.amber, fontSize: 12),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.amber, size: 18),
            tooltip: 'Open',
            onPressed: () {
              final uri = Uri.tryParse(_groupLink!);
              if (uri != null) {
                canLaunchUrl(uri).then((ok) {
                  if (ok) launchUrl(uri, mode: LaunchMode.externalApplication);
                });
              }
            },
          ),
          if (widget.isAdmin)
            IconButton(
              icon: Icon(Icons.edit_rounded, color: isDark ? Colors.white54 : Colors.black45, size: 16),
              tooltip: 'Edit Group Link',
              onPressed: () => _showGroupLinkDialog(),
            ),
        ],
      ),
    );
  }

  Widget _buildSelectionToolbar() {
    if (!_isSelectMode || !widget.isAdmin) return const SizedBox.shrink();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 0),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(Icons.checklist_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
        const SizedBox(width: 6),
        Text('${_selectedIds.length} selected', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.w600, fontSize: 13)),
        const Spacer(),
        _toolbarIconButton(Icons.delete_outline_rounded, Colors.redAccent, 'Delete', _confirmDeleteSelected),
        const SizedBox(width: 4),
        _toolbarIconButton(Icons.content_copy_rounded, Colors.blue, 'Copy', () => _showCopyMoveDialog(false)),
        const SizedBox(width: 4),
        _toolbarIconButton(Icons.drive_file_move_rounded, Colors.orange, 'Move', () => _showCopyMoveDialog(true)),
        const SizedBox(width: 4),
        _toolbarIconButton(Icons.close_rounded, isDark ? Colors.white54 : Colors.black45, 'Close', _clearSelection),
      ]),
    );
  }

  Widget _toolbarIconButton(IconData icon, Color color, String tooltip, VoidCallback onPressed) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, color: color, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildContentCard(BuildContext context, String id, Map<String, dynamic> data, String type, int index) {
    final locked = data['locked'] as bool? ?? false;
    final updating = data['updating'] as bool? ?? false;
    final invisible = data['invisible'] as bool? ?? false;
    Widget card;
    switch (type) {
      case 'lecture': card = _buildLectureCard(context, id, data, locked, updating, invisible, index);
      case 'subfolder': card = _buildSubFolderCard(context, id, data, locked, updating, invisible, index);
      case 'mocktest_url': card = _buildMockTestUrlCard(context, id, data, locked, updating, invisible, index);
      case 'mocktest_code': card = _buildMockTestCodeCard(context, id, data, locked, updating, invisible, index);
      default: card = _buildFileCard(context, id, data, locked, updating, invisible, index);
    }
    final selected = _selectedIds.contains(id);
    return Stack(
      children: [
        card,
        if (selected)
          Positioned(
            top: 4, right: 4,
            child: Container(
              width: 24, height: 24,
              decoration: const BoxDecoration(
                color: Color(0xFF4A148C),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, color: Colors.white, size: 16),
            ),
          ),
        if (selected)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF4A148C).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF4A148C).withValues(alpha: 0.5), width: 1.5),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // ─── Lecture Card ────────────────────────────────────────────────────────────

  Widget _buildLectureCard(BuildContext context, String id, Map<String, dynamic> data, bool locked, bool updating, bool invisible, int index) {
    final name = data['name'] as String? ?? 'Lecture';
    final disabled = _isDisabled(data, id);
    return GestureDetector(
      onLongPress: (!widget.isAdmin || disabled) ? null : () => _onContentSelect(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: GlassmorphicContainer(
          padding: const EdgeInsets.all(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : () {
              if (_isSelectMode) { _onContentSelect(id); return; }
              _openContent(data);
            },
            child: Row(children: [
              if (widget.isAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_indicator, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26),
                  ),
                ),
              Icon(Icons.play_circle_fill_rounded, color: disabled ? Colors.grey : (updating ? Colors.orange : Colors.red), size: 36),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(color: disabled ? Colors.grey : null, fontWeight: FontWeight.bold, fontSize: 14)),
                if (updating)
                  const Row(children: [Icon(Icons.update_rounded, color: Colors.orange, size: 12), SizedBox(width: 4), Text('Updating...', style: TextStyle(color: Colors.orange, fontSize: 11))]),
                if (locked && !updating)
                  const Row(children: [Icon(Icons.lock_rounded, color: Colors.redAccent, size: 12), SizedBox(width: 4), Text('Locked', style: TextStyle(color: Colors.redAccent, fontSize: 11))]),
                if (invisible)
                  const Row(children: [Icon(Icons.visibility_off_rounded, color: Colors.purple, size: 12), SizedBox(width: 4), Text('Hidden', style: TextStyle(color: Colors.purple, fontSize: 11))]),
              ])),
              if (widget.isAdmin || widget.canEdit) ...[
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D2D2D) : Colors.white,
                  onSelected: (value) {
                    switch (value) {
                      case 'lock':
                        _showContentLockSheet(id, name, locked, updating, invisible);
                      case 'Assistant':
                        _showContentAssistantSheet(id, name);
                      case 'edit':
                        if (data['type'] == 'subfolder') {
                          _showRenameContentDialog(id, name);
                        } else {
                          _showEditContentDialog(id, name, data['type'] as String? ?? 'file', data);
                        }
                      case 'rename':
                        _showRenameContentDialog(id, name);
                      case 'delete':
                        _confirmDeleteContent(id, name, data);
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.isAdmin) ...[
                      PopupMenuItem(
                        value: 'lock',
                        child: ListTile(
                          leading: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.redAccent),
                          title: Text(locked ? 'Unlock' : 'Lock'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'Assistant',
                        child: ListTile(leading: Icon(Icons.people_alt_rounded, color: Colors.orange), title: Text('Assistant Access')),
                      ),
                    ],
                    const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, color: Colors.green), title: Text('Edit'))),
                    const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.drive_file_rename_outline, color: Colors.blue), title: Text('Rename'))),
                    const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)))),
                  ],
                ),
              ] else if (!disabled)
                const Icon(Icons.chevron_right, color: Colors.white38),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── Sub-Folder Card ─────────────────────────────────────────────────────────

  Widget _buildSubFolderCard(BuildContext context, String id, Map<String, dynamic> data, bool locked, bool updating, bool invisible, int index) {
    final name = data['name'] as String? ?? 'Sub-Folder';
    final disabled = _isDisabled(data, id);
    return GestureDetector(
      onLongPress: (!widget.isAdmin || disabled) ? null : () => _onContentSelect(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: GlassmorphicContainer(
          padding: const EdgeInsets.all(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : () {
              if (_isSelectMode) { _onContentSelect(id); return; }
              context.push('/folders/${widget.folderId}/sub/$id', extra: {
                'canEdit': widget.canEdit, 'canManage': widget.canManage,
                'isAdmin': widget.isAdmin,
                if (widget.assistantContentAccess != null) 'assistantContentAccess': widget.assistantContentAccess!.toList(),
              });
            },
            child: Row(children: [
              if (widget.isAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_indicator, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26),
                  ),
                ),
              Icon(Icons.folder_rounded, color: disabled ? Colors.grey : (updating ? Colors.orange : Colors.blue), size: 36),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(color: disabled ? Colors.grey : null, fontWeight: FontWeight.bold, fontSize: 14)),
                if (updating)
                  const Row(children: [Icon(Icons.update_rounded, color: Colors.orange, size: 12), SizedBox(width: 4), Text('Updating...', style: TextStyle(color: Colors.orange, fontSize: 11))]),
                if (locked && !updating)
                  const Row(children: [Icon(Icons.lock_rounded, color: Colors.redAccent, size: 12), SizedBox(width: 4), Text('Locked', style: TextStyle(color: Colors.redAccent, fontSize: 11))]),
                if (invisible)
                  const Row(children: [Icon(Icons.visibility_off_rounded, color: Colors.purple, size: 12), SizedBox(width: 4), Text('Hidden', style: TextStyle(color: Colors.purple, fontSize: 11))]),
              ])),
              if (widget.isAdmin || widget.canEdit) ...[
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D2D2D) : Colors.white,
                  onSelected: (value) {
                    switch (value) {
                      case 'lock':
                        _showContentLockSheet(id, name, locked, updating, invisible);
                      case 'Assistant':
                        _showContentAssistantSheet(id, name);
                      case 'group':
                        _showGroupLinkDialogForContent(id);
                      case 'edit':
                        if (data['type'] == 'subfolder') {
                          _showRenameContentDialog(id, name);
                        } else {
                          _showEditContentDialog(id, name, data['type'] as String? ?? 'file', data);
                        }
                      case 'rename':
                        _showRenameContentDialog(id, name);
                      case 'delete':
                        _confirmDeleteContent(id, name, data);
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.isAdmin) ...[
                      PopupMenuItem(
                        value: 'lock',
                        child: ListTile(
                          leading: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.redAccent),
                          title: Text(locked ? 'Unlock' : 'Lock'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'Assistant',
                        child: ListTile(leading: Icon(Icons.people_alt_rounded, color: Colors.orange), title: Text('Assistant Access')),
                      ),
                      const PopupMenuItem(
                        value: 'group',
                        child: ListTile(leading: Icon(Icons.groups_rounded, color: Colors.amber), title: Text('Group Link')),
                      ),
                    ],
                    const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, color: Colors.green), title: Text('Edit'))),
                    const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.drive_file_rename_outline, color: Colors.blue), title: Text('Rename'))),
                    const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)))),
                  ],
                ),
              ] else if (!disabled)
                const Icon(Icons.chevron_right, color: Colors.white38),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── Mock Test URL Card ──────────────────────────────────────────────────────

  Widget _buildMockTestUrlCard(BuildContext context, String id, Map<String, dynamic> data, bool locked, bool updating, bool invisible, int index) {
    final name = data['name'] as String? ?? 'Mock Test';
    final disabled = _isDisabled(data, id);
    return GestureDetector(
      onLongPress: (!widget.isAdmin || disabled) ? null : () => _onContentSelect(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: GlassmorphicContainer(
          padding: const EdgeInsets.all(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : () {
              if (_isSelectMode) { _onContentSelect(id); return; }
              _openContent(data);
            },
            child: Row(children: [
              if (widget.isAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_indicator, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26),
                  ),
                ),
              Icon(Icons.assignment_rounded, color: disabled ? Colors.grey : (updating ? Colors.orange : Colors.orange), size: 36),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(color: disabled ? Colors.grey : null, fontWeight: FontWeight.bold, fontSize: 14)),
                if (updating)
                  const Row(children: [Icon(Icons.update_rounded, color: Colors.orange, size: 12), SizedBox(width: 4), Text('Updating...', style: TextStyle(color: Colors.orange, fontSize: 11))]),
                if (locked && !updating)
                  const Row(children: [Icon(Icons.lock_rounded, color: Colors.redAccent, size: 12), SizedBox(width: 4), Text('Locked', style: TextStyle(color: Colors.redAccent, fontSize: 11))]),
                if (invisible)
                  const Row(children: [Icon(Icons.visibility_off_rounded, color: Colors.purple, size: 12), SizedBox(width: 4), Text('Hidden', style: TextStyle(color: Colors.purple, fontSize: 11))]),
              ])),
              if (widget.isAdmin || widget.canEdit) ...[
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D2D2D) : Colors.white,
                  onSelected: (value) {
                    switch (value) {
                      case 'lock':
                        _showContentLockSheet(id, name, locked, updating, invisible);
                      case 'Assistant':
                        _showContentAssistantSheet(id, name);
                      case 'edit':
                        if (data['type'] == 'subfolder') {
                          _showRenameContentDialog(id, name);
                        } else {
                          _showEditContentDialog(id, name, data['type'] as String? ?? 'file', data);
                        }
                      case 'rename':
                        _showRenameContentDialog(id, name);
                      case 'delete':
                        _confirmDeleteContent(id, name, data);
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.isAdmin) ...[
                      PopupMenuItem(
                        value: 'lock',
                        child: ListTile(
                          leading: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.redAccent),
                          title: Text(locked ? 'Unlock' : 'Lock'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'Assistant',
                        child: ListTile(leading: Icon(Icons.people_alt_rounded, color: Colors.orange), title: Text('Assistant Access')),
                      ),
                    ],
                    const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, color: Colors.green), title: Text('Edit'))),
                    const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.drive_file_rename_outline, color: Colors.blue), title: Text('Rename'))),
                    const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)))),
                  ],
                ),
              ] else if (!disabled)
                const Icon(Icons.chevron_right, color: Colors.orange, size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── Mock Test Code Card ─────────────────────────────────────────────────────

  Widget _buildMockTestCodeCard(BuildContext context, String id, Map<String, dynamic> data, bool locked, bool updating, bool invisible, int index) {
    final name = data['name'] as String? ?? 'Mock Test';
    final disabled = _isDisabled(data, id);
    return GestureDetector(
      onLongPress: (!widget.isAdmin || disabled) ? null : () => _onContentSelect(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: GlassmorphicContainer(
          padding: const EdgeInsets.all(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : () {
              if (_isSelectMode) { _onContentSelect(id); return; }
              _openContent(data);
            },
            child: Row(children: [
              if (widget.isAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_indicator, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26),
                  ),
                ),
              Icon(Icons.assignment_rounded, color: disabled ? Colors.grey : (updating ? Colors.orange : Colors.orange), size: 36),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(color: disabled ? Colors.grey : null, fontWeight: FontWeight.bold, fontSize: 14)),
                if (updating)
                  const Row(children: [Icon(Icons.update_rounded, color: Colors.orange, size: 12), SizedBox(width: 4), Text('Updating...', style: TextStyle(color: Colors.orange, fontSize: 11))]),
                if (locked && !updating)
                  const Row(children: [Icon(Icons.lock_rounded, color: Colors.redAccent, size: 12), SizedBox(width: 4), Text('Locked', style: TextStyle(color: Colors.redAccent, fontSize: 11))]),
                if (invisible)
                  const Row(children: [Icon(Icons.visibility_off_rounded, color: Colors.purple, size: 12), SizedBox(width: 4), Text('Hidden', style: TextStyle(color: Colors.purple, fontSize: 11))]),
              ])),
              if (widget.isAdmin || widget.canEdit) ...[
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D2D2D) : Colors.white,
                  onSelected: (value) {
                    switch (value) {
                      case 'lock':
                        _showContentLockSheet(id, name, locked, updating, invisible);
                      case 'Assistant':
                        _showContentAssistantSheet(id, name);
                      case 'edit':
                        if (data['type'] == 'subfolder') {
                          _showRenameContentDialog(id, name);
                        } else {
                          _showEditContentDialog(id, name, data['type'] as String? ?? 'file', data);
                        }
                      case 'rename':
                        _showRenameContentDialog(id, name);
                      case 'delete':
                        _confirmDeleteContent(id, name, data);
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.isAdmin) ...[
                      PopupMenuItem(
                        value: 'lock',
                        child: ListTile(
                          leading: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.redAccent),
                          title: Text(locked ? 'Unlock' : 'Lock'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'Assistant',
                        child: ListTile(leading: Icon(Icons.people_alt_rounded, color: Colors.orange), title: Text('Assistant Access')),
                      ),
                    ],
                    const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, color: Colors.green), title: Text('Edit'))),
                    const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.drive_file_rename_outline, color: Colors.blue), title: Text('Rename'))),
                    const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)))),
                  ],
                ),
              ] else if (!disabled)
                const Icon(Icons.chevron_right, color: Colors.orange, size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── File Card ───────────────────────────────────────────────────────────────

  Widget _buildFileCard(BuildContext context, String id, Map<String, dynamic> data, bool locked, bool updating, bool invisible, int index) {
    final name = data['name'] as String? ?? 'File';
    final disabled = _isDisabled(data, id);
    return GestureDetector(
      onLongPress: (!widget.isAdmin || disabled) ? null : () => _onContentSelect(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        child: GlassmorphicContainer(
          padding: const EdgeInsets.all(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: disabled ? null : () {
              if (_isSelectMode) { _onContentSelect(id); return; }
              _openContent(data);
            },
            child: Row(children: [
              if (widget.isAdmin)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_indicator, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white24 : Colors.black26),
                  ),
                ),
              Icon(_fileIcon(name), color: disabled ? Colors.grey : (updating ? Colors.orange : Colors.teal), size: 36),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: TextStyle(color: disabled ? Colors.grey : null, fontWeight: FontWeight.bold, fontSize: 14)),
                if (updating)
                  const Row(children: [Icon(Icons.update_rounded, color: Colors.orange, size: 12), SizedBox(width: 4), Text('Updating...', style: TextStyle(color: Colors.orange, fontSize: 11))]),
                if (locked && !updating)
                  const Row(children: [Icon(Icons.lock_rounded, color: Colors.redAccent, size: 12), SizedBox(width: 4), Text('Locked', style: TextStyle(color: Colors.redAccent, fontSize: 11))]),
                if (invisible)
                  const Row(children: [Icon(Icons.visibility_off_rounded, color: Colors.purple, size: 12), SizedBox(width: 4), Text('Hidden', style: TextStyle(color: Colors.purple, fontSize: 11))]),
              ])),
              if (widget.isAdmin || widget.canEdit) ...[
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_vert, size: 20, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D2D2D) : Colors.white,
                  onSelected: (value) {
                    switch (value) {
                      case 'lock':
                        _showContentLockSheet(id, name, locked, updating, invisible);
                      case 'Assistant':
                        _showContentAssistantSheet(id, name);
                      case 'edit':
                        if (data['type'] == 'subfolder') {
                          _showRenameContentDialog(id, name);
                        } else {
                          _showEditContentDialog(id, name, data['type'] as String? ?? 'file', data);
                        }
                      case 'rename':
                        _showRenameContentDialog(id, name);
                      case 'delete':
                        _confirmDeleteContent(id, name, data);
                    }
                  },
                  itemBuilder: (context) => [
                    if (widget.isAdmin) ...[
                      PopupMenuItem(
                        value: 'lock',
                        child: ListTile(
                          leading: Icon(locked ? Icons.lock_rounded : Icons.lock_open_rounded, color: Colors.redAccent),
                          title: Text(locked ? 'Unlock' : 'Lock'),
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'Assistant',
                        child: ListTile(leading: Icon(Icons.people_alt_rounded, color: Colors.orange), title: Text('Assistant Access')),
                      ),
                    ],
                    const PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit, color: Colors.green), title: Text('Edit'))),
                    const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.drive_file_rename_outline, color: Colors.blue), title: Text('Rename'))),
                    const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete, color: Colors.red), title: Text('Delete', style: TextStyle(color: Colors.red)))),
                  ],
                ),
              ] else if (!disabled)
                const Icon(Icons.chevron_right, color: Colors.teal, size: 20),
            ]),
          ),
        ),
      ),
    );
  }

  // ─── Upload Options ──────────────────────────────────────────────────────────

  void _showUploadOptions(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Add Content', style: TextStyle(color: dimColor, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 20),
          ListTile(leading: const Icon(Icons.folder_rounded, color: Colors.blue), title: Text('Sub-Folder', style: TextStyle(color: baseColor)), subtitle: Text('Create a sub-folder inside', style: TextStyle(color: dimColor, fontSize: 12)),
            onTap: () { Navigator.pop(context); _addSubFolder(context); }),
          ListTile(leading: const Icon(Icons.play_circle_fill_rounded, color: Colors.red), title: Text('Recorded Lecture', style: TextStyle(color: baseColor)), subtitle: Text('Add YouTube video link', style: TextStyle(color: dimColor, fontSize: 12)),
            onTap: () { Navigator.pop(context); _addYouTubeLecture(context); }),
          ListTile(leading: const Icon(Icons.assignment_rounded, color: Colors.orange), title: Text('Mock Test', style: TextStyle(color: baseColor)), subtitle: Text('Add URL or paste code', style: TextStyle(color: dimColor, fontSize: 12)),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(
                context: context, isScrollControlled: true, backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
                shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                builder: (ctx) => Padding(padding: const EdgeInsets.all(24), child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Add Mock Test', style: TextStyle(color: dimColor, fontWeight: FontWeight.bold, fontSize: 15)),
                  const SizedBox(height: 20),
                  ListTile(leading: const Icon(Icons.link, color: Colors.orange), title: Text('Add URL', style: TextStyle(color: baseColor)),
                    onTap: () { Navigator.pop(ctx); _addMockTestUrl(context); }),
                  Divider(color: isDark ? Colors.white12 : Colors.black12),
                  ListTile(leading: const Icon(Icons.code, color: Colors.orange), title: Text('Paste a Code', style: TextStyle(color: baseColor)),
                    onTap: () { Navigator.pop(ctx); _addMockTestCode(context); }),
                ]))));
            }),
          ListTile(leading: const Icon(Icons.upload_file_rounded, color: Colors.teal), title: Text('Upload File', style: TextStyle(color: baseColor)), subtitle: Text('Internal Storage / Drive / URL', style: TextStyle(color: dimColor, fontSize: 12)),
            onTap: () { Navigator.pop(context); _addUploadFile(context); }),
          const SizedBox(height: 8),
        ])),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    if (['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'].contains(ext)) return Icons.image_rounded;
    if (ext == 'pdf') return Icons.picture_as_pdf_rounded;
    if (['mp4', 'avi', 'mkv', 'mov', 'wmv', 'flv', 'webm'].contains(ext)) return Icons.videocam_rounded;
    if (['mp3', 'wav', 'aac', 'ogg', 'flac', 'wma', 'm4a', 'opus'].contains(ext)) return Icons.audiotrack_rounded;
    if (['doc', 'docx'].contains(ext)) return Icons.description_rounded;
    if (['xls', 'xlsx', 'csv'].contains(ext)) return Icons.table_chart_rounded;
    if (['ppt', 'pptx'].contains(ext)) return Icons.slideshow_rounded;
    if (['zip', 'rar', '7z', 'tar', 'gz'].contains(ext)) return Icons.folder_zip_rounded;
    if (['txt', 'rtf'].contains(ext)) return Icons.article_rounded;
    return Icons.book_rounded;
  }
}

class GroupLinkDialog extends StatefulWidget {
  final String folderId;
  final String parentContentId;

  const GroupLinkDialog({
    super.key,
    required this.folderId,
    required this.parentContentId,
  });

  @override
  State<GroupLinkDialog> createState() => _GroupLinkDialogState();
}

class _GroupLinkDialogState extends State<GroupLinkDialog> {
  final _linkCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _inheritGroup = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentLink();
  }

  Future<void> _loadCurrentLink() async {
    try {
      final link = await FirebaseService.getGroupLinkForLevel(widget.folderId, parentContentId: widget.parentContentId);
      if (mounted) {
        _linkCtrl.text = link ?? '';
      }
      if (widget.parentContentId != null && widget.parentContentId != 'root') {
        final doc = await FirebaseService.firestore
            .collection('folders').doc(widget.folderId)
            .collection('contents').doc(widget.parentContentId).get();
        if (doc.exists) {
          final data = doc.data() as Map<String, dynamic>?;
          final inherit = data?['inherit_group'] as bool?;
          if (inherit != null) {
            _inheritGroup = inherit;
          }
        }
      } else {
        final folderDoc = await FirebaseService.firestore.collection('folders').doc(widget.folderId).get();
        if (folderDoc.exists) {
          final data = folderDoc.data() as Map<String, dynamic>?;
          final inherit = data?['inherit_group'] as bool?;
          if (inherit != null) {
            _inheritGroup = inherit;
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _linkCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(16),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Container(
            margin: const EdgeInsets.only(top: 40),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A0533),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Row(
                children: [
                  Icon(Icons.groups_rounded, color: Colors.amber),
                  SizedBox(width: 8),
                  Text('Group Link', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 16),
              _loading
                  ? const SizedBox(
                      height: 100,
                      child: Center(child: CircularProgressIndicator(color: Colors.amber)),
                    )
                  : Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                        controller: _linkCtrl,
                        maxLines: 1,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Paste group link...',
                          hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                          filled: true,
                          fillColor: Colors.white10,
                          suffixIcon: const Icon(Icons.link, color: Colors.amber),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                      if (_linkCtrl.text.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.link, color: Colors.amber, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _linkCtrl.text.trim(),
                                  style: const TextStyle(color: Colors.amber, fontSize: 12, decoration: TextDecoration.underline),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ]),
                      if (!_loading) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Inherit to sub-folders',
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500)),
                            Text('ON = all sub-folders get this link',
                              style: const TextStyle(color: Colors.white38, fontSize: 10)),
                          ],
                        ),
                      ),
                      Switch(
                        value: _inheritGroup,
                        onChanged: (v) => setState(() => _inheritGroup = v),
                        activeColor: Colors.amber,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                      tooltip: 'Remove',
                      onPressed: _saving || _linkCtrl.text.trim().isEmpty
                          ? null
                          : () {
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1A0533),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                  title: const Text('Remove Group Link?', style: TextStyle(color: Colors.white)),
                                  content: const Text('Are you sure you want to remove this group link?', style: TextStyle(color: Colors.white70)),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                                    ElevatedButton(
                                      onPressed: () async {
                                        Navigator.pop(ctx);
                                        setState(() => _saving = true);
                                        await FirebaseService.removeGroupLink(widget.folderId, parentContentId: widget.parentContentId);
                                        if (mounted) Navigator.pop(context);
                                      },
                                      style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                                      child: const Text('Remove', style: TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                            },
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                    ),
                    ElevatedButton(
                      onPressed: _saving
                          ? null
                          : () async {
                              final link = _linkCtrl.text.trim();
                              if (link.isEmpty) return;
                              setState(() => _saving = true);
                              try {
                                await FirebaseService.setGroupLink(widget.folderId, link, parentContentId: widget.parentContentId, inheritGroup: _inheritGroup);
                                if (mounted) Navigator.pop(context);
                              } catch (e) {
                                setState(() => _saving = false);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Error saving: $e'), backgroundColor: Colors.redAccent),
                                  );
                                }
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.amber.shade800,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: _saving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save'),
                    ),
                  ],
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

