import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});
  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  bool _loading = true;
  String _storageProvider = 'supabase';
  List<Map<String, dynamic>> _cloudinaryAccounts = [];
  List<Map<String, dynamic>> _assistantCloudinaryAccounts = [];
  List<Map<String, dynamic>> _supabaseAccounts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = await FirebaseService.getStorageProvider();
    var accounts = await FirebaseService.getCloudinaryAccounts();
    final assistantAccounts = await FirebaseService.getAssistantCloudinaryAccounts();
    final supabaseAccounts = await FirebaseService.getSupabaseAccounts();

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
      _storageProvider = provider;
      _cloudinaryAccounts = accounts;
      _assistantCloudinaryAccounts = assistantAccounts;
      _supabaseAccounts = supabaseAccounts;
      _loading = false;
    });
  }

  bool get _showCloudinary => _storageProvider == 'cloudinary' || _storageProvider == 'both';
  bool get _showSupabase => _storageProvider == 'supabase' || _storageProvider == 'both';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;
    final cardColor = isDark ? const Color(0xFF1E1E1E) : const Color(0xFFFFFFFF);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded), onPressed: () => context.pop()),
      ),
      body: _loading
          ? const Center(child: ProfessionalLoader())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ─── Storage Provider Toggle (3 chips) ────────────────────────
                Card(
                  color: cardColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                                Text('Storage Provider', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                                Text('Choose upload backend', style: TextStyle(color: hintColor, fontSize: 12)),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(
                            child: _providerChip('Supabase', Icons.storage_rounded, _storageProvider == 'supabase', Colors.green, () async {
                              if (_storageProvider != 'supabase') {
                                await FirebaseService.setStorageProvider('supabase');
                                if (mounted) setState(() => _storageProvider = 'supabase');
                              }
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _providerChip('Cloudinary', Icons.cloud_upload_rounded, _storageProvider == 'cloudinary', Colors.deepPurple, () async {
                              if (_storageProvider != 'cloudinary') {
                                await FirebaseService.setStorageProvider('cloudinary');
                                if (mounted) setState(() => _storageProvider = 'cloudinary');
                              }
                            }),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _providerChip('Both', Icons.layers_rounded, _storageProvider == 'both', Colors.orange, () async {
                              if (_storageProvider != 'both') {
                                await FirebaseService.setStorageProvider('both');
                                if (mounted) setState(() => _storageProvider = 'both');
                              }
                            }),
                          ),
                        ]),
                        if (_storageProvider == 'both') ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                            ),
                            child: Row(children: [
                              const Icon(Icons.info_outline_rounded, color: Colors.orange, size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text('Files ≤ 10 MB → Cloudinary | > 10 MB → Supabase', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w500))),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ─── Supabase Accounts Section ────────────────────────────────
                if (_showSupabase) ...[
                  _buildSupabaseSection(cardColor, textColor, hintColor, isDark),
                  const SizedBox(height: 12),
                ],

                // ─── Admin Storage (Cloudinary) Accounts ──────────────────────
                if (_showCloudinary) ...[
                  _buildCloudinarySection(cardColor, textColor, hintColor, isDark),
                  const SizedBox(height: 12),
                ],

                // ─── Assistant Storage (Cloudinary) Accounts ──────────────────
                if (_showCloudinary) ...[
                  _buildAssistantCloudinarySection(cardColor, textColor, hintColor, isDark),
                ],
              ],
            ),
    );
  }

  // ─── Supabase Accounts Section ────────────────────────────────────────────

  Widget _buildSupabaseSection(Color cardColor, Color textColor, Color hintColor, bool isDark) {
    return Card(
      color: cardColor,
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

  // ─── Admin Storage (Cloudinary) Section ────────────────────────────────────

  Widget _buildCloudinarySection(Color cardColor, Color textColor, Color hintColor, bool isDark) {
    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.admin_panel_settings_rounded, color: Colors.deepPurple),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Admin Storage', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
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

  // ─── Assistant Storage (Cloudinary) Section ────────────────────────────────

  Widget _buildAssistantCloudinarySection(Color cardColor, Color textColor, Color hintColor, bool isDark) {
    return Card(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.support_agent_rounded, color: Colors.teal),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Assistant Storage', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                    Text('Per-assistant upload accounts', style: TextStyle(color: hintColor, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: Colors.teal, size: 28),
                onPressed: () => _showAddAssistantCloudinaryDialog(),
              ),
            ]),
            const SizedBox(height: 8),
            if (_assistantCloudinaryAccounts.isEmpty)
              _emptyState('No assistant accounts', 'Assign Cloudinary accounts to assistants', Icons.person_add_rounded, isDark, hintColor)
            else
              ...List.generate(_assistantCloudinaryAccounts.length, (i) {
                final acc = _assistantCloudinaryAccounts[i];
                final isActive = acc['isActive'] as bool? ?? false;
                final assistantName = acc['assistantName'] as String? ?? 'Unknown';
                return _accountTile(
                  acc: acc, isActive: isActive, textColor: textColor, hintColor: hintColor, isDark: isDark,
                  activeColor: Colors.teal,
                  badge: assistantName,
                  onToggle: () async {
                    if (isActive) return;
                    setState(() {
                      for (final a in _assistantCloudinaryAccounts) {
                        if (a['assistantUid'] == acc['assistantUid']) {
                          a['isActive'] = (a['id'] == acc['id']);
                        }
                      }
                    });
                    try {
                      await FirebaseService.updateAssistantCloudinaryAccount(acc['id'], isActive: true);
                    } catch (_) {}
                  },
                  onEdit: () => _showEditAssistantCloudinaryDialog(acc),
                  onDelete: () => _showDeleteAssistantCloudinaryDialog(acc),
                );
              }),
          ],
        ),
      ),
    );
  }

  // ─── Reusable Widgets ──────────────────────────────────────────────────────

  Widget _providerChip(String label, IconData icon, bool isSelected, Color activeColor, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? activeColor.withValues(alpha: isDark ? 0.2 : 0.1) : (isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? activeColor : (isDark ? Colors.white24 : Colors.black12), width: isSelected ? 2 : 1),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 18, color: isSelected ? activeColor : Colors.grey),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400, color: isSelected ? activeColor : Colors.grey)),
        ]),
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

  Widget _accountTile({
    required Map<String, dynamic> acc, required bool isActive,
    required Color textColor, required Color hintColor, required bool isDark,
    required Color activeColor, String? badge,
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
            Row(children: [
              Expanded(child: Text(acc['cloudName'] as String? ?? 'Unknown', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13))),
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(badge, style: const TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
            ]),
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

  // ─── Supabase Dialogs ──────────────────────────────────────────────────────

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
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
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
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project URL', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        TextField(controller: serviceKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Service Role Key', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        TextField(controller: anonKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Anon Key', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      ])),
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
      content: Text('Delete $url? This cannot be undone.', style: TextStyle(color: dimColor, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteSupabaseAccount(acc['id']);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  // ─── Admin Cloudinary Dialogs ──────────────────────────────────────────────

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
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: cloudCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', hintText: 'e.g. fun6bxu6', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        TextField(controller: presetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', hintText: 'e.g. prepora_unsigned', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 8),
        Text('This account will become active (others turn off)', style: TextStyle(color: dimColor, fontSize: 11)),
      ])),
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
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: cloudCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        TextField(controller: presetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      ])),
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
      content: Text('Delete $cloudName? This cannot be undone.', style: TextStyle(color: dimColor, fontSize: 13)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteCloudinaryAccount(acc['id']);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  // ─── Assistant Cloudinary Dialogs ──────────────────────────────────────────

  void _showAddAssistantCloudinaryDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final cloudCtrl = TextEditingController();
    final presetCtrl = TextEditingController();
    String? selectedUid;
    String selectedName = '';
    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.person_add_rounded, color: Colors.teal, size: 22), const SizedBox(width: 8), Text('Add Assistant Account', style: TextStyle(color: baseColor, fontSize: 15))]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.firestore.collection('users').where('role', isEqualTo: 'Assistant').snapshots(),
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
          ),
          const SizedBox(height: 12),
          TextField(controller: cloudCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', hintText: 'e.g. fun6bxu6', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 12),
          TextField(controller: presetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', hintText: 'e.g. prepora_unsigned', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
          const SizedBox(height: 8),
          Text('This becomes the active account for this assistant', style: TextStyle(color: dimColor, fontSize: 11)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(onPressed: () async {
            if (selectedUid == null || cloudCtrl.text.trim().isEmpty || presetCtrl.text.trim().isEmpty) return;
            await FirebaseService.addAssistantCloudinaryAccount(assistantUid: selectedUid!, assistantName: selectedName, cloudName: cloudCtrl.text.trim(), uploadPreset: presetCtrl.text.trim());
            if (d.mounted) Navigator.pop(d); _load();
          }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Add', style: TextStyle(color: Colors.white))),
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
    final cloudCtrl = TextEditingController(text: acc['cloudName'] as String? ?? '');
    final presetCtrl = TextEditingController(text: acc['uploadPreset'] as String? ?? '');
    final assistantName = acc['assistantName'] as String? ?? 'Unknown';
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.teal, size: 22), const SizedBox(width: 8), Text('Edit $assistantName', style: TextStyle(color: baseColor, fontSize: 15))]),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: cloudCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Cloud Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
        const SizedBox(height: 12),
        TextField(controller: presetCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Upload Preset', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          if (cloudCtrl.text.trim().isEmpty || presetCtrl.text.trim().isEmpty) return;
          await FirebaseService.updateAssistantCloudinaryAccount(acc['id'], cloudName: cloudCtrl.text.trim(), uploadPreset: presetCtrl.text.trim());
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
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
    final activeCount = _assistantCloudinaryAccounts.where((a) => a['assistantUid'] == assistantUid && a['isActive'] == true).length;
    if (isActive && activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot delete $assistantName\'s only active account.'), backgroundColor: Colors.orange));
      return;
    }
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 8), Text('Delete Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: Text('Delete $assistantName\'s Cloudinary account ($cloudName)?', style: TextStyle(color: dimColor, fontSize: 13)),
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
