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
  int _adminSupabaseCount = 0;
  int _assistantSupabaseCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await FirebaseService.setStorageProvider('supabase');
    final supAccounts = await FirebaseService.getSupabaseAccounts();
    final assistantSup = await FirebaseService.getAssistantSupabaseAccounts();

    if (mounted) setState(() {
      _adminSupabaseCount = supAccounts.length;
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
                // ─── Storage Provider (Supabase only) ──────────────────
                Card(
                  color: cardColor,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    child: Row(children: [
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
                            Text('Supabase', style: TextStyle(color: Colors.green, fontSize: 13, fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
                    ]),
                  ),
                ),

                const SizedBox(height: 16),

                // ─── Admin Storage Card ───────────────────────────────
                _storageCard(
                  icon: Icons.admin_panel_settings_rounded,
                  iconColor: Colors.deepPurple,
                  title: 'Admin Storage',
                  subtitle: '$_adminSupabaseCount Supabase account(s)',
                  cardColor: cardColor, textColor: textColor, hintColor: hintColor,
                  onTap: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminStorageScreen()));
                    _load();
                  },
                ),
                const SizedBox(height: 12),

                // ─── Assistant Storage Card ───────────────────────────
                _storageCard(
                  icon: Icons.people_rounded,
                  iconColor: Colors.orange,
                  title: 'Assistant Storage',
                  subtitle: '$_assistantSupabaseCount Supabase account(s)',
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
