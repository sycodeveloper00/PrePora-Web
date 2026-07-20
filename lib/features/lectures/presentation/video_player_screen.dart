import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/services/firebase_service.dart';
import '../../notepad/presentation/notepad_view.dart';

class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final String lectureName;
  final String? folderId;
  final String? parentContentId;

  const VideoPlayerScreen({super.key, required this.videoId, required this.lectureName, this.folderId, this.parentContentId});

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late final YoutubePlayerController _controller;

  // Notepad state
  bool _isNotepadOpen = false;
  bool _isNotepadFullScreen = false;
  double _notepadHeight = 280;
  double _dragStartY = 0;
  double _dragStartHeight = 0;

  // Cache the folder future to prevent blinking
  Future<DocumentSnapshot>? _folderFuture;
  Future<String?>? _groupLinkFuture;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        mute: false,
        showControls: true,
        showFullscreenButton: true,
      ),
    );
    if (widget.folderId != null) {
      _folderFuture = FirebaseService.firestore.collection('folders').doc(widget.folderId).get();
      _groupLinkFuture = FirebaseService.getGroupLinkForLevel(widget.folderId!, parentContentId: widget.parentContentId);
    }
    _controller.setFullScreenListener(_onFullScreenChange);
  }

  void _onFullScreenChange(bool isFullScreen) {
    if (isFullScreen) {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } else {
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  @override
  void dispose() {
    _controller.close();
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      appBar: _isNotepadFullScreen
          ? null
          : AppBar(
              title: Text(widget.lectureName, style: const TextStyle(fontWeight: FontWeight.bold)),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ),
      body: _isNotepadFullScreen
          ? NotepadView(
              lectureId: widget.videoId,
              lectureName: widget.lectureName,
              isEmbedded: true,
              isFullScreen: true,
              onClose: () => setState(() {
                _isNotepadOpen = false;
                _isNotepadFullScreen = false;
              }),
              onFullScreenToggle: () => setState(() {
                _isNotepadFullScreen = false;
              }),
            )
          : SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Column(
                children: [
                // ─── Video Player ───────────────────────────────────────
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: YoutubePlayer(
                    controller: _controller,
                    aspectRatio: 16 / 9,
                  ),
                ),

                // ─── Info & Action Buttons ──────────────────────────────
                if (!_isNotepadOpen)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(widget.lectureName,
                            style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87, fontWeight: FontWeight.bold, fontSize: 18)),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.red),
                                label: const Text('See on YouTube', style: TextStyle(color: Colors.red, fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Colors.red),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                          onPressed: () {
                            context.push('/webview', extra: {'url': 'https://www.youtube.com/watch?v=${widget.videoId}', 'title': widget.lectureName});
                          },
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.edit_note_rounded, size: 18, color: Color(0xFF00B8D4)),
                                label: const Text('NotePad', style: TextStyle(color: Color(0xFF00B8D4), fontSize: 13)),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(color: Color(0xFF00B8D4)),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                                onPressed: () => setState(() => _isNotepadOpen = true),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                // ─── Inline Notepad ─────────────────────────────────────
                if (_isNotepadOpen) ...[
                  // Drag Handle
                  GestureDetector(
                    onVerticalDragStart: (d) {
                      _dragStartY = d.globalPosition.dy;
                      _dragStartHeight = _notepadHeight;
                    },
                    onVerticalDragUpdate: (d) {
                      final delta = _dragStartY - d.globalPosition.dy;
                      setState(() {
                        _notepadHeight = (_dragStartHeight + delta)
                            .clamp(150.0, screenHeight * 0.65);
                      });
                    },
                    child: Container(
                      width: double.infinity,
                      height: 24,
                      color: Colors.transparent,
                      child: Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Notepad content
                  SizedBox(
                    height: _notepadHeight,
                    child: NotepadView(
                      lectureId: widget.videoId,
                      lectureName: widget.lectureName,
                      isEmbedded: true,
                      isFullScreen: false,
                      onClose: () => setState(() {
                        _isNotepadOpen = false;
                      }),
                      onFullScreenToggle: () => setState(() {
                        _isNotepadFullScreen = true;
                      }),
                    ),
                  ),
                ],
              ],
              ),
            ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildNotepadFab(),
          if (!_isNotepadOpen || _isNotepadFullScreen) ...[
            const SizedBox(height: 16),
            if (widget.folderId != null)
              FutureBuilder<String?>(
                future: _groupLinkFuture,
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
            else
              _buildAiFab(context),
          ],
        ],
      ),
    );
  }

  Widget _buildNotepadFab() {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'notepad_${widget.videoId}',
        onPressed: () => setState(() => _isNotepadOpen = !_isNotepadOpen),
        backgroundColor: Colors.transparent, elevation: 0,
        child: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF00B8D4),
            boxShadow: [BoxShadow(color: const Color(0xFF00B8D4).withValues(alpha: 0.4), blurRadius: 12, spreadRadius: 1)],
          ),
          child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 28),
        ),
      ),
    );
  }

  Widget _buildAiFab(BuildContext context) {
    return SizedBox(
      width: 56, height: 56,
      child: FloatingActionButton(
        heroTag: 'ai_chat_lecture_${widget.videoId}',
        onPressed: () {
          context.push('/ai_tutor', extra: {'folderContext': 'Lecture: ${widget.lectureName}'});
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
        heroTag: 'group_lecture_${widget.videoId}',
        onPressed: () {
          if (link.isNotEmpty) context.push('/webview', extra: {'url': link, 'title': 'Group'});
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
