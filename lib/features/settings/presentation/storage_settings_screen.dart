import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';
import 'admin_storage_screen.dart';
import 'assistant_storage_screen.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});
  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  bool _loading = true;
  bool _showProviderDropdown = false;
  String _storageProvider = 'supabase';
  int _adminCloudCount = 0;
  int _adminSupabaseCount = 0;
  int _assistantCloudCount = 0;
  int _assistantSupabaseCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = await FirebaseService.getStorageProvider();
    final cloudAccounts = await FirebaseService.getCloudinaryAccounts();
    final supAccounts = await FirebaseService.getSupabaseAccounts();
    final assistantCloud = await FirebaseService.getAssistantCloudinaryAccounts();
    final assistantSup = await FirebaseService.getAssistantSupabaseAccounts();

    if (mounted) setState(() {
      _storageProvider = provider;
      _adminCloudCount = cloudAccounts.length;
      _adminSupabaseCount = supAccounts.length;
      _assistantCloudCount = assistantCloud.length;
      _assistantSupabaseCount = assistantSup.length;
      _loading = false;
    });
  }

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
                // ─── Storage Provider Dropdown ──────────────────────────
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
                          GestureDetector(
                            onTap: () => setState(() => _showProviderDropdown = !_showProviderDropdown),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: _providerColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: _providerColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(_providerIcon, color: _providerColor, size: 16),
                                const SizedBox(width: 6),
                                Text(_providerLabel, style: TextStyle(color: _providerColor, fontWeight: FontWeight.w600, fontSize: 13)),
                                const SizedBox(width: 4),
                                Icon(
                                  _showProviderDropdown
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.keyboard_arrow_down_rounded,
                                  color: _providerColor,
                                  size: 16,
                                ),
                              ]),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),

                // ─── Inline Dropdown Options ──────────────────────────────
                if (_showProviderDropdown) ...[
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _providerColor.withValues(alpha: 0.4)),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: _providerOptions.map((o) {
                        final isSelected = o.$1 == _storageProvider;
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ListTile(
                              dense: true,
                              leading: Icon(o.$3, color: o.$4, size: 20),
                              title: Text(
                                o.$2,
                                style: TextStyle(
                                  color: isSelected ? o.$4 : textColor,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                                  fontSize: 14,
                                ),
                              ),
                              trailing: isSelected
                                  ? Icon(Icons.check_circle_rounded, color: o.$4, size: 20)
                                  : Icon(Icons.chevron_right_rounded, color: hintColor, size: 18),
                              onTap: () async {
                                if (!isSelected) {
                                  await FirebaseService.setStorageProvider(o.$1);
                                  if (mounted) setState(() {
                                    _storageProvider = o.$1;
                                    _showProviderDropdown = false;
                                  });
                                } else {
                                  setState(() => _showProviderDropdown = false);
                                }
                              },
                            ),
                            if (o != _providerOptions.last)
                              Divider(height: 1, indent: 48, color: isDark ? Colors.white10 : Colors.black12),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ],

                // ─── Both mode info ───────────────────────────────────────
                if (_storageProvider == 'both' && !_showProviderDropdown) ...[
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
                      Expanded(child: Text('Files \u2264 10 MB \u2192 Cloudinary | > 10 MB \u2192 Supabase', style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w500))),
                    ]),
                  ),
                ],

                const SizedBox(height: 16),

                // ─── Admin Storage Card ───────────────────────────────────
                _storageCard(
                  icon: Icons.admin_panel_settings_rounded,
                  iconColor: Colors.deepPurple,
                  title: 'Admin Storage',
                  subtitle: _storageProvider == 'supabase'
                      ? '$_adminSupabaseCount Supabase account(s)'
                      : _storageProvider == 'cloudinary'
                          ? '$_adminCloudCount Cloudinary account(s)'
                          : '$_adminSupabaseCount Supabase \u00b7 $_adminCloudCount Cloudinary',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminStorageScreen()));
                    _load();
                  },
                ),
                const SizedBox(height: 12),

                // ─── Assistant Storage Card ───────────────────────────────
                _storageCard(
                  icon: Icons.people_rounded,
                  iconColor: Colors.orange,
                  title: 'Assistant Storage',
                  subtitle: _storageProvider == 'supabase'
                      ? '$_assistantSupabaseCount Supabase account(s)'
                      : _storageProvider == 'cloudinary'
                          ? '$_assistantCloudCount Cloudinary account(s)'
                          : '$_assistantSupabaseCount Supabase \u00b7 $_assistantCloudCount Cloudinary',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantStorageScreen()));
                    _load();
                  },
                ),
              ],
            ),
    );
  }

  // ─── Provider Helpers ──────────────────────────────────────────────────

  static const List<(String, String, IconData, Color)> _providerOptions = [
    ('supabase', 'Supabase', Icons.storage_rounded, Colors.green),
    ('cloudinary', 'Cloudinary', Icons.cloud_upload_rounded, Colors.deepPurple),
    ('both', 'Both', Icons.layers_rounded, Colors.orange),
  ];

  String get _providerLabel => switch (_storageProvider) {
    'supabase' => 'Supabase',
    'cloudinary' => 'Cloudinary',
    _ => 'Both',
  };

  IconData get _providerIcon => switch (_storageProvider) {
    'supabase' => Icons.storage_rounded,
    'cloudinary' => Icons.cloud_upload_rounded,
    _ => Icons.layers_rounded,
  };

  Color get _providerColor => switch (_storageProvider) {
    'supabase' => Colors.green,
    'cloudinary' => Colors.deepPurple,
    _ => Colors.orange,
  };

  Widget _storageCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color cardColor,
    required Color textColor,
    required Color hintColor,
    required VoidCallback onTap,
  }) {
    return Card(
      color: cardColor,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(color: hintColor, fontSize: 12)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, color: hintColor, size: 16),
          ]),
        ),
      ),
    );
  }
}
