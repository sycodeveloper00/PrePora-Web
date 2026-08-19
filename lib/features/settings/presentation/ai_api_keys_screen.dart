import 'package:flutter/material.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/widgets/professional_loader.dart';

class AiApiKeysScreen extends StatefulWidget {
  const AiApiKeysScreen({super.key});
  @override
  State<AiApiKeysScreen> createState() => _AiApiKeysScreenState();
}

class _AiApiKeysScreenState extends State<AiApiKeysScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _keys = [];

  static const _providers = [
    {'id': 'openai', 'label': 'OpenAI-compatible (BazaarLink, Groq, OpenRouter, etc.)'},
    {'id': 'gemini', 'label': 'Google Gemini'},
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final keys = await FirebaseService.getAiApiKeys();
    if (mounted) {
      setState(() {
        _keys = keys;
        _loading = false;
      });
    }
  }

  String _providerLabel(String? id) {
    for (final p in _providers) {
      if (p['id'] == id) return p['label'] as String;
    }
    return id ?? 'openai';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final hintColor = isDark ? Colors.white38 : Colors.black54;

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI API Keys', style: TextStyle(fontWeight: FontWeight.bold)),
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
                          const Icon(Icons.auto_awesome_rounded, color: Colors.deepPurple),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('AI API Keys', style: TextStyle(color: textColor, fontWeight: FontWeight.w600)),
                                Text('${_keys.length} key(s) \u00b7 One active at a time', style: TextStyle(color: hintColor, fontSize: 12)),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.add_circle_rounded, color: Colors.deepPurple, size: 28),
                            onPressed: () => _showAddKeyDialog(),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        if (_keys.isEmpty)
                          _emptyState('No AI API keys', 'Tap + to add your first API key', Icons.auto_awesome_outlined, isDark, hintColor)
                        else
                          ...List.generate(_keys.length, (i) {
                            final k = _keys[i];
                            final isActive = k['isActive'] as bool? ?? false;
                            return _keyTile(
                              k: k, isActive: isActive,
                              textColor: textColor, hintColor: hintColor, isDark: isDark,
                              onToggle: () async {
                                if (isActive) return;
                                setState(() {
                                  for (final x in _keys) {
                                    x['isActive'] = (x['id'] == k['id']);
                                  }
                                });
                                try {
                                  await FirebaseService.updateAiApiKey(k['id'], isActive: true);
                                  AiService.refreshKey();
                                } catch (_) {}
                              },
                              onEdit: () => _showEditKeyDialog(k),
                              onDelete: () => _showDeleteKeyDialog(k),
                              onRemoveModel: (m) => _removeModel(k, m),
                              onMoveModel: (m, delta) => _moveModel(k, m, delta),
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

  Widget _keyTile({
    required Map<String, dynamic> k, required bool isActive,
    required Color textColor, required Color hintColor, required bool isDark,
    required VoidCallback onToggle, required VoidCallback onEdit, required VoidCallback onDelete,
    required void Function(String) onRemoveModel,
    required void Function(String, int) onMoveModel,
  }) {
    final name = k['name'] as String? ?? 'AI Key';
    final model = k['model'] as String? ?? '';
    final provider = k['provider'] as String? ?? 'openai';
    final rawModels = k['models'];
    final List<String> models = rawModels is List
        ? rawModels.map((m) => m.toString()).where((m) => m.trim().isNotEmpty).toList()
        : (rawModels is String && rawModels.trim().isNotEmpty ? [rawModels] : const <String>[]);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isActive ? Colors.deepPurple.withValues(alpha: 0.08) : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isActive ? Colors.deepPurple.withValues(alpha: 0.4) : (isDark ? Colors.white12 : Colors.black12)),
      ),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(shape: BoxShape.circle, color: isActive ? Colors.deepPurple : Colors.grey.withValues(alpha: 0.4))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(name, style: TextStyle(color: textColor, fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
              if (isActive)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.deepPurple.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                  child: const Text('ACTIVE', style: TextStyle(color: Colors.deepPurple, fontSize: 10, fontWeight: FontWeight.w700)),
                ),
            ]),
            const SizedBox(height: 2),
            Text(_providerLabel(provider), style: TextStyle(color: hintColor, fontSize: 11)),
            if (model.isNotEmpty)
              Text(model, style: TextStyle(color: hintColor, fontSize: 11), overflow: TextOverflow.ellipsis),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var mi = 0; mi < models.length; mi++)
                  InputChip(
                    label: Text(models[mi], style: const TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    onDeleted: () => onRemoveModel(models[mi]),
                    backgroundColor: isDark ? Colors.white12 : Colors.deepPurple.withValues(alpha: 0.08),
                    side: BorderSide(color: isDark ? Colors.white24 : Colors.deepPurple.withValues(alpha: 0.3)),
                    labelStyle: TextStyle(color: isDark ? Colors.white70 : Colors.deepPurple),
                    deleteIconColor: Colors.redAccent,
                    avatar: Row(mainAxisSize: MainAxisSize.min, children: [
                      InkWell(
                        onTap: () => onMoveModel(models[mi], -1),
                        child: const Icon(Icons.keyboard_arrow_up_rounded, size: 16, color: Colors.deepPurple),
                      ),
                      InkWell(
                        onTap: () => onMoveModel(models[mi], 1),
                        child: const Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: Colors.deepPurple),
                      ),
                    ]),
                  ),
              ],
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Switch(value: isActive, activeThumbColor: Colors.deepPurple, onChanged: (_) => onToggle()),
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

  void _showAddKeyDialog() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController();
    final baseUrlCtrl = TextEditingController();
    final keyCtrl = TextEditingController();
    String provider = 'openai';
    bool isLoading = false;
    String? errorMsg;
    List<String> editorModels = [];

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.auto_awesome_rounded, color: Colors.deepPurple, size: 22), const SizedBox(width: 8), Text('Add AI API Key', style: TextStyle(color: baseColor, fontSize: 16))]),
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
            TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Key Name', hintText: 'e.g. BazaarLink Free', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: provider,
              dropdownColor: bgColor,
              style: TextStyle(color: baseColor),
              decoration: InputDecoration(labelText: 'Provider', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              items: _providers.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text(p['label'] as String, style: TextStyle(color: baseColor, fontSize: 12)))).toList(),
              onChanged: (v) { if (v != null) setDialog(() => provider = v); },
            ),
            const SizedBox(height: 12),
            TextField(controller: baseUrlCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Base URL', hintText: provider == 'gemini' ? 'https://generativelanguage.googleapis.com' : 'https://bazaarlink.ai/api/v1', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: keyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'API Key', hintText: provider == 'gemini' ? 'AIza...' : 'sk-...', labelStyle: TextStyle(color: dimColor), hintStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            _ModelsEditor(
              initial: const [],
              onChanged: (v) => editorModels = v,
              baseColor: baseColor,
              dimColor: dimColor,
              fillColor: fillColor,
            ),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              final models = editorModels.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
              if (nameCtrl.text.trim().isEmpty || baseUrlCtrl.text.trim().isEmpty || keyCtrl.text.trim().isEmpty || models.isEmpty) return;
              setDialog(() { isLoading = true; errorMsg = null; });
              try {
                await FirebaseService.addAiApiKey(
                  name: nameCtrl.text.trim(),
                  provider: provider,
                  baseUrl: baseUrlCtrl.text.trim(),
                  apiKey: keyCtrl.text.trim(),
                  model: models.first,
                  models: models,
                  isActive: true,
                );
                AiService.refreshKey();
                if (d.mounted) Navigator.pop(d);
                _load();
              } catch (e) {
                setDialog(() { isLoading = false; errorMsg = 'Failed to save key: $e'; });
              }
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

  void _showEditKeyDialog(Map<String, dynamic> k) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black12;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController(text: k['name'] as String? ?? '');
    final baseUrlCtrl = TextEditingController(text: k['baseUrl'] as String? ?? '');
    final keyCtrl = TextEditingController(text: k['apiKey'] as String? ?? '');
    String provider = k['provider'] as String? ?? 'openai';
    bool isLoading = false;
    List<String> editorModels = [];
    final rawModels = k['models'];
    editorModels = rawModels is List
        ? rawModels.map((m) => m.toString()).where((m) => m.trim().isNotEmpty).toList()
        : ((k['model'] as String? ?? '').trim().isNotEmpty ? [k['model'] as String] : <String>[]);

    showDialog(context: context, builder: (d) => StatefulBuilder(builder: (ctx, setDialog) {
      return AlertDialog(
        backgroundColor: bgColor,
        title: Row(children: [const Icon(Icons.edit_rounded, color: Colors.deepPurple, size: 22), const SizedBox(width: 8), Text('Edit AI API Key', style: TextStyle(color: baseColor, fontSize: 16))]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: nameCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Key Name', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: provider,
              dropdownColor: bgColor,
              style: TextStyle(color: baseColor),
              decoration: InputDecoration(labelText: 'Provider', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
              items: _providers.map((p) => DropdownMenuItem(value: p['id'] as String, child: Text(p['label'] as String, style: TextStyle(color: baseColor, fontSize: 12)))).toList(),
              onChanged: (v) { if (v != null) setDialog(() => provider = v); },
            ),
            const SizedBox(height: 12),
            TextField(controller: baseUrlCtrl, style: TextStyle(color: baseColor), decoration: InputDecoration(labelText: 'Base URL', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            TextField(controller: keyCtrl, style: TextStyle(color: baseColor), maxLines: 3, decoration: InputDecoration(labelText: 'API Key', labelStyle: TextStyle(color: dimColor), filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
            const SizedBox(height: 12),
            _ModelsEditor(
              initial: editorModels,
              onChanged: (v) => editorModels = v,
              baseColor: baseColor,
              dimColor: dimColor,
              fillColor: fillColor,
            ),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
          ElevatedButton(
            onPressed: isLoading ? null : () async {
              final models = editorModels.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
              if (nameCtrl.text.trim().isEmpty || baseUrlCtrl.text.trim().isEmpty || keyCtrl.text.trim().isEmpty || models.isEmpty) return;
              setDialog(() { isLoading = true; });
              try {
                await FirebaseService.updateAiApiKey(
                  k['id'],
                  name: nameCtrl.text.trim(),
                  provider: provider,
                  baseUrl: baseUrlCtrl.text.trim(),
                  apiKey: keyCtrl.text.trim(),
                  model: models.first,
                  models: models,
                );
                AiService.refreshKey();
                if (d.mounted) Navigator.pop(d);
                _load();
              } catch (_) {
                setDialog(() { isLoading = false; });
              }
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

  void _removeModel(Map<String, dynamic> k, String m) {
    final rawModels = k['models'];
    final List<String> models = rawModels is List
        ? rawModels.map((x) => x.toString()).where((x) => x != m).toList()
        : <String>[];
    setState(() { k['models'] = models; });
    FirebaseService.updateAiApiKey(k['id'], models: models);
    AiService.refreshKey();
  }

  void _moveModel(Map<String, dynamic> k, String m, int delta) {
    final rawModels = k['models'];
    final List<String> models = rawModels is List
        ? rawModels.map((x) => x.toString()).toList()
        : <String>[];
    final i = models.indexOf(m);
    if (i < 0) return;
    final j = i + delta;
    if (j < 0 || j >= models.length) return;
    final t = models.removeAt(i);
    models.insert(j, t);
    setState(() { k['models'] = models; });
    FirebaseService.updateAiApiKey(k['id'], models: models);
    AiService.refreshKey();
  }

  void _showDeleteKeyDialog(Map<String, dynamic> k) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final name = k['name'] as String? ?? 'this key';
    final isActive = k['isActive'] as bool? ?? false;
    final activeCount = _keys.where((x) => x['isActive'] == true).length;
    if (isActive && activeCount <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot delete the only active key. Add another first.'), backgroundColor: Colors.orange));
      return;
    }
    showDialog(context: context, builder: (d) => AlertDialog(
      backgroundColor: bgColor,
      title: Row(children: [const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 22), const SizedBox(width: 8), Text('Delete API Key', style: TextStyle(color: baseColor, fontSize: 16))]),
      content: SizedBox(width: 400, child: Text('Delete $name? This cannot be undone.', style: TextStyle(color: dimColor, fontSize: 13))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d), child: Text('Cancel', style: TextStyle(color: dimColor))),
        ElevatedButton(onPressed: () async {
          await FirebaseService.deleteAiApiKey(k['id']);
          AiService.refreshKey();
          if (d.mounted) Navigator.pop(d);
          _load();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent), child: const Text('Delete', style: TextStyle(color: Colors.white))),
      ],
    ));
  }
}

/// Ordered model-pool editor used in the Add/Edit key dialogs. Models are tried
/// in the order shown (top = preferred), so up/down arrows reorder them.
class _ModelsEditor extends StatefulWidget {
  final List<String> initial;
  final void Function(List<String>) onChanged;
  final Color baseColor;
  final Color dimColor;
  final Color fillColor;
  const _ModelsEditor({
    required this.initial,
    required this.onChanged,
    required this.baseColor,
    required this.dimColor,
    required this.fillColor,
  });

  @override
  State<_ModelsEditor> createState() => _ModelsEditorState();
}

class _ModelsEditorState extends State<_ModelsEditor> {
  late final List<TextEditingController> _boxes;

  @override
  void initState() {
    super.initState();
    _boxes = [...widget.initial.map((m) => m.trim()).where((m) => m.isNotEmpty),
              if (widget.initial.every((m) => m.trim().isEmpty)) '']
        .map((m) => TextEditingController(text: m))
        .toList();
    if (_boxes.isEmpty) _boxes.add(TextEditingController());
  }

  void _emit() {
    widget.onChanged(_boxes.map((c) => c.text.trim()).where((s) => s.isNotEmpty).toList());
  }

  void _addBox() {
    setState(() => _boxes.add(TextEditingController()));
  }

  void _removeBox(int i) {
    setState(() {
      _boxes.removeAt(i).dispose();
      if (_boxes.isEmpty) _boxes.add(TextEditingController());
    });
    _emit();
  }

  void _move(int i, int delta) {
    final j = i + delta;
    if (j < 0 || j >= _boxes.length) return;
    setState(() {
      final t = _boxes.removeAt(i);
      _boxes.insert(j, t);
    });
    _emit();
  }

  @override
  void dispose() {
    for (final c in _boxes) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.baseColor == Colors.white;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Models in order of preference (top = tried first). Har box mein ek model likhein.', style: TextStyle(color: widget.dimColor, fontSize: 11, height: 1.4)),
      const SizedBox(height: 10),
      for (var i = 0; i < _boxes.length; i++)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _boxes[i],
                style: TextStyle(color: widget.baseColor),
                onChanged: (_) => _emit(),
                decoration: InputDecoration(
                  labelText: 'Model ${i + 1}',
                  hintText: 'e.g. qwen/qwen3.7-flash:free',
                  labelStyle: TextStyle(color: widget.dimColor),
                  hintStyle: TextStyle(color: widget.dimColor),
                  filled: true,
                  fillColor: widget.fillColor,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up_rounded, color: Colors.deepPurple),
              visualDensity: VisualDensity.compact,
              onPressed: i == 0 ? null : () => _move(i, -1),
              tooltip: 'Higher priority',
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.deepPurple),
              visualDensity: VisualDensity.compact,
              onPressed: i == _boxes.length - 1 ? null : () => _move(i, 1),
              tooltip: 'Lower priority',
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.redAccent),
              visualDensity: VisualDensity.compact,
              onPressed: () => _removeBox(i),
              tooltip: 'Remove model',
            ),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(
            icon: const Icon(Icons.add_circle_rounded, color: Colors.deepPurple),
            onPressed: _addBox,
            tooltip: 'Add model box',
          ),
          Text('Add Model Box', style: TextStyle(color: isDark ? Colors.deepPurple.shade200 : Colors.deepPurple, fontSize: 12)),
        ]),
      ),
    ]);
  }
}