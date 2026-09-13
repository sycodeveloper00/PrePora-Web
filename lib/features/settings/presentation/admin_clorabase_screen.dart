import 'package:flutter/material.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/clorabase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AdminClorabaseScreen extends StatefulWidget {
  const AdminClorabaseScreen({super.key});
  @override
  State<AdminClorabaseScreen> createState() => _AdminClorabaseScreenState();
}

class _AdminClorabaseScreenState extends State<AdminClorabaseScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _clorabaseAccounts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await FirebaseService.getClorabaseAccounts();
    if (mounted) setState(() {
      _clorabaseAccounts = accounts ?? [];
      _clorabaseAccounts.sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt'] as String? ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['createdAt'] as String? ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Clorabase', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: ProfessionalLoader())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.cloud_upload_rounded, color: Colors.orange),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Clorabase Accounts', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                                Text('${_clorabaseAccounts.length} account(s) \u00b7 GitHub-backed storage', style: TextStyle(color: hintColor, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_rounded, color: Colors.orange, size: 28),
                            onPressed: () => _showAddClorabaseDialog(),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        if (_clorabaseAccounts.isEmpty)
                          _emptyState('No Clorabase accounts', 'Tap + to add your first Clorabase account', Icons.cloud_upload_outlined, isDark, hintColor)
                        else
                          ...List.generate(_clorabaseAccounts.length, (i) {
                            final acc = _clorabaseAccounts[i];
                            final isActive = acc['isActive'] as bool? ?? false;
                            return _clorabaseAccountTile(
                              acc: acc, isActive: isActive,
                              textColor: textColor, hintColor: hintColor, isDark: isDark,
                              onToggle: () async {
                                if (isActive) return;
                                setState(() {
                                  for (final a in _clorabaseAccounts) {
                                    a['isActive'] = (a['id'] == acc['id']);
                                  }
                                });
                                try {
                                  await FirebaseService.updateClorabaseAccount(acc['id'], isActive: true);
                                } catch (e) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Failed to switch account'), backgroundColor: Colors.redAccent),
                                  );
                                  return;
                                }
                                await _load();
                              },
                              onEdit: () => _showEditClorabaseDialog(acc),
                              onDelete: () => _showDeleteClorabaseDialog(acc),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _emptyState(String title, String subtitle, IconData icon, bool isDark, Color hintColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Icon(icon, size: 32, color: Colors.orange.withValues(alpha: 0.4)),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(color: hintColor, fontSize: 13)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 11)),
      ]),
    );
  }

  Widget _clorabaseAccountTile({
    required Map<String, dynamic> acc, required bool isActive,
    required Color textColor, required Color hintColor, required bool isDark,
    required VoidCallback onToggle, required VoidCallback onEdit, required VoidCallback onDelete,
  }) {
    final githubUsername = acc['githubUsername'] as String? ?? '';
    final projectName = acc['projectName'] as String? ?? '';
    final repoName = acc['repoName'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.orange.withValues(alpha: 0.06) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? Colors.orange.withValues(alpha: 0.3) : (isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Column(children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.orange : Colors.redAccent.withValues(alpha: 0.5))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text('@$githubUsername', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(isActive ? 'Active' : 'Inactive', style: TextStyle(color: isActive ? Colors.orange : hintColor, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 2),
              Text('Project: $projectName', style: TextStyle(color: hintColor, fontSize: 11)),
              if (repoName.isNotEmpty) Text('Repo: $repoName', style: TextStyle(color: hintColor, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(value: isActive, activeColor: Colors.orange, onChanged: (_) => onToggle()),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, size: 18, color: hintColor),
            onSelected: (v) { if (v == 'edit') onEdit(); if (v == 'delete') onDelete(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 8), Text('Edit')])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, size: 16, color: Colors.redAccent), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.redAccent))])),
            ],
          ),
        ]),
      ]),
    );
  }

  void _showAddClorabaseDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final usernameCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final projectCtrl = TextEditingController();
    final repoCtrl = TextEditingController();
    bool isActive = true;
    bool isLoading = false;
    String? errorMsg;

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.cloud_upload_rounded, color: Colors.orange, size: 22), const SizedBox(width: 8), Text('Add Clorabase Account', style: TextStyle(color: baseColor, fontSize: 16))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [const Icon(Icons.error_outline, color: Colors.redAccent, size: 16), const SizedBox(width: 8), Expanded(child: Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)))]),
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: usernameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'GitHub Username', hintText: 'your_github_username', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: tokenCtrl, style: TextStyle(color: baseColor), maxLines: 2, decoration: InputDecoration(labelText: 'GitHub PAT (Personal Access Token)', hintText: 'ghp_xxxxxxxxxxxx', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: projectCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project Name', hintText: 'my_project', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: repoCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'GitHub Repo Name', hintText: 'Clorabase-projects', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 4),
            Text('Repo where files will be stored. Created automatically if missing.', style: TextStyle(color: dimColor, fontSize: 10)),
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(value: isActive, activeColor: Colors.orange, onChanged: (v) => setDialog(() => isActive = v ?? true)),
              Expanded(child: Text('Set as active account', style: TextStyle(color: baseColor, fontSize: 13))),
            ]),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Requirements:', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text('\u2022 GitHub account with a repo (name entered above)', style: TextStyle(color: dimColor, fontSize: 10)),
                Text('\u2022 PAT with "repo" scope (Full control of private repositories)', style: TextStyle(color: dimColor, fontSize: 10)),
                Text('\u2022 Max file size: 50 MB (regular) / 2 GB (blob)', style: TextStyle(color: dimColor, fontSize: 10)),
              ]),
            ),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              if (usernameCtrl.text.trim().isEmpty || tokenCtrl.text.trim().isEmpty || projectCtrl.text.trim().isEmpty) return;
              setDialog(() { isLoading = true; errorMsg = null; });
              final verifyResult = await ClorabaseService.verifyCredentials(
                username: usernameCtrl.text.trim(),
                token: tokenCtrl.text.trim(),
                repoName: repoCtrl.text.trim().isNotEmpty ? repoCtrl.text.trim() : null,
              );
              if (verifyResult['valid'] == true) {
                await FirebaseService.addClorabaseAccount(
                  usernameCtrl.text.trim(),
                  tokenCtrl.text.trim(),
                  projectCtrl.text.trim(),
                  repoName: repoCtrl.text.trim().isNotEmpty ? repoCtrl.text.trim() : null,
                  isActive: isActive,
                );
                if (d.mounted) Navigator.pop(d);
                _load();
                return;
              }
              setDialog(() { isLoading = false; errorMsg = verifyResult['error'] as String? ?? 'Verification failed'; });
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save & Verify', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }));
  }

  void _showEditClorabaseDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final usernameCtrl = TextEditingController(text: acc['githubUsername'] as String? ?? '');
    final tokenCtrl = TextEditingController(text: acc['githubToken'] as String? ?? '');
    final projectCtrl = TextEditingController(text: acc['projectName'] as String? ?? '');
    final repoCtrl = TextEditingController(text: acc['repoName'] as String? ?? '');

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.orange, size: 22), const SizedBox(width: 8), Text('Edit Clorabase Account', style: TextStyle(color: baseColor, fontSize: 16))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: usernameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'GitHub Username', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: tokenCtrl, style: TextStyle(color: baseColor), maxLines: 2, decoration: InputDecoration(labelText: 'GitHub PAT', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: projectCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: repoCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'GitHub Repo Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(onPressed: () async {
            if (usernameCtrl.text.trim().isEmpty || tokenCtrl.text.trim().isEmpty || projectCtrl.text.trim().isEmpty) return;
            await FirebaseService.updateClorabaseAccount(
              acc['id'],
              githubUsername: usernameCtrl.text.trim(),
              githubToken: tokenCtrl.text.trim(),
              projectName: projectCtrl.text.trim(),
              repoName: repoCtrl.text.trim().isNotEmpty ? repoCtrl.text.trim() : null,
            );
            if (d.mounted) Navigator.pop(d); _load();
          }, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      );
    }));
  }

  void _showDeleteClorabaseDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final githubUsername = acc['githubUsername'] as String? ?? '';
    final isActive = acc['isActive'] as bool? ?? false;
    final activeCount = _clorabaseAccounts.where((a) => a['isActive'] == true).length;
    if (isActive && activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the only active account. Add another first.'), backgroundColor: Colors.orange));
      return;
    }
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 8), Text('Delete Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(width: 400, child: Text('Delete Clorabase account "@$githubUsername"? This cannot be undone.', style: TextStyle(color: dimColor, fontSize: 13))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteClorabaseAccount(acc['id']);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
}
