import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../../../core/services/firebase_service.dart';
import '../../../core/helpers/blob_helper_stub.dart'
    if (dart.library.html) '../../../core/helpers/blob_helper.dart';

class DrawPoint {
  final Offset position;
  final Color color;
  final double width;
  DrawPoint(this.position, this.color, this.width);
}

enum _ActionType { stroke, text }

class _Action {
  final _ActionType type;
  final List<DrawPoint>? stroke;
  final _TextAnnotation? text;
  _Action({required this.type, this.stroke, this.text});
}

class PdfReaderScreen extends StatefulWidget {
  final String documentId;
  final String? folderId;
  final String? parentContentId;
  const PdfReaderScreen({super.key, required this.documentId, this.folderId, this.parentContentId});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  String? _localPath;
  bool _isLoading = true;
  String? _error;
  String? _fileName;

  // Annotation state
  bool _annotating = false;
  String _annotationTool = 'draw';
  final List<List<DrawPoint>> _strokes = [];
  List<DrawPoint> _currentStroke = [];
  Color _penColor = Colors.red;
  double _strokeWidth = 3.0;
  final List<_TextAnnotation> _textAnnotations = [];

  // Undo/Redo
  final List<_Action> _undoStack = [];
  final List<_Action> _redoStack = [];

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  Future<void> _loadPdf() async {
    try {
      final url = widget.documentId;
      if (url.isEmpty) {
        setState(() { _error = 'No file path provided'; _isLoading = false; });
        return;
      }

      final rawName = url.split('/').last.split('?').first.split('#').first;
      _fileName = rawName.replaceAll(RegExp(r'[%&+:?/#\\]'), '_');
      _fileName = _fileName!.replaceFirst(RegExp(r'^\d+_'), '');

      if (kIsWeb) {
        try {
          final response = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 20));
          if (response.statusCode == 200 && response.bodyBytes.length > 100) {
            final blobUrl = createBlobUrl(response.bodyBytes, 'application/pdf');
            setState(() { _localPath = blobUrl; _isLoading = false; });
            return;
          }
        } catch (_) {}
        setState(() { _error = 'Could not load PDF. Check your connection.'; _isLoading = false; });
        return;
      }

      if (url.startsWith('http://') || url.startsWith('https://')) {
        final dir = await getTemporaryDirectory();
        final safeName = _fileName!.replaceAll(RegExp(r'[^\w\.\-]'), '_');
        final localFile = File('${dir.path}/$safeName');
        if (!await localFile.exists()) {
          final response = await http.get(Uri.parse(url));
          if (response.statusCode == 200) {
            await localFile.writeAsBytes(response.bodyBytes);
          } else {
            setState(() { _error = 'Failed to download PDF'; _isLoading = false; });
            return;
          }
        }
        if (!mounted) return;
        if (await localFile.exists()) {
          setState(() { _localPath = localFile.path; _isLoading = false; });
        } else {
          setState(() { _error = 'Downloaded file not found'; _isLoading = false; });
        }
      } else {
        final file = File(url);
        if (await file.exists()) {
          setState(() { _localPath = url; _isLoading = false; });
        } else {
          setState(() { _error = 'File not found on device'; _isLoading = false; });
        }
      }
    } catch (e) {
      setState(() { _error = 'Error: $e'; _isLoading = false; });
    }
  }

  void _pushStrokeUndo(List<DrawPoint> stroke) {
    _undoStack.add(_Action(type: _ActionType.stroke, stroke: stroke));
    _redoStack.clear();
  }

  void _pushTextUndo(_TextAnnotation text) {
    _undoStack.add(_Action(type: _ActionType.text, text: text));
    _redoStack.clear();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    final action = _undoStack.removeLast();
    setState(() {
      if (action.type == _ActionType.stroke && action.stroke != null) {
        _strokes.removeLast();
      } else if (action.type == _ActionType.text && action.text != null) {
        _textAnnotations.remove(action.text);
      }
      _redoStack.add(action);
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    final action = _redoStack.removeLast();
    setState(() {
      if (action.type == _ActionType.stroke && action.stroke != null) {
        _strokes.add(action.stroke!);
      } else if (action.type == _ActionType.text && action.text != null) {
        _textAnnotations.add(action.text!);
      }
      _undoStack.add(action);
    });
  }

  void _clearAnnotations() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
      _textAnnotations.clear();
      _undoStack.clear();
      _redoStack.clear();
    });
  }

  Future<void> _saveAnnotationsToNotes() async {
    final noteContent = StringBuffer();
    noteContent.writeln('--- PDF Annotations: ${_fileName ?? 'PDF'} ---');
    noteContent.writeln();
    if (_textAnnotations.isNotEmpty) {
      noteContent.writeln('Text Notes:');
      for (final t in _textAnnotations) {
        noteContent.writeln('- ${t.text}');
      }
      noteContent.writeln();
    }
    if (_strokes.isNotEmpty) {
      noteContent.writeln('[${_strokes.length} drawing stroke(s) made]');
    }

    final lectureId = 'pdf_${DateTime.now().millisecondsSinceEpoch}';
    try {
      await FirebaseService.saveNote(lectureId, noteContent.toString(), lectureName: 'PDF: ${_fileName ?? 'Unknown'}');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Saved to Notes!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isLoading ? 'Loading...' : (_fileName ?? 'PDF Viewer')),
        actions: [
          if (_localPath != null)
            IconButton(
              icon: Icon(_annotating ? Icons.edit_off_rounded : Icons.edit_rounded),
              tooltip: _annotating ? 'Stop Annotating' : 'Annotate',
              onPressed: () => setState(() {
                _annotating = !_annotating;
                if (!_annotating) _annotationTool = 'draw';
              }),
            ),
        ],
      ),
      body: Column(
        children: [
          if (_annotating) _buildInlineToolbar(isDark),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildErrorView()
                    : kIsWeb
                        ? _buildWebPdfView()
                        : _buildMobilePdfView(),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineToolbar(bool isDark) {
    final bgColor = isDark ? const Color(0xFF140326) : const Color(0xFFE5DDF5);
    final borderColor = isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.08);
    final textColor = isDark ? Colors.white70 : const Color(0xFF1A0533).withValues(alpha: 0.8);
    final hasContent = _strokes.isNotEmpty || _textAnnotations.isNotEmpty;

    return Container(
      color: bgColor,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolBtn(Icons.draw_rounded, 'Draw', _annotationTool == 'draw', () => setState(() => _annotationTool = 'draw'), isDark),
            const SizedBox(width: 4),
            _toolBtn(Icons.text_fields_rounded, 'Text', _annotationTool == 'text', () => setState(() => _annotationTool = 'text'), isDark),
            const SizedBox(width: 4),
            _toolBtn(Icons.auto_fix_normal_rounded, 'Eraser', _annotationTool == 'erase', () => setState(() => _annotationTool = 'erase'), isDark),
            const SizedBox(width: 8),
            Container(height: 20, width: 1, color: borderColor),
            const SizedBox(width: 8),

            if (_annotationTool == 'draw') ...[
              _colorBtn(Colors.red),
              _colorBtn(Colors.blue),
              _colorBtn(Colors.black),
              _colorBtn(Colors.green),
              _colorBtn(Colors.orange),
              const SizedBox(width: 8),
              Container(height: 20, width: 1, color: borderColor),
              const SizedBox(width: 8),
              _strokeWidthBtn(2),
              _strokeWidthBtn(5),
              _strokeWidthBtn(10),
              const SizedBox(width: 8),
              Container(height: 20, width: 1, color: borderColor),
              const SizedBox(width: 8),
            ],

            if (_annotationTool == 'text')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('Tap PDF to add text', style: TextStyle(color: textColor, fontSize: 12, fontStyle: FontStyle.italic)),
              ),

            if (_annotationTool == 'erase')
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text('Draw over strokes to erase', style: TextStyle(color: textColor, fontSize: 12, fontStyle: FontStyle.italic)),
              ),

            _undoRedoBtn(Icons.undo_rounded, _undoStack.isNotEmpty, _undo, isDark),
            const SizedBox(width: 4),
            _undoRedoBtn(Icons.redo_rounded, _redoStack.isNotEmpty, _redo, isDark),

            if (hasContent) ...[
              const SizedBox(width: 8),
              Container(height: 20, width: 1, color: borderColor),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _saveAnnotationsToNotes,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.save_rounded, color: Colors.teal, size: 14),
                      SizedBox(width: 4),
                      Text('Save', style: TextStyle(color: Colors.teal, fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  _clearAnnotations();
                  setState(() => _annotating = false);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withValues(alpha: 0.15),
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
  }

  Widget _undoRedoBtn(IconData icon, bool enabled, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: enabled
              ? (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.06))
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled
              ? (isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.12))
              : Colors.transparent),
        ),
        child: Icon(icon, color: enabled ? (isDark ? Colors.white70 : Colors.black54) : (isDark ? Colors.white12 : Colors.black12), size: 18),
      ),
    );
  }

  Widget _toolBtn(IconData icon, String label, bool active, VoidCallback onTap, bool isDark) {
    final activeBg = isDark ? const Color(0xFF4A148C) : const Color(0xFFB388FF).withValues(alpha: 0.4);
    final activeBorder = isDark ? const Color(0xFF00B8D4) : const Color(0xFF4A148C);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeBg : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: active ? activeBorder : (isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.09))),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: active ? (isDark ? Colors.white : const Color(0xFF4A148C)) : (isDark ? Colors.white38 : Colors.black38), size: 16),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(
              color: active ? (isDark ? Colors.white : const Color(0xFF4A148C)) : (isDark ? Colors.white38 : Colors.black38),
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }

  Widget _colorBtn(Color color) {
    final selected = _penColor == color;
    return GestureDetector(
      onTap: () => setState(() { _penColor = color; _annotationTool = 'draw'; }),
      child: Container(
        margin: const EdgeInsets.only(right: 5),
        width: 22, height: 22,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? Colors.white : Colors.white24, width: selected ? 2.5 : 1),
          boxShadow: selected ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)] : null,
        ),
      ),
    );
  }

  Widget _strokeWidthBtn(double width) {
    final selected = _strokeWidth == width;
    return GestureDetector(
      onTap: () => setState(() => _strokeWidth = width),
      child: Container(
        margin: const EdgeInsets.only(right: 5),
        width: width + 8, height: width + 8,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected ? Colors.white : Colors.white24,
        ),
      ),
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 64, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_error!, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () { setState(() { _isLoading = true; _error = null; }); _loadPdf(); },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWebPdfView() {
    if (_annotating) {
      return Stack(
        children: [
          HtmlElementView.fromTagName(
            tagName: 'div',
            onElementCreated: (Object element) {
              final div = element as dynamic;
              div.id = 'pdf-viewer-${DateTime.now().millisecondsSinceEpoch}';
              div.setAttribute('data-pdf-url', _localPath!);
              div.style.width = '100%';
              div.style.height = '100%';
              div.style.background = '#525355';
              div.style.overflow = 'auto';
            },
          ),
          _buildAnnotationOverlay(),
        ],
      );
    }
    return HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (Object element) {
        final div = element as dynamic;
        div.id = 'pdf-viewer-${DateTime.now().millisecondsSinceEpoch}';
        div.setAttribute('data-pdf-url', _localPath!);
        div.style.width = '100%';
        div.style.height = '100%';
        div.style.background = '#525355';
        div.style.overflow = 'auto';
      },
    );
  }

  Widget _buildMobilePdfView() {
    if (_annotating) {
      return Stack(
        children: [
          Center(
            child: Text('PDF loaded: $_localPath', style: const TextStyle(color: Colors.white70)),
          ),
          _buildAnnotationOverlay(),
        ],
      );
    }
    return Center(
      child: Text('PDF loaded: $_localPath', style: const TextStyle(color: Colors.white70)),
    );
  }

  Widget _buildAnnotationOverlay() {
    final isEraser = _annotationTool == 'erase';

    if (_annotationTool == 'text') {
      return Positioned.fill(
        child: GestureDetector(
          onTapUp: (details) => _addTextAtPosition(details.localPosition),
          child: Container(
            color: Colors.transparent,
            child: Stack(
              children: [
                for (final t in _textAnnotations)
                  Positioned(
                    left: t.position.dx,
                    top: t.position.dy,
                    child: GestureDetector(
                      onPanUpdate: (d) {
                        setState(() {
                          t.position = Offset(t.position.dx + d.delta.dx, t.position.dy + d.delta.dy);
                        });
                      },
                      child: Material(
                        color: Colors.yellow.withValues(alpha: 0.85),
                        elevation: 4,
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          child: Text(t.text, style: const TextStyle(color: Colors.black, fontSize: 14, fontWeight: FontWeight.w500)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Positioned.fill(
      child: GestureDetector(
        onPanStart: isEraser ? (details) {
          _eraseAt(details.localPosition);
        } : (details) {
          setState(() {
            _currentStroke = [DrawPoint(details.localPosition, _penColor, _strokeWidth)];
          });
        },
        onPanUpdate: isEraser ? (details) {
          _eraseAt(details.localPosition);
        } : (details) {
          setState(() {
            _currentStroke.add(DrawPoint(details.localPosition, _penColor, _strokeWidth));
          });
        },
        onPanEnd: isEraser ? (_) {} : (_) {
          final stroke = List<DrawPoint>.from(_currentStroke);
          setState(() {
            _strokes.add(stroke);
            _currentStroke = [];
          });
          _pushStrokeUndo(stroke);
        },
        child: CustomPaint(
          painter: _AnnotationPainter(
            strokes: _strokes,
            currentStroke: _currentStroke,
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  void _eraseAt(Offset position) {
    const eraserRadius = 25.0;
    final removed = <List<DrawPoint>>[];
    setState(() {
      _strokes.removeWhere((stroke) {
        final hit = stroke.any((p) => (p.position - position).distance < eraserRadius);
        if (hit) removed.add(stroke);
        return hit;
      });
    });
    for (final s in removed) {
      _undoStack.add(_Action(type: _ActionType.stroke, stroke: s));
      _redoStack.clear();
    }
  }

  void _addTextAtPosition(Offset position) {
    final ctrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Add Text'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'Type your note...',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                final annotation = _TextAnnotation(text: ctrl.text.trim(), position: position);
                setState(() {
                  _textAnnotations.add(annotation);
                });
                _pushTextUndo(annotation);
              }
              Navigator.pop(ctx);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

class _TextAnnotation {
  String text;
  Offset position;
  _TextAnnotation({required this.text, required this.position});
}

class _AnnotationPainter extends CustomPainter {
  final List<List<DrawPoint>> strokes;
  final List<DrawPoint> currentStroke;

  _AnnotationPainter({required this.strokes, required this.currentStroke});

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
  bool shouldRepaint(covariant _AnnotationPainter old) => true;
}
