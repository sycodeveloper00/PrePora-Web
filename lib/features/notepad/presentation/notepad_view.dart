import 'package:flutter/material.dart';
import '../../../core/services/firebase_service.dart';

class DrawPoint {
  final Offset position;
  final Color color;
  final double width;
  DrawPoint(this.position, this.color, this.width);
}

class NotepadView extends StatefulWidget {
  final String lectureId;
  final String lectureName;
  final bool isEmbedded;
  final VoidCallback? onClose;
  final VoidCallback? onFullScreenToggle;
  final bool isFullScreen;

  const NotepadView({
    super.key,
    required this.lectureId,
    required this.lectureName,
    this.isEmbedded = false,
    this.onClose,
    this.onFullScreenToggle,
    this.isFullScreen = false,
  });

  @override
  State<NotepadView> createState() => _NotepadViewState();
}

class _NotepadViewState extends State<NotepadView> {
  bool _isDrawMode = false;
  final _textController = TextEditingController();

  // Drawing state
  final List<List<DrawPoint>> _strokes = [];
  List<DrawPoint> _currentStroke = [];
  Color _penColor = Colors.blue;
  double _strokeWidth = 3.0;
  bool _isEraser = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadNote();
  }

  Future<void> _loadNote() async {
    final doc = await FirebaseService.getNote(widget.lectureId);
    if (doc != null && mounted) {
      setState(() => _textController.text = (doc.data() as Map<String, dynamic>?)?['content'] ?? '');
    }
  }

  Future<void> _saveNote() async {
    setState(() => _isSaving = true);
    await FirebaseService.saveNote(widget.lectureId, _textController.text, lectureName: widget.lectureName);
    if (mounted) {
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('âœ… Note saved!'), backgroundColor: Colors.green),
      );
    }
  }

  void _clearCanvas() {
    setState(() => _strokes.clear());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = isDark ? const Color(0xFF1A0533) : const Color(0xFFEFE8FC);
    final editorBg = isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04);
    final inputBorderColor = isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.1);
    final textColor = isDark ? Colors.white : const Color(0xFF1A0533);
    final toolbarTextIconColor = isDark ? Colors.white70 : const Color(0xFF1A0533).withValues(alpha: 0.8);

    Widget header = Container(
      color: headerColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.isEmbedded ? 'NotePad' : widget.lectureName,
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textColor),
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.isEmbedded)
                  Text(
                    widget.lectureName,
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white54 : Colors.black54),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (_isSaving)
            const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.blue))
          else
            IconButton(
              icon: const Icon(Icons.save_rounded, color: Colors.blue, size: 20),
              onPressed: _isDrawMode ? null : _saveNote,
              tooltip: 'Save Note',
            ),
          if (widget.isEmbedded && widget.onFullScreenToggle != null)
            IconButton(
              icon: Icon(widget.isFullScreen ? Icons.fullscreen_exit_rounded : Icons.fullscreen_rounded, color: toolbarTextIconColor, size: 22),
              onPressed: widget.onFullScreenToggle,
              tooltip: widget.isFullScreen ? 'Exit Full Screen' : 'Full Screen',
            ),
          if (widget.isEmbedded && widget.onClose != null)
            IconButton(
              icon: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
              onPressed: widget.onClose,
              tooltip: 'Close NotePad',
            ),
        ],
      ),
    );

    Widget toolbar = Container(
      color: isDark ? const Color(0xFF140326) : const Color(0xFFE5DDF5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _modeToggleBtn(Icons.edit_rounded, 'Draw', _isDrawMode, () => setState(() => _isDrawMode = true), isDark),
            const SizedBox(width: 6),
            _modeToggleBtn(Icons.keyboard_rounded, 'Type', !_isDrawMode, () => setState(() => _isDrawMode = false), isDark),
            const SizedBox(width: 12),
            Container(height: 20, width: 1, color: isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.09)),
            const SizedBox(width: 12),
            if (_isDrawMode) ...[
              _colorBtn(Colors.blue),
              _colorBtn(Colors.black),
              _colorBtn(Colors.red),
              _colorBtn(Colors.green),
              _colorBtn(Colors.orange),
              const SizedBox(width: 10),
              Container(height: 20, width: 1, color: isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.09)),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => setState(() => _strokeWidth = 2),
                child: _strokeIcon(2, _strokeWidth == 2, isDark),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _strokeWidth = 5),
                child: _strokeIcon(5, _strokeWidth == 5, isDark),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () => setState(() => _strokeWidth = 10),
                child: _strokeIcon(10, _strokeWidth == 10, isDark),
              ),
              const SizedBox(width: 10),
              Container(height: 20, width: 1, color: isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.09)),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: () => setState(() => _isEraser = !_isEraser),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isEraser ? (isDark ? Colors.white24 : Colors.black12) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: _isEraser ? (isDark ? Colors.white : Colors.black87) : (isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.09))),
                  ),
                  child: Icon(Icons.auto_fix_normal_rounded, color: toolbarTextIconColor, size: 18),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _clearCanvas,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: const Text('Clear', style: TextStyle(color: Colors.redAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ],
        ),
      ),
    );

    Widget content = Expanded(
      child: _isDrawMode
          ? Container(
              color: Colors.white,
              child: GestureDetector(
                onPanStart: (details) {
                  setState(() {
                    _currentStroke = [DrawPoint(details.localPosition, _isEraser ? Colors.white : _penColor, _isEraser ? 20 : _strokeWidth)];
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    _currentStroke.add(DrawPoint(details.localPosition, _isEraser ? Colors.white : _penColor, _isEraser ? 20 : _strokeWidth));
                  });
                },
                onPanEnd: (_) {
                  setState(() {
                    _strokes.add(List.from(_currentStroke));
                    _currentStroke = [];
                  });
                },
                child: CustomPaint(
                  painter: _DrawingPainter(strokes: _strokes, currentStroke: _currentStroke),
                  size: Size.infinite,
                ),
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                controller: _textController,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(color: textColor, fontSize: 14, height: 1.6),
                decoration: InputDecoration(
                  hintText: 'Start typing your notes here...',
                  hintStyle: TextStyle(color: isDark ? Colors.white24 : Colors.black38),
                  filled: true,
                  fillColor: editorBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: inputBorderColor),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: inputBorderColor),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.blue),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
    );

    return Container(
      color: isDark ? const Color(0xFF0D0D1A) : Colors.white,
      child: Column(
        children: [
          header,
          toolbar,
          content,
        ],
      ),
    );
  }

  Widget _modeToggleBtn(IconData icon, String label, bool active, VoidCallback onTap, bool isDark) {
    final activeBgColor = isDark ? const Color(0xFF4A148C) : const Color(0xFFB388FF).withValues(alpha: 0.4);
    final activeBorderColor = isDark ? const Color(0xFF00B8D4) : const Color(0xFF4A148C);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeBgColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? activeBorderColor : (isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.09))),
        ),
        child: Row(
          children: [
            Icon(icon, color: active ? (isDark ? Colors.white : const Color(0xFF4A148C)) : (isDark ? Colors.white38 : Colors.black38), size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: active ? (isDark ? Colors.white : const Color(0xFF4A148C)) : (isDark ? Colors.white38 : Colors.black38), fontSize: 12, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  Widget _colorBtn(Color color) {
    final selected = _penColor == color && !_isEraser;
    return GestureDetector(
      onTap: () => setState(() { _penColor = color; _isEraser = false; }),
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        width: 22,
        height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 2 : 1),
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
        ),
      ),
    );
  }

  Widget _strokeIcon(double size, bool selected, bool isDark) {
    return Container(
      width: size + 8,
      height: size + 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? (isDark ? Colors.white : Colors.black) : (isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.09)),
      ),
    );
  }
}

class _DrawingPainter extends CustomPainter {
  final List<List<DrawPoint>> strokes;
  final List<DrawPoint> currentStroke;

  _DrawingPainter({required this.strokes, required this.currentStroke});

  @override
  void paint(Canvas canvas, Size size) {
    for (final stroke in [...strokes, currentStroke]) {
      if (stroke.isEmpty) continue;
      for (int i = 0; i < stroke.length - 1; i++) {
        final paint = Paint()
          ..color = stroke[i].color
          ..strokeWidth = stroke[i].width
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        canvas.drawLine(stroke[i].position, stroke[i + 1].position, paint);
      }
      if (stroke.length == 1) {
        final paint = Paint()
          ..color = stroke[0].color
          ..strokeWidth = stroke[0].width
          ..strokeCap = StrokeCap.round;
        canvas.drawCircle(stroke[0].position, stroke[0].width / 2, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter old) => true;
}

