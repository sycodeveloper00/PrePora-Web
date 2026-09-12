import 'package:flutter/material.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AdminCloudinaryScreen extends StatefulWidget {
  const AdminCloudinaryScreen({super.key});
  @override
  State<AdminCloudinaryScreen> createState() => _AdminCloudinaryScreenState();
}

class _AdminCloudinaryScreenState extends State<AdminCloudinaryScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _cloudinaryAccounts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final accounts = await FirebaseService.getCloudinaryAccounts();
    if (mounted) setState(() {
      _cloudinaryAccounts = accounts ?? [];
      _cloudinaryAccounts.sort((a, b) {
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
        title: const Text('Admin Cloudinary', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          const Icon(Icons.cloud_upload_rounded, color: Colors.deepPurple),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Cloudinary Accounts', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                                Text('${_cloudinaryAccounts.length} account(s) \u00b7 One active at a time', style: TextStyle(color: hintColor, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_rounded, color: Colors.deepPurple, size: 28),
                            onPressed: () => _showAddCloudinaryDialog(),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        if (_cloudinaryAccounts.isEmpty)
                          _emptyState('No Cloudinary accounts', 'Tap + to add your first Cloudinary account', Icons.cloud_upload_outlined, isDark, hintColor)
                        else
                          ...List.generate(_cloudinaryAccounts.length, (i) {
                            final acc = _cloudinaryAccounts[i];
                            final isActive = acc['isActive'] as bool? ?? false;
                            return _cloudinaryAccountTile(
                              acc: acc, isActive: isActive,
                              textColor: textColor, hintColor: hintColor, isDark: isDark,
                              onToggle: () async {
                                if (isActive) return;
                                setState(() {
                                  for (final a in _cloudinaryAccounts) {
                                    a['isActive'] = (a['id'] == acc['id']);
                                  }
                                });
                                try {
                                  await FirebaseService.updateCloudinaryAccount(acc['id'], isActive: true);
                                } catch (e) {
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Failed to switch account'), backgroundColor: Colors.redAccent),
                                  );
                                  return;
                                }
                                await _load();
                              },
                              onEdit: () => _showEditCloudinaryDialog(acc),
                              onDelete: () => _showDeleteCloudinaryDialog(acc),
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

  Widget _cloudinaryAccountTile({
    required Map<String, dynamic> acc, required bool isActive,
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
      child: Column(children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.deepPurple : Colors.redAccent.withValues(alpha: 0.5))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(cloudName, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.deepPurple.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(isActive ? 'Active' : 'Inactive', style: TextStyle(color: isActive ? Colors.deepPurple : hintColor, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 2),
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
      ]),
    );
  }

  void _showAddCloudinaryDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cloudNameCtrl = TextEditingController();
    final uploadPresetCtrl = TextEditingController();
    bool isActive = true;
    bool isLoading = false;

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.cloud_upload_rounded, color: Colors.deepPurple, size: 22), const SizedBox(width: 8), Text('Add Cloudinary Account', style: TextStyle(color: baseColor, fontSize: 16))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: cloudNameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', hintText: 'dxxxxxxxx', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: uploadPresetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', hintText: 'your_upload_preset', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            Row(children: [
              Checkbox(value: isActive, activeColor: Colors.deepPurple, onChanged: (v) => setDialog(() => isActive = v ?? true)),
              Expanded(child: Text('Set as active account', style: TextStyle(color: baseColor, fontSize: 13))),
            ]),
            const SizedBox(height: 8),
            Text('Create an unsigned upload preset in your Cloudinary dashboard (Settings \u2192 Upload \u2192 Upload presets).', style: TextStyle(color: dimColor, fontSize: 11)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              if (cloudNameCtrl.text.trim().isEmpty || uploadPresetCtrl.text.trim().isEmpty) return;
              setDialog(() => isLoading = true);
              await FirebaseService.addCloudinaryAccount(
                cloudNameCtrl.text.trim(),
                uploadPresetCtrl.text.trim(),
                isActive: isActive,
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

  void _showEditCloudinaryDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cloudNameCtrl = TextEditingController(text: acc['cloudName'] as String? ?? '');
    final uploadPresetCtrl = TextEditingController(text: acc['uploadPreset'] as String? ?? '');

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.deepPurple, size: 22), const SizedBox(width: 8), Text('Edit Cloudinary Account', style: TextStyle(color: baseColor, fontSize: 16))]),
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
            await FirebaseService.updateCloudinaryAccount(
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

  void _showDeleteCloudinaryDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cloudName = acc['cloudName'] as String? ?? '';
    final isActive = acc['isActive'] as bool? ?? false;
    final activeCount = _cloudinaryAccounts.where((a) => a['isActive'] == true).length;
    if (isActive && activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the only active account. Add another first.'), backgroundColor: Colors.orange));
      return;
    }
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 8), Text('Delete Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(width: 400, child: Text('Delete Cloudinary account "$cloudName"? This cannot be undone.', style: TextStyle(color: dimColor, fontSize: 13))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteCloudinaryAccount(acc['id']);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
}
