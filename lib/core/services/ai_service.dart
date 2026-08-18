import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/firebase_service.dart';

class AiService {
  static const String _defaultApiKey =
      'sk-bl-foHbeBqqZJM8O6gYEmmouGtftnSBdpPNqvy_aRc-BTEW7Qfr';
  static const String _defaultBaseUrl = 'https://bazaarlink.ai/api/v1';
  static const String _defaultModel = 'qwen/qwen3.7-flash:free';

  // Loaded from the active AI API key in Firestore (admin-managed).
  static String _apiKey = _defaultApiKey;
  static String _baseUrl = _defaultBaseUrl;
  static String _model = _defaultModel;
  static String _provider = 'openai';
  static bool _keyLoaded = false;

  /// The active key's model pool. Each entry pairs the shared key/baseUrl with
  /// one model, so a failed model automatically falls back to the next one.
  static List<Map<String, dynamic>> _keyPool = [];

  /// Caches the last successfully-loaded key so the AI keeps working even if
  /// the Firestore read fails (e.g. free-tier quota exhausted).
  static String? _cachedApiKey;
  static String? _cachedBaseUrl;
  static String? _cachedModel;
  static String? _cachedProvider;
  static List<Map<String, dynamic>>? _cachedPool;

  static void _applyPoolEntry(Map<String, dynamic> entry) {
    _apiKey = (entry['apiKey'] as String?)?.trim() ?? _defaultApiKey;
    _baseUrl = (entry['baseUrl'] as String?)?.trim() ?? _defaultBaseUrl;
    _model = (entry['model'] as String?)?.trim() ?? _defaultModel;
    _provider = (entry['provider'] as String?)?.trim() ?? 'openai';
  }

  /// Loads the active AI API key config from Firestore (once). Falls back to
  /// the last known good key, then the built-in defaults, when Firestore is
  /// unavailable. Builds the model pool so failed models can be retried.
  static Future<void> loadActiveKey() async {
    if (_keyLoaded) return;
    try {
      final key = await FirebaseService.getActiveAiApiKey();
      if (key != null) {
        final apiKeyVal = (key['apiKey'] as String?)?.trim();
        final baseUrlVal = (key['baseUrl'] as String?)?.trim();
        final providerVal = (key['provider'] as String?)?.trim() ?? 'openai';
        final baseModel = (key['model'] as String?)?.trim();
        final pool = <Map<String, dynamic>>[];
        final models = key['models'];
        if (models is List) {
          for (final m in models) {
            final s = m.toString().trim();
            if (s.isEmpty) continue;
            pool.add({'apiKey': apiKeyVal, 'baseUrl': baseUrlVal, 'model': s, 'provider': providerVal});
          }
        }
        if (pool.isEmpty && baseModel != null && baseModel.isNotEmpty) {
          pool.add({'apiKey': apiKeyVal, 'baseUrl': baseUrlVal, 'model': baseModel, 'provider': providerVal});
        }
        if (pool.isEmpty) {
          pool.add({'apiKey': _defaultApiKey, 'baseUrl': _defaultBaseUrl, 'model': _defaultModel, 'provider': 'openai'});
        }
        _keyPool = pool;
        _cachedPool = pool;
        _applyPoolEntry(pool.first);
        _cachedApiKey = _apiKey;
        _cachedBaseUrl = _baseUrl;
        _cachedModel = _model;
        _cachedProvider = _provider;
      }
    } catch (_) {
      // Firestore read failed — reuse the last known good key if we have one.
      if (_cachedPool != null && _cachedPool!.isNotEmpty) {
        _keyPool = _cachedPool!;
        _applyPoolEntry(_keyPool.first);
      } else if (_cachedApiKey != null) {
        _apiKey = _cachedApiKey!;
        _baseUrl = _cachedBaseUrl ?? _defaultBaseUrl;
        _model = _cachedModel ?? _defaultModel;
        _provider = _cachedProvider ?? 'openai';
        _keyPool = [
          {'apiKey': _apiKey, 'baseUrl': _baseUrl, 'model': _model, 'provider': _provider}
        ];
      }
    } finally {
      _keyLoaded = true;
    }
  }

  /// Force reload after an admin edits API keys.
  static void refreshKey() {
    _keyLoaded = false;
    loadActiveKey();
  }

  static String _errorForStatus(int status) {
    if (status == 401) {
      return '⚠️ The AI service needs a moment to refresh. Please try again in a few minutes.';
    }
    if (status == 429) {
      return '🤖 The AI is very popular right now and reached its daily limit. Please try again tomorrow.';
    }
    if (status == 400 || status == 404) {
      return '⚠️ This AI model is not available right now. Trying another model...';
    }
    return '🤖 AI server is unavailable right now. Please try later.';
  }

  static Future<void> _notifyPoolFailure() async {
    try {
      await FirebaseService.addAdminNotification(
        'ai_failure',
        'AI model pool exhausted — all ${_keyPool.length} model(s) failed. Check the AI API Keys settings.',
      );
    } catch (_) {}
  }

  static const String _baseSystemPrompt =
      'You are PrePora AI — an advanced, professional, and highly capable study assistant '
      'for Pakistani students. Your ONLY focus is helping students with their studies.\n\n'
      'GREETING RULE (STRICT — VIOLATION = WRONG): When greeting a student, talk ONLY about '
      'their general studies. NEVER mention ANY specific topics, exams, or categories — '
      'do NOT mention Entry Tests (MDCAT, ECAT, NUST, FAST, USAT, CSS, IELTS, SAT, GRE, etc.), '
      'do NOT mention online earning, do NOT mention abroad scholarships, abroad jobs, '
      'language learning, or programming. Say simply: "I\'m here to help you with your studies." '
      'Keep the greeting short and generic.\n\n'
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
      '- ALL math MUST be wrapped in \$...\$ (inline) or \$\$...\$\$ (block). This is ABSOLUTELY CRITICAL.\n'
      '- EVERY fraction, every exponent, every symbol — always inside \$ delimiters.\n'
      '- GOOD: The answer is \$\\frac{a}{b}\$  BAD: The answer is \\frac{a}{b}\n'
      '- GOOD: \$x^{2} + y^{2} = r^{2}\$  BAD: x^2 + y^2 = r^2\n'
      '- NEVER output bare LaTeX commands without \$ wrapping. If you write \\frac, \\sqrt, \\int, \\sum, etc., they MUST be inside \$...\$.\n'
      '- Fractions: \$\\frac{a}{b}\$\n'
      '- Exponents: \$x^{n}\$\n'
      '- Subscripts: \$x_{i}\$\n'
      '- Square roots: \$\\sqrt{x}\$\n'
      '- Summations: \$\\sum_{i=1}^{n}\$\n'
      '- Integrals: \$\\int_{a}^{b}\$\n'
      '- Greek letters: \$\\alpha, \\beta, \\theta, \\pi\$\n\n'
      'PROFESSIONALISM & RESPONSE STYLE:\n'
      '- You are a world-class academic tutor — be confident, clear, and precise.\n'
      '- NEVER start responses with "Sure!", "Of course!", "Great question!", or similar filler.\n'
      '- NEVER use emojis in responses. Be professional and academic.\n'
      '- Use clear structure: headings, bullet points, numbered steps.\n\n'
      'MATH PROBLEMS (CRITICAL - MUST FOLLOW):\n'
      '- ALWAYS solve step-by-step. NEVER give just the final answer.\n'
      '- ALWAYS start with "Given:" or "We need to find:" to state the problem.\n'
      '- Show EVERY algebraic step on a SEPARATE LINE using markdown numbered list.\n'
      '- Each step must have a brief English explanation of what was done.\n'
      '- End with "**Answer:**" or "**Therefore:**" clearly.\n'
      '- Format: use block math delimiters for equations on their own lines.\n'
      '- Example for "solve 2x+3=7":\n'
      '  **Given:** \$2x + 3 = 7\$\n'
      '  **Step 1:** Subtract 3 from both sides\n'
      '\$\$2x + 3 - 3 = 7 - 3\$\$\n'
      '\$\$2x = 4\$\$\n'
      '  **Step 2:** Divide both sides by 2\n'
      '\$\$x = \\\\frac{4}{2}\$\$\n'
      '\$\$x = 2\$\$\n'
      '  **Answer:** \$x = 2\$\n'
      '  **Verification:** Substitute back: \$2(2) + 3 = 4 + 3 = 7\$ ✓\n\n'
      '- For MCQs: state the answer first, then brief explanation.\n'
      '- For concepts: define → explain → example → key takeaway.\n'
      '- Reference exam patterns ONLY if the student explicitly asks about a specific exam.\n'
      '- Use mnemonics for difficult memorization tasks.\n'
      '- Be encouraging but not patronizing. Be direct but not rude.\n'
      '- Keep responses concise but COMPLETE. Do NOT skip steps.\n\n'
      'LANGUAGE RULES (STRICT — VIOLATION = WRONG):\n'
      'DETECTION: Look at what script the student uses. Determine their language BEFORE replying.\n'
      'English alphabet = English or Roman Urdu. Arabic script = Urdu. No ambiguity.\n\n'
      'RULE 1: ENGLISH input (like "What is photosynthesis?", "solve 2x+3=7", "explain Newton\'s laws") → Reply 100% in ENGLISH.\n'
      'Labels: "Solution:", "Step 1:", "Answer:", "Given:", "Therefore:", "Method:", "Explanation:".\n'
      'RULE 2: PURE MATH with English alphabet ONLY (like "2x+3=7", "x^2+5x+6=0", "solve this: 3x-9=0") → Reply in ENGLISH.\n'
      'Even if there is no English word, English alphabet math = ENGLISH reply. Use "Solution:", NOT "حل:".\n'
      'RULE 3: ROMAN URDU input (English alphabet Urdu words like "aap kaise hain", "ye kya hai", "solve karo", "mujhe samjhao") → Reply in ROMAN URDU using English alphabet ONLY.\n'
      'Labels: "hal:", "step 1:", "jawab:", "diya gaya:", "is liye:". NEVER convert to نستعلیق.\n'
      'RULE 4: URDU input (نستعلیق script like "تجویز کریں", "یہ کیا ہے", "مجھے سمجھاؤ") → Reply in نستعلیق ONLY.\n'
      'Labels: "حل:", "مرحلہ 1:", "جواب:", "دیا گیا:", "اس لیے:".\n'
      'RULE 5: MIXED English+Roman Urdu (like "ye photosynthesis kya hota hai") → Reply in ROMAN URDU.\n\n'
      'CRITICAL: "solve this: 2x+3=7" is ENGLISH alphabet input → ENGLISH reply. NOT Urdu.\n'
      'CRITICAL: "kisi aur method se kroo" has Roman Urdu words → ROMAN Urdu reply. NOT نستعلیق.\n'
      'CRITICAL: NEVER use نستعلیق script unless the student EXPLICITLY writes in نستعلیق.\n'
      'CRITICAL: NEVER mix نستعلیق labels (حل:, جواب:) with Roman Urdu or English text.\n\n'
      '- HINDI input (Devanagari script) → HINDI reply in Devanagari script.\n'
      '- ROMAN HINDI input (like "yeh kya hai bhai") → Reply in ROMAN HINDI using English alphabet.\n'
      '- ARABIC input → ARABIC reply.\n'
      '- CHINESE/JAPANESE/KOREAN input → Reply in ENGLISH (never in those languages).\n'
      '- NEVER mix languages in a single reply. One reply = one language/script.\n'
      '- NEVER switch to English if the student is writing in Urdu/Roman Urdu. Stay in their language.\n'
      '- NEVER switch to Urdu (نستعلیق) if the student is writing in Roman Urdu or English.\n'
      '- NEVER switch to Urdu (نستعلیق) if the student is writing in English. Stay in English.\n'
      '- Code snippets inside ```code blocks``` are always in English regardless of conversation language.\n'
      '- Mathematical formulas are always in LaTeX regardless of conversation language.\n'
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
      'You have access to the user\'s study catalog — folders, lectures, files, '
      'mock tests, and notes. Only unlocked and visible content is included. '
      'Locked or hidden items are NOT accessible. For assistants, only assigned folders are shown.\n'
      'Use this to provide contextually relevant answers. When discussing a topic, '
      'reference available lectures or resources the user can review for deeper understanding.\n'
      'IMPORTANT: Never output any URLs, file paths, folder IDs, or document links '
      'from the catalog. Only mention folder or lecture names in plain text.\n\n'
      'IDENTITY & PRIVACY:\n'
      '- You are "PrePora AI" — NEVER reveal the name of any API provider, service, backend, '
      'or technology powering you (e.g., BazaarLink, OpenAI, Anthropic, or any other provider).\n'
      '- If asked what AI model you are, say "I am PrePora AI, your study assistant."\n'
      '- NEVER include API keys, endpoint URLs, model names, or any technical backend details in responses.\n'
      '- NEVER mention that you use any third-party AI service.';

  final List<Map<String, String>> _messages = [];
  bool _contextLoaded = false;

  AiService() {
    _messages.add({'role': 'system', 'content': _baseSystemPrompt});
  }

  String get _apiUrl {
    // Gemini calls Google API directly (native), on both web and mobile.
    if (_provider == 'gemini') return '$_baseUrl/v1beta/models/$_model:generateContent';
    if (kIsWeb) return _webProxyUrl;
    return '$_baseUrl/chat/completions';
  }

  /// On web, OpenAI-compatible providers go through the proxy. We use the
  /// absolute Vercel proxy URL so it also works from Cloudflare Pages
  /// (admin-prepora.pages.dev) where there is no local /api/proxy.
  static String get _webProxyUrl =>
      'https://prepora-web.vercel.app/api/proxy';

  Map<String, String> _headers({bool withAuth = true}) {
    final h = <String, String>{'Content-Type': 'application/json'};
    if (withAuth) {
      // Gemini uses x-goog-api-key header (native API, no proxy needed).
      if (_provider == 'gemini') {
        h['x-goog-api-key'] = _apiKey;
      } else {
        h['Authorization'] = 'Bearer $_apiKey';
      }
    }
    return h;
  }

  Map<String, dynamic> _body({required bool stream}) {
    // Gemini: use native format everywhere (Google allows browser CORS, so it
    // works on both web and mobile WITHOUT the proxy). On web, only
    // OpenAI-compatible providers (BazaarLink/OpenRouter/DeepSeek) use the proxy.
    if (_provider == 'gemini') {
      return {
        'contents': [
          for (final m in _messages)
            {'role': m['role'] == 'assistant' ? 'model' : m['role'], 'parts': [{'text': m['content']}]}
        ],
        'systemInstruction': {'parts': [{'text': _baseSystemPrompt}]},
        'generationConfig': {
          'maxOutputTokens': 4096,
          'temperature': 0.3,
        },
      };
    }

    // Web: OpenAI-compatible providers go through the proxy.
    if (kIsWeb) {
      return {
        'model': _model,
        'messages': _messages,
        'max_tokens': 4096,
        'temperature': 0.3,
        'stream': stream,
        'baseUrl': _baseUrl,
      };
    }

    // Mobile: OpenAI-compatible format
    return {
      'model': _model,
      'messages': _messages,
      'max_tokens': 4096,
      'temperature': 0.3,
      'stream': stream,
      'baseUrl': _baseUrl,
    };
  }

  Future<String> sendMessage(String message) async {
    await loadActiveKey();
    _messages.add({'role': 'user', 'content': message});

    if (_messages.length > 21) {
      _messages.removeRange(1, _messages.length - 20);
    }

    final pool = [..._keyPool];
    if (pool.isEmpty) {
      pool.add({'apiKey': _apiKey, 'baseUrl': _baseUrl, 'model': _model, 'provider': _provider});
    }

    String? lastError;
    for (final entry in pool) {
      _applyPoolEntry(entry);
      try {
        final response = await http
            .post(
              Uri.parse(_apiUrl),
              headers: _headers(),
              body: jsonEncode(_body(stream: false)),
            )
            .timeout(const Duration(seconds: 90));

        if (response.statusCode == 200) {
          String reply;
          if (_provider == 'gemini') {
            final data = jsonDecode(response.body);
            reply = ((data['candidates'] as List<dynamic>?)?.firstOrNull
                as Map<String, dynamic>?)?['content']?['parts']?.firstOrNull?['text'] as String? ?? '';
          } else {
            final data = jsonDecode(response.body);
            reply = data['choices'][0]['message']['content'] as String;
          }
          _messages.add({'role': 'assistant', 'content': reply});
          return reply;
        }

        lastError = _errorForStatus(response.statusCode);
      } catch (e) {
        lastError = '❌ No internet connection. Please check your network and try again.';
      }
    }

    await _notifyPoolFailure();
    return lastError ?? '🤖 AI server is unavailable right now. Please try later.';
  }

  /// Fixes messy AI LaTeX output so flutter_math_fork can parse it.
  /// Uses line-by-line processing for reliability.
  static String fixLatex(String text) {
    String result = text
        .replaceAll('\u000c', '\\f')
        .replaceAll('\u0009', '\\t')
        .replaceAll('\u0008', '\\b');

    // Step 1: Convert ```latex or ```math code blocks to $$...$$
    result = result.replaceAllMapped(
      RegExp(r'```(?:latex|math)?\s*\r?\n([\s\S]*?)\r?\n```', multiLine: true),
      (m) => '\n\n\$\$${m[1]}\$\$\n\n',
    );

    // Step 2: Replace \left/\right — flutter_math_fork does NOT support them
    result = result
        .replaceAllMapped(RegExp(r'\\left\s*\('), (_) => '(')
        .replaceAllMapped(RegExp(r'\\left\s*\['), (_) => '[')
        .replaceAllMapped(RegExp(r'\\left\s*\\\{'), (_) => r'\{')
        .replaceAllMapped(RegExp(r'\\left\s*\|'), (_) => '|')
        .replaceAllMapped(RegExp(r'\\right\s*\)'), (_) => ')')
        .replaceAllMapped(RegExp(r'\\right\s*\]'), (_) => ']')
        .replaceAllMapped(RegExp(r'\\right\s*\\\}'), (_) => r'\}')
        .replaceAllMapped(RegExp(r'\\right\s*\|'), (_) => '|');

    // Step 3: Strip pre-existing $ delimiters AND single backticks from lines containing LaTeX
    // AI sends $...$ around math and `\frac{...}` in backticks which conflicts with rendering
    final preLines = result.split('\n');
    final latexCmdRe2 = RegExp(r'\\[a-zA-Z]+|\^[\{\d]|\_[\{\d]');
    final strippedLines = <String>[];
    for (var line in preLines) {
      final t = line.trim();
      if (t.isNotEmpty && latexCmdRe2.hasMatch(t)) {
        var stripped = line.replaceAll('\$', '');
        // Strip single backticks around LaTeX: `\frac{4}{2}` → \frac{4}{2}
        stripped = stripped.replaceAllMapped(
          RegExp(r'`([^`]*\\[a-zA-Z][^`]*?)`'),
          (m) => m[1]!,
        );
        strippedLines.add(stripped);
      } else {
        strippedLines.add(line);
      }
    }
    result = strippedLines.join('\n');

    // Step 3.5: Split crammed multi-step equations into separate lines
    // AI sometimes sends "2x + 3 = 7 2x = 7 - 3 2x = 4 x =\frac{4}{2} = 2" all on one line
    // Split before patterns like "2x =", "x =" when preceded by other math (multiple = signs)
    final equationSplitRe = RegExp(r'(?<=\S)\s+(?=\d*x\s*=|x\s*=|Solution|Step\s|Method|hal:|jawab:)');
    final splitLines = result.split('\n');
    final splitProcessed = <String>[];
    for (var line in splitLines) {
      final trimmed = line.trim();
      // Only split lines with 3+ equals signs (multi-step equations crammed together)
      if (trimmed.isNotEmpty &&
          !trimmed.startsWith('\$\$') &&
          !trimmed.startsWith('#') &&
          !trimmed.startsWith('```') &&
          RegExp(r'=').allMatches(trimmed).length >= 3) {
        final parts = trimmed.split(equationSplitRe);
        for (var part in parts) {
          if (part.trim().isNotEmpty) {
            splitProcessed.add(part.trim());
          }
        }
      } else {
        splitProcessed.add(line);
      }
    }
    result = splitProcessed.join('\n');

    // Step 4: Process line-by-line
    final lines = result.split('\n');
    final processed = <String>[];
    final latexCmdRe = RegExp(r'\\[a-zA-Z]+|\^[\{\d]|\_[\{\d]');
    // Matches 3+ consecutive letters NOT preceded by \ (real text words)
    final textWordRe = RegExp(r'[a-zA-Z]{3,}');

    for (var line in lines) {
      final trimmed = line.trim();

      // Skip empty lines, already $$ wrapped, indented (code), headings, horizontal rules
      if (trimmed.isEmpty ||
          trimmed.startsWith('\$\$') ||
          trimmed.startsWith('    ') ||
          trimmed.startsWith('\t') ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('---') ||
          trimmed.startsWith('***')) {
        processed.add(line);
        continue;
      }

      // If line has NO LaTeX commands, leave as-is
      if (!latexCmdRe.hasMatch(trimmed)) {
        processed.add(line);
        continue;
      }

      final hasBoldMarkers = trimmed.contains('**');
      final strippedForWords = trimmed.replaceAll(RegExp(r'\\[a-zA-Z]+'), '');
      final hasTextWords = textWordRe.hasMatch(strippedForWords);
      final isJustNumber = RegExp(r'^[\d\s\.\+\-\*\/\=\(\)\√]+$', caseSensitive: false).hasMatch(trimmed);
      // Check for non-Latin scripts (Arabic, Urdu, Chinese, etc.) — treat as text so they don't get wrapped in $$...$$
      final hasNonLatin = RegExp(r'[\u0600-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFF\u4E00-\u9FFF\u3040-\u309F\u30A0-\u30FF]').hasMatch(trimmed);

      final isFullMath = !hasTextWords && !hasBoldMarkers && !isJustNumber && !hasNonLatin;

      if (isFullMath) {
        processed.add('\$$trimmed\$');
      } else {
        processed.add(_wrapInlineMath(trimmed));
      }
    }
    result = processed.join('\n');

    // Step 5: Escape | inside inline math $...$
    result = result.replaceAllMapped(
      RegExp(r'\$(.+?)\$'),
      (m) => '\$${m[1]!.replaceAll('|', '\\vert')}\$',
    );
    // Step 6: Escape | inside block math $$...$$
    result = result.replaceAllMapped(
      RegExp(r'\$\$(.+?)\$\$', dotAll: true),
      (m) => '\$\$${m[1]!.replaceAll('|', '\\vert')}\$\$',
    );

    return result;
  }

  /// Reads a brace-enclosed group starting at [start] (the char after \command).
  /// Returns the index after the closing }, or -1 if unbalanced.
  /// Skips escaped braces \{ and \} so they don't break depth counting.
  static int _readBraceGroup(String text, int start) {
    if (start >= text.length || text[start] != '{') return -1;
    int depth = 0;
    for (int i = start; i < text.length; i++) {
      if (text[i] == '\\' && i + 1 < text.length && (text[i + 1] == '{' || text[i + 1] == '}')) {
        i++; // skip \{ or \}
        continue;
      }
      if (text[i] == '{') {
        depth++;
      } else if (text[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// Extracts a full LaTeX command (with all its brace groups) starting at [pos]
  /// where text[pos] == '\'. Returns the full command string or null.
  static String? _extractLatexCommand(String text, int pos) {
    if (pos >= text.length || text[pos] != '\\') return null;
    // Read command name: \frac, \sqrt, \boxed, etc.
    final nameMatch = RegExp(r'\\([a-zA-Z]+)').firstMatch(text.substring(pos));
    if (nameMatch == null) return null;
    final cmdName = nameMatch.group(0)!;
    int end = pos + cmdName.length;

    // \sqrt[n]{...} — optional bracket argument
    if (cmdName == '\\sqrt' && end < text.length && text[end] == '[') {
      final bracketEnd = text.indexOf(']', end);
      if (bracketEnd != -1) end = bracketEnd + 1;
    }

    // Commands that take brace arguments: \frac takes 2, \boxed/\sqrt/\text takes 1
    int braceArgs = 0;
    if (cmdName == '\\frac' || cmdName == '\\dfrac' || cmdName == '\\tfrac') {
      braceArgs = 2;
    } else if (cmdName == '\\boxed' || cmdName == '\\sqrt' || cmdName == '\\text' ||
        cmdName == '\\mathrm' || cmdName == '\\mathbf' || cmdName == '\\overline' ||
        cmdName == '\\underline' || cmdName == '\\hat' || cmdName == '\\bar' ||
        cmdName == '\\vec' || cmdName == '\\dot' || cmdName == '\\ddot' ||
        cmdName == '\\tilde' || cmdName == '\\widehat' || cmdName == '\\overbrace' ||
        cmdName == '\\underbrace' || cmdName == '\\color' || cmdName == '\\operatorname') {
      braceArgs = 1;
    }

    for (int i = 0; i < braceArgs; i++) {
      while (end < text.length && text[end] == ' ') {
        end++;
      }
      if (end < text.length && text[end] == '{') {
        final closeIdx = _readBraceGroup(text, end);
        if (closeIdx != -1) {
          end = closeIdx + 1;
        } else {
          break; // unbalanced
        }
      } else {
        break; // no brace group
      }
    }

    // Handle sub/superscripts for operators like \int, \sum, \prod, \lim
    if (braceArgs == 0) {
      // Check for _{...} or _x
      if (end < text.length && text[end] == '_') {
        end++;
        if (end < text.length && text[end] == '{') {
          final close = _readBraceGroup(text, end);
          if (close != -1) {
            end = close + 1;
          } else if (end < text.length) {
            end++;
          }
        } else if (end < text.length) {
          end++;
        }
      }
      // Check for ^{...} or ^x
      if (end < text.length && text[end] == '^') {
        end++;
        if (end < text.length && text[end] == '{') {
          final close = _readBraceGroup(text, end);
          if (close != -1) {
            end = close + 1;
          } else if (end < text.length) {
            end++;
          }
        } else if (end < text.length) {
          end++;
        }
      }
    }

    return text.substring(pos, end);
  }

  /// Wraps individual LaTeX commands in $...$ for mixed text+math lines.
  /// Simple char-by-char scan: finds \command, extracts full thing with brace-balancing, wraps it.
  static String _wrapInlineMath(String line) {
    final buf = StringBuffer();
    int i = 0;

    while (i < line.length) {
      if (line[i] == '\\' && i + 1 < line.length) {
        final next = line[i + 1];

        // Skip escaped braces \{ and \}
        if (next == '{' || next == '}') {
          buf.write(line.substring(i, i + 2));
          i += 2;
          continue;
        }

        // Skip escaped dollar sign \$
        if (next == '\$') {
          buf.write(line.substring(i, i + 2));
          i += 2;
          continue;
        }

        // Must be a letter to be a LaTeX command
        if (RegExp(r'[a-zA-Z]').hasMatch(next)) {
          final cmd = _extractLatexCommand(line, i);
          if (cmd != null && cmd.length > 1) {
            buf.write('\$$cmd\$');
            i += cmd.length;
            continue;
          }
        }
      }

      // Handle ^{...} and _{...} superscript/subscript
      if ((line[i] == '^' || line[i] == '_') && i + 1 < line.length && line[i + 1] == '{') {
        final endBrace = _readBraceGroup(line, i + 1);
        if (endBrace > 0) {
          // Remove preceding token from buffer if already written
          final bufStr = buf.toString();
          final precedingChar = bufStr.isNotEmpty ? bufStr[bufStr.length - 1] : '';
          if (RegExp(r'[\d\.\)]').hasMatch(precedingChar)) {
            buf.clear();
            buf.write(bufStr.substring(0, bufStr.length - 1));
            final fullExpr = '$precedingChar${line.substring(i, endBrace + 1)}';
            buf.write('\$$fullExpr\$');
          } else if (precedingChar == '}' && bufStr.length >= 2) {
            // Find the matching $...$ block before this }
            final dollarIdx = bufStr.lastIndexOf('\$');
            if (dollarIdx >= 0) {
              final mathBlock = bufStr.substring(dollarIdx);
              buf.clear();
              buf.write(bufStr.substring(0, dollarIdx));
              final fullExpr = '$mathBlock${line.substring(i, endBrace + 1)}';
              buf.write('\$$fullExpr\$');
            } else {
              buf.write('\$${line.substring(i, endBrace + 1)}\$');
            }
          } else {
            buf.write('\$${line.substring(i, endBrace + 1)}\$');
          }
          i = endBrace + 1;
          continue;
        }
      }

      // Handle ^digit and _digit (without braces) — e.g. ^2, _3
      if ((line[i] == '^' || line[i] == '_') && i + 1 < line.length && RegExp(r'[\d]').hasMatch(line[i + 1])) {
        // Remove preceding token from buffer if already written
        final bufStr = buf.toString();
        final precedingChar = bufStr.isNotEmpty ? bufStr[bufStr.length - 1] : '';
        if (RegExp(r'[\d\.\)]').hasMatch(precedingChar)) {
          buf.clear();
          buf.write(bufStr.substring(0, bufStr.length - 1));
          final fullExpr = '$precedingChar${line.substring(i, i + 2)}';
          buf.write('\$$fullExpr\$');
        } else if (precedingChar == '}' && bufStr.length >= 2) {
          final dollarIdx = bufStr.lastIndexOf('\$');
          if (dollarIdx >= 0) {
            final mathBlock = bufStr.substring(dollarIdx);
            buf.clear();
            buf.write(bufStr.substring(0, dollarIdx));
            final fullExpr = '$mathBlock${line.substring(i, i + 2)}';
            buf.write('\$$fullExpr\$');
          } else {
            buf.write('\$${line.substring(i, i + 2)}\$');
          }
        } else {
          buf.write('\$${line.substring(i, i + 2)}\$');
        }
        i += 2;
        continue;
      }

      // Not a command — copy as-is
      buf.write(line[i]);
      i++;
    }

    return buf.toString();
  }

  /// Streams a response chunk-by-chunk via SSE for a live typing effect.
  Stream<String> sendMessageStream(String message) async* {
    await loadActiveKey();
    _messages.add({'role': 'user', 'content': message});
    if (_messages.length > 21) {
      _messages.removeRange(1, _messages.length - 20);
    }

    final pool = [..._keyPool];
    if (pool.isEmpty) {
      pool.add({'apiKey': _apiKey, 'baseUrl': _baseUrl, 'model': _model, 'provider': _provider});
    }

    String? lastError;
    for (final entry in pool) {
      _applyPoolEntry(entry);
      final fullBuffer = StringBuffer();
      http.Client? client;
      try {
        client = http.Client();
        final streamed = _provider == 'gemini'
            ? await _geminiRequest(client)
            : await _openAiRequest(client);

        if (streamed.statusCode != 200) {
          lastError = _errorForStatus(streamed.statusCode);
          client.close();
          continue;
        }

        if (_provider != 'gemini') {
          final contentType = streamed.headers['content-type'] ?? '';
          if (!contentType.contains('text/event-stream') && !contentType.contains('application/json')) {
            lastError = '🤖 AI server is unavailable right now. Please try later.';
            client.close();
            continue;
          }
        }

        await for (final chunk in streamed.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!chunk.startsWith('data: ')) continue;
          final data = chunk.substring(6).trim();
          if (data.isEmpty || data == '[DONE]') continue;
          try {
            final json = jsonDecode(data) as Map<String, dynamic>;
            if (_provider == 'gemini') {
              final parts = (((json['candidates'] as List<dynamic>?)?.firstOrNull
                  as Map<String, dynamic>?)?['content'] as Map<String, dynamic>?)?['parts'] as List<dynamic>?;
              if (parts == null || parts.isEmpty) continue;
              final raw = (parts.first as Map<String, dynamic>)['text'] as String?;
              if (raw != null && raw.isNotEmpty) {
                fullBuffer.write(raw);
                yield raw;
              }
            } else {
              if (json['error'] == true) {
                final status = json['status'] as int?;
                final m = json['message'] as String?;
                lastError = status != null
                    ? _errorForStatus(status)
                    : (m != null && m.isNotEmpty
                        ? '🤖 AI issue: $m'
                        : '🤖 AI server is unavailable right now. Please try later.');
                break;
              }
              final delta = ((json['choices'] as List<dynamic>?)?.firstOrNull
                  as Map<String, dynamic>?)?['delta'] as Map<String, dynamic>?;
              final raw = delta?['content'] as String?;
              if (raw != null && raw.isNotEmpty) {
                fullBuffer.write(raw);
                yield raw;
              }
            }
          } catch (_) {}
        }
        client.close();

        final full = fullBuffer.toString();
        if (full.isNotEmpty) {
          _messages.add({'role': 'assistant', 'content': full});
          return;
        }
        if (lastError == null) {
          lastError = '⚠️ AI returned an empty response. Please try again.';
        }
      } on TimeoutException catch (_) {
        client?.close();
        if (fullBuffer.isNotEmpty) {
          _messages.add({'role': 'assistant', 'content': fullBuffer.toString()});
          return;
        }
        lastError = '\n\n⚠️ The AI server is not responding (timeout). Please try again in a few moments.';
      } catch (e) {
        client?.close();
        if (fullBuffer.isNotEmpty) {
          _messages.add({'role': 'assistant', 'content': fullBuffer.toString()});
          return;
        }
        lastError = _provider == 'gemini'
            ? '\n\n❌ No internet connection. Please check your network and try again.'
            : '❌ Connection Error\n\nPlease check your internet connection and try again.';
      }
    }

    await _notifyPoolFailure();
    yield lastError ?? '🤖 AI server is unavailable right now. Please try later.';
  }

  /// Sends one OpenAI-compatible streaming request (via proxy on web).
  Future<http.StreamedResponse> _openAiRequest(http.Client client) {
    final request = http.Request('POST', Uri.parse(_apiUrl));
    request.headers.addAll(_headers());
    request.body = jsonEncode(_body(stream: true));
    return client.send(request).timeout(const Duration(seconds: 90));
  }

  /// Sends one Gemini native SSE streaming request (no proxy needed).
  Future<http.StreamedResponse> _geminiRequest(http.Client client) {
    final uri = Uri.parse('$_baseUrl/v1beta/models/$_model:streamGenerateContent?alt=sse');
    final request = http.Request('POST', uri);
    request.headers.addAll(_headers());
    request.body = jsonEncode(_body(stream: true));
    return client.send(request).timeout(const Duration(seconds: 90));
  }

  /// Static caches so the heavy catalog/student-info reads happen at most once
  /// per app run instead of on every chat screen open (saves hundreds of
  /// Firestore reads).
  static String? _cachedCatalog;
  static String? _cachedStudentInfo;

  Future<void> setContext(String context) async {
    if (!_contextLoaded) {
      _contextLoaded = true;
      final catalog = _cachedCatalog ??= await _fetchUserContentCatalog();
      if (catalog.isNotEmpty) {
        _messages.add({'role': 'system', 'content': catalog});
      }
      final info = _cachedStudentInfo ??= await _fetchStudentInfo();
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
      final userDoc = await FirebaseService.firestore.collection('users').doc(uid).get();
      final role = (userDoc.data()?['role'] as String?) ?? 'student';

      Set<String> allowedFolderIds;
      if (role == 'Assistant') {
        final accessSnap = await FirebaseService.firestore
            .collection('Assistant_access')
            .where('uid', isEqualTo: uid)
            .get();
        allowedFolderIds = accessSnap.docs
            .map((d) => d.data()['folderId'] as String? ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        if (allowedFolderIds.isEmpty) return '';
      } else {
        allowedFolderIds = {};
      }

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
        final folderInvisible = folderData['invisible'] as bool? ?? false;

        if (folderLocked || folderUpdating || folderInvisible) continue;
        if (role == 'Assistant' && !allowedFolderIds.contains(folderId)) continue;

        buffer.writeln('\n📁 Folder: $folderName');

        final contentsSnap = await FirebaseService.firestore
            .collection('folders')
            .doc(folderId)
            .collection('contents')
            .orderBy('createdAt')
            .get();

        final contentMap = <String, Map<String, dynamic>>{};
        for (final c in contentsSnap.docs) {
          contentMap[c.id] = c.data();
        }

        final lockedIds = <String>{};
        final invisibleIds = <String>{};
        for (final entry in contentMap.entries) {
          final d = entry.value;
          final t = d['type'] as String? ?? '';
          if (d['locked'] == true && t == 'subfolder') lockedIds.add(entry.key);
          if (d['invisible'] == true && t == 'subfolder') invisibleIds.add(entry.key);
        }

        String buildPath(String? parentContentId) {
          if (parentContentId == null || parentContentId.isEmpty) return '';
          final parent = contentMap[parentContentId];
          if (parent == null) return '';
          final parentName = parent['name'] as String? ?? '';
          final grandParent = parent['parentContentId'] as String? ?? '';
          if (grandParent.isNotEmpty) {
            return '${buildPath(grandParent)} > $parentName';
          }
          return parentName;
        }

        bool isAncestorLocked(String? parentContentId, {int depth = 0}) {
          if (parentContentId == null || parentContentId.isEmpty || depth > 10) return false;
          if (lockedIds.contains(parentContentId) || invisibleIds.contains(parentContentId)) return true;
          final parent = contentMap[parentContentId];
          if (parent == null) return false;
          final gp = parent['parentContentId'] as String? ?? '';
          return isAncestorLocked(gp, depth: depth + 1);
        }

        for (final contentDoc in contentsSnap.docs) {
          final data = contentDoc.data();
          final type = data['type'] as String? ?? 'file';
          final name = data['name'] as String? ?? 'Unnamed';
          final locked = data['locked'] as bool? ?? false;
          final invisible = data['invisible'] as bool? ?? false;
          final parentContentId = data['parentContentId'] as String? ?? '';

          if (locked || invisible) continue;
          if (isAncestorLocked(parentContentId)) continue;

          final path = buildPath(parentContentId);
          final prefix = path.isNotEmpty ? '  [$path] ' : '  ';

          switch (type) {
            case 'lecture':
              final url = data['youtubeUrl'] as String? ?? '';
              buffer.writeln(url.isNotEmpty
                  ? '$prefix🎬 Lecture: "$name" → $url'
                  : '$prefix🎬 Lecture: "$name"');
            case 'file':
              final url = data['url'] as String? ?? '';
              buffer.writeln(url.isNotEmpty
                  ? '$prefix📄 File: "$name" → $url'
                  : '$prefix📄 File: "$name"');
            case 'link':
              final url = data['url'] as String? ?? '';
              buffer.writeln(url.isNotEmpty
                  ? '$prefix🔗 Link: "$name" → $url'
                  : '$prefix🔗 Link: "$name"');
            case 'mocktest_url':
              final url = data['url'] as String? ?? '';
              buffer.writeln(url.isNotEmpty
                  ? '$prefix📝 Mock Test: "$name" → $url'
                  : '$prefix📝 Mock Test: "$name"');
            case 'mocktest_code':
              buffer.writeln('$prefix📝 Mock Test (Code): "$name"');
            case 'subfolder':
              buffer.writeln('$prefix📂 Sub-folder: "$name"');
            case 'group':
              final url = data['url'] as String? ?? data['group_link'] as String? ?? '';
              buffer.writeln(url.isNotEmpty
                  ? '$prefix💬 Group: "$name" → $url'
                  : '$prefix💬 Group: "$name"');
          }
        }
      }

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