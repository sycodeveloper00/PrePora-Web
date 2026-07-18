import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'notepad_view.dart';

class NotepadScreen extends StatelessWidget {
  final String lectureId;
  final String lectureName;

  const NotepadScreen({
    super.key,
    required this.lectureId,
    required this.lectureName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NotePad', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: NotepadView(
        lectureId: lectureId,
        lectureName: lectureName,
        isEmbedded: false,
      ),
    );
  }
}
