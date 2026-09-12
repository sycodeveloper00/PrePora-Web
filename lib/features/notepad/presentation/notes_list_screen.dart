import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:uuid/uuid.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class NotesListScreen extends StatefulWidget {
  const NotesListScreen({super.key});
  @override
  State<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends State<NotesListScreen> {
  List<Map<String, dynamic>>? _notes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final allNotes = await FirebaseService.getAllNotes();
    if (mounted) setState(() { _notes = allNotes; _loading = false; });
  }

  Future<void> _createNote() async {
    final c = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Note'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'Note title')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Create')),
        ],
      ),
    );
    c.dispose();
    if (name != null && name.isNotEmpty) {
      final id = const Uuid().v4();
      final ok = await FirebaseService.saveNote(id, '', lectureName: name);
      if (ok && mounted) {
        _load();
        if (mounted) context.push('/notepad/$id', extra: {'name': name});
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create note'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Note?'),
        content: const Text('Are you sure you want to delete this note? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
    if (confirm == true) {
      await FirebaseService.deleteNote(id);
      _load();
    }
  }

  Future<void> _rename(String id, String currentName) async {
    final c = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename Note'),
        content: TextField(controller: c, autofocus: true, decoration: const InputDecoration(hintText: 'New name')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Rename')),
        ],
      ),
    );
    c.dispose();
    if (newName != null && newName.isNotEmpty && newName != currentName) {
      await FirebaseService.renameNote(id, newName);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Notes', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createNote,
        backgroundColor: const Color(0xFF00B8D4),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: ProfessionalLoader())
          : _notes == null || _notes!.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.note_add_rounded, size: 64, color: isDark ? Colors.white12 : Colors.black12),
                      const SizedBox(height: 16),
                      Text('No notes yet', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 16)),
                      const SizedBox(height: 8),
                      Text('Tap + to create a note', style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: _notes!.length,
                  itemBuilder: (context, i) {
                        final note = _notes![i];
                        final id = note['id'] as String;
                        final lectureName = note['lectureName'] as String? ?? 'Unknown Lecture';
                        final content = note['content'] as String? ?? '';
                        final source = note['source'] as String? ?? 'notepad';
                        final pdfUrl = note['pdfUrl'] as String? ?? '';
                        final isPdf = source == 'pdf' && pdfUrl.isNotEmpty;
                        final preview = content.length > 100 ? '${content.substring(0, 100)}...' : content;
                        final timeStrRaw = note['updatedAt'] as String?;
                        final time = timeStrRaw != null ? DateTime.tryParse(timeStrRaw) : null;
                        final timeStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';
                    return Card(
                      color: isDark ? const Color(0xFF1A0533) : Colors.white,
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ListTile(
                          leading: Icon(isPdf ? Icons.picture_as_pdf_rounded : Icons.note_rounded, color: isPdf ? Colors.redAccent : (isDark ? const Color(0xFF00B8D4) : const Color(0xFF4A148C))),
                          title: Text(lectureName, style: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87)),
                          subtitle: content.isEmpty
                              ? Text(isPdf ? 'Tap to open PDF' : 'Tap to edit', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 12, fontStyle: FontStyle.italic))
                              : Text(isPdf ? 'PDF: $preview' : preview, style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                          trailing: PopupMenuButton<String>(
                            icon: Icon(Icons.more_vert_rounded, color: isDark ? Colors.white70 : Colors.black54),
                            onSelected: (v) {
                              if (v == 'rename') _rename(id, lectureName);
                              if (v == 'delete') _delete(id);
                            },
                            itemBuilder: (_) => [
                              const PopupMenuItem(value: 'rename', child: ListTile(leading: Icon(Icons.edit_rounded), title: Text('Rename'), dense: true)),
                              const PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_rounded, color: Colors.redAccent), title: Text('Delete', style: TextStyle(color: Colors.redAccent)), dense: true)),
                            ],
                          ),
                          onTap: () {
                            if (isPdf) {
                              context.push('/pdf_reader/view', extra: {'url': pdfUrl, 'title': lectureName});
                            } else {
                              context.push('/notepad/$id', extra: {'name': lectureName});
                            }
                          },
                        ),
                        if (timeStr.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                            child: Text(timeStr, style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 11)),
                          ),
                      ]),
                    );
                  },
                ),
    );
  }
}
