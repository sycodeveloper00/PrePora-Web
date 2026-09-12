import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AssistantCloudinaryScreen extends StatefulWidget {
  final String? assistantUid;
  final String? assistantName;
  const AssistantCloudinaryScreen({super.key, this.assistantUid, this.assistantName});
  @override
  State<AssistantCloudinaryScreen> createState() => _AssistantCloudinaryScreenState();
}

class _AssistantCloudinaryScreenState extends State<AssistantCloudinaryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _cloudinaryAccounts = [];
  List<Map<String, dynamic>> _assistants = [];

  bool get _isScoped => widget.assistantUid != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await FirebaseService.getAssistantCloudinaryAccounts();
    if (_isScoped) {
      final scoped = all.where((a) => a['assistantUid'] == widget.assistantUid).toList();
      scoped.sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt'] as String? ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['createdAt'] as String? ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      if (mounted) setState(() {
        _cloudinaryAccounts = scoped;
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
        _cloudinaryAccounts = all;
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
          _isScoped ? '${widget.assistantName ?? "Assistant"} Cloudinary' : 'Assistant Cloudinary',
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
                    Text('Tap an assistant to manage their Cloudinary accounts', style: TextStyle(color: hintColor, fontSize: 12)),
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
            final accounts = _cloudinaryAccounts.where((a) => a['assistantUid'] == uid).toList();
            final active = accounts.where((a) => a['isActive'] == true).toList();
            final activeCloudName = active.isNotEmpty ? (active.first['cloudName'] as String? ?? '') : '';
            final statusText = accounts.isEmpty
                ? 'No Cloudinary assigned'
                : (activeCloudName.isNotEmpty ? activeCloudName : '${accounts.length} account(s), none active');
            return InkWell(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AssistantCloudinaryScreen(assistantUid: uid, assistantName: name)));
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
                      Text(statusText, style: TextStyle(color: activeCloudName.isNotEmpty ? Colors.deepPurple : hintColor, fontSize: 12), overflow: TextOverflow.ellipsis),
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
                  const Icon(Icons.cloud_upload_rounded, color: Colors.deepPurple),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Cloudinary Accounts', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                        Text(widget.assistantName == null ? 'Per-assistant Cloudinary storage' : 'Accounts for ${widget.assistantName}', style: TextStyle(color: hintColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_rounded, color: Colors.deepPurple, size: 28),
                    onPressed: () => _showAddAssistantCloudinaryDialog(),
                  ),
                ]),
                const SizedBox(height: 8),
                if (_cloudinaryAccounts.isEmpty)
                  _emptyState('No assistant Cloudinary accounts', 'Assign Cloudinary accounts to assistants', Icons.person_add_rounded, isDark, hintColor)
                else
                  ...List.generate(_cloudinaryAccounts.length, (i) {
                    final acc = _cloudinaryAccounts[i];
                    final isActive = acc['isActive'] as bool? ?? false;
                    final assistantName = acc['assistantName'] as String? ?? 'Unknown';
                    return _cloudinaryAccountTile(
                      acc: acc, isActive: isActive, assistantName: assistantName,
                      textColor: textColor, hintColor: hintColor, isDark: isDark,
                      onToggle: () async {
                        if (isActive) return;
                        setState(() {
                          for (final a in _cloudinaryAccounts) {
                            if (a['assistantUid'] == acc['assistantUid']) {
                              a['isActive'] = (a['id'] == acc['id']);
                            }
                          }
                        });
                        try {
                          await FirebaseService.updateAssistantCloudinaryAccount(acc['id'], isActive: true);
                        } catch (_) {}
                        _load();
                      },
                      onEdit: () => _showEditAssistantCloudinaryDialog(acc),
                      onDelete: () => _showDeleteAssistantCloudinaryDialog(acc),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _cloudinaryAccountTile({
    required Map<String, dynamic> acc, required bool isActive,
    required String assistantName,
    required Color textColor, required Color hintColor, required bool isDark,
    required VoidCallback onToggle, required VoidCallback onEdit, required VoidCallback onDelete,
  }) {
    final cloudName = acc['cloudName'] as String? ?? '';
    final uploadPreset = acc['uploadPreset'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.deepPurple.withValues(alpha: 0.06) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? Colors.deepPurple.withValues(alpha: 0.3) : (isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.deepPurple : Colors.redAccent.withValues(alpha: 0.5))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(cloudName, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.deepPurple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(assistantName, style: const TextStyle(color: Colors.deepPurple, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: isActive ? Colors.green.withValues(alpha: 0.15) : Colors.redAccent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(isActive ? 'Active' : 'Inactive', style: TextStyle(color: isActive ? Colors.green : Colors.redAccent, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ]),
            const SizedBox(height: 4),
            Text('Preset: $uploadPreset', style: TextStyle(color: hintColor, fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 8),
        Switch(value: isActive, activeColor: Colors.deepPurple, onChanged: (_) => onToggle()),
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
        color: Colors.deepPurple.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Icon(icon, size: 32, color: Colors.deepPurple.withValues(alpha: 0.4)),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(color: hintColor, fontSize: 13)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 11)),
      ]),
    );
  }

  void _showAddAssistantCloudinaryDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cloudNameCtrl = TextEditingController();
    final uploadPresetCtrl = TextEditingController();
    final scopedUid = widget.assistantUid;
    final scopedName = widget.assistantName;
    String? selectedUid = scopedUid;
    String selectedName = scopedName ?? '';
    bool isLoading = false;

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.person_add_rounded, color: Colors.deepPurple, size: 22), const SizedBox(width: 8), Text('Add Assistant Cloudinary', style: TextStyle(color: baseColor, fontSize: 15))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                decoration: BoxDecoration(color: Colors.deepPurple.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.person_rounded, color: Colors.deepPurple, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(scopedName ?? 'Assistant', style: TextStyle(color: baseColor, fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 12),
            TextField(controller: cloudNameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', hintText: 'dxxxxxxxx', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: uploadPresetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', hintText: 'your_upload_preset', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 8),
            Text('Create an unsigned upload preset in Cloudinary dashboard.', style: TextStyle(color: dimColor, fontSize: 11)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              if (selectedUid == null || cloudNameCtrl.text.trim().isEmpty || uploadPresetCtrl.text.trim().isEmpty) return;
              setDialog(() => isLoading = true);
              await FirebaseService.addAssistantCloudinaryAccount(
                assistantUid: selectedUid!, assistantName: selectedName,
                cloudName: cloudNameCtrl.text.trim(), uploadPreset: uploadPresetCtrl.text.trim(),
              );
              if (d.mounted) Navigator.pop(d);
              _load();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }));
  }

  void _showEditAssistantCloudinaryDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cloudNameCtrl = TextEditingController(text: acc['cloudName'] as String? ?? '');
    final uploadPresetCtrl = TextEditingController(text: acc['uploadPreset'] as String? ?? '');
    final assistantName = acc['assistantName'] as String? ?? 'Unknown';

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.deepPurple, size: 22), const SizedBox(width: 8), Text('Edit $assistantName Cloudinary', style: TextStyle(color: baseColor, fontSize: 15))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cloudNameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: uploadPresetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(onPressed: () async {
            if (cloudNameCtrl.text.trim().isEmpty || uploadPresetCtrl.text.trim().isEmpty) return;
            await FirebaseService.updateAssistantCloudinaryAccount(
              acc['id'],
              cloudName: cloudNameCtrl.text.trim(),
              uploadPreset: uploadPresetCtrl.text.trim(),
            );
            if (d.mounted) Navigator.pop(d); _load();
          }, style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple), child: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      );
    }));
  }

  void _showDeleteAssistantCloudinaryDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final assistantName = acc['assistantName'] as String? ?? 'Unknown';
    final cloudName = acc['cloudName'] as String? ?? '';
    final assistantUid = acc['assistantUid'] as String? ?? '';
    final isActive = acc['isActive'] as bool? ?? false;
    final activeCount = _cloudinaryAccounts.where((a) => a['assistantUid'] == assistantUid && a['isActive'] == true).length;
    if (isActive && activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot delete $assistantName\'s only active Cloudinary account.'), backgroundColor: Colors.orange));
      return;
    }
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 8), Text('Delete Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(width: 400, child: Text('Delete $assistantName\'s Cloudinary account ($cloudName)?', style: TextStyle(color: dimColor, fontSize: 13))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteAssistantCloudinaryAccount(acc['id']);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
}
