import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

class MediaPlayerScreen extends StatefulWidget {
  final String url;
  final String title;
  final bool isAudio;

  const MediaPlayerScreen({super.key, required this.url, required this.title, this.isAudio = false});

  @override
  State<MediaPlayerScreen> createState() => _MediaPlayerScreenState();
}

class _MediaPlayerScreenState extends State<MediaPlayerScreen> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _isFullScreen = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      _controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
      await _controller!.initialize();
      _controller!.addListener(_listener);
      if (!mounted) return;
      setState(() {
        _duration = _controller!.value.duration;
        _isInitialized = true;
      });
      _controller!.play();
      setState(() => _isPlaying = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _listener() {
    if (!mounted || _controller == null) return;
    setState(() {
      _isPlaying = _controller!.value.isPlaying;
      _position = _controller!.value.position;
      _duration = _controller!.value.duration;
    });
  }

  void _togglePlayPause() {
    if (_controller == null) return;
    if (_isPlaying) {
      _controller!.pause();
    } else {
      _controller!.play();
    }
  }

  void _seekTo(double value) {
    _controller!.seekTo(Duration(seconds: value.toInt()));
    setState(() => _position = Duration(seconds: value.toInt()));
  }

  void _toggleFullScreen() {
    setState(() => _isFullScreen = !_isFullScreen);
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) return '${h}:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '${m}:${s.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _controller?.removeListener(_listener);
    _controller?.dispose();
    if (_isFullScreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      SystemChrome.setPreferredOrientations([]);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isFullScreen) {
      return _buildFullScreenView();
    }
    return _buildNormalView();
  }

  Widget _buildFullScreenView() {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Center(
            child: GestureDetector(
              onTap: _togglePlayPause,
              child: AspectRatio(
                aspectRatio: _controller!.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller!),
                    if (!_isPlaying)
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.5)),
                        child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 52),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: 16, left: 16,
            child: SafeArea(
              child: _buildCircleButton(Icons.arrow_back_ios_new_rounded, () => _toggleFullScreen()),
            ),
          ),
          Positioned(
            bottom: 24, left: 0, right: 0,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildCircleButton(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, _togglePlayPause),
                  const SizedBox(width: 12),
                  Text(_formatDuration(_position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Slider(
                      value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1),
                      max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1,
                      activeColor: Colors.amber,
                      inactiveColor: Colors.white24,
                      onChanged: _seekTo,
                    ),
                  ),
                  Text(_formatDuration(_duration), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                  const SizedBox(width: 8),
                  _buildCircleButton(Icons.fullscreen_exit_rounded, _toggleFullScreen),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalView() {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: _isFullScreen ? null : AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white), onPressed: () => context.pop()),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
      ),
      body: _isInitialized
          ? GestureDetector(
              onTap: _togglePlayPause,
              child: SafeArea(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxHeight = constraints.maxHeight;
                    final maxWidth = constraints.maxWidth;
                    return SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: maxHeight),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (widget.isAudio)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 40),
                                child: Icon(Icons.audiotrack_rounded, size: 120, color: Colors.white24),
                              )
                            else if (_controller != null)
                              Center(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: maxHeight * 0.7,
                                    maxWidth: maxWidth,
                                  ),
                                  child: AspectRatio(
                                    aspectRatio: _controller!.value.aspectRatio,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        VideoPlayer(_controller!),
                                        if (!_isPlaying)
                                          Container(
                                            width: 56, height: 56,
                                            decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.black.withValues(alpha: 0.5)),
                                            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 40),
                                          ),
                                        Positioned(
                                          bottom: 8, right: 8,
                                          child: GestureDetector(
                                            onTap: _toggleFullScreen,
                                            child: Container(
                                              width: 36, height: 36,
                                              decoration: BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Colors.black.withValues(alpha: 0.6),
                                              ),
                                              child: const Icon(Icons.fullscreen, color: Colors.white, size: 22),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            const SizedBox(height: 20),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  GestureDetector(
                                    onTap: _togglePlayPause,
                                    child: Container(
                                      width: 36, height: 36,
                                      decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.15)),
                                      child: Icon(_isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 22),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(_formatDuration(_position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Slider(
                                      value: _position.inSeconds.toDouble().clamp(0, _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1),
                                      max: _duration.inSeconds > 0 ? _duration.inSeconds.toDouble() : 1,
                                      activeColor: Colors.amber,
                                      inactiveColor: Colors.white24,
                                      onChanged: _seekTo,
                                    ),
                                  ),
                                  Text(_formatDuration(_position), style: const TextStyle(color: Colors.white54, fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            )
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: Colors.amber),
                  const SizedBox(height: 16),
                  Text(widget.isAudio ? 'Loading audio...' : 'Loading video...', style: const TextStyle(color: Colors.white54)),
                ],
              ),
            ),
    );
  }

  Widget _buildCircleButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.6),
        ),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}
