import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/firebase_service.dart';

class AiService {
  // Free API key from BazaarLink — sign up at https://bazaarlink.ai/free for your own key
  static const String _apiKey =
      'sk-bl-foHbeBqqZJM8O6gYEmmouGtftnSBdpPNqvy_aRc-BTEW7Qfr';
  static const String _baseUrl = 'https://bazaarlink.ai/api/v1';

  static const String _baseSystemPrompt =
      'You are PrePora AI — an advanced, professional, and highly capable study assistant '
      'for Pakistani students preparing for MDCAT, ECAT, NUST, FAST, CSS, IELTS, '
      'and other competitive exams.\n\n'
      'RESPONSE FORMAT:\n'
      '- STRICT LENGTH: Answer ONLY what is asked. If asked a specific question, '
      'give the answer directly without introduction, extra details, or follow-up suggestions.\n'
      '- If the answer is short (<3 sentences), do NOT add extra explanations.\n'
      '- For MCQs, give the answer + 1-line explanation only (unless asked for details).\n'
      '- Use professional Markdown formatting:\n'
      '  **bold** for key terms\n'
      '  ~~strikethrough~~ for corrections\n'
      '  `code` for technical terms\n'
      '  > blockquotes for important points\n'
      '  | tables | for structured data (KEEP TABLES COMPACT: max 4-5 columns, use short headers, prioritize length not excessive width)\n'
      '  CRITICAL: In table cells, NEVER use | (pipe) character inside math formulas. Use \\vert instead of | for absolute values, e.g., \$\\ln\\vert x\\vert\$ not \$\\ln|x|\$. The | character breaks table column alignment.\n'
      '  ### headings for sections (max 2 levels deep)\n'
      '  - bullet lists for items\n'
      '  1. numbered lists for steps\n\n'
      'TABLE RULES:\n'
      '- ALWAYS use markdown tables for structured/comparative data. Tables are REQUIRED when showing multiple rows/columns.\n'
      '- Keep tables compact: max 4-5 columns, short headers (1-2 words), concise cells.\n'
      '- If data has more than 5 columns, split into two smaller tables.\n'
      '- Example GOOD table: | Subject | Marks | Grade |\n'
      '- Example BAD (too wide): | Subject Name | Total Marks Obtained | Percentage | Grade Awarded | Remarks |\n\n'
      'ALIGNMENT & ORIENTATION:\n'
      '- Ensure all content is left-aligned (no unnecessary left indentation/space).\n'
      '- Lists, tables, code blocks — all must start at the leftmost column.\n'
      '- Do not add extra blank lines at the start of your response.\n'
      '- Keep proper formatting for readability.\n\n'
      'MATHEMATICAL EXPRESSIONS:\n'
      '- ALWAYS wrap math in \$...\$ or \$\$...\$\$: \$\frac{a}{b}\$ NOT \frac{a}{b}\n'
      '- Fractions: \$\frac{a}{b}\$\n'
      '- Exponents: \$x^{n}\$\n'
      '- Subscripts: \$x_{i}\$\n'
      '- Square roots: \$\sqrt{x}\$\n'
      '- Summations: \$\sum_{i=1}^{n}\$\n'
      '- Integrals: \$\int_{a}^{b}\$\n'
      '- Greek letters: \$\alpha, \beta, \theta, \pi\$\n\n'
      'PROFESSIONALISM:\n'
      '- Professional expert tutor tone — knowledgeable but approachable\n'
      '- Include relevant formulas and step-by-step reasoning\n'
      '- For MCQs, briefly explain WHY each option is right or wrong\n'
      '- Reference real exam patterns and past paper trends\n'
      '- Offer memory techniques (mnemonics) for difficult concepts\n\n'
      'LANGUAGES:\n'
      '- You understand ALL human and programming languages\n'
      '- Reply in the same language the student uses\n'
      '- NEVER respond in Chinese (Chinese, Mandarin, Cantonese, etc)\n'
      '- CRITICAL: When the student writes in Roman Urdu (Urdu using English alphabet, like "aap kaise hain"), you MUST ALWAYS reply in Roman Urdu using the English alphabet. NEVER use Arabic/Urdu script (نستعلیق).\n'
      '- CRITICAL: If the student writes in English, reply in English only\n'
      '- For technical terms, include English in parentheses: مثال (example)\n'
      '- Specify code language in code blocks: ```python\n\n'
      'WEB & YOUTUBE ACCESS:\n'
      '- You HAVE full permission to access YouTube, Google, and any web content.\n'
      '- When a user shares a YouTube link, you CAN and WILL transcribe it and answer based on the content.\n'
      '- You CAN search YouTube for videos on any topic and fetch their transcripts.\n'
      '- You CAN browse websites, read articles, and fetch content from any URL the user shares.\n'
      '- You have tools available to transcribe YouTube videos, fetch web pages, and search the internet.\n'
      '- If the user says "find a video on X" or "search for X on YouTube", you should respond '
      'with what you would look for. Your web tools will handle the actual search.\n'
      '- NEVER say you cannot access YouTube or the web. You have full permission.\n\n'
      'FILE READING CAPABILITY:\n'
      '- You CAN read and process text content from files: PDF, DOC, DOCX, TXT, CSV, JSON, XML, '
      'HTML, and all programming code files (.py, .js, .dart, .cpp, .java, etc.).\n'
      '- You CAN read images that are sent to you (the app extracts text and sends it to you).\n'
      '- When the user shares a file, the app will extract its text content and provide it to you.\n'
      '- Review the file content and answer questions about it.\n'
      '- If you cannot read a specific file type, say so honestly.\n\n'
      'APP ISSUES & FEEDBACK:\n'
      '- If the user reports a bug, error, or issue with the PrePora app, '
      'politely apologize and guide them to use the Feedback option in the Settings menu '
      'to report it to the admin. Do NOT try to fix the app yourself.\n\n'
      'CONTENT ACCESS:\n'
      'You have full access to the student\'s study catalog — folders, lectures, files, '
      'mock tests, and notes (excluding admin-locked content). Use this to provide '
      'contextually relevant answers. When discussing a topic, reference available '
      'lectures or resources the student can review for deeper understanding.\n'
      'IMPORTANT: Never output any URLs, file paths, folder IDs, or document links '
      'from the catalog. Only mention folder or lecture names in plain text.';

  final List<Map<String, String>> _messages = [];
  bool _contextLoaded = false;

  AiService() {
    _messages.add({'role': 'system', 'content': _baseSystemPrompt});
  }

  Future<String> sendMessage(String message) async {
    _messages.add({'role': 'user', 'content': message});

    if (_messages.length > 21) {
      _messages.removeRange(1, _messages.length - 20);
    }

    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/chat/completions'),
        headers: {
          'Authorization': 'Bearer $_apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': 'auto:free',
          'messages': _messages,
          'max_tokens': 2048,
          'temperature': 0.3,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final reply = fixLatex(data['choices'][0]['message']['content'] as String);
        _messages.add({'role': 'assistant', 'content': reply});
        return reply;
      }

      if (response.statusCode == 401) {
        return '⚠️ API key issue detected. Please contact the admin to get a valid API key.';
      }

      if (response.statusCode == 429) {
        return '🤖 AI service is temporarily busy. Please wait a moment and try again.';
      }

      return '⚠️ AI Error: ${response.statusCode}\n\n'
          'Please check your internet connection and try again.';

    } catch (e) {
      return '❌ Connection Error: $e\n\nPlease check your internet connection and try again.';
    }
  }

  /// Fixes LaTeX commands corrupted by JSON decoding (\\f → formfeed, \\t → tab, etc.)
  /// Also escapes | → \vert inside $...$ and $$...$$ to prevent markdown table breakage.
  static String fixLatex(String text) {
    String result = text
        .replaceAll('\u000c', '\\f')
        .replaceAll('\u0009', '\\t')
        .replaceAll('\u0008', '\\b');
    // Escape | inside inline math $...$
    result = result.replaceAllMapped(
      RegExp(r'\$(.+?)\$'),
      (m) => '\$${m[1]!.replaceAll('|', '\\vert')}\$',
    );
    // Escape | inside block math $$...$$
    result = result.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$', dotAll: true),
      (m) => '\$\$${m[1]!.replaceAll('|', '\\vert')}\$\$',
    );
    return result;
  }

  /// Streams a response chunk-by-chunk via SSE for a live typing effect.
  Stream<String> sendMessageStream(String message) async* {
    _messages.add({'role': 'user', 'content': message});
    if (_messages.length > 21) {
      _messages.removeRange(1, _messages.length - 20);
    }

    if (kIsWeb) {
      // On web, try multiple CORS proxies then direct
      final apiUrl = '$_baseUrl/chat/completions';
      final proxies = [
        'https://api.allorigins.win/raw?url=${Uri.encodeComponent(apiUrl)}',
        'https://corsproxy.io/?${Uri.encodeComponent(apiUrl)}',
        apiUrl,
      ];
      for (final url in proxies) {
        try {
          final response = await http.post(
            Uri.parse(url),
            headers: {
              'Authorization': 'Bearer $_apiKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': 'auto:free',
              'messages': _messages,
              'max_tokens': 2048,
              'temperature': 0.3,
              'stream': false,
            }),
          ).timeout(Duration(seconds: url == apiUrl ? 15 : 30));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final reply = fixLatex(data['choices'][0]['message']['content'] as String);
            _messages.add({'role': 'assistant', 'content': reply});
            yield reply;
            return;
          }
          if (response.statusCode == 401) {
            yield '⚠️ API key issue detected. Please contact the admin to get a valid API key.';
            return;
          }
          if (response.statusCode == 429) {
            yield '🤖 AI service is temporarily busy. Please wait a moment and try again.';
            return;
          }
        } catch (_) {
          continue;
        }
      }
      yield '❌ Connection Error\n\nPlease check your internet connection and try again.';
      return;
    }

    final request = http.Request(
      'POST',
      Uri.parse('$_baseUrl/chat/completions'),
    );
    request.headers.addAll({
      'Authorization': 'Bearer $_apiKey',
      'Content-Type': 'application/json',
    });
    request.body = jsonEncode({
      'model': 'auto:free',
      'messages': _messages,
      'max_tokens': 2048,
      'temperature': 0.3,
      'stream': true,
    });

    final fullBuffer = StringBuffer();
    http.Client? client;

    try {
      client = http.Client();
      final streamed =
          await client.send(request).timeout(const Duration(seconds: 30));

      await for (final chunk in streamed.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (chunk.startsWith('data: ')) {
          final data = chunk.substring(6).trim();
          if (data == '[DONE]') break;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            final delta = ((json['choices'] as List<dynamic>?)?.firstOrNull
                as Map<String, dynamic>?)?['delta'] as Map<String, dynamic>?;
            final raw = delta?['content'] as String?;
            if (raw != null && raw.isNotEmpty) {
              final content = fixLatex(raw);
              fullBuffer.write(content);
              yield content;
            }
          } catch (_) {
            // skip malformed chunks
          }
        }
      }
    } on TimeoutException catch (_) {
      yield '\n\n⚠️ The AI server is not responding (timeout). Please try again in a few moments.';
    } catch (e) {
      yield '\n\n❌ Connection Error\n\nPlease check your internet connection and try again.\n\nDetails: $e';
    } finally {
      client?.close();
    }

    // Save full response to history
    final full = fullBuffer.toString();
    if (full.isNotEmpty) {
      _messages.add({'role': 'assistant', 'content': full});
    }
  }

  Future<void> setContext(String context) async {
    if (!_contextLoaded) {
      _contextLoaded = true;
      final catalog = await _fetchUserContentCatalog();
      if (catalog.isNotEmpty) {
        _messages.add({'role': 'system', 'content': catalog});
      }
      final info = await _fetchStudentInfo();
      if (info != null) {
        _messages.add({'role': 'system', 'content': info});
      }
    }
    _messages.add({'role': 'system', 'content': '[Context: $context]'});
  }

  void resetChat() {
    _messages.clear();
    _messages.add({'role': 'system', 'content': _baseSystemPrompt});
    _contextLoaded = false;
  }

  /// Loads historical conversation messages into the AI context so it remembers past exchanges.
  /// Keeps the system prompt (index 0), replaces everything else with [history].
  void loadHistory(List<Map<String, String>> history) {
    final system = _messages.isNotEmpty ? _messages[0] : {'role': 'system', 'content': _baseSystemPrompt};
    _messages.clear();
    _messages.add(system);
    _messages.addAll(history);
    _contextLoaded = true;
  }

  Future<String?> _fetchStudentInfo() async {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null) return null;

    try {
      final doc = await FirebaseService.firestore.collection('users').doc(uid).get();
      if (!doc.exists) return null;

      final data = doc.data()!;
      final name = data['name'] as String? ?? data['displayName'] as String? ?? 'Student';
      final email = data['email'] as String? ?? '';
      final role = data['role'] as String? ?? 'student';
      final verified = data['verified'] as bool? ?? true;
      final blocked = data['blocked'] as bool? ?? false;

      // Get enrolled subjects from folders the student has access to
      final subjects = <String>{};
      try {
        final foldersSnap = await FirebaseService.firestore.collection('folders').get();
        for (final f in foldersSnap.docs) {
          final fData = f.data();
          final name2 = fData['name'] as String? ?? '';
          if (name2.isNotEmpty) subjects.add(name2);
        }
      } catch (_) {}

      final subjectsStr = subjects.isNotEmpty ? subjects.take(5).join(', ') : 'General';

      return '''
[Student Profile]
Name: $name
Email: ${email.isNotEmpty ? email : 'Not available'}
Role: $role
Verified: $verified
Account Active: ${!blocked}
Enrolled Subjects/Topics: $subjectsStr

Use this information to personalize your responses. Address the student by name occasionally. 
If the student seems confused, offer simpler explanations. Suggest relevant topics based on their enrolled subjects.
''';
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchUserContentCatalog() async {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null) return '';

    final buffer = StringBuffer();
    buffer.writeln(
        'Here is the complete study content catalog available to this user in the PrePora app:');

    try {
      final foldersSnap = await FirebaseService.firestore
          .collection('folders')
          .orderBy('createdAt')
          .get();

      for (final folderDoc in foldersSnap.docs) {
        final folderData = folderDoc.data();
        final folderName = folderData['name'] as String? ?? 'Unnamed';
        final folderId = folderDoc.id;
        final folderLocked = folderData['locked'] as bool? ?? false;
        final folderUpdating = folderData['updating'] as bool? ?? false;

        if (folderLocked || folderUpdating) continue;

        buffer.writeln('\n📁 Folder: $folderName');

        final contentsSnap = await FirebaseService.firestore
            .collection('folders')
            .doc(folderId)
            .collection('contents')
            .orderBy('createdAt')
            .get();

        for (final contentDoc in contentsSnap.docs) {
          final data = contentDoc.data();
          final type = data['type'] as String? ?? 'file';
          final name = data['name'] as String? ?? 'Unnamed';
          final locked = data['locked'] as bool? ?? false;

          if (locked) continue;

          switch (type) {
            case 'lecture':
              final url = data['youtubeUrl'] as String? ?? '';
              buffer.writeln('  🎬 Lecture: "$name" → $url');
            case 'file':
              final url = data['url'] as String? ?? '';
              buffer.writeln('  📄 File: "$name"');
              if (url.isNotEmpty) buffer.writeln('    URL: $url');
            case 'link':
              final url = data['url'] as String? ?? '';
              buffer.writeln('  🔗 Link: "$name" → $url');
            case 'mocktest_url':
              final url = data['url'] as String? ?? '';
              buffer.writeln('  📝 Mock Test (URL): "$name" → $url');
            case 'mocktest_code':
              buffer.writeln('  📝 Mock Test (Code): "$name"');
            case 'subfolder':
              buffer.writeln('  📂 Sub-folder: "$name"');
            case 'group':
              final url = data['url'] as String? ?? '';
              buffer.writeln('  💬 Group: "$name" → $url');
          }
        }
      }

      // Fetch user's saved notes
      final notesSnap = await FirebaseService.firestore
          .collection('users')
          .doc(uid)
          .collection('notes')
          .orderBy('updatedAt', descending: true)
          .limit(10)
          .get();

      if (notesSnap.docs.isNotEmpty) {
        buffer.writeln('\n📝 Recent notes:');
        for (final noteDoc in notesSnap.docs) {
          final noteData = noteDoc.data();
          final lectureName =
              noteData['lectureName'] as String? ?? noteDoc.id;
          final preview = (noteData['content'] as String? ?? '');
          buffer.writeln('  - $lectureName');
          if (preview.length > 80) {
            buffer.writeln('    Preview: ${preview.substring(0, 80)}...');
          }
        }
      }

    } catch (e) {
      return '';
    }

    return buffer.toString();
  }
}