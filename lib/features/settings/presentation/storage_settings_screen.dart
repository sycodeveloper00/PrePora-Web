import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';
import 'admin_storage_screen.dart';
import 'assistant_storage_screen.dart';
import 'admin_cloudinary_screen.dart';
import 'assistant_cloudinary_screen.dart';
import 'admin_clorabase_screen.dart';
import 'assistant_clorabase_screen.dart';

class StorageSettingsScreen extends StatefulWidget {
  const StorageSettingsScreen({super.key});
  @override
  State<StorageSettingsScreen> createState() => _StorageSettingsScreenState();
}

class _StorageSettingsScreenState extends State<StorageSettingsScreen> {
  bool _loading = true;
  String _currentProvider = 'supabase';
  int _adminSupabaseCount = 0;
  int _assistantSupabaseCount = 0;
  int _adminCloudinaryCount = 0;
  int _assistantCloudinaryCount = 0;
  int _adminClorabaseCount = 0;
  int _assistantClorabaseCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = await FirebaseService.getStorageProvider();
    final supAccounts = await FirebaseService.getSupabaseAccounts();
    final assistantSup = await FirebaseService.getAssistantSupabaseAccounts();
    final cloudAccounts = await FirebaseService.getCloudinaryAccounts();
    final assistantCloud = await FirebaseService.getAssistantCloudinaryAccounts();
    final clorabaseAccounts = await FirebaseService.getClorabaseAccounts();
    final assistantClorabase = await FirebaseService.getAssistantClorabaseAccounts();

    if (mounted) setState(() {
      _currentProvider = provider;
      final adminSeen = <String>{};
      _adminSupabaseCount = (supAccounts ?? []).where((a) {
        final url = a['projectUrl'] as String? ?? '';
        if (url.isEmpty || !url.contains('supabase')) return false;
        if (adminSeen.contains(url)) return false;
        adminSeen.add(url);
        return true;
      }).length;
      final assistantSeen = <String>{};
      _assistantSupabaseCount = (assistantSup ?? []).where((a) {
        final url = a['projectUrl'] as String? ?? '';
        if (url.isEmpty || !url.contains('supabase')) return false;
        if (assistantSeen.contains(url)) return false;
        assistantSeen.add(url);
        return true;
      }).length;
      _adminCloudinaryCount = (cloudAccounts ?? []).length;
      _assistantCloudinaryCount = (assistantCloud ?? []).length;
      _adminClorabaseCount = (clorabaseAccounts ?? []).length;
      _assistantClorabaseCount = (assistantClorabase ?? []).length;
      _loading = false;
    });
  }

  Future<void> _setProvider(String provider) async {
    await FirebaseService.setStorageProvider(provider);
    setState(() => _currentProvider = provider);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Storage provider set to ${provider.toUpperCase()}'),
        backgroundColor: Colors.green,
      ));
    }
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
                // ─── Storage Provider Selector ────────────────────────
                Card(
                  color: cardColor,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.green.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.storage_rounded, color: Colors.green, size: 24),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Storage Provider', style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 15)),
                                const SizedBox(height: 2),
                                Text('Select where files are uploaded', style: TextStyle(color: hintColor, fontSize: 12)),
                              ],
                            ),
                          ),
                        ]),
                        const SizedBox(height: 16),
                        // Provider selection chips
                        Row(
                          children: [
                            _providerChip('Supabase', 'supabase', Colors.green, textColor, hintColor),
                            const SizedBox(width: 8),
                            _providerChip('Clorabase', 'clorabase', Colors.orange, textColor, hintColor),
                            const SizedBox(width: 8),
                            _providerChip('Supa+Clora', 'supabase_clorabase', Colors.teal, textColor, hintColor),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _providerChip('Cloudinary', 'cloudinary', Colors.deepPurple, textColor, hintColor),
                            const SizedBox(width: 8),
                            _providerChip('Both', 'both', Colors.cyan, textColor, hintColor),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.cyan.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.cyan.withValues(alpha: 0.2)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.info_outline_rounded, color: Colors.cyan, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                _currentProvider == 'supabase'
                                    ? 'Files will be uploaded to Supabase Storage only.'
                                    : _currentProvider == 'clorabase'
                                        ? 'Files will be uploaded to Clorabase (GitHub) only.'
                                        : _currentProvider == 'supabase_clorabase'
                                            ? 'Files go to Clorabase first, fallback to Supabase on error.'
                                            : _currentProvider == 'cloudinary'
                                                ? 'Files will be uploaded to Cloudinary only.'
                                                : 'Small files (<10MB) go to Cloudinary, larger files go to Supabase.',
                                style: TextStyle(color: Colors.cyan, fontSize: 11),
                              ),
                            ),
                          ]),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Admin Supabase Storage Card ──────────────────────
                _storageCard(
                  icon: Icons.admin_panel_settings_rounded,
                  iconColor: Colors.green,
                  title: 'Admin Supabase',
                  subtitle: '$_adminSupabaseCount account(s)',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminStorageScreen()));
                    _load();
                  },
                ),
                const SizedBox(height: 12),

                // ─── Admin Cloudinary Storage Card ────────────────────
                _storageCard(
                  icon: Icons.admin_panel_settings_rounded,
                  iconColor: Colors.deepPurple,
                  title: 'Admin Cloudinary',
                  subtitle: '$_adminCloudinaryCount account(s)',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminCloudinaryScreen()));
                    _load();
                  },
                ),
                const SizedBox(height: 12),

                // ─── Assistant Supabase Storage Card ──────────────────
                _storageCard(
                  icon: Icons.people_rounded,
                  iconColor: Colors.teal,
                  title: 'Assistant Supabase',
                  subtitle: '$_assistantSupabaseCount account(s)',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantStorageScreen()));
                    _load();
                  },
                ),
                const SizedBox(height: 12),

                // ─── Assistant Cloudinary Storage Card ────────────────
                _storageCard(
                  icon: Icons.people_rounded,
                  iconColor: Colors.orange,
                  title: 'Assistant Cloudinary',
                  subtitle: '$_assistantCloudinaryCount account(s)',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantCloudinaryScreen()));
                    _load();
                  },
                ),
                const SizedBox(height: 12),

                // ─── Admin Clorabase Storage Card ─────────────────────
                _storageCard(
                  icon: Icons.admin_panel_settings_rounded,
                  iconColor: Colors.orange,
                  title: 'Admin Clorabase',
                  subtitle: '$_adminClorabaseCount account(s)',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminClorabaseScreen()));
                    _load();
                  },
                ),
                const SizedBox(height: 12),

                // ─── Assistant Clorabase Storage Card ─────────────────
                _storageCard(
                  icon: Icons.people_rounded,
                  iconColor: Colors.orange,
                  title: 'Assistant Clorabase',
                  subtitle: '$_assistantClorabaseCount account(s)',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AssistantClorabaseScreen()));
                    _load();
                  },
                ),
              ],
            ),
    );
  }

  Widget _providerChip(String label, String value, Color color, Color textColor, Color hintColor) {
    final isSelected = _currentProvider == value;
    IconData icon;
    switch (value) {
      case 'supabase':
        icon = Icons.storage_rounded;
        break;
      case 'clorabase':
        icon = Icons.code_rounded;
        break;
      case 'supabase_clorabase':
        icon = Icons.layers_rounded;
        break;
      case 'cloudinary':
        icon = Icons.cloud_upload_rounded;
        break;
      default:
        icon = Icons.layers_rounded;
    }
    return Expanded(
      child: GestureDetector(
        onTap: () => _setProvider(value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? color : (textColor.withValues(alpha: 0.15)),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? color : hintColor,
                size: 20,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : hintColor,
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
