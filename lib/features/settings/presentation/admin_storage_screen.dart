import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AdminStorageScreen extends StatefulWidget {
  const AdminStorageScreen({super.key});
  @override
  State<AdminStorageScreen> createState() => _AdminStorageScreenState();
}

class _AdminStorageScreenState extends State<AdminStorageScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  bool _loading = true;
  String _providerMode = 'both';
  List<Map<String, dynamic>> _cloudinaryAccounts = [];
  List<Map<String, dynamic>> _supabaseAccounts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _tabController?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    var accounts = await FirebaseService.getCloudinaryAccounts();
    final supabaseAccounts = await FirebaseService.getSupabaseAccounts();
    final providerMode = await FirebaseService.getStorageProvider();

    final activeAccounts = accounts.where((a) => a['isActive'] == true).toList();
    if (activeAccounts.length > 1) {
      final batch = FirebaseFirestore.instance.batch();
      for (int i = 1; i < activeAccounts.length; i++) {
        batch.update(FirebaseFirestore.instance.collection('cloudinary_accounts').doc(activeAccounts[i]['id']), {'isActive': false});
      }
      await batch.commit();
      accounts = await FirebaseService.getCloudinaryAccounts();
    }

    if (mounted) setState(() {
      _cloudinaryAccounts = accounts;
      _supabaseAccounts = supabaseAccounts;
      _providerMode = providerMode;
      _loading = false;
      if (_providerMode == 'both') {
        _tabController = TabController(length: 2, vsync: this);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;

    final bool showTabs = _providerMode == 'both';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Storage', style: TextStyle(fontWeight: FontWeight.bold)),
        bottom: showTabs && _tabController != null
            ? TabBar(
                controller: _tabController,
                indicatorColor: Colors.deepPurple,
                labelColor: textColor,
                unselectedLabelColor: hintColor,
                tabs: const [
                  Tab(icon: Icon(Icons.storage_rounded), text: 'Supabase Storage'),
                  Tab(icon: Icon(Icons.cloud_upload_rounded), text: 'Cloudinary Storage'),
                ],
              )
            : null,
      ),
      body: _loading
          ? const Center(child: ProfessionalLoader())
          : showTabs && _tabController != null
              ? TabBarView(
                  controller: _tabController,
                  children: [
                    _buildSupabaseTab(textColor, hintColor, isDark),
                    _buildCloudinaryTab(textColor, hintColor, isDark),
                  ],
                )
              : _providerMode == 'supabase'
                  ? _buildSupabaseTab(textColor, hintColor, isDark)
                  : _buildCloudinaryTab(textColor, hintColor, isDark),
    );
  }

  // ─── Supabase Tab ───────────────────────────────────────────────────────

  Widget _buildSupabaseTab(Color textColor, Color hintColor, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildSupabaseSection(textColor, hintColor, isDark),
      ],
    );
  }

  Widget _buildSupabaseSection(Color textColor, Color hintColor, bool isDark) {
    return Card(
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
              _emptyState('No Supabase accounts', 'Tap + to add your first Supabase account', Icons.storage_outlined, isDark, hintColor)
            else
              ...List.generate(_supabaseAccounts.length, (i) {
                final acc = _supabaseAccounts[i];
                final isActive = acc['isActive'] as bool? ?? false;
                final bucketStatus = acc['bucketStatus'] as String? ?? 'pending';
                final failedBuckets = (acc['failedBuckets'] as List?)?.cast<String>() ?? [];
                return _supabaseAccountTile(
                  acc: acc, isActive: isActive, bucketStatus: bucketStatus, failedBuckets: failedBuckets,
                  textColor: textColor, hintColor: hintColor, isDark: isDark,
                  onToggle: () async {
                    if (isActive) return;
                    setState(() {
                      for (final a in _supabaseAccounts) {
                        a['isActive'] = (a['id'] == acc['id']);
                      }
                    });
                    try {
                      await FirebaseService.updateSupabaseAccount(acc['id'], isActive: true);
                      await FirebaseService.reinitializeSupabase();
                    } catch (_) {}
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
                  onEdit: () => _showEditSupabaseDialog(acc),
                  onDelete: () => _showDeleteSupabaseDialog(acc),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _supabaseAccountTile({
    required Map<String, dynamic> acc, required bool isActive,
    required String bucketStatus, required List<String> failedBuckets,
    required Color textColor, required Color hintColor, required bool isDark,
    required VoidCallback onToggle, required VoidCallback onRetry,
    required VoidCallback onEdit, required VoidCallback onDelete,
  }) {
    final url = acc['projectUrl'] as String? ?? '';
    final displayUrl = url.replaceFirst('https://', '');
    final hasFailed = bucketStatus == 'failed' || bucketStatus == 'partial';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.green.withValues(alpha: 0.06) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? Colors.green.withValues(alpha: 0.3) : (isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.green : Colors.redAccent.withValues(alpha: 0.5))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(displayUrl, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
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
                    child: const Icon(Icons.error_outline_rounded, color: Colors.orange, size: 16),
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
              Text('Missing: ${failedBuckets.join(', ')}', style: const TextStyle(color: Colors.orange, fontSize: 11)),
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
    );
  }

  // ─── Cloudinary Tab ─────────────────────────────────────────────────────

  Widget _buildCloudinaryTab(Color textColor, Color hintColor, bool isDark) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildCloudinarySection(textColor, hintColor, isDark),
      ],
    );
  }

  Widget _buildCloudinarySection(Color textColor, Color hintColor, bool isDark) {
    return Card(
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
              _emptyState('No accounts yet', 'Tap + to add your first Cloudinary account', Icons.cloud_upload_outlined, isDark, hintColor)
            else
              ...List.generate(_cloudinaryAccounts.length, (i) {
                final acc = _cloudinaryAccounts[i];
                final isActive = acc['isActive'] as bool? ?? false;
                return _accountTile(
                  acc: acc, isActive: isActive, textColor: textColor, hintColor: hintColor, isDark: isDark,
                  activeColor: Colors.deepPurple,
                  onToggle: () async {
                    if (isActive) return;
                    setState(() {
                      for (final a in _cloudinaryAccounts) {
                        a['isActive'] = (a['id'] == acc['id']);
                      }
                    });
                    try {
                      await FirebaseService.updateCloudinaryAccount(acc['id'], isActive: true);
                    } catch (_) {}
                  },
                  onEdit: () => _showEditCloudinaryDialog(acc),
                  onDelete: () => _showDeleteCloudinaryDialog(acc),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ─── Reusable Widgets ────────────────────────────────────────────────────

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

  Widget _accountTile({
    required Map<String, dynamic> acc, required bool isActive,
    required Color textColor, required Color hintColor, required bool isDark,
    required Color activeColor,
    required VoidCallback onToggle, required VoidCallback onEdit, required VoidCallback onDelete,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? activeColor.withValues(alpha: 0.06) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? activeColor.withValues(alpha: 0.3) : (isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.green : Colors.redAccent.withValues(alpha: 0.5))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(acc['cloudName'] as String? ?? 'Unknown', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 2),
            Text(acc['uploadPreset'] as String? ?? '', style: TextStyle(color: hintColor, fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 8),
        Switch(value: isActive, activeColor: activeColor, onChanged: (_) => onToggle()),
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

  // ─── Supabase Dialogs ────────────────────────────────────────────────────

  void _showAddSupabaseDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final urlCtrl = TextEditingController();
    final serviceKeyCtrl = TextEditingController();
    final anonKeyCtrl = TextEditingController();
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
                decoration: BoxDecoration(color: Colors.redAccent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [const Icon(Icons.error_outline, color: Colors.redAccent, size: 16), const SizedBox(width: 8), Expanded(child: Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)))]),
              ),
              const SizedBox(height: 12),
            ],
            TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project URL', hintText: 'https://xxx.supabase.co', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: serviceKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Service Role Key', hintText: 'eyJhbGciOi...', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: anonKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Anon Key', hintText: 'eyJhbGciOi...', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 8),
            Text('Buckets will be auto-created if they don\'t exist', style: TextStyle(color: dimColor, fontSize: 11)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              if (urlCtrl.text.trim().isEmpty || serviceKeyCtrl.text.trim().isEmpty || anonKeyCtrl.text.trim().isEmpty) return;
              setDialog(() { isLoading = true; errorMsg = null; });
              final verifyResult = await FirebaseService.verifySupabaseCredentials(urlCtrl.text.trim(), serviceKeyCtrl.text.trim());
              if (verifyResult['valid'] != true) {
                setDialog(() { isLoading = false; errorMsg = verifyResult['error'] as String? ?? 'Invalid credentials'; });
                return;
              }
              await FirebaseService.addSupabaseAccount(urlCtrl.text.trim(), serviceKeyCtrl.text.trim(), anonKeyCtrl.text.trim(), isActive: true);
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
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.green, size: 22), const SizedBox(width: 8), Text('Edit Supabase Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project URL', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: serviceKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Service Role Key', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: anonKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Anon Key', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          if (urlCtrl.text.trim().isEmpty || serviceKeyCtrl.text.trim().isEmpty || anonKeyCtrl.text.trim().isEmpty) return;
          await FirebaseService.updateSupabaseAccount(acc['id'], projectUrl: urlCtrl.text.trim(), serviceRoleKey: serviceKeyCtrl.text.trim(), anonKey: anonKeyCtrl.text.trim());
          if (acc['isActive'] == true) await FirebaseService.reinitializeSupabase();
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.green), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
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

  // ─── SQL Dialog ──────────────────────────────────────────────────────────

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

  // ─── Cloudinary Dialogs ──────────────────────────────────────────────────

  void _showAddCloudinaryDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cloudCtrl = TextEditingController();
    final presetCtrl = TextEditingController();
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.cloud_upload_rounded, color: Colors.deepPurple, size: 22), const SizedBox(width: 8), Text('Add Cloudinary Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cloudCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', hintText: 'e.g. fun6bxu6', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: presetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', hintText: 'e.g. prepora_unsigned', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 8),
          Text('This account will become active (others turn off)', style: TextStyle(color: dimColor, fontSize: 11)),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          if (cloudCtrl.text.trim().isEmpty || presetCtrl.text.trim().isEmpty) return;
          await FirebaseService.addCloudinaryAccount(cloudCtrl.text.trim(), presetCtrl.text.trim(), isActive: true);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Add', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _showEditCloudinaryDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cloudCtrl = TextEditingController(text: acc['cloudName'] as String? ?? '');
    final presetCtrl = TextEditingController(text: acc['uploadPreset'] as String? ?? '');
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.deepPurple, size: 22), const SizedBox(width: 8), Text('Edit Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: cloudCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: presetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        ])),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          if (cloudCtrl.text.trim().isEmpty || presetCtrl.text.trim().isEmpty) return;
          await FirebaseService.updateCloudinaryAccount(acc['id'], cloudName: cloudCtrl.text.trim(), uploadPreset: presetCtrl.text.trim());
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
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
      content: SizedBox(width: 400, child: Text('Delete $cloudName? This cannot be undone.', style: TextStyle(color: dimColor, fontSize: 13))),
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
