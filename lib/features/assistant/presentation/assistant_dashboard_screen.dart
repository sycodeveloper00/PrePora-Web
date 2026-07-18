import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/widgets/glassmorphic_container.dart';
import '../../../core/services/firebase_service.dart';

class AssistantDashboardScreen extends StatefulWidget {
  final List<String>? folderIds;
  final String? assistantName;
  const AssistantDashboardScreen({super.key, this.folderIds, this.assistantName});

  @override
  State<AssistantDashboardScreen> createState() => _AssistantDashboardScreenState();
}

class _AssistantDashboardScreenState extends State<AssistantDashboardScreen> {
  Map<String, List<String>> _contentAccess = {};
  bool _loadingAccess = true;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadContentAccess();
  }

  Future<void> _loadContentAccess() async {
    final user = FirebaseService.currentUser;
    if (user != null) {
      final access = await FirebaseService.getContentAccess(user.uid);
      if (mounted) setState(() { _contentAccess = access; _loadingAccess = false; });
    } else {
      setState(() => _loadingAccess = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accessibleIds = widget.folderIds ?? [];
    final extraFolderIds = _contentAccess.keys.where((fid) => !accessibleIds.contains(fid)).toList();

    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'ai_chat_Assistant',
        onPressed: () => context.push('/ai_tutor'),
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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [Color(0xFF0D1B2A), Color(0xFF0D2818)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(children: [
                Image.asset('assets/logo.png', height: 36, width: 36),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('PrePora', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
                  Text(widget.assistantName ?? 'Assistant', style: TextStyle(color: isDark ? Colors.greenAccent.shade200 : Colors.green.shade700, fontSize: 12)),
                ]),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.orange)),
                  child: const Row(children: [
                    Icon(Icons.workspace_premium, color: Colors.orange, size: 14),
                    SizedBox(width: 4),
                    Text('Assistant', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.bold)),
                  ]),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.settings_outlined, color: isDark ? Colors.white70 : Colors.black54, size: 24),
                  tooltip: 'Settings',
                  onPressed: () => context.push('/settings'),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.logout, color: isDark ? Colors.white70 : Colors.black54, size: 22),
                  onPressed: () async { await FirebaseService.signOut(); if (mounted) context.go('/auth/login'); },
                ),
              ]),
            ),
            if (accessibleIds.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.withValues(alpha: 0.4))),
                  child: Row(children: [
                    const Icon(Icons.lock_open_rounded, color: Colors.green, size: 18),
                    const SizedBox(width: 8),
                    Text('You have access to ${accessibleIds.length} folder(s)', style: TextStyle(color: isDark ? Colors.greenAccent.shade200 : Colors.green.shade700, fontSize: 13)),
                  ]),
                ),
              ),
            const SizedBox(height: 12),
            _buildAssistantSearchBar(),
            if (_searchResults == null) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Align(alignment: Alignment.centerLeft, child: Text('MY FOLDERS', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.8))),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: (accessibleIds.isEmpty && extraFolderIds.isEmpty)
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(Icons.folder_off_rounded, size: 60, color: isDark ? Colors.white12 : Colors.black12),
                        SizedBox(height: 16),
                        Text('No folders assigned', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54, fontSize: 16)),
                        SizedBox(height: 8),
                        Text('Contact admin for folder access', style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 13)),
                      ]))
                    : _loadingAccess
                        ? const Center(child: CircularProgressIndicator())
                        : _buildFolderList(accessibleIds, extraFolderIds),
              ),
            ]
          ]),
        ),
      ),
    );
  }

  List<Map<String, dynamic>>? _searchResults;
  bool _searching = false;

  Widget _buildAssistantSearchBar() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hintColor = isDark ? Colors.white38 : Colors.black45;
    final fillColor = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Column(children: [
        TextField(
          controller: _searchController,
          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Search folders & content...',
            hintStyle: TextStyle(color: hintColor, fontSize: 14),
            prefixIcon: Icon(Icons.search_rounded, color: hintColor, size: 20),
            suffixIcon: _searchQuery.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear_rounded, color: hintColor, size: 18),
                    onPressed: () { _searchController.clear(); setState(() { _searchQuery = ''; _searchResults = null; }); },
                  )
                : null,
            filled: true, fillColor: fillColor,
            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
          onChanged: (val) {
            setState(() => _searchQuery = val.trim());
            if (_searchQuery.length >= 2) _performSearch();
            else setState(() => _searchResults = null);
          },
        ),
        if (_searchResults != null)
          Container(
            margin: const EdgeInsets.only(top: 8),
            constraints: const BoxConstraints(maxHeight: 240),
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 4),
              itemCount: _searchResults!.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (_, i) {
                final r = _searchResults![i];
                final isContent = r['type'] != 'folder';
                final title = r['name'] as String? ?? '';
                final subtitle = r['subtitle'] as String? ?? '';
                final folderId = r['folderId'] as String? ?? '';
                final contentId = r['contentId'] as String?;
                return ListTile(
                  dense: true,
                  leading: Icon(isContent ? Icons.description_rounded : Icons.folder_rounded,
                      color: isContent ? Colors.teal : Colors.purple, size: 22),
                  title: Text(title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w500)),
                  subtitle: Text(subtitle, style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 11)),
                  onTap: () {
                    setState(() { _searchQuery = ''; _searchResults = null; _searchController.clear(); });
                    if (isContent && contentId != null) {
                      context.push('/folders/$folderId/sub/$contentId', extra: {
                        'canEdit': true, 'canManage': true,
                      });
                    } else {
                      context.push('/folders/$folderId', extra: {
                        'canEdit': true, 'canManage': true,
                      });
                    }
                  },
                );
              },
            ),
          ),
      ]),
    );
  }

  Future<void> _performSearch() async {
    if (_searching) return;
    setState(() => _searching = true);
    try {
      final q = _searchQuery.toLowerCase();
      final results = <Map<String, dynamic>>[];
      final accessibleIds = widget.folderIds ?? [];
      final extraFolderIds = _contentAccess.keys.where((fid) => !accessibleIds.contains(fid)).toList();
      final allIds = {...accessibleIds, ...extraFolderIds};
      for (final folderId in allIds) {
        final folderDoc = await FirebaseService.firestore.collection('folders').doc(folderId).get();
        if (!folderDoc.exists) continue;
        final folderData = folderDoc.data() as Map<String, dynamic>;
        if (folderData['invisible'] == true) continue;
        final folderName = folderData['name'] as String? ?? '';
        if (folderName.toLowerCase().contains(q)) {
          results.add({
            'name': folderName, 'type': 'folder', 'folderId': folderId,
            'subtitle': 'Folder',
          });
        }
        final contentSnap = await FirebaseService.firestore
            .collection('folders').doc(folderId).collection('content').get();
        for (final contentDoc in contentSnap.docs) {
          final contentData = contentDoc.data() as Map<String, dynamic>;
          if (contentData['invisible'] == true || contentData['locked'] == true || contentData['updating'] == true) continue;
          final contentName = contentData['name'] as String? ?? '';
          if (contentName.toLowerCase().contains(q)) {
            results.add({
              'name': contentName, 'type': 'content', 'folderId': folderId,
              'contentId': contentDoc.id,
              'subtitle': '$folderName › ${contentData['type'] ?? 'item'}',
            });
          }
        }
      }
      if (mounted) setState(() => _searchResults = results.take(15).toList());
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Widget _buildFolderList(List<String> accessibleIds, List<String> extraFolderIds) {
    final allIds = [...accessibleIds, ...extraFolderIds];
    final colors = [Colors.purple, Colors.teal, Colors.blue, Colors.orange, Colors.pink, Colors.indigo];

    return FutureBuilder<List<DocumentSnapshot>>(
      future: Future.wait(allIds.map((id) => FirebaseService.firestore.collection('folders').doc(id).get())),
      builder: (context, snapshot) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
        if (!snapshot.hasData) return Center(child: Text('Error loading folders', style: TextStyle(color: isDark ? Colors.white38 : Colors.black54)));
        final docs = snapshot.data!.where((d) => d.exists).toList();
        final filtered = _searchQuery.isNotEmpty
            ? docs.where((d) {
                final data = d.data() as Map<String, dynamic>;
                final name = (data['name'] as String? ?? '').toLowerCase();
                return name.contains(_searchQuery.toLowerCase());
              }).toList()
            : docs;
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: filtered.length,
          itemBuilder: (context, index) {
            final data = filtered[index].data() as Map<String, dynamic>;
            final folderId = filtered[index].id;
            final name = data['name'] as String? ?? 'Folder';
            final count = data['itemCount'] ?? 0;
            final color = colors[index % colors.length];
            final isLocked = data['locked'] == true || data['updating'] == true;
            final hasFullAccess = accessibleIds.contains(folderId);
            final hasPartialAccess = !hasFullAccess && _contentAccess.containsKey(folderId);
            final partialCount = hasPartialAccess ? (_contentAccess[folderId]?.length ?? 0) : 0;

            final contentAccessSet = hasFullAccess ? null : (_contentAccess[folderId]?.toList());
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: isLocked
                    ? null
                    : () => context.push('/folders/$folderId', extra: {
                        'canEdit': true, 'canManage': true,
                        if (contentAccessSet != null) 'assistantContentAccess': contentAccessSet,
                      }),
                child: GlassmorphicContainer(
                  padding: const EdgeInsets.all(16),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: (isLocked ? Colors.grey : color).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.folder_rounded, color: isLocked ? Colors.grey : color, size: 36),
                    ),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: TextStyle(color: isLocked ? (isDark ? Colors.white38 : Colors.black38) : (isDark ? Colors.white : Colors.black87), fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 3),
                      if (isLocked)
                        const Row(children: [Icon(Icons.lock_rounded, color: Colors.redAccent, size: 12), SizedBox(width: 4), Text('Locked', style: TextStyle(color: Colors.redAccent, fontSize: 12))])
                      else if (hasFullAccess)
                        Text('$count items • Full access', style: TextStyle(color: isDark ? Colors.greenAccent.shade200 : Colors.green.shade700, fontSize: 12))
                      else
                        Text('$partialCount items • Partial access', style: TextStyle(color: isDark ? Colors.orange.shade200 : Colors.deepOrange.shade700, fontSize: 12)),
                    ])),
                    if (!isLocked)
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.edit_rounded, color: Colors.green, size: 18),
                      ),
                  ]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}