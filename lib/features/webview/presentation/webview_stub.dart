import 'package:flutter/material.dart';

class WebViewWebWidget extends StatelessWidget {
  final String? url;
  final String? html;
  const WebViewWebWidget({super.key, this.url, this.html});

  @override
  Widget build(BuildContext context) {
    return const Center(child: Text('WebView not available on this platform'));
  }
}