import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/master_supabase_service.dart';
import '../../../core/services/supabase_read_service.dart';
import '../../../core/utils.dart';
import '../../../core/widgets/professional_loader.dart';
import '../../../core/widgets/network_error_overlay.dart';

class BrowseNode {
  final String id;
  final String name;
  final bool isTopLevel;
  final String topLevelFolderId;
  final String? parentContentId;

  BrowseNode({
    required this.id,
    required this.name,
    required this.isTopLevel,
    required this.topLevelFolderId,
    this.parentContentId,
  });
}

class FolderBrowserScreen extends StatefulWidget {
  final String sourceFolderId;
  final bool isMove;
  final List<String> selectedIds;
  final String? parentContentId;

  const FolderBrowserScreen({
    super.key,
    required this.sourceFolderId,
    required this.isMove,
    required this.selectedIds,
    this.parentContentId,
  });

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  bool _loading = true;
  String? _error;

  // Tree structure: top-level folders (root level)
  List<BrowseNode> _rootFolders = [];

  // Cache: for each topLevelFolderId, a map of parentContentId -> children
  final Map<String, Map<String?, List<BrowseNode>>> _subFolderCache = {};

  // Navigation path
  final List<BrowseNode> _path = [];

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() { _loading = true; _error = null; });
    try {
      final folders = await SupabaseReadService.getFolders()
          .timeout(const Duration(seconds: 10), onTimeout: () {
        throw Exception('timeout');
      });
      if (folders == null || !mounted) return;
      
      // Build tree structure from flat list
      final rootNodes = <BrowseNode>[];
      final subFoldersByTopLevel = <String, List<Map<String, dynamic>>>{};
      
      for (final f in folders) {
        final isTopLevel = f['parentContentId'] == null;
        if (isTopLevel) {
          rootNodes.add(BrowseNode(
            id: f['id'] as String,
            name: f['name'] as String? ?? 'Untitled',
            isTopLevel: true,
            topLevelFolderId: f['id'] as String,
            parentContentId: null,
          ));
        } else {
          final topLevelId = f['topLevelFolderId'] as String? ?? f['id'] as String;
          subFoldersByTopLevel.putIfAbsent(topLevelId, () => []).add(f);
        }
      }
      
      rootNodes.sort((a, b) => a.name.compareTo(b.name));
      _rootFolders = rootNodes;

      // Build sub-folder cache from flat list
      _subFolderCache.clear();
      for (final entry in subFoldersByTopLevel.entries) {
        final topLevelId = entry.key;
        final subs = entry.value;
        final byParent = <String?, List<BrowseNode>>{};
        for (final f in subs) {
          final parentId = f['parentContentId'] as String?;
          byParent.putIfAbsent(parentId, () => []);
          byParent[parentId]!.add(BrowseNode(
            id: f['id'] as String,
            name: f['name'] as String? ?? 'Untitled',
            isTopLevel: false,
            topLevelFolderId: topLevelId,
            parentContentId: parentId,
          ));
        }
        for (final key in byParent.keys) {
          byParent[key]!.sort((a, b) => a.name.compareTo(b.name));
        }
        _subFolderCache[topLevelId] = byParent;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() { _loading = false; _error = 'Network error'; });
      }
    }
  }

  List<BrowseNode> _getChildren(BrowseNode node) {
    if (node.isTopLevel) {
      return _subFolderCache[node.id]?[null] ?? [];
    }
    return _subFolderCache[node.topLevelFolderId]?[node.id] ?? [];
  }

  void _enter(BrowseNode node) {
    setState(() {
      _path.add(node);
    });
  }

  void _goBack() {
    if (_path.isEmpty) return;
    setState(() {
      _path.removeLast();
    });
  }

  List<BrowseNode> get _currentNodes {
    if (_path.isEmpty) return _rootFolders;
    return _getChildren(_path.last);
  }

  Future<void> _pasteHere() async {
    if (!debounce('folder_paste')) return;
    if (_path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Open a folder first, then tap Paste Here'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final last = _path.last;
    final targetTopLevelFolderId = last.topLevelFolderId;
    final targetParentContentId = last.isTopLevel ? null : last.id;
    final srcFolderId = widget.sourceFolderId;
    final action = widget.isMove ? 'Moved' : 'Copied';
    try {
      for (final contentId in widget.selectedIds) {
        await _copyContentRecursive(
          srcFolderId: srcFolderId,
          contentId: contentId,
          targetTopLevelFolderId: targetTopLevelFolderId,
          targetParentContentId: targetParentContentId,
        );
      }
      await FirebaseService.addNotification('$action ${widget.selectedIds.length} item(s)', folderId: srcFolderId, parentContentId: targetParentContentId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$action successfully'), backgroundColor: Colors.green),
        );
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _copyContentRecursive({
    required String srcFolderId,
    required String contentId,
    required String targetTopLevelFolderId,
    required String? targetParentContentId,
  }) async {
    final doc = await FirebaseService.firestore
        .collection('folders').doc(srcFolderId)
        .collection('contents').doc(contentId).get();
    if (!doc.exists) return;
    final srcData = doc.data() as Map<String, dynamic>;
    final isSubfolder = srcData['type'] == 'subfolder';
    final newData = Map<String, dynamic>.from(srcData)
      ..remove('createdAt');
    if (targetParentContentId != null) {
      newData['parentContentId'] = targetParentContentId;
    } else {
      newData.remove('parentContentId');
    }

    // Get max order at destination to place item at end
    final targetQuery = await FirebaseService.firestore
        .collection('folders').doc(targetTopLevelFolderId)
        .collection('contents')
        .where('parentContentId', isEqualTo: targetParentContentId)
        .get();
    int maxOrder = -1;
    for (final d in targetQuery.docs) {
      final order = (d.data()['order'] as num?)?.toInt() ?? -1;
      if (order > maxOrder) maxOrder = order;
    }
    newData['order'] = maxOrder + 1;

    final newContentId = await FirebaseService.addFolderContent(targetTopLevelFolderId, newData);
    if (isSubfolder && newContentId != null) {
      final childrenSnap = await FirebaseService.firestore
          .collection('folders').doc(srcFolderId)
          .collection('contents')
          .where('parentContentId', isEqualTo: contentId)
          .get();
      for (final childDoc in childrenSnap.docs) {
        await _copyContentRecursive(
          srcFolderId: srcFolderId,
          contentId: childDoc.id,
          targetTopLevelFolderId: targetTopLevelFolderId,
          targetParentContentId: newContentId,
        );
      }
    }
    if (widget.isMove) {
      await FirebaseService.deleteFolderContent(srcFolderId, contentId);
    }
  }

  Future<void> _createNewFolder() async {
    if (_path.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Open a folder first to create sub-folder'),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    final parent = _path.last;
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (d) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('New Sub-Folder', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
          content: TextField(
            controller: ctrl, autofocus: true,
            style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            decoration: InputDecoration(
              hintText: 'Folder name...',
              hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black38),
              filled: true, fillColor: isDark ? Colors.white10 : Colors.black12,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: Text('Cancel', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(d, ctrl.text.trim()),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
              child: const Text('Create', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
    if (name == null || name.isEmpty) return;
    try {
      await MasterSupabaseService.insert('folder_contents', {
        'folder_id': parent.topLevelFolderId,
        'type': 'subfolder',
        'name': name,
        'parent_content_id': parent.isTopLevel ? null : parent.id,
        'created_at': DateTime.now().toIso8601String(),
      });
      await FirebaseService.firestore
          .collection('folders').doc(parent.topLevelFolderId)
          .collection('contents').add({
        'type': 'subfolder',
        'name': name,
        'parentContentId': parent.isTopLevel ? null : parent.id,
        'createdAt': DateTime.now().toIso8601String(),
      });
      // Re-fetch sub-folders for this top-level folder
      final snap = await FirebaseService.firestore
          .collection('folders').doc(parent.topLevelFolderId)
          .collection('contents')
          .where('type', isEqualTo: 'subfolder')
          .get();
      final byParent = <String?, List<BrowseNode>>{};
      for (final d in snap.docs) {
        final pid = d.data()['parentContentId'] as String?;
        byParent.putIfAbsent(pid, () => []);
        byParent[pid]!.add(BrowseNode(
          id: d.id,
          name: d.data()['name'] as String? ?? 'Untitled',
          isTopLevel: false,
          topLevelFolderId: parent.topLevelFolderId,
          parentContentId: pid,
        ));
      }
      for (final key in byParent.keys) {
        byParent[key]!.sort((a, b) => a.name.compareTo(b.name));
      }
      setState(() {
        _subFolderCache[parent.topLevelFolderId] = byParent;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white54 : Colors.black45;
    final isAtRoot = _path.isEmpty;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D2E) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.pop()),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.isMove ? 'Move to...' : 'Copy to...', style: TextStyle(color: textColor, fontSize: 14)),
            Text(isAtRoot ? 'All folders' : _path.last.name, style: TextStyle(color: dimColor, fontSize: 11)),
          ],
        ),
        actions: [
          if (!isAtRoot)
            TextButton.icon(
              onPressed: _goBack,
              icon: const Icon(Icons.arrow_upward_rounded, size: 16),
              label: const Text('Up', style: TextStyle(fontSize: 11)),
            ),
          if (!isAtRoot)
            TextButton.icon(
              onPressed: _createNewFolder,
              icon: const Icon(Icons.create_new_folder_rounded, size: 16),
              label: const Text('New', style: TextStyle(fontSize: 11)),
            ),
        ],
      ),
      body: Column(
        children: [
          if (!isAtRoot)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.withValues(alpha: 0.08),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () { setState(() => _path.clear()); },
                      child: const Text('Root', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                    for (final p in _path)
                      Row(
                        children: [
                          Icon(Icons.chevron_right, size: 14, color: dimColor),
                          Text(p.name, style: const TextStyle(color: Colors.amber, fontSize: 12)),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: _loading
                ? const Center(child: ProfessionalLoader())
                : _error != null
                    ? NetworkErrorOverlay(message: _error!, onRetry: _loadAll)
                    : _currentNodes.isEmpty
                    ? Center(child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.folder_open_rounded, size: 48, color: dimColor),
                          const SizedBox(height: 8),
                          Text(isAtRoot ? 'No folders found' : 'No sub-folders', style: TextStyle(color: dimColor)),
                          if (!isAtRoot) ...[
                            const SizedBox(height: 16),
                            TextButton.icon(
                              onPressed: _createNewFolder,
                              icon: const Icon(Icons.create_new_folder_rounded, size: 18),
                              label: const Text('Create New Folder'),
                              style: TextButton.styleFrom(foregroundColor: Colors.amber),
                            ),
                          ],
                        ],
                      ))
                    : ListView.separated(
                        itemCount: _currentNodes.length,
                        separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
                        itemBuilder: (_, i) {
                          final node = _currentNodes[i];
                          return ListTile(
                            leading: Icon(
                              node.isTopLevel ? Icons.folder_rounded : Icons.subdirectory_arrow_right_rounded,
                              color: Colors.amber,
                              size: 28,
                            ),
                            title: Text(node.name, style: TextStyle(
                              color: textColor,
                              fontWeight: FontWeight.bold, fontSize: 14,
                            )),
                            trailing: const Icon(Icons.chevron_right, size: 18),
                            onTap: () => _enter(node),
                          );
                        },
                      ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _pasteHere,
                  icon: Icon(widget.isMove ? Icons.drive_file_move_rounded : Icons.content_copy_rounded, size: 18),
                  label: Text(widget.isMove ? 'Paste Here' : 'Copy Here',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
