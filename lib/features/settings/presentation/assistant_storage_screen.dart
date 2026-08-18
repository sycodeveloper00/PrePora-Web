import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AssistantStorageScreen extends StatefulWidget {
  final String? assistantUid;
  final String? assistantName;
  const AssistantStorageScreen({super.key, this.assistantUid, this.assistantName});
  @override
  State<AssistantStorageScreen> createState() => _AssistantStorageScreenState();
}

class _AssistantStorageScreenState extends State<AssistantStorageScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _supabaseAccounts = [];
  List<Map<String, dynamic>> _assistants = [];

  bool get _isScoped => widget.assistantUid != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final all = await FirebaseService.getAssistantSupabaseAccounts();
    if (_isScoped) {
      final scoped = all.where((a) => a['assistantUid'] == widget.assistantUid).toList();
      if (mounted) setState(() {
        _supabaseAccounts = scoped;
        _loading = false;
      });
    } else {
      final snap = await FirebaseService.getAllAssistant().first;
      final assistants = snap.docs.map((e) => {'id': e.id, ...(e.data() as Map<String, dynamic>)}).toList();
      if (mounted) setState(() {
        _assistants = assistants;
        _supabaseAccounts = all;
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
          _isScoped ? (widget.assistantName ?? 'Assistant Storage') : 'Assistant Storage',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.code_rounded, color: Colors.cyan),
            tooltip: 'Supabase SQL',
            onPressed: _showSupabaseSqlDialog,
          ),
        ],
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
                    Text('Tap an assistant to manage their Supabase accounts', style: TextStyle(color: hintColor, fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add_circle_rounded, color: Colors.orange, size: 28),
                tooltip: 'Add Supabase account',
                onPressed: _showAddAssistantSupabaseDialog,
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
            final accounts = _supabaseAccounts.where((a) => a['assistantUid'] == uid).toList();
            final active = accounts.where((a) => a['isActive'] == true).toList();
            final activeUrl = active.isNotEmpty ? (active.first['projectUrl'] as String? ?? '') : '';
            final displayUrl = activeUrl.replaceFirst('https://', '');
            final statusText = accounts.isEmpty
                ? 'No storage assigned'
                : (activeUrl.isNotEmpty ? displayUrl : '${accounts.length} account(s), none active');
            return InkWell(
              onTap: () async {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => AssistantStorageScreen(assistantUid: uid, assistantName: name)));
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
                      Text(statusText, style: TextStyle(color: activeUrl.isNotEmpty ? Colors.teal : hintColor, fontSize: 12), overflow: TextOverflow.ellipsis),
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
                  const Icon(Icons.storage_rounded, color: Colors.teal),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Supabase Accounts', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                        Text(widget.assistantName == null ? 'Per-assistant Supabase storage' : 'Accounts for ${widget.assistantName}', style: TextStyle(color: hintColor, fontSize: 12)),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_rounded, color: Colors.teal, size: 28),
                    onPressed: () => _showAddAssistantSupabaseDialog(),
                  ),
                ]),
                const SizedBox(height: 8),
                if (_supabaseAccounts.isEmpty)
                  _emptyState('No assistant Supabase accounts', 'Assign Supabase accounts to assistants', Icons.person_add_rounded, isDark, hintColor)
                else
                  ...List.generate(_supabaseAccounts.length, (i) {
                    final acc = _supabaseAccounts[i];
                    final isActive = acc['isActive'] as bool? ?? false;
                    final bucketStatus = acc['bucketStatus'] as String? ?? 'pending';
                    final failedBuckets = (acc['failedBuckets'] as List?)?.cast<String>() ?? [];
                    final assistantName = acc['assistantName'] as String? ?? 'Unknown';
                    return _supabaseAccountTile(
                      acc: acc, isActive: isActive, bucketStatus: bucketStatus,
                      failedBuckets: failedBuckets, assistantName: assistantName,
                      textColor: textColor, hintColor: hintColor, isDark: isDark,
                      onToggle: () async {
                        if (isActive) return;
                        setState(() {
                          for (final a in _supabaseAccounts) {
                            if (a['assistantUid'] == acc['assistantUid']) {
                              a['isActive'] = (a['id'] == acc['id']);
                            }
                          }
                        });
                        try {
                          await FirebaseService.updateAssistantSupabaseAccount(acc['id'], isActive: true);
                        } catch (_) {}
                      },
                      onRetry: () async {
                        final result = await FirebaseService.retryAssistantSupabaseBuckets(acc['id']);
                        _load();
                        if (mounted) {
                          final status = result['status'] as String? ?? 'failed';
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(status == 'ready' ? 'All buckets ready!' : 'Some buckets still failed. Create them manually.'),
                            backgroundColor: status == 'ready' ? Colors.green : Colors.orange,
                          ));
                        }
                      },
                      onEdit: () => _showEditAssistantSupabaseDialog(acc),
                      onDelete: () => _showDeleteAssistantSupabaseDialog(acc),
                    );
                  }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _supabaseAccountTile({
    required Map<String, dynamic> acc, required bool isActive,
    required String bucketStatus, required List<String> failedBuckets,
    required String assistantName,
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
        color: isActive ? Colors.teal.withValues(alpha: 0.06) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? Colors.teal.withValues(alpha: 0.3) : (isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.green : Colors.redAccent.withValues(alpha: 0.5))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(displayUrl, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                child: Text(assistantName, style: const TextStyle(color: Colors.teal, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
              if (bucketStatus == 'ready') ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                  child: const Text('Ready', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600)),
                ),
              ],
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(Icons.circle, size: 6, color: isActive ? Colors.green : Colors.redAccent),
              const SizedBox(width: 4),
              Text(isActive ? 'Active' : 'Inactive', style: TextStyle(color: isActive ? Colors.green : Colors.redAccent, fontSize: 11)),
              if (hasFailed) ...[
                const SizedBox(width: 8),
                Icon(Icons.warning_amber_rounded, size: 12, color: Colors.orange),
                const SizedBox(width: 4),
                Text('Bucket issues', style: TextStyle(color: Colors.orange, fontSize: 11)),
              ],
            ]),
          ]),
        ),
        const SizedBox(width: 8),
        Switch(value: isActive, activeColor: Colors.teal, onChanged: (_) => onToggle()),
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
        color: Colors.teal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.15)),
      ),
      child: Column(children: [
        Icon(icon, size: 32, color: Colors.teal.withValues(alpha: 0.4)),
        const SizedBox(height: 8),
        Text(title, style: TextStyle(color: hintColor, fontSize: 13)),
        const SizedBox(height: 4),
        Text(subtitle, style: TextStyle(color: isDark ? Colors.white24 : Colors.black26, fontSize: 11)),
      ]),
    );
  }

  void _showAddAssistantSupabaseDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final urlCtrl = TextEditingController();
    final serviceKeyCtrl = TextEditingController();
    final anonKeyCtrl = TextEditingController();
    final scopedUid = widget.assistantUid;
    final scopedName = widget.assistantName;
    String? selectedUid = scopedUid;
    String selectedName = scopedName ?? '';
    bool isLoading = false;
    String? errorMsg;

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.person_add_rounded, color: Colors.teal, size: 22), const SizedBox(width: 8), Text('Add Assistant Supabase', style: TextStyle(color: baseColor, fontSize: 15))]),
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
                decoration: BoxDecoration(color: Colors.teal.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  const Icon(Icons.person_rounded, color: Colors.teal, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(scopedName ?? 'Assistant', style: TextStyle(color: baseColor, fontWeight: FontWeight.w600))),
                ]),
              ),
            const SizedBox(height: 12),
            TextField(controller: urlCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Project URL', hintText: 'https://xxx.supabase.co', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: serviceKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Service Role Key', hintText: 'eyJhbGciOi...', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: anonKeyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'Anon Key', hintText: 'eyJhbGciOi...', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 8),
            Text('Buckets will be auto-created. Invalid credentials = account NOT added.', style: TextStyle(color: dimColor, fontSize: 11)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              if (selectedUid == null || urlCtrl.text.trim().isEmpty || serviceKeyCtrl.text.trim().isEmpty || anonKeyCtrl.text.trim().isEmpty) return;
              setDialog(() { isLoading = true; errorMsg = null; });
              final verifyResult = await FirebaseService.verifySupabaseCredentials(urlCtrl.text.trim(), serviceKeyCtrl.text.trim());
              if (verifyResult['valid'] != true) {
                setDialog(() { isLoading = false; errorMsg = verifyResult['error'] as String? ?? 'Invalid credentials'; });
                return;
              }
              await FirebaseService.addAssistantSupabaseAccount(
                assistantUid: selectedUid!, assistantName: selectedName,
                projectUrl: urlCtrl.text.trim(), serviceRoleKey: serviceKeyCtrl.text.trim(), anonKey: anonKeyCtrl.text.trim(),
              );
              if (d.mounted) Navigator.pop(d);
              _load();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: isLoading
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Save & Setup', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
    }));
  }

  void _showEditAssistantSupabaseDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final urlCtrl = TextEditingController(text: acc['projectUrl'] as String? ?? '');
    final serviceKeyCtrl = TextEditingController(text: acc['serviceRoleKey'] as String? ?? '');
    final anonKeyCtrl = TextEditingController(text: acc['anonKey'] as String? ?? '');
    final assistantName = acc['assistantName'] as String? ?? 'Unknown';
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.teal, size: 22), const SizedBox(width: 8), Text('Edit $assistantName', style: TextStyle(color: baseColor, fontSize: 15))]),
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
          await FirebaseService.updateAssistantSupabaseAccount(acc['id'], projectUrl: urlCtrl.text.trim(), serviceRoleKey: serviceKeyCtrl.text.trim(), anonKey: anonKeyCtrl.text.trim());
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal), child: const Text('Save', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _showDeleteAssistantSupabaseDialog(Map<String, dynamic> acc) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final assistantName = acc['assistantName'] as String? ?? 'Unknown';
    final url = acc['projectUrl'] as String? ?? '';
    final assistantUid = acc['assistantUid'] as String? ?? '';
    final isActive = acc['isActive'] as bool? ?? false;
    final activeCount = _supabaseAccounts.where((a) => a['assistantUid'] == assistantUid && a['isActive'] == true).length;
    if (isActive && activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Cannot delete $assistantName\'s only active account.'), backgroundColor: Colors.orange));
      return;
    }
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 8), Text('Delete Account', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(width: 400, child: Text('Delete $assistantName\'s Supabase account ($url)?', style: TextStyle(color: dimColor, fontSize: 13))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteAssistantSupabaseAccount(acc['id']);
          if (d.mounted) Navigator.pop(d); _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }

  void _showSupabaseSqlDialog() {
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
