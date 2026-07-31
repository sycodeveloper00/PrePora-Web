import 'package:flutter/material.dart';

class ShortcutKey {
  final String key;
  final String action;
  final String category;

  const ShortcutKey({required this.key, required this.action, required this.category});
}

class ShortcutsHelpDialog extends StatelessWidget {
  const ShortcutsHelpDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const ShortcutsHelpDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = _getShortcuts();
    final categories = shortcuts.map((s) => s.category).toSet().toList();

    return Dialog(
      backgroundColor: const Color(0xFF1A0533),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 600,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7C4DFF).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.keyboard_rounded, color: Color(0xFF7C4DFF), size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Text(
                    'Keyboard Shortcuts',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.close_rounded, color: Colors.white.withOpacity(0.5)),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: categories.length,
                separatorBuilder: (_, __) => const SizedBox(height: 16),
                itemBuilder: (context, catIndex) {
                  final category = categories[catIndex];
                  final categoryShortcuts = shortcuts.where((s) => s.category == category).toList();
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category.toUpperCase(),
                        style: TextStyle(
                          color: const Color(0xFF7C4DFF),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...categoryShortcuts.map((s) => _ShortcutRow(shortcut: s)),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<ShortcutKey> _getShortcuts() {
    return const [
      // Navigation
      ShortcutKey(key: 'Enter', action: 'Open selected item', category: 'Navigation'),
      ShortcutKey(key: 'Backspace', action: 'Go back to parent folder', category: 'Navigation'),
      ShortcutKey(key: 'Arrow Keys', action: 'Navigate between items', category: 'Navigation'),
      ShortcutKey(key: 'Escape', action: 'Deselect / Close menu', category: 'Navigation'),

      // Folder/File Operations
      ShortcutKey(key: 'Ctrl + N', action: 'Create new folder', category: 'Folder & File'),
      ShortcutKey(key: 'F2', action: 'Rename selected item', category: 'Folder & File'),
      ShortcutKey(key: 'Ctrl + E', action: 'Edit selected item', category: 'Folder & File'),
      ShortcutKey(key: 'Delete', action: 'Delete selected item', category: 'Folder & File'),
      ShortcutKey(key: 'Ctrl + D', action: 'Duplicate selected item', category: 'Folder & File'),

      // Clipboard
      ShortcutKey(key: 'Ctrl + C', action: 'Copy selected item', category: 'Clipboard'),
      ShortcutKey(key: 'Ctrl + X', action: 'Cut selected item', category: 'Clipboard'),
      ShortcutKey(key: 'Ctrl + V', action: 'Paste item', category: 'Clipboard'),
      ShortcutKey(key: 'Ctrl + A', action: 'Select all items', category: 'Clipboard'),

      // Upload
      ShortcutKey(key: 'Ctrl + U', action: 'Upload file (Internal Storage)', category: 'Upload'),
      ShortcutKey(key: 'Ctrl + Shift + U', action: 'Upload from Google Drive', category: 'Upload'),
      ShortcutKey(key: 'Ctrl + Shift + L', action: 'Paste link / Upload from URL', category: 'Upload'),

      // Content
      ShortcutKey(key: 'Ctrl + Shift + M', action: 'Add Mock Test', category: 'Content'),
      ShortcutKey(key: 'Ctrl + Shift + P', action: 'Upload PDF', category: 'Content'),
      ShortcutKey(key: 'Ctrl + Shift + N', action: 'Add Note', category: 'Content'),

      // Lock & Visibility
      ShortcutKey(key: 'Ctrl + L', action: 'Lock / Unlock item', category: 'Lock & Visibility'),
      ShortcutKey(key: 'Ctrl + Shift + V', action: 'Show / Hide item', category: 'Lock & Visibility'),

      // Groups & Access
      ShortcutKey(key: 'Ctrl + Shift + G', action: 'Create group', category: 'Groups & Access'),
      ShortcutKey(key: 'Ctrl + Shift + A', action: 'Manage assistant access', category: 'Groups & Access'),

      // Misc
      ShortcutKey(key: 'Ctrl + R', action: 'Refresh data', category: 'Miscellaneous'),
      ShortcutKey(key: 'Ctrl + /', action: 'Show this help dialog', category: 'Miscellaneous'),
    ];
  }
}

class _ShortcutRow extends StatelessWidget {
  final ShortcutKey shortcut;

  const _ShortcutRow({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
            ),
            child: Text(
              shortcut.key,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 12,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              shortcut.action,
              style: TextStyle(
                color: Colors.white.withOpacity(0.7),
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
