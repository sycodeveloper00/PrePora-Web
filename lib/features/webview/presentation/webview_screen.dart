import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'webview_stub.dart'
    if (dart.library.html) 'webview_web.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/widgets/professional_loader.dart';

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
  double _loadingProgress = 0;
  String _currentUrl = '';

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _isLoading = false;
    } else {
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(NavigationDelegate(
          onPageStarted: (url) => setState(() { _isLoading = true; _currentUrl = url; }),
          onProgress: (progress) => setState(() => _loadingProgress = progress / 100),
          onPageFinished: (_) => setState(() => _isLoading = false),
          onNavigationRequest: (request) {
            final url = request.url;
            if (url.contains('accounts.google.com') || url.contains('login.microsoftonline.com') || url.contains('onedrive.live.com') || url.contains('drive.google.com')) {
              return NavigationDecision.navigate;
            }
            return NavigationDecision.navigate;
          },
        ));

      if (widget.html != null && widget.html!.isNotEmpty) {
        _controller!.loadHtmlString(widget.html!);
      } else if (widget.url != null && widget.url!.isNotEmpty) {
        _currentUrl = widget.url!;
        _controller!.loadRequest(Uri.parse(widget.url!));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D0D2E) : Colors.white,
      appBar: AppBar(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: isDark ? Colors.white : Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.title, style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          if (!kIsWeb && _controller != null) ...[
            IconButton(
              icon: Icon(Icons.arrow_back_ios_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () async {
                try { if (await _controller!.canGoBack()) await _controller!.goBack(); } catch (_) {}
              },
              tooltip: 'Back',
            ),
            IconButton(
              icon: Icon(Icons.arrow_forward_ios_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () async {
                try { if (await _controller!.canGoForward()) await _controller!.goForward(); } catch (_) {}
              },
              tooltip: 'Forward',
            ),
            IconButton(
              icon: Icon(Icons.refresh_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () => _controller!.reload(),
              tooltip: 'Refresh',
            ),
            IconButton(
              icon: Icon(Icons.open_in_browser_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () async {
                final url = _currentUrl.isNotEmpty ? _currentUrl : (widget.url ?? '');
                if (url.isNotEmpty) {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              tooltip: 'Open in browser',
            ),
            IconButton(
              icon: Icon(Icons.download_rounded, size: 18, color: isDark ? Colors.white70 : Colors.black54),
              onPressed: () async {
                final url = _currentUrl.isNotEmpty ? _currentUrl : (widget.url ?? '');
                if (url.isNotEmpty) {
                  final uri = Uri.parse(url);
                  if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
                }
              },
              tooltip: 'Download',
            ),
          ],
        ],
      ),
      body: Column(
        children: [
          if (_isLoading && !kIsWeb)
            LinearProgressIndicator(
              value: _loadingProgress > 0 ? _loadingProgress : null,
              backgroundColor: isDark ? Colors.white12 : Colors.black12,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF4A148C)),
              minHeight: 2,
            ),
          Expanded(
            child: kIsWeb ? _buildWebBody() : _buildMobileBody(),
          ),
        ],
      ),
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
    if (_controller == null) return const Center(child: ProfessionalLoader());
    return Stack(
      children: [
        WebViewWidget(controller: _controller!),
        if (_isLoading)
          const Center(child: ProfessionalLoader()),
      ],
    );
  }

  Widget _buildAiFab(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'ai_chat_webview_${widget.title}',
        onPressed: () => context.push('/ai_tutor'),
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
          if (link.isNotEmpty && context.mounted) {
            context.push('/webview', extra: {'url': link, 'title': 'Group'});
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
