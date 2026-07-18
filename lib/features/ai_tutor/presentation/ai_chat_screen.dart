import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../core/services/ai_service.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/web_scraper_service.dart';
import '../../../core/services/file_reader_service.dart';

class AiChatScreen extends StatefulWidget {
  final String? folderContext;
  const AiChatScreen({super.key, this.folderContext});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> with SingleTickerProviderStateMixin {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _aiService = AiService();
  final _focusNode = FocusNode();
  _FilePickResult? _selectedFile;

  List<_Message> _messages = [];
  bool _isLoading = false;
  bool _showScrollDown = false;
  String? _sessionId;
  bool _isPendingResume = false;
  String? _failedText;
  String? _loadingError;
  StreamSubscription? _connectivitySubscription;
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  final List<String> _quickPrompts = [
    '\u{1F4DA} Explain this topic simply',
    '\u{1F4DD} Give me MCQs on this topic',
    '\u{1F4CB} Create a study timetable',
    '\u{1F9EE} Solve this step by step',
    '\u{1F4D6} Summarize this for me',
    '\u{1F3AF} Past paper trend analysis',
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    _aiService.setContext(widget.folderContext ?? 'New chat');
    _messages.add(_Message(
      text: "Welcome to PrePora AI! \u{1F44B}\n\nI am your AI-powered learning assistant. I can help you understand concepts, solve problems, and prepare for exams. Feel free to ask me anything!",
      isUser: false,
    ));
    _scrollController.addListener(_onScroll);
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      if (!result.contains(ConnectivityResult.none) && _failedText != null && _loadingError != null) {
        _retryLastMessage();
      }
    });
  }

  void _onScroll() {
    final pos = _scrollController.position;
    if (!pos.hasContentDimensions) return;
    final atBottom = pos.pixels >= pos.maxScrollExtent - 60;
    if (atBottom != !_showScrollDown) {
      setState(() => _showScrollDown = !atBottom);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _connectivitySubscription?.cancel();
    super.dispose();
  }

  Future<void> _sendMessage([String? quickPrompt]) async {
    final text = quickPrompt ?? _controller.text.trim();
    if (text.isEmpty && _selectedFile == null) return;
    if (_isLoading && _loadingError == null) return;
    _controller.clear();
    _failedText = null;
    _loadingError = null;

    String fullMessage = text;
    _FilePickResult? attachedFile;
    if (_selectedFile != null) {
      attachedFile = _selectedFile;
      if (fullMessage.isNotEmpty) fullMessage += '\n\n';
      fullMessage += 'The user shared a file: "${_selectedFile!.fileName}"\n\n'
          'File contents:\n${_selectedFile!.content}';
    }

    setState(() {
      if (attachedFile != null) {
        _messages.add(_Message(
          text: '\u{1F4C4} File: ${attachedFile.fileName}${text.isNotEmpty ? '\n$text' : ''}',
          isUser: true,
        ));
      } else {
        _messages.add(_Message(text: text, isUser: true));
      }
      _isLoading = true;
      _selectedFile = null;
    });
    _scrollToBottom();

    _saveMessageToHistory(fullMessage, 'user');

    try {
      String messageToSend = fullMessage;

      final webContext = await WebScraperService.processMessage(fullMessage);
      if (webContext != null) {
        messageToSend = '$fullMessage\n\n[WEB CONTEXT]\n$webContext';
      }

      final aiMsg = _Message(text: '', isUser: false);
      if (mounted) setState(() => _messages.add(aiMsg));

      bool hasContent = false;
      await for (final chunk in _aiService.sendMessageStream(messageToSend)) {
        if (!mounted) break;
        setState(() {
          aiMsg.text += chunk;
          hasContent = true;
        });
        _scrollToBottom();
      }

      if (mounted) {
        setState(() => _isLoading = false);
        if (hasContent) _saveMessageToHistory(aiMsg.text, 'ai');
        _scrollToBottom();
      }
    } catch (e) {
      if (mounted) {
        _failedText = fullMessage;
        _messages.removeWhere((m) => m.text.isEmpty && !m.isUser);
        setState(() {
          _loadingError = '\u26A0\uFE0F Connection lost. Tap to retry.';
          _isLoading = true;
        });
      }
    }
  }

  Future<void> _pickAttachFile() async {
    if (_isLoading && _loadingError == null) return;
    final result = await FileReaderService.pickAndReadFile();
    if (result == null) return;
    setState(() {
      _selectedFile = _FilePickResult(fileName: result.fileName, content: result.content);
    });
  }

  void _retryLastMessage() {
    if (_failedText != null && _loadingError != null) {
      _messages.removeWhere((m) => m.isError);
      setState(() {
        _loadingError = null;
        _isLoading = false;
      });
      _sendMessage(_failedText);
    }
  }

  Future<void> _saveMessageToHistory(String text, String role) async {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null || _sessionId == null) return;
    await FirebaseService.firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(_sessionId)
        .collection('messages')
        .add({
      'role': role,
      'content': text,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await FirebaseService.firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(_sessionId)
        .set({
      'lastMessage': text.length > 60 ? '${text.substring(0, 60)}...' : text,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _showHistory() {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Chat History', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseService.firestore
                  .collection('users')
                  .doc(uid)
                  .collection('conversations')
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (_, snap) {
                if (!snap.hasData || snap.data!.docs.isEmpty) {
                  return Center(child: Text('No history yet', style: TextStyle(color: isDark ? Colors.white38 : Colors.black45)));
                }
                return ListView.separated(
                  itemCount: snap.data!.docs.length,
                  separatorBuilder: (_, __) => Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
                  itemBuilder: (_, i) {
                    final doc = snap.data!.docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final sessionId = doc.id;
                    return ListTile(
                      leading: const Icon(Icons.chat_bubble_outline_rounded, color: Color(0xFF00B8D4)),
                      title: Text(data['lastMessage'] ?? 'Chat', style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13)),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: const Icon(Icons.open_in_new_rounded, color: Color(0xFF00B8D4), size: 18),
                          tooltip: 'Open',
                          onPressed: () {
                            Navigator.pop(ctx);
                            _loadSession(sessionId);
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                          tooltip: 'Delete',
                          onPressed: () async {
                            await FirebaseService.firestore
                                .collection('users')
                                .doc(uid)
                                .collection('conversations')
                                .doc(sessionId)
                                .delete();
                          },
                        ),
                      ]),
                      onTap: () {
                        Navigator.pop(ctx);
                        _loadSession(sessionId);
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSession(String sessionId) async {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null) return;
    final snap = await FirebaseService.firestore
        .collection('users').doc(uid)
        .collection('conversations').doc(sessionId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .get();
    final msgs = snap.docs.map((d) {
      final data = d.data();
      return _Message(
        text: data['content'] as String? ?? '',
        isUser: data['role'] == 'user',
      );
    }).toList();
    if (mounted) {
      final history = msgs
          .where((m) => m.text.isNotEmpty)
          .map((m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text})
          .toList();
      _aiService.loadHistory(history);
      setState(() {
        _messages = msgs;
        _sessionId = sessionId;
      });
      // Check if last message is from user (pending AI response)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _checkPendingResponse(msgs);
      });
    }
  }

  void _checkPendingResponse(List<_Message> msgs) {
    if (msgs.isEmpty || _isPendingResume) return;
    if (msgs.length >= 2 && msgs.last.isUser) {
      _isPendingResume = true;
      _sendMessage(msgs.last.text);
    }
  }

  void _newChat() {
    setState(() {
      _messages = [
        _Message(
          text: "New conversation started. How can I help you today? \u{1F60A}",
          isUser: false,
        ),
      ];
      _sessionId = DateTime.now().millisecondsSinceEpoch.toString();
      _aiService.resetChat();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)]),
                boxShadow: [BoxShadow(color: const Color(0xFF00B8D4).withValues(alpha: 0.4), blurRadius: 8)],
              ),
              child: ClipOval(
                child: Image.asset('assets/logo.png', width: 40, height: 40, fit: BoxFit.cover),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('PrePora AI', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text('Your AI Tutor', style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.5) : Colors.black54, fontSize: 11)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Chat History',
            onPressed: _showHistory,
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'New Chat',
            onPressed: _newChat,
          ),
        ],
      ),
      body: Stack(
        children: [
          Column(
            children: [
              if (_messages.length == 1 && !_messages[0].isUser)
                _buildHeroSection(isDark),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_isLoading ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) return _buildTypingIndicator();
                    return _buildMessage(_messages[index], isDark);
                  },
                ),
              ),
              _buildErrorBanner(),
          if (_messages.length <= 1 && MediaQuery.of(context).viewInsets.bottom == 0)
            SizedBox(
              height: 44,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _quickPrompts.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (_, i) => GestureDetector(
                  onTap: () => _sendMessage(_quickPrompts[i]),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF4A148C).withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF00B8D4).withValues(alpha: 0.4)),
                    ),
                    child: Text(_quickPrompts[i], style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13)),
                  ),
                ),
              ),
            ),
          if (_selectedFile != null)
            Padding(
              padding: EdgeInsets.only(bottom: 4),
              child: GestureDetector(
                onTap: () => setState(() => _selectedFile = null),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 12),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4A148C).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF00B8D4).withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.description_rounded, size: 18, color: const Color(0xFF00B8D4)),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _selectedFile!.fileName,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 13, fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.close_rounded, size: 16, color: isDark ? Colors.white54 : Colors.black54),
                    ],
                  ),
                ),
              ),
            ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom > 0 ? 0 : 8),
          Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom > 0 ? 8 : 12),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: Focus(
                        onKey: (node, event) {
                          if (event.logicalKey == LogicalKeyboardKey.enter && !event.isShiftPressed) {
                            _sendMessage();
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14),
                          maxLines: 6,
                          minLines: 1,
                          scrollPhysics: const BouncingScrollPhysics(),
                          keyboardType: TextInputType.multiline,
                          textInputAction: TextInputAction.newline,
                          decoration: InputDecoration(
                            hintText: 'Ask anything... (Enter to send, Shift+Enter for new line, 6 lines max)',
                            hintStyle: TextStyle(color: isDark ? Colors.white38 : Colors.black45),
                            filled: false,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: _pickAttachFile,
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                          shape: BoxShape.circle,
                          border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                        ),
                        child: Icon(Icons.attach_file_rounded, color: isDark ? Colors.white54 : Colors.black45, size: 18),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) => Transform.scale(
                        scale: _pulseAnimation.value,
                        child: child,
                      ),
                      child: GestureDetector(
                        onTap: _sendMessage,
                        child: Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF4A148C), Color(0xFF00B8D4)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF00B8D4).withValues(alpha: 0.5),
                                blurRadius: 12,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: const Icon(Icons.send_rounded, color: Colors.white, size: 18),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
      if (MediaQuery.of(context).viewInsets.bottom == 0)
        Positioned(
          right: 16,
          bottom: 120,
          child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: _showScrollDown ? 1.0 : 0.0,
          child: GestureDetector(
            onTap: () => _scrollToBottom(),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF4A148C), Color(0xFF00B8D4)],
                ),
                shape: BoxShape.circle,
                boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)],
              ),
              child: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 24),
            ),
          ),
        ),
      ),
    ],
      ),
    );
  }

  Widget _buildHeroSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)]),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00B8D4).withValues(alpha: 0.3),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: ClipOval(
              child: Image.asset('assets/logo.png', width: 120, height: 120, fit: BoxFit.cover),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(_Message msg, bool isDark) {
    final isUser = msg.isUser;
    final isError = msg.isError;

    Widget bubble;
    if (isError) {
      bubble = Align(
        alignment: Alignment.centerLeft,
        child: GestureDetector(
          onTap: _failedText != null ? _retryLastMessage : null,
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.refresh_rounded, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    msg.text,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13, height: 1.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      final timeStr = '${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';
      final maxBubbleWidth = MediaQuery.of(context).size.width - 32;
      bubble = Align(
        alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          constraints: BoxConstraints(maxWidth: maxBubbleWidth),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: isUser
                ? const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF6A1B9A)])
                : LinearGradient(colors: [
                    isDark ? Colors.white.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                    isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
                  ]),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: isUser ? const Radius.circular(18) : const Radius.circular(4),
              bottomRight: isUser ? const Radius.circular(4) : const Radius.circular(18),
            ),
            border: isUser ? null : Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (isUser)
                Text(
                  msg.text,
                  style: TextStyle(
                    color: msg.isError ? Colors.redAccent : Colors.white,
                    fontSize: 14,
                    height: 1.5,
                  ),
                )
              else
                MarkdownBody(
                    data: msg.text,
                    selectable: true,
                    inlineSyntaxes: [
                      MathBlockSyntax(),
                      MathInlineSyntax(),
                    ],
                    builders: {
                      'mathBlock': MathBlockBuilder(),
                      'mathInline': MathInlineBuilder(),
                      'code': CodeBlockBuilder(isDark: isDark),
                    },
                    styleSheet: MarkdownStyleSheet(
                      textScaleFactor: 1.0,
                      p: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 14, height: 1.6),
                      h1: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 18, fontWeight: FontWeight.bold),
                      h2: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
                      h3: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 15, fontWeight: FontWeight.w600),
                      code: TextStyle(
                        color: const Color(0xFF00E5FF),
                        backgroundColor: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.grey.withValues(alpha: 0.15),
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                      codeblockDecoration: BoxDecoration(
                        color: const Color(0xFF0D0221),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                      ),
                      blockquoteDecoration: BoxDecoration(
                        border: Border(left: BorderSide(color: const Color(0xFFCE93D8), width: 3)),
                        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.1),
                      ),
                      listBullet: const TextStyle(color: Color(0xFFCE93D8)),
                      tableBorder: TableBorder.all(color: isDark ? Colors.white24 : Colors.black26),
                      tableHead: TextStyle(fontWeight: FontWeight.bold, color: isDark ? Colors.white : Colors.black87),
                      tableColumnWidth: const IntrinsicColumnWidth(),
                      tableScrollbarThumbVisibility: null,
                      tablePadding: EdgeInsets.only(bottom: 6),
                      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      strong: const TextStyle(fontWeight: FontWeight.bold),
                      em: const TextStyle(fontStyle: FontStyle.italic),
                      codeblockPadding: const EdgeInsets.all(14),
                      blockquotePadding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      horizontalRuleDecoration: BoxDecoration(
                        border: Border(top: BorderSide(color: isDark ? Colors.white.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.2))),
                      ),
                    ),
                  ),
              if (!isUser)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _bubbleAction(
                        icon: Icons.copy_rounded,
                        tooltip: 'Copy',
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: msg.text));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Copied to clipboard'), duration: Duration(seconds: 1)),
                          );
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  timeStr,
                  style: TextStyle(color: isDark ? Colors.white.withValues(alpha: 0.3) : Colors.black.withValues(alpha: 0.3), fontSize: 10),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset((isUser ? 30 : -30) * (1 - value), 0),
            child: child!,
          ),
        );
      },
      child: bubble,
    );
  }

  Widget _bubbleAction({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 16, color: isDark ? Colors.white38 : Colors.black38),
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Thinking', style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          const SizedBox(width: 8),
          SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.amber),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    if (_loadingError == null) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _loadingError!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ),
          GestureDetector(
            onTap: _retryLastMessage,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.refresh_rounded, color: Colors.redAccent, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _Message {
  String text;
  final bool isUser;
  final bool isError;
  final DateTime timestamp;
  _Message({required this.text, required this.isUser, this.isError = false, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now();
}

class _FilePickResult {
  final String fileName;
  final String content;
  _FilePickResult({required this.fileName, required this.content});
}

class MathInlineBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.attributes['raw'] ?? element.textContent;
    if (text.isEmpty) return const SizedBox.shrink();
    try {
      return FittedBox(
        fit: BoxFit.scaleDown,
        child: Math.tex(
          text,
          textStyle: const TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 16,
          ),
          onErrorFallback: (_) => Text(
            text,
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontFamily: 'monospace',
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    } catch (_) {
      return Text(
        text,
        style: const TextStyle(
          color: Color(0xFF00E5FF),
          fontFamily: 'monospace',
          fontSize: 13,
          fontStyle: FontStyle.italic,
        ),
      );
    }
  }
}

class MathBlockBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.attributes['raw'] ?? element.textContent;
    if (text.isEmpty) return const SizedBox.shrink();
    try {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0221),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF00B8D4).withValues(alpha: 0.3)),
        ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Math.tex(
              text,
              textStyle: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 18,
              ),
          onErrorFallback: (_) => Text(
                text,
                style: const TextStyle(
                  color: Color(0xFF00E5FF),
                  fontFamily: 'monospace',
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ),
      );
    } catch (_) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF0D0221),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFF00B8D4).withValues(alpha: 0.3)),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF00E5FF),
              fontFamily: 'monospace',
              fontSize: 13,
              fontStyle: FontStyle.italic,
            ),
          ),
        ),
      );
    }
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final bool isDark;
  CodeBlockBuilder({this.isDark = true});

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    final lang = element.attributes['class']?.replaceAll('language-', '') ?? '';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0221),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (lang.isNotEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.15),
                border: Border(bottom: BorderSide(color: isDark ? Colors.white12 : Colors.black12)),
              ),
              child: Row(
                children: [
                  Icon(Icons.code_rounded, size: 14, color: const Color(0xFF00B8D4)),
                  const SizedBox(width: 6),
                  Text(
                    lang,
                    style: TextStyle(
                      color: const Color(0xFF00B8D4),
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: text));
                    },
                    child: Icon(Icons.copy_rounded, size: 14, color: isDark ? Colors.white38 : Colors.black38),
                  ),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: SelectableText(
              text,
              style: TextStyle(
                color: const Color(0xFF00E5FF),
                fontFamily: 'monospace',
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}



class MathBlockSyntax extends md.InlineSyntax {
  MathBlockSyntax() : super(r'\$\$(.*?)\$\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element('mathBlock', [md.Text(match[1]!)]);
    el.attributes['raw'] = match[1]!;
    parser.addNode(el);
    return true;
  }
}

class MathInlineSyntax extends md.InlineSyntax {
  MathInlineSyntax() : super(r'\$(.*?)\$', startCharacter: 0x24);

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final el = md.Element('mathInline', [md.Text(match[1]!)]);
    el.attributes['raw'] = match[1]!;
    parser.addNode(el);
    return true;
  }
}
