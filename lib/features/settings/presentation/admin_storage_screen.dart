import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AdminStorageScreen extends StatefulWidget {
  const AdminStorageScreen({super.key});
  @override
  State<AdminStorageScreen> createState() => _AdminStorageScreenState();
}

class _AdminStorageScreenState extends State<AdminStorageScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _supabaseAccounts = [];
  List<Map<String, dynamic>> _cloudinaryAccounts = [];
  final Map<String, Map<String, dynamic>> _storageUsage = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final supabaseAccounts = await FirebaseService.getSupabaseAccounts();
    final cloudinaryAccounts = await FirebaseService.getCloudinaryAccounts();
    if (mounted) setState(() {
      final seen = <String>{};
      _supabaseAccounts = (supabaseAccounts ?? []).where((a) {
        final url = a['projectUrl'] as String? ?? '';
        if (url.isEmpty || !url.contains('supabase')) return false;
        if (seen.contains(url)) return false;
        seen.add(url);
        return true;
      }).toList();
      _supabaseAccounts.sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt'] as String? ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['createdAt'] as String? ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      _cloudinaryAccounts = cloudinaryAccounts ?? [];
      _cloudinaryAccounts.sort((a, b) {
        final aTime = DateTime.tryParse(a['createdAt'] as String? ?? '') ?? DateTime(1970);
        final bTime = DateTime.tryParse(b['createdAt'] as String? ?? '') ?? DateTime(1970);
        return bTime.compareTo(aTime);
      });
      _loading = false;
    });
    _loadStorageUsage();
  }

  Future<void> _loadStorageUsage() async {
    for (final acc in _supabaseAccounts) {
      final url = acc['projectUrl'] as String? ?? '';
      final key = acc['serviceRoleKey'] as String? ?? '';
      if (url.isEmpty || key.isEmpty) continue;
      try {
        final usage = await FirebaseService.getStorageUsage(url, key);
        if (mounted) setState(() { _storageUsage[acc['id'] as String] = usage; });
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Storage', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: ProfessionalLoader())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─── Supabase Section ─────────────────────────────────
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          const Icon(Icons.storage_rounded, color: Colors.green),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Supabase Accounts', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                                Text('${_supabaseAccounts.length} account(s) \u00b7 One active at a time', style: TextStyle(color: hintColor, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_rounded, color: Colors.green, size: 28),
                            onPressed: () => _showAddSupabaseDialog(),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        if (_supabaseAccounts.isEmpty)
                          _emptyState('No Supabase accounts', 'Tap + to add your first Supabase account', Icons.storage_outlined, isDark, hintColor, Colors.green)
                        else
                          ...List.generate(_supabaseAccounts.length, (i) {
                            final acc = _supabaseAccounts[i];
                            final isActive = acc['isActive'] as bool? ?? false;
                            final bucketStatus = acc['bucketStatus'] as String? ?? 'pending';
                            final failedBuckets = (acc['failedBuckets'] as List?)?.cast<String>() ?? [];
                            final accId = acc['id'] as String;
                            final usage = _storageUsage[accId];
                            return _supabaseAccountTile(
                              acc: acc, isActive: isActive, bucketStatus: bucketStatus, failedBuckets: failedBuckets,
                              usage: usage,
                              textColor: textColor, hintColor: hintColor, isDark: isDark,
                              onToggle: () async {
                                if (isActive) return;
                                final prevAccounts = List<Map<String, dynamic>>.from(_supabaseAccounts);
                                setState(() {
                                  for (final a in _supabaseAccounts) {
                                    a['isActive'] = (a['id'] == acc['id']);
                                  }
                                });
                                try {
                                  await FirebaseService.updateSupabaseAccount(acc['id'], isActive: true);
                                  await FirebaseService.reinitializeSupabase();
                                } catch (e) {
                                  if (mounted) setState(() { _supabaseAccounts = prevAccounts; });
                                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Failed to switch account'), backgroundColor: Colors.redAccent),
                                  );
                                  return;
                                }
                                await _load();
                              },
                              onRetry: () async {
                                final result = await FirebaseService.retryBucketCreation(acc['id']);
                                _load();
                                if (mounted) {
                                  final status = result['status'] as String? ?? 'failed';
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(status == 'ready' ? 'All buckets ready!' : 'Some buckets still failed. Create them manually.'),
                                    backgroundColor: status == 'ready' ? Colors.green : Colors.orange,
                                  ));
                                }
                              },
                              onVerify: () async {
                                if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Verifying buckets directly...'), backgroundColor: Colors.blue),
                                );
                                final result = await FirebaseService.retryBucketCreation(acc['id']);
                                _load();
                                if (mounted) {
                                  final status = result['status'] as String? ?? 'unknown';
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text(status == 'ready' ? 'Buckets verified and ready!' : 'Status: $status — use SQL if buckets need manual creation.'),
                                    backgroundColor: status == 'ready' ? Colors.green : Colors.orange,
                                  ));
                                }
                              },
                              onEdit: () => _showEditSupabaseDialog(acc),
                              onDelete: () => _showDeleteSupabaseDialog(acc),
                            );
                          }),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Cloudinary Section ───────────────────────────────
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
                          _emptyState('No Cloudinary accounts', 'Tap + to add your first Cloudinary account', Icons.cloud_upload_outlined, isDark, hintColor, Colors.deepPurple)
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

  Widget _emptyState(String title, String subtitle, IconData icon, bool isDark, Color hintColor, [Color? accentColor]) {
    final color = accentColor ?? Colors.green;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Icon(icon, size: 32, color: color.withValues(alpha: 0.4)),
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

  Widget _supabaseAccountTile({
    required Map<String, dynamic> acc, required bool isActive,
    required String bucketStatus, required List<String> failedBuckets,
    Map<String, dynamic>? usage,
    required Color textColor, required Color hintColor, required bool isDark,
    required VoidCallback onToggle, required VoidCallback onRetry, required VoidCallback onVerify,
    required VoidCallback onEdit, required VoidCallback onDelete,
  }) {
    final url = acc['projectUrl'] as String? ?? '';
    final displayUrl = url.replaceFirst('https://', '');
    final accName = acc['name'] as String? ?? '';
    final accEmail = acc['email'] as String? ?? '';
    final accProject = acc['projectName'] as String? ?? '';
    final hasFailed = bucketStatus == 'failed' || bucketStatus == 'partial';
    final usedBytes = usage?['usedBytes'] as int? ?? 0;
    final fileCount = usage?['fileCount'] as int? ?? 0;
    final usedMB = usedBytes / (1024 * 1024);
    final maxMB = (acc['storageLimitMB'] as int? ?? 1024).toDouble();
    final usageRatio = (usedMB / maxMB).clamp(0.0, 1.0);
    final usageColor = usageRatio > 0.8 ? Colors.redAccent : (usageRatio > 0.5 ? Colors.orange : Colors.green);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.withValues(alpha: 0.06) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? Colors.green.withValues(alpha: 0.3) : (isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Column(children: [
        Row(children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.green : Colors.redAccent.withValues(alpha: 0.5))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                accName.isNotEmpty ? accName : displayUrl,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w700, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
              Row(children: [
                if (bucketStatus == 'ready')
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: const Text('Ready', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                if (hasFailed) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(bucketStatus == 'partial' ? 'Partial' : 'Failed', style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: onRetry,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Icon(Icons.refresh_rounded, color: Colors.orange, size: 16),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: onVerify,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Text('Verify', style: TextStyle(color: Colors.blue, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () => _showSupabaseSqlDialog(url),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(color: Colors.cyan.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                      child: const Text('SQL', style: TextStyle(color: Colors.cyan, fontSize: 10, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ]),
              const SizedBox(height: 2),
              if (failedBuckets.isNotEmpty)
                Text('Buckets need setup: ${failedBuckets.join(', ')}', style: const TextStyle(color: Colors.orange, fontSize: 11)),
            ]),
          ),
          const SizedBox(width: 8),
          Switch(value: isActive, activeColor: Colors.green, onChanged: (_) => onToggle()),
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, size: 18, color: hintColor),
            onSelected: (v) { if (v == 'edit') onEdit(); if (v == 'delete') onDelete(); },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_rounded, size: 16), SizedBox(width: 8), Text('Edit')])),
              const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_rounded, size: 16, color: Colors.redAccent), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.redAccent))])),
            ],
          ),
        ]),
        if (usage != null) ...[
          const SizedBox(height: 8),
          Row(children: [
            Icon(Icons.cloud_rounded, size: 14, color: usageColor),
            const SizedBox(width: 6),
            Text('${usedMB.toStringAsFixed(1)}MB / ${maxMB.toStringAsFixed(0)}MB', style: TextStyle(color: usageColor, fontSize: 11, fontWeight: FontWeight.w600)),
            const Spacer(),
            Text('$fileCount files', style: TextStyle(color: hintColor, fontSize: 10)),
          ]),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: usageRatio,
              minHeight: 5,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(usageColor),
            ),
          ),
        ],
      ]),
    );
  }

  void _showAddSupabaseDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final urlCtrl = TextEditingController();
    final serviceKeyCtrl = TextEditingController();
    final anonKeyCtrl = TextEditingController();
    final storageLimitCtrl = TextEditingController(text: '1024');
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final projectCtrl = TextEditingController();
    bool autoSwitchEnabled = true;
    bool isLoading = false;
    String? errorMsg;

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.storage_rounded, color: Colors.green, size: 22), const SizedBox(width: 8), Text('Add Supabase Account', style: TextStyle(color: baseColor, fontSize: 16))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (errorMsg != null) ...[
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: errorMsg!.contains('530') ? Colors.orange.withValues(alpha: 0.1) : Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [Icon(errorMsg!.contains('530') ? Icons.warning_amber_rounded : Icons.error_outline, color: errorMsg!.contains('530') ? Colors.orangeAccent : Colors.redAccent, size: 16), const SizedBox(width: 8), Expanded(child: Text(errorMsg!, style: TextStyle(color: errorMsg!.contains('530') ? Colors.orangeAccent : Colors.redAccent, fontSize: 12)))]),
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Account Name', hintText: 'e.g. Main Project', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: emailCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Email', hintText: 'owner@email.com', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: projectCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project Name', hintText: 'e.g. PrePora', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project URL', hintText: 'https://xxx.supabase.co', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: serviceKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Service Role Key', hintText: 'eyJhbGciOi...', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: anonKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Anon Key', hintText: 'eyJhbGciOi...', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: storageLimitCtrl, style: TextStyle(color: baseColor), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Storage Limit (MB)', hintText: '1024 (1GB)', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 8),
            Row(children: [
              Checkbox(value: autoSwitchEnabled, activeColor: Colors.green, onChanged: (v) => setDialog(() => autoSwitchEnabled = v ?? true)),
              Expanded(child: Text('Auto-switch to next account when storage limit reached', style: TextStyle(color: baseColor, fontSize: 13))),
            ]),
            const SizedBox(height: 8),
            Text('Buckets will be auto-created if they don\'t exist. Storage usage will be checked every 24h.', style: TextStyle(color: dimColor, fontSize: 11)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              if (urlCtrl.text.trim().isEmpty || serviceKeyCtrl.text.trim().isEmpty || anonKeyCtrl.text.trim().isEmpty) return;
              final storageLimit = int.tryParse(storageLimitCtrl.text.trim()) ?? 1024;
              setDialog(() { isLoading = true; errorMsg = null; });
              final verifyResult = await FirebaseService.verifySupabaseCredentials(urlCtrl.text.trim(), serviceKeyCtrl.text.trim());
              if (verifyResult['valid'] == true) {
                await FirebaseService.addSupabaseAccount(
                   urlCtrl.text.trim(), 
                   serviceKeyCtrl.text.trim(), 
                   anonKeyCtrl.text.trim(), 
                   isActive: false,
                   storageLimitMB: storageLimit,
                   autoSwitchEnabled: autoSwitchEnabled,
                );
                try {
                  await FirebaseService.getStorageUsage(urlCtrl.text.trim(), serviceKeyCtrl.text.trim());
                } catch (_) {}
                await FirebaseService.reinitializeSupabase();
                if (d.mounted) Navigator.pop(d);
                _load();
                return;
              }
              final err = (verifyResult['error'] as String?) ?? 'Unknown error';
              final isAuthError = err.contains('Invalid credentials');
              if (isAuthError) {
                setDialog(() { isLoading = false; errorMsg = err; });
                return;
              }
              // Non-auth error (530, Proxy error, etc.) — show warning, allow proceed on 2nd click
              if (errorMsg == null) {
                setDialog(() { isLoading = false; errorMsg = err; });
                return;
              }
              // 2nd click — save anyway
              await FirebaseService.addSupabaseAccount(
                urlCtrl.text.trim(), 
                serviceKeyCtrl.text.trim(), 
                anonKeyCtrl.text.trim(), 
                isActive: false,
                storageLimitMB: storageLimit,
                autoSwitchEnabled: autoSwitchEnabled,
              );
              await FirebaseService.reinitializeSupabase();
              if (d.mounted) Navigator.pop(d);
              _load();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save & Setup', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }));
  }

  void _showEditSupabaseDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final urlCtrl = TextEditingController(text: acc['projectUrl'] as String? ?? '');
    final serviceKeyCtrl = TextEditingController(text: acc['serviceRoleKey'] as String? ?? '');
    final anonKeyCtrl = TextEditingController(text: acc['anonKey'] as String? ?? '');
    final storageLimitCtrl = TextEditingController(text: (acc['storageLimitMB'] as int? ?? 1024).toString());
    final nameCtrl = TextEditingController(text: acc['name'] as String? ?? '');
    final emailCtrl = TextEditingController(text: acc['email'] as String? ?? '');
    final projectCtrl = TextEditingController(text: acc['projectName'] as String? ?? '');
    bool autoSwitchEnabled = acc['autoSwitchEnabled'] as bool? ?? true;
    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.green, size: 22), const SizedBox(width: 8), Text('Edit Supabase Account', style: TextStyle(color: baseColor, fontSize: 16))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Account Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: emailCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Email', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: projectCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project URL', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: serviceKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Service Role Key', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: anonKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Anon Key', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: storageLimitCtrl, style: TextStyle(color: baseColor), keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Storage Limit (MB)', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 8),
            Row(children: [
              Checkbox(value: autoSwitchEnabled, activeColor: Colors.green, onChanged: (v) => setDialog(() => autoSwitchEnabled = v ?? true)),
              Expanded(child: Text('Auto-switch to next account when storage limit reached', style: TextStyle(color: baseColor, fontSize: 13))),
            ]),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(onPressed: () async {
            if (urlCtrl.text.trim().isEmpty || serviceKeyCtrl.text.trim().isEmpty || anonKeyCtrl.text.trim().isEmpty) return;
            final storageLimit = int.tryParse(storageLimitCtrl.text.trim()) ?? 1024;
            await FirebaseService.updateSupabaseAccount(
              acc['id'], 
              projectUrl: urlCtrl.text.trim(), 
              serviceRoleKey: serviceKeyCtrl.text.trim(), 
              anonKey: anonKeyCtrl.text.trim(),
              storageLimitMB: storageLimit,
              autoSwitchEnabled: autoSwitchEnabled,
            );
            if (acc['isActive'] == true) await FirebaseService.reinitializeSupabase();
            if (d.mounted) Navigator.pop(d); _load();
          }, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('Save', style: TextStyle(color: Colors.white))),
        ],
      );
    }));
  }

  void _showDeleteSupabaseDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final url = acc['projectUrl'] as String? ?? '';
    final isActive = acc['isActive'] as bool? ?? false;
    final activeCount = _supabaseAccounts.where((a) => a['isActive'] == true).length;
    if (isActive && activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the only active account. Add another first.'), backgroundColor: Colors.orange));
      return;
    }
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 8), Text('Delete Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(width: 400, child: Text('Delete $url? This cannot be undone.', style: TextStyle(color: dimColor, fontSize: 13))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteSupabaseAccount(acc['id']);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _showSupabaseSqlDialog(String projectUrl) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;

    final sql = """-- Create buckets
INSERT INTO storage.buckets (id, name, public) VALUES ('folder_files', 'folder_files', true) ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public) VALUES ('notices', 'notices', true) ON CONFLICT (id) DO NOTHING;

-- folder_files policies
CREATE POLICY "folder_files_read" ON storage.objects FOR SELECT USING (bucket_id = 'folder_files');
CREATE POLICY "folder_files_insert" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'folder_files' AND auth.role() = 'authenticated');
CREATE POLICY "folder_files_update" ON storage.objects FOR UPDATE USING (bucket_id = 'folder_files' AND auth.role() = 'authenticated');
CREATE POLICY "folder_files_delete" ON storage.objects FOR DELETE USING (bucket_id = 'folder_files' AND auth.role() = 'authenticated');

-- notices policies
CREATE POLICY "notices_read" ON storage.objects FOR SELECT USING (bucket_id = 'notices');
CREATE POLICY "notices_insert" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'notices' AND auth.role() = 'authenticated');
CREATE POLICY "notices_delete" ON storage.objects FOR DELETE USING (bucket_id = 'notices' AND auth.role() = 'authenticated');""";

    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [
        const Icon(Icons.code_rounded, color: Colors.cyan, size: 22),
        const SizedBox(width: 8),
        Expanded(child: Text('Supabase SQL', style: TextStyle(color: baseColor, fontSize: 16))),
      ]),
      content: SizedBox(
        width: 600,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Paste this in Supabase SQL Editor to create buckets + policies:', style: TextStyle(color: dimColor, fontSize: 12)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white12),
              ),
              child: SelectableText(sql, style: const TextStyle(color: Colors.greenAccent, fontSize: 11, fontFamily: 'monospace', height: 1.5)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Close', style: TextStyle(color: dimColor))),
        ElevatedButton.icon(
          onPressed: () {
            Clipboard.setData(ClipboardData(text: sql));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('SQL copied to clipboard!'), backgroundColor: Colors.green));
          },
          icon: const Icon(Icons.copy_rounded, size: 16),
          label: const Text('Copy SQL'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.cyan),
        ),
      ],
    ));
  }
}
