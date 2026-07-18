import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'webview_stub.dart'
    if (dart.library.html) 'webview_web.dart';
import '../../../core/services/firebase_service.dart';

class AppWebViewScreen extends StatefulWidget {
  final String? url;
  final String? html;
  final String title;
  final String? folderId;
  final String? parentContentId;
  final bool isMockTest;

  const AppWebViewScreen({super.key, this.url, this.html, required this.title, this.folderId, this.parentContentId, this.isMockTest = false});

  @override
  State<AppWebViewScreen> createState() => _AppWebViewScreenState();
}

class _AppWebViewScreenState extends State<AppWebViewScreen> {
  late final WebViewController? _controller;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _isLoading = false;
    } else {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (_) => setState(() => _isLoading = true),
          onPageFinished: (_) => setState(() => _isLoading = false),
        ));

      if (widget.html != null && widget.html!.isNotEmpty) {
        _controller!.loadHtmlString(widget.html!);
      } else if (widget.url != null && widget.url!.isNotEmpty) {
        _controller!.loadRequest(Uri.parse(widget.url!));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: kIsWeb ? _buildWebBody() : _buildMobileBody(),
      floatingActionButton: !widget.isMockTest && widget.folderId != null
          ? FutureBuilder<String?>(
              future: FirebaseService.getGroupLinkForLevel(widget.folderId!, parentContentId: widget.parentContentId),
              builder: (context, snap) {
                final link = snap.data;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAiFab(context),
                    if (link != null && link.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      _buildGroupFab(context, link),
                    ],
                  ],
                );
              },
            )
          : null,
    );
  }

  Widget _buildWebBody() {
    if (widget.html != null && widget.html!.isNotEmpty) {
      return WebViewWebWidget(html: widget.html!);
    }
    if (widget.url != null && widget.url!.isNotEmpty) {
      return WebViewWebWidget(url: widget.url!);
    }
    return const Center(child: Text('No content'));
  }

  Widget _buildMobileBody() {
    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_isLoading)
          const Center(
            child: CircularProgressIndicator(color: Color(0xFF4A148C)),
          ),
      ],
    );
  }

  Widget _buildAiFab(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'ai_chat_webview_${widget.title}',
        onPressed: () {
          context.push('/ai_tutor');
        },
        backgroundColor: Colors.transparent, elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)], begin: Alignment.topLeft, end: Alignment.bottomRight),
            boxShadow: [BoxShadow(color: Color(0xFF00B8D4).withValues(alpha: 0.5), blurRadius: 16, spreadRadius: 2)],
          ),
          child: ClipOval(child: Image.asset('assets/logo.png', width: 28, height: 28, fit: BoxFit.cover)),
        ),
      ),
    );
  }

  Widget _buildGroupFab(BuildContext context, String link) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'group_webview_${widget.title}',
        onPressed: () async {
      if (link.isNotEmpty) {
        if (context.mounted) context.push('/webview', extra: {'url': link, 'title': 'Group'});
      }
        },
        backgroundColor: Colors.transparent, elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.amber.shade700,
            boxShadow: [BoxShadow(color: Colors.amber.withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)],
          ),
          child: const Icon(Icons.groups_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}