import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class WebViewWebWidget extends StatefulWidget {
  final String? url;
  final String? html;
  const WebViewWebWidget({super.key, this.url, this.html});

  @override
  State<WebViewWebWidget> createState() => _WebViewWebWidgetState();
}

class _WebViewWebWidgetState extends State<WebViewWebWidget> {
  String? _src;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSrc();
  }

  @override
  void didUpdateWidget(WebViewWebWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.url != oldWidget.url || widget.html != oldWidget.html) {
      _loading = true;
      _loadSrc();
    }
  }

  Future<Uint8List?> _fetchBytes(String url) async {
    final attempts = [
      url,
      'https://corsproxy.io/?url=${Uri.encodeComponent(url)}',
      'https://api.allorigins.win/raw?url=${Uri.encodeComponent(url)}',
    ];
    for (final attempt in attempts) {
      try {
        final response = await http.get(Uri.parse(attempt)).timeout(const Duration(seconds: 15));
        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          return response.bodyBytes;
        }
      } catch (_) {}
    }
    return null;
  }

  String _guessMime(String url) {
    final ext = url.split('?').first.split('#').first.split('.').last.toLowerCase();
    const mimes = {
      'pdf': 'application/pdf',
      'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
      'gif': 'image/gif', 'webp': 'image/webp', 'svg': 'image/svg+xml',
      'mp4': 'video/mp4', 'webm': 'video/webm', 'ogg': 'video/ogg',
      'mp3': 'audio/mpeg', 'wav': 'audio/wav',
      'doc': 'application/msword', 'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel', 'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'txt': 'text/plain', 'html': 'text/html',
    };
    return mimes[ext] ?? 'application/octet-stream';
  }

  Future<void> _loadSrc() async {
    if (widget.html != null && widget.html!.isNotEmpty) {
      setState(() {
        _src = 'data:text/html;charset=utf-8,${Uri.encodeComponent(widget.html!)}';
        _loading = false;
      });
      return;
    }
    final url = widget.url;
    if (url == null || url.isEmpty) {
      setState(() => _loading = false);
      return;
    }

    final mime = _guessMime(url);
    final ext = url.split('?').first.split('#').first.split('.').last.toLowerCase();

    if (['doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'].contains(ext)) {
      final gviewUrl = 'https://docs.google.com/gview?url=${Uri.encodeComponent(url)}&embedded=true';
      setState(() {
        _src = gviewUrl;
        _loading = false;
      });
      return;
    }

    final bytes = await _fetchBytes(url);
    if (bytes != null && mounted) {
      final blob = html.Blob([bytes], mime);
      final blobUrl = html.Url.createObjectUrlFromBlob(blob);
      setState(() {
        _src = blobUrl;
        _loading = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _error = url;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator(color: Color(0xFF4A148C)));
    if (_src != null && _src!.isNotEmpty) {
      return HtmlElementView.fromTagName(
        tagName: 'iframe',
        onElementCreated: (Object element) {
          (element as dynamic).src = _src;
          (element as dynamic).style.border = 'none';
          (element as dynamic).style.width = '100%';
          (element as dynamic).style.height = '100%';
          (element as dynamic).style.overflow = 'auto';
        },
      );
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            const Text('Could not load file.\nCheck your connection and try again.', textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () { setState(() { _loading = true; _error = null; }); _loadSrc(); },
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
            ),
          ],
        ),
      );
    }
    return const Center(child: Text('No content', style: TextStyle(color: Colors.white54)));
  }
}
