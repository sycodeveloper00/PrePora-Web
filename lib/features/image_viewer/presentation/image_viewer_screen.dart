import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';

class ImageViewerScreen extends StatelessWidget {
  final String url;
  final String title;

  const ImageViewerScreen({super.key, required this.url, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.close_rounded, color: Colors.white), onPressed: () => context.pop()),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: InteractiveViewer(
        minScale: 0.5,
        maxScale: 4.0,
        child: Center(
          child: CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.contain,
            placeholder: (_, __) => const Center(child: CircularProgressIndicator(color: Colors.amber)),
            errorWidget: (_, __, ___) => const Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.broken_image_rounded, size: 60, color: Colors.white24),
                SizedBox(height: 8),
                Text('Failed to load image', style: TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
