import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/clorabase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AssistantClorabaseScreen extends StatefulWidget {
  final String? assistantUid;
  final String? assistantName;
  const AssistantClorabaseScreen({super.key, this.assistantUid, this.assistantName});
  @override
  State<AssistantClorabaseScreen> createState() => _AssistantClorabaseScreenState();
}

class _AssistantClorabaseScreenState extends State<AssistantClorabaseScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _clorabaseAccounts = [];
  List<Map<String, dynamic>> _assistants = [];

  bool get _isScoped => widget.assistantUid != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await FirebaseService.getAssistantClorabaseAccounts();
    if (_isScoped) {
      final scoped = all.where((a) => a['assistantUid'] == widget.assistantUid).toList();
      scoped.sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt'] as String? ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['createdAt'] as String? ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      if (mounted) setState(() {
        _clorabaseAccounts = scoped;
        _loading = false;
      });
    } else {
      final snap = await FirebaseService.getAllAssistant().first;
      final assistants = snap.docs.map((e) => {'id': e.id, ...(e.data() as Map<String, dynamic>)}).toList();
      all.sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt'] as String? ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['createdAt'] as String? ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      if (mounted) setState(() {
        _assistants = assistants;
        _clorabaseAccounts = all;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isScoped ? '${widget.assistantName ?? "Assistant"} Clorabase' : 'Assistant Clorabase',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: ProfessionalLoader())
          : _isScoped
              ? _buildAccountsView(isDark, textColor, hintColor)
              : _buildAssistantsList(isDark, textColor, hintColor),
    );
  }

  Widget _buildAssistantsList(bool isDark, Color textColor, Color hintColor) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              const Icon(Icons.people_rounded, color: Colors.orange),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Assistants', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                    Text('Tap an assistant to manage their Clorabase accounts', style: TextStyle(color: hintColor, fontSize: 12)),
                  ],
                ),
              ),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        if (_assistants.isEmpty)
          _emptyState('No assistants found', 'Create assistants from the admin panel', Icons.person_off_rounded, isDark, hintColor)
        else
          ...List.generate(_assistants.length, (i) {
            final assistant = _assistants[i];
            final uid = assistant['id'] as String;
            final name = assistant['name'] as String? ?? 'Unknown';
            final accounts = _clorabaseAccounts.where((a) => a['assistantUid'] == uid).toList();
            final active = accounts.where((a) => a['isActive'] == true).toList();
            final activeUsername = active.isNotEmpty ? (active.first['githubUsername'] as String? ?? '') : '';
            final statusText = accounts.isEmpty
                ? 'No Clorabase assigned'
                : (activeUsername.isNotEmpty ? '@$activeUsername' : '${accounts.length} account(s), none active');
            return InkWell(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AssistantClorabaseScreen(assistantUid: uid, assistantName: name)));
                _load();
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.05 : 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.1 : 0.08)),
                ),
                child: Row(children: [
                  CircleAvatar(backgroundColor: Colors.orange.withValues(alpha: isDark ? 0.2 : 0.1), child: const Icon(Icons.person, color: Colors.orange, size: 20)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 2),
                      Text(statusText, style: TextStyle(color: activeUsername.isNotEmpty ? Colors.orange : hintColor, fontSize: 12), overflow: TextOverflow.ellipsis),
                    ]),
                  ),
                  Icon(Icons.chevron_right_rounded, color: hintColor, size: 22),
                ]),
              ),
            );
          }),
      ],
    );
  }

  Widget _buildAccountsView(bool isDark, Color textColor, Color hintColor) {
    return ListView(
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
                        Text(widget.assistantName == null ? 'Per-assistant Clorabase storage' : 'Accounts for ${widget.assistantName}', style: TextStyle(color: hintColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_rounded, color: Colors.orange, size: 28),
                    onPressed: () => _showAddAssistantClorabaseDialog(),
                  ),
                ]),
                const SizedBox(height: 8),
                if (_clorabaseAccounts.isEmpty)
                  _emptyState('No assistant Clorabase accounts', 'Assign Clorabase accounts to assistants', Icons.person_add_rounded, isDark, hintColor)
                else
                  ...List.generate(_clorabaseAccounts.length, (i) {
                    final acc = _clorabaseAccounts[i];
                    final isActive = acc['isActive'] as bool? ?? false;
                    final assistantName = acc['assistantName'] as String? ?? 'Unknown';
                    return _clorabaseAccountTile(
                      acc: acc, isActive: isActive, assistantName: assistantName,
                      textColor: textColor, hintColor: hintColor, isDark: isDark,
                      onToggle: () async {
                        if (isActive) return;
                        setState(() {
                          for (final a in _clorabaseAccounts) {
                            if (a['assistantUid'] == acc['assistantUid']) {
                              a['isActive'] = (a['id'] == acc['id']);
                            }
                          }
                        });
                        try {
                          await FirebaseService.updateAssistantClorabaseAccount(acc['id'], isActive: true);
                        } catch (_) {}
                        _load();
                      },
                      onEdit: () => _showEditAssistantClorabaseDialog(acc),
                      onDelete: () => _showDeleteAssistantClorabaseDialog(acc),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _clorabaseAccountTile({
    required Map<String, dynamic> acc, required bool isActive,
    required String assistantName,
    required Color textColor, required Color hintColor, required bool isDark,
    required VoidCallback onToggle, required VoidCallback onEdit, required VoidCallback onDelete,
  }) {
    final githubUsername = acc['githubUsername'] as String? ?? '';
    final projectName = acc['projectName'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.orange.withValues(alpha: 0.06) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? Colors.orange.withValues(alpha: 0.3) : (isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.orange : Colors.redAccent.withValues(alpha: 0.5))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('@$githubUsername', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(assistantName, style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: isActive ? Colors.green.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(isActive ? 'Active' : 'Inactive', style: TextStyle(color: isActive ? Colors.green : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Project: $projectName', style: TextStyle(color: hintColor, fontSize: 11)),
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

  void _showAddAssistantClorabaseDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final usernameCtrl = TextEditingController();
    final tokenCtrl = TextEditingController();
    final projectCtrl = TextEditingController();
    final scopedUid = widget.assistantUid;
    final scopedName = widget.assistantName;
    String? selectedUid = scopedUid;
    String selectedName = scopedName ?? '';
    bool isLoading = false;
    String? errorMsg;

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.person_add_rounded, color: Colors.orange, size: 22), const SizedBox(width: 8), Text('Add Assistant Clorabase', style: TextStyle(color: baseColor, fontSize: 15))]),
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
            if (scopedUid == null)
              StreamBuilder<QuerySnapshot>(
                stream: FirebaseService.getAllAssistant(),
                builder: (ctx, snap) {
                  if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                  final docs = snap.data!.docs;
                  if (docs.isEmpty) return Text('No assistants found', style: TextStyle(color: dimColor));
                  final assistants = docs.map((e) => {'id': e.id, ...(e.data() as Map<String, dynamic>)}).toList();
                  return DropdownButtonFormField<String>(
                    isExpanded: true, value: selectedUid,
                    dropdownColor: isDark ? const Color(0xFF2A2A2A) : Colors.white,
                    style: TextStyle(color: baseColor),
                    decoration: InputDecoration(labelText: 'Select Assistant', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                    items: assistants.map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['name'] as String? ?? 'Unknown'))).toList(),
                    onChanged: (v) { final match = assistants.firstWhere((a) => a['id'] == v, orElse: () => {}); setDialog(() { selectedUid = v; selectedName = match['name'] as String? ?? ''; }); },
                  );
                },
              )
            else
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.person_rounded, color: Colors.orange, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(scopedName ?? 'Assistant', style: TextStyle(color: baseColor, fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 12),
            TextField(controller: usernameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'GitHub Username', hintText: 'your_github_username', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: tokenCtrl, style: TextStyle(color: baseColor), maxLines: 2, decoration: InputDecoration(labelText: 'GitHub PAT', hintText: 'ghp_xxxxxxxxxxxx', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: projectCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project Name', hintText: 'my_project', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 8),
            Text('Requires "Clorabase-projects" repo + PAT with "repo" scope.', style: TextStyle(color: dimColor, fontSize: 11)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              if (selectedUid == null || usernameCtrl.text.trim().isEmpty || tokenCtrl.text.trim().isEmpty || projectCtrl.text.trim().isEmpty) return;
              setDialog(() { isLoading = true; errorMsg = null; });
              final verifyResult = await ClorabaseService.verifyCredentials(
                username: usernameCtrl.text.trim(),
                token: tokenCtrl.text.trim(),
              );
              if (verifyResult['valid'] == true) {
                await FirebaseService.addAssistantClorabaseAccount(
                  assistantUid: selectedUid!, assistantName: selectedName,
                  githubUsername: usernameCtrl.text.trim(),
                  githubToken: tokenCtrl.text.trim(),
                  projectName: projectCtrl.text.trim(),
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

  void _showEditAssistantClorabaseDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final usernameCtrl = TextEditingController(text: acc['githubUsername'] as String? ?? '');
    final tokenCtrl = TextEditingController(text: acc['githubToken'] as String? ?? '');
    final projectCtrl = TextEditingController(text: acc['projectName'] as String? ?? '');
    final assistantName = acc['assistantName'] as String? ?? 'Unknown';

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.orange, size: 22), const SizedBox(width: 8), Text('Edit $assistantName Clorabase', style: TextStyle(color: baseColor, fontSize: 15))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: usernameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'GitHub Username', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: tokenCtrl, style: TextStyle(color: baseColor), maxLines: 2, decoration: InputDecoration(labelText: 'GitHub PAT', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: projectCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(onPressed: () async {
            if (usernameCtrl.text.trim().isEmpty || tokenCtrl.text.trim().isEmpty || projectCtrl.text.trim().isEmpty) return;
            await FirebaseService.updateAssistantClorabaseAccount(
              acc['id'],
              githubUsername: usernameCtrl.text.trim(),
              githubToken: tokenCtrl.text.trim(),
              projectName: projectCtrl.text.trim(),
            );
            if (d.mounted) Navigator.pop(d); _load();
          }, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), child: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      );
    }));
  }

  void _showDeleteAssistantClorabaseDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final assistantName = acc['assistantName'] as String? ?? 'Unknown';
    final githubUsername = acc['githubUsername'] as String? ?? '';
    final assistantUid = acc['assistantUid'] as String? ?? '';
    final isActive = acc['isActive'] as bool? ?? false;
    final activeCount = _clorabaseAccounts.where((a) => a['assistantUid'] == assistantUid && a['isActive'] == true).length;
    if (isActive && activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot delete $assistantName\'s only active Clorabase account.'), backgroundColor: Colors.orange));
      return;
    }
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 8), Text('Delete Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(width: 400, child: Text('Delete $assistantName\'s Clorabase account (@$githubUsername)?', style: TextStyle(color: dimColor, fontSize: 13))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteAssistantClorabaseAccount(acc['id']);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
}
