import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/utils.dart';

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

  const FolderBrowserScreen({
    super.key,
    required this.sourceFolderId,
    required this.isMove,
    required this.selectedIds,
  });

  @override
  State<FolderBrowserScreen> createState() => _FolderBrowserScreenState();
}

class _FolderBrowserScreenState extends State<FolderBrowserScreen> {
  bool _loading = true;

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
    setState(() => _loading = true);
    try {
      // 1. Fetch all top-level folders
      final folderSnap = await FirebaseService.firestore.collection('folders').get();
      final rootNodes = <BrowseNode>[];
      for (final doc in folderSnap.docs) {
        final data = doc.data() as Map<String, dynamic>;
        rootNodes.add(BrowseNode(
          id: doc.id,
          name: data['name'] as String? ?? 'Untitled',
          isTopLevel: true,
          topLevelFolderId: doc.id,
          parentContentId: null,
        ));
      }
      rootNodes.sort((a, b) => a.name.compareTo(b.name));
      _rootFolders = rootNodes;

      // 2. Batch load all sub-folders for each top-level folder
      _subFolderCache.clear();
      for (final root in rootNodes) {
        final snap = await FirebaseService.firestore
            .collection('folders').doc(root.id)
            .collection('contents')
            .where('type', isEqualTo: 'subfolder')
            .get();
        final byParent = <String?, List<BrowseNode>>{};
        for (final doc in snap.docs) {
          final d = doc.data() as Map<String, dynamic>;
          final parentId = d['parentContentId'] as String?;
          byParent.putIfAbsent(parentId, () => []);
          byParent[parentId]!.add(BrowseNode(
            id: doc.id,
            name: d['name'] as String? ?? 'Untitled',
            isTopLevel: false,
            topLevelFolderId: root.id,
            parentContentId: parentId,
          ));
        }
        // Sort each list
        for (final key in byParent.keys) {
          byParent[key]!.sort((a, b) => a.name.compareTo(b.name));
        }
        _subFolderCache[root.id] = byParent;
      }

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error loading: $e'),
          backgroundColor: Colors.redAccent,
        ));
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
        final doc = await FirebaseService.firestore
            .collection('folders').doc(srcFolderId)
            .collection('contents').doc(contentId).get();
        if (!doc.exists) continue;
        final data = Map<String, dynamic>.from(doc.data() as Map<String, dynamic>);
        data.remove('createdAt');
        data.remove('order');
        if (targetParentContentId != null) {
          data['parentContentId'] = targetParentContentId;
        } else {
          data.remove('parentContentId');
        }
        await FirebaseService.addFolderContent(targetTopLevelFolderId, data);
        if (widget.isMove) {
          await FirebaseService.deleteFolderContent(srcFolderId, contentId);
        }
      }
      await FirebaseService.addNotification('$action ${widget.selectedIds.length} item(s)', folderId: srcFolderId);
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
      await FirebaseService.firestore
          .collection('folders').doc(parent.topLevelFolderId)
          .collection('contents').add({
        'type': 'subfolder',
        'name': name,
        'parentContentId': parent.isTopLevel ? null : parent.id,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Re-fetch sub-folders for this top-level folder
      final snap = await FirebaseService.firestore
          .collection('folders').doc(parent.topLevelFolderId)
          .collection('contents')
          .where('type', isEqualTo: 'subfolder')
          .get();
      final byParent = <String?, List<BrowseNode>>{};
      for (final doc in snap.docs) {
        final d = doc.data() as Map<String, dynamic>;
        final pid = d['parentContentId'] as String?;
        byParent.putIfAbsent(pid, () => []);
        byParent[pid]!.add(BrowseNode(
          id: doc.id,
          name: d['name'] as String? ?? 'Untitled',
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
                ? const Center(child: CircularProgressIndicator(color: Colors.amber))
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
