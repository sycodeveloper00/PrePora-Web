import 'package:flutter/material.dart';

class ContextMenuItem {
  final IconData icon;
  final String label;
  final String? shortcut;
  final VoidCallback? onTap;
  final bool isDestructive;
  final bool isDivider;

  const ContextMenuItem({
    required this.icon,
    required this.label,
    this.shortcut,
    this.onTap,
    this.isDestructive = false,
    this.isDivider = false,
  });
}

class AdminContextMenu extends StatelessWidget {
  final Offset position;
  final List<ContextMenuItem> items;
  final VoidCallback? onDismiss;

  const AdminContextMenu({
    super.key,
    required this.position,
    required this.items,
    this.onDismiss,
  });

  static void show(BuildContext context, Offset position, List<ContextMenuItem> items, {VoidCallback? onDismiss}) {
    OverlayState? overlay = Overlay.of(context);
    if (overlay == null) return;

    OverlayEntry? entry;
    entry = OverlayEntry(
      builder: (ctx) => AdminContextMenu(
        position: position,
        items: items,
        onDismiss: () {
          entry?.remove();
          onDismiss?.call();
        },
      ),
    );
    overlay.insert(entry);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    double left = position.dx;
    double top = position.dy;

    if (left + 240 > screenSize.width) left = screenSize.width - 250;
    if (top + (items.length * 44.0) > screenSize.height) top = screenSize.height - (items.length * 44.0) - 20;
    if (left < 10) left = 10;
    if (top < 10) top = 10;

    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
            onSecondaryTap: onDismiss,
          ),
        ),
        Positioned(
          left: left,
          top: top,
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 240,
              decoration: BoxDecoration(
                color: const Color(0xFF1E1040),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.5),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: items.map((item) {
                  if (item.isDivider) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: Divider(height: 1, color: Colors.white.withOpacity(0.1)),
                    );
                  }
                  return _ContextMenuItemWidget(
                    item: item,
                    onTap: () {
                      item.onTap?.call();
                      onDismiss?.call();
                    },
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ContextMenuItemWidget extends StatefulWidget {
  final ContextMenuItem item;
  final VoidCallback onTap;

  const _ContextMenuItemWidget({required this.item, required this.onTap});

  @override
  State<_ContextMenuItemWidget> createState() => _ContextMenuItemWidgetState();
}

class _ContextMenuItemWidgetState extends State<_ContextMenuItemWidget> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final color = item.isDestructive
        ? const Color(0xFFEF4444)
        : _isHovered
            ? const Color(0xFF7C4DFF)
            : Colors.white.withOpacity(0.8);

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          color: _isHovered
              ? (item.isDestructive
                  ? const Color(0xFFEF4444).withOpacity(0.15)
                  : const Color(0xFF7C4DFF).withOpacity(0.15))
              : Colors.transparent,
          child: Row(
            children: [
              Icon(item.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  item.label,
                  style: TextStyle(
                    color: color,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              if (item.shortcut != null)
                Text(
                  item.shortcut!,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.35),
                    fontSize: 11,
                    fontWeight: FontWeight.w400,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

void showAdminContextMenu(
  BuildContext context,
  Offset position, {
  required VoidCallback onOpen,
  required VoidCallback onCopy,
  required VoidCallback onCut,
  required VoidCallback onPaste,
  required VoidCallback onRename,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  bool canPaste = true,
  bool canEdit = true,
}) {
  AdminContextMenu.show(
    context,
    position,
    [
      ContextMenuItem(
        icon: Icons.folder_open_rounded,
        label: 'Open',
        shortcut: 'Enter',
        onTap: onOpen,
      ),
      ContextMenuItem(
        icon: Icons.copy_rounded,
        label: 'Copy',
        shortcut: 'Ctrl+C',
        onTap: onCopy,
      ),
      ContextMenuItem(
        icon: Icons.cut_rounded,
        label: 'Cut',
        shortcut: 'Ctrl+X',
        onTap: onCut,
      ),
      ContextMenuItem(
        icon: Icons.paste_rounded,
        label: 'Paste',
        shortcut: 'Ctrl+V',
        onTap: canPaste ? onPaste : null,
      ),
      const ContextMenuItem(
        icon: Icons.circle,
        label: '',
        isDivider: true,
      ),
      ContextMenuItem(
        icon: Icons.edit_rounded,
        label: 'Rename',
        shortcut: 'F2',
        onTap: onRename,
      ),
      ContextMenuItem(
        icon: Icons.edit_note_rounded,
        label: 'Edit',
        shortcut: 'Ctrl+E',
        onTap: canEdit ? onEdit : null,
      ),
      ContextMenuItem(
        icon: Icons.content_copy_rounded,
        label: 'Duplicate',
        shortcut: 'Ctrl+D',
        onTap: onCopy,
      ),
      const ContextMenuItem(
        icon: Icons.circle,
        label: '',
        isDivider: true,
      ),
      ContextMenuItem(
        icon: Icons.delete_rounded,
        label: 'Delete',
        shortcut: 'Del',
        onTap: onDelete,
        isDestructive: true,
      ),
    ],
  );
}
