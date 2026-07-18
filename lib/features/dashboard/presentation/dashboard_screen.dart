import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../../core/widgets/glassmorphic_container.dart';
import '../../../core/widgets/animated_pressable.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/widget_service.dart';
import '../../../core/theme/theme_provider.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<_SearchResult> _searchResults = [];
  bool _isSearching = false;
  Timer? _searchDebounce;

  final List<String> _typingTexts = [
    'MDCAT', 'ECAT', 'NUST', 'NET', 'FAST', 'USAT', 'NTS NAT', 'GAT',
    'GRE', 'HAT', 'SAT', 'NED', 'NUTECH', 'CUET', 'BCAT', 'TCAT',
    'IBA', 'LCAT', 'LSE', 'GIKI', 'BUET', 'AUET', 'VU',
    'DUHS', 'JSMU', 'IIUI', 'NUML', 'KU', 'UAF',
    'IELTS', 'CCE', 'CSS', 'PMS', 'KPPSC', 'PPSC', 'BPSC', 'AJKPSC',
    'SPSC', 'GBPSC', 'ISSB', 'ASF', 'FPSC',
    'Abroad Scholarships', 'Abroad Jobs', 'Language Learning', 'Programming',
  ];
  String _currentText = '';
  int _textIndex = 0;
  int _charIndex = 0;
  Timer? _typingTimer;
  bool _isDeleting = false;
  bool _hasStarted = false;

  late AnimationController _floatController;
  late Animation<double> _floatAnim;

  // Stable key to prevent unnecessary rebuilds
  final GlobalKey<_DashboardGridState> _gridKey = GlobalKey<_DashboardGridState>();
  bool _isBlocked = false;
  bool _isVerified = true;
  bool _isPaidAccess = false;
  double _price = 0;
  String _accountTitle = '';
  String _accountNo = '';
  String _bankName = '';

  // Real-time listener for user verification/blocked status
  StreamSubscription? _userStatusSub;
  Stream<QuerySnapshot>? _notificationStream;
  int _streakCount = 0;
  int _totalActiveDays = 0;

  @override
  void initState() {
    super.initState();
    _checkStatus();
    _listenUserStatus();
    _startTypingAnimation();
    _checkForUpdates();
    _rebuildNotificationStream();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _floatAnim = Tween<double>(begin: -10, end: 10)
        .animate(CurvedAnimation(parent: _floatController, curve: Curves.easeInOut));
  }

  DateTime _userCreatedAt = DateTime(2020);

  void _checkStatus() async {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null) return;
    final blocked = await FirebaseService.isStudentBlocked(uid);
    final settings = await FirebaseService.getSettings();
    final paidAccess = settings['paidAccess'] as bool? ?? false;
    final verified = paidAccess ? await FirebaseService.isStudentVerified(uid) : true;
    final user = FirebaseService.currentUser;
    final userDoc = await FirebaseService.getUser(uid);
    final createdAt = (userDoc?.data() as Map<String, dynamic>?)?['createdAt'] as Timestamp?;
    if (mounted) setState(() {
      _isBlocked = blocked;
      _isVerified = verified;
      _isPaidAccess = paidAccess;
      _price = (settings['price'] as num?)?.toDouble() ?? 0;
      _accountTitle = settings['accountTitle'] as String? ?? '';
      _accountNo = settings['accountNo'] as String? ?? '';
      _bankName = settings['bankName'] as String? ?? '';
      _userName = user?.displayName ?? '';
      _userEmail = user?.email ?? '';
      _userCreatedAt = createdAt?.toDate() ?? DateTime(2020);
      _rebuildNotificationStream();
    });
    // Load streak
    final streakData = await FirebaseService.getStreak(uid);
    if (mounted) setState(() {
      _streakCount = streakData['streakCount'] as int? ?? 0;
      _totalActiveDays = streakData['totalActiveDays'] as int? ?? 0;
    });
    WidgetService.updateStreakWidget(_streakCount, _totalActiveDays);
  }

  void _rebuildNotificationStream() {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null) return;
    _notificationStream = FirebaseService.getNotificationsForUser(uid, _userCreatedAt);
  }

  /// Listens to the user's Firestore document in real-time so that verification
  /// and blocked status updates from admin reflect immediately without a restart.
  void _listenUserStatus() {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null) return;
    _userStatusSub = FirebaseService.firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((snap) async {
      if (!snap.exists || !mounted) return;
      final data = snap.data() as Map<String, dynamic>;
      final blocked = data['blocked'] as bool? ?? false;
      final settings = await FirebaseService.getSettings();
      final paidAccess = settings['paidAccess'] as bool? ?? false;
      final verified = paidAccess ? (data['verified'] as bool? ?? false) : true;
      if (mounted) setState(() {
        _isBlocked = blocked;
        _isVerified = verified;
        _isPaidAccess = paidAccess;
      });
    });
  }

  void _startTypingAnimation() {
    _typingTimer?.cancel();
    _typingTimer = Timer.periodic(const Duration(milliseconds: 85), (timer) {
      if (!mounted) return;
      setState(() {
        if (!_isDeleting) {
          if (_charIndex < _typingTexts[_textIndex].length) {
            _currentText += _typingTexts[_textIndex][_charIndex];
            _charIndex++;
          } else {
            _isDeleting = true;
            timer.cancel();
            Future.delayed(const Duration(seconds: 2), () {
              if (mounted) _startTypingAnimation();
            });
          }
        } else {
          if (_currentText.isNotEmpty) {
            _currentText = _currentText.substring(0, _currentText.length - 1);
          } else {
            _isDeleting = false;
            _charIndex = 0;
            _textIndex = (_textIndex + 1) % _typingTexts.length;
            timer.cancel();
            Future.delayed(const Duration(milliseconds: 300), () {
              if (mounted) _startTypingAnimation();
            });
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();
    _userStatusSub?.cancel();
    _floatController.dispose();
    _searchController.dispose();
    _searchDebounce?.cancel();
    super.dispose();
  }

  void _showNotifications() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.white70 : Colors.black54;
    final dimColor = isDark ? Colors.white38 : Colors.black38;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Icon(Icons.notifications_none_rounded, color: mutedColor),
                  const SizedBox(width: 8),
                  Text('Notifications', style: TextStyle(color: baseColor, fontSize: 18, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Icon(Icons.close, color: dimColor),
                  ),
                ],
              ),
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12, height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
            stream: FirebaseService.getNotificationsForUser(FirebaseService.currentUser!.uid, _userCreatedAt),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.notifications_off_rounded, size: 60, color: isDark ? Colors.white12 : Colors.black12),
                          const SizedBox(height: 16),
                          Text('No notifications yet', style: TextStyle(color: dimColor)),
                        ],
                      ),
                    );
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: snapshot.data!.docs.length,
                    itemBuilder: (context, index) {
                      final data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                      final message = data['message'] as String? ?? '';
                      final userName = data['userName'] as String? ?? '';
                      final role = data['role'] as String? ?? '';
                      final time = data['createdAt'] as Timestamp?;
                      final timeStr = time != null
                          ? '${DateTime.now().difference(time.toDate()).inMinutes}m ago'
                          : '';
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.05 : 0.03),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.08 : 0.06)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              role == 'admin' ? Icons.admin_panel_settings : Icons.workspace_premium,
                              size: 20,
                              color: role == 'admin' ? Colors.redAccent : Colors.orange,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    message,
                                    style: TextStyle(color: baseColor, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '$userName • $timeStr',
                                    style: TextStyle(color: dimColor, fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  final List<Map<String, List<String>>> _examCategories = [
    {'Entry Tests': ['MDCAT', 'ECAT', 'NUST', 'NET', 'FAST', 'USAT', 'NTS NAT', 'GAT', 'GRE', 'HAT', 'SAT']},
    {'University Tests': ['NED', 'NUTECH', 'CUET', 'BCAT', 'TCAT', 'IBA', 'LSE', 'LCAT', 'GIKI', 'BUET', 'AUET', 'VU']},
    {'Medical & Other': ['DUHS', 'JSMU', 'IIUI', 'NUML', 'KU', 'UAF', 'IELTS', 'CCE']},
    {'CSS & Services': ['CSS', 'PMS', 'KPPSC', 'PPSC', 'BPSC', 'AJKPSC', 'SPSC', 'GBPSC', 'ISSB', 'ASF', 'FPSC']},
    {'Global Opportunities': ['Abroad Scholarships', 'Abroad Jobs', 'Language Learning', 'Programming']},
  ];

  Widget _buildIntroScreen() {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF060D1F), Color(0xFF0D0D2E), Color(0xFF1A0533)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        ...List.generate(15, (i) => Positioned(
          top: (i * 67.0) % 800,
          left: (i * 43.0) % 400,
          child: AnimatedBuilder(
            animation: _floatController,
            builder: (_, __) => Container(
              width: (i % 5 + 2).toDouble(),
              height: (i % 5 + 2).toDouble(),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: [
                  const Color(0xFF00E5FF),
                  Colors.purple,
                  Colors.blueAccent,
                ][i % 3].withValues(alpha: 0.15 + (i % 4) * 0.04),
              ),
            ),
          ),
        )),
        SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Expanded(
                flex: 5,
                child: _buildEducationAnimation(),
              ),
              const Spacer(flex: 1),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Column(
                  children: [
                    const Text(
                      'PREPORA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.0,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your Gateway to Academic Excellence',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 18,
                        fontWeight: FontWeight.w400,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Study Smarter with AI',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 13,
                        fontWeight: FontWeight.w300,
                        decoration: TextDecoration.none,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Text(
                          'Prepare for ',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.none,
                          ),
                        ),
                        Flexible(
                          child: Text(
                            _currentText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              decoration: TextDecoration.none,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        _buildCursor(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    AnimatedOpacity(
                      opacity: _currentText.isNotEmpty ? 1.0 : 0.0,
                      duration: const Duration(milliseconds: 400),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: Container(
                          key: ValueKey(_currentText),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _getCategoryFor(_currentText),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.4),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.5,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(flex: 2),
              _buildArrowButton(),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCursor() {
    return AnimatedBuilder(
      animation: _floatController,
      builder: (_, __) => Container(
        width: 2,
        height: 22,
        margin: const EdgeInsets.only(left: 3),
        decoration: BoxDecoration(
          color: _floatAnim.value > 0
              ? const Color(0xFF00E5FF)
              : const Color(0xFF00E5FF).withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(1),
        ),
      ),
    );
  }

  String _getCategoryFor(String exam) {
    for (final cat in _examCategories) {
      final title = cat.keys.first;
      final items = cat.values.first;
      if (items.contains(exam)) return title.toUpperCase();
    }
    return '';
  }  Widget _buildArrowButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: AnimatedPressable(
        onTap: () {
          _typingTimer?.cancel();
          setState(() => _hasStarted = true);
        },
        scaleFactor: 0.95,
        child: AnimatedBuilder(
          animation: _floatController,
          builder: (_, __) => Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A148C), Color(0xFF00B8D4)],
              ),
              borderRadius: BorderRadius.circular(40),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00B8D4).withValues(alpha: 0.25 + (_floatAnim.value.abs() / 40) * 0.3),
                  blurRadius: 16 + _floatAnim.value.abs(),
                  spreadRadius: 1,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                const SizedBox(width: 24),
                Text("Let's Continue",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                      decoration: TextDecoration.none,
                    )),
                const SizedBox(width: 10),
                AnimatedBuilder(
                  animation: _floatController,
                  builder: (_, __) => Transform.translate(
                    offset: Offset(_floatAnim.value * 0.6, 0),
                    child: const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEducationAnimation() {
    return const Center(
      child: SizedBox(
        width: 300,
        height: 260,
        child: _StudyRoomAnimation(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, {bool showFullMenu = true}) {
    return AppBar(
      automaticallyImplyLeading: false,
      title: Row(
        children: [
          Image.asset('assets/logo.png', height: 30, width: 30),
          const SizedBox(width: 10),
          const Text('PrePora', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      actions: [
        if (showFullMenu)
          StreamBuilder<QuerySnapshot>(
            stream: _notificationStream ?? FirebaseService.getNotificationsForUser(FirebaseService.currentUser?.uid ?? '', _userCreatedAt),
            builder: (context, snap) {
              final count = snap.hasData ? snap.data!.docs.length : 0;
              return IconButton(
                icon: Stack(
                  children: [
                    Icon(Icons.notifications_none_rounded, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                    if (count > 0)
                      Positioned(
                        right: -2, top: -2,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: const BoxDecoration(color: Colors.redAccent, shape: BoxShape.circle),
                          constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                          child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                        ),
                      ),
                  ],
                ),
                onPressed: _showNotifications,
                tooltip: 'Notifications',
              );
            },
          ),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseService.getNotices(),
          builder: (context, noticeSnap) {
            final noticeCount = noticeSnap.hasData ? noticeSnap.data!.docs.length : 0;
            return PopupMenuButton<String>(
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(Icons.more_vert, color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87),
                  if (noticeCount > 0 && showFullMenu)
                    Positioned(
                      right: -6, top: -4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                        child: Text('$noticeCount', style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ),
                ],
              ),
              color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2D2D2D) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              itemBuilder: (_) => showFullMenu
                  ? [
                      PopupMenuItem(value: 'settings', child: Row(children: [Icon(Icons.settings_outlined, size: 18, color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.black87), SizedBox(width: 10), Text('Settings', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87))])),
                      PopupMenuItem(value: 'notes', child: Row(children: [Icon(Icons.note_rounded, size: 18, color: Color(0xFF00B8D4)), SizedBox(width: 10), Text('Notes', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87))])),
                      PopupMenuItem(value: 'notices', child: Row(children: [
                        const Icon(Icons.campaign_rounded, size: 18, color: Colors.amber),
                        const SizedBox(width: 10),
                        Text('Notice Board', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87)),
                        if (noticeCount > 0) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: Colors.amber, borderRadius: BorderRadius.circular(10)),
                            child: Text('$noticeCount', style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ])),
                      PopupMenuItem(value: 'rate_app', child: Row(children: [const Icon(Icons.star_rounded, size: 18, color: Colors.amber), SizedBox(width: 10), Text('Rate the App', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87))])),
                      PopupMenuItem(value: 'contact_support', child: Row(children: [Icon(Icons.support_agent_rounded, size: 18, color: Colors.orange), SizedBox(width: 10), Text('Contact Support', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87))])),
                      PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 18, color: Colors.redAccent), SizedBox(width: 10), Text('Logout', style: TextStyle(color: Colors.redAccent))])),
                    ]
                  : [
                      PopupMenuItem(value: 'contact_support', child: Row(children: [Icon(Icons.support_agent_rounded, size: 18, color: Colors.orange), SizedBox(width: 10), Text('Contact Support', style: TextStyle(color: Theme.of(context).brightness == Brightness.dark ? Colors.white : Colors.black87))])),
                      const PopupMenuItem(value: 'logout', child: Row(children: [Icon(Icons.logout, size: 18, color: Colors.redAccent), SizedBox(width: 10), Text('Logout', style: TextStyle(color: Colors.redAccent))])),
                    ],
              onSelected: (val) async {
                if (val == 'settings') {
                  context.push('/settings');
                } else if (val == 'notes') {
                  context.push('/notes');
                } else if (val == 'notices') {
                  context.push('/student/notices');
                } else if (val == 'rate_app') {
                  _rateApp(context);
                } else if (val == 'contact_support') {
                  _handleFeedback(context);
                } else if (val == 'logout') {
                  await FirebaseService.signOut();
                  if (context.mounted) context.go('/auth/login');
                }
              },
            );
          },
        ),
      ],
    );
  }

  Widget _buildDashboard(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(context),
      body: Column(
        children: [
          _buildSearchBar(context),
          _buildStreakBar(context),
          Expanded(
            child: _searchQuery.isNotEmpty
                ? _buildSearchResults(context)
                : _DashboardGrid(key: _gridKey),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'ai_chat',
        onPressed: () => context.push('/ai_tutor'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF4A148C), Color(0xFF00B8D4)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF00B8D4).withValues(alpha: 0.5),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
          child: ClipOval(child: Image.asset('assets/logo.png', width: 30, height: 30, fit: BoxFit.cover)),
        ),
      ),
    );
  }

  Widget _buildStreakBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF4A148C).withValues(alpha: 0.3), const Color(0xFFFF6F00).withValues(alpha: 0.2)]
              : [const Color(0xFF4A148C).withValues(alpha: 0.08), const Color(0xFFFF6F00).withValues(alpha: 0.06)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department_rounded, color: Colors.orange, size: 28),
          const SizedBox(width: 8),
          Text('$_streakCount', style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold, fontSize: 18,
          )),
          const SizedBox(width: 4),
          Text('day streak', style: TextStyle(color: isDark ? Colors.white54 : Colors.black45, fontSize: 12)),
          const Spacer(),
          Icon(Icons.stars_rounded, color: Colors.amber.shade600, size: 16),
          const SizedBox(width: 4),
          Text('$_totalActiveDays total', style: TextStyle(color: isDark ? Colors.white38 : Colors.black38, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final hintColor = isDark ? Colors.white38 : Colors.black45;
    final fillColor = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04);
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: TextField(
        controller: _searchController,
        style: TextStyle(color: baseColor, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search folders & contents...',
          hintStyle: TextStyle(color: hintColor, fontSize: 14),
          prefixIcon: Icon(Icons.search_rounded, color: hintColor, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear_rounded, color: hintColor, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() { _searchQuery = ''; _searchResults = []; });
                  },
                )
              : null,
          filled: true,
          fillColor: fillColor,
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (val) {
          _searchDebounce?.cancel();
          _searchDebounce = Timer(const Duration(milliseconds: 400), () {
            setState(() => _searchQuery = val.trim());
            if (val.trim().isNotEmpty) {
              _performSearch(val.trim());
            } else {
              setState(() { _searchResults = []; _isSearching = false; });
            }
          });
        },
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );
  }

  Future<void> _performSearch(String query) async {
    if (query.length < 2) {
      if (mounted) setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    if (mounted) setState(() => _isSearching = true);
    final q = query.toLowerCase();
    final results = <_SearchResult>[];
    final foldersSnap = await FirebaseService.firestore.collection('folders').get();
    for (final folderDoc in foldersSnap.docs) {
      final folderData = folderDoc.data() as Map<String, dynamic>;
      if (folderData['invisible'] == true) continue;
      final folderName = folderData['name'] as String? ?? '';
      final folderId = folderDoc.id;
      if (folderName.toLowerCase().contains(q)) {
        results.add(_SearchResult(
          title: folderName, folderId: folderId, isFolder: true,
        ));
      }
      final contentsSnap = await FirebaseService.firestore
          .collection('folders').doc(folderId)
          .collection('contents').get();
      for (final contentDoc in contentsSnap.docs) {
        final contentData = contentDoc.data() as Map<String, dynamic>;
        final contentName = contentData['name'] as String? ?? contentData['title'] as String? ?? '';
        if (contentName.toLowerCase().contains(q)) {
          if (contentData['invisible'] == true || contentData['locked'] == true || contentData['updating'] == true) continue;
          final docType = contentData['type'] as String?;
          final isSubfolder = docType == 'subfolder' || (docType == null && contentData['url'] == null);
          final contentParentId = contentData['parentContentId'] as String?;
          results.add(_SearchResult(
            title: contentName,
            folderId: folderId,
            folderName: folderName,
            contentId: contentDoc.id,
            isFolder: false,
            isSubfolder: isSubfolder,
            parentContentId: contentParentId,
          ));
        }
      }
    }
    if (mounted) setState(() { _searchResults = results; _isSearching = false; });
  }

  Widget _buildSearchResults(BuildContext navContext) {
    final isDark = Theme.of(navContext).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final mutedColor = isDark ? Colors.white54 : Colors.black54;
    if (_isSearching) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 60, color: isDark ? Colors.white12 : Colors.black12),
            const SizedBox(height: 12),
            Text('No results found', style: TextStyle(color: dimColor, fontSize: 16)),
            Text('Try a different search term', style: TextStyle(color: dimColor, fontSize: 13)),
          ],
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      itemCount: _searchResults.length,
      itemBuilder: (context, index) {
        final r = _searchResults[index];
        final label = r.isFolder ? 'Folder' : 'Content';
        final path = r.isFolder
            ? '/folders/${r.folderId}'
            : r.contentId != null
                ? '/folders/${r.folderId}/sub/${r.contentId}'
                : '/folders/${r.folderId}';
        return GestureDetector(
          onTap: () {
            if (!navContext.mounted) return;
            navContext.push(path);
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.05 : 0.03),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  r.isFolder ? Icons.folder_rounded : Icons.description_rounded,
                  color: r.isFolder ? Colors.amber : const Color(0xFF00B8D4),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(child: Text(r.title, style: TextStyle(color: baseColor, fontWeight: FontWeight.w600, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis)),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: r.isFolder ? Colors.amber : const Color(0xFF00B8D4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      if (!r.isFolder && r.folderName != null)
                        Text('in ${r.folderName!}', style: TextStyle(color: mutedColor, fontSize: 11)),
                      Text(path, style: TextStyle(color: dimColor, fontSize: 11, fontFamily: 'monospace'), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: dimColor, size: 18),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSettings() {
    final user = FirebaseService.currentUser;
    final userName = user?.displayName ?? _userName;
    final userEmail = user?.email ?? _userEmail;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.white70 : Colors.black54;
    final dimColor = isDark ? Colors.white38 : Colors.black45;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(      builder: (ctx, setLocal) {
        final container = ProviderScope.containerOf(context);
        final themeMode = container.read(themeModeProvider.notifier);
        ThemeMode currentTheme = container.read(themeModeProvider);
        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.settings_outlined, color: mutedColor, size: 22),
              const SizedBox(width: 10),
              Text('Settings', style: TextStyle(color: baseColor, fontSize: 18, fontWeight: FontWeight.bold)),
            ]),
            const SizedBox(height: 12),
            ListTile(
              leading: CircleAvatar(child: Text(userName.isNotEmpty ? userName[0].toUpperCase() : '?', style: const TextStyle(color: Colors.white))),
              title: Text(userName, style: TextStyle(color: baseColor, fontWeight: FontWeight.bold)),
              subtitle: Text(userEmail, style: TextStyle(color: dimColor, fontSize: 12)),
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            ListTile(
              leading: Icon(currentTheme == ThemeMode.light ? Icons.light_mode_rounded : (currentTheme == ThemeMode.dark ? Icons.dark_mode_rounded : Icons.settings_brightness_rounded), color: Colors.amber),
              title: Text('Theme', style: TextStyle(color: baseColor)),
              subtitle: Text(currentTheme == ThemeMode.light ? 'Light' : (currentTheme == ThemeMode.dark ? 'Dark' : 'System'), style: TextStyle(color: dimColor, fontSize: 12)),
              trailing: Icon(Icons.chevron_right, color: dimColor, size: 18),
              onTap: () {
                Navigator.pop(ctx);
                _showThemeDialog(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_rounded, color: Colors.blue),
              title: Text('Notifications', style: TextStyle(color: baseColor)),
              subtitle: Text('Daily streak reminders', style: TextStyle(color: dimColor, fontSize: 12)),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_rounded, color: Colors.orange),
              title: Text('Contact Support', style: TextStyle(color: baseColor)),
              subtitle: Text('Need help? Get in touch', style: TextStyle(color: dimColor, fontSize: 12)),
              onTap: () { Navigator.pop(context); context.push('/student/feedbacks'); },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline_rounded, color: Colors.grey),
              title: Text('Version', style: TextStyle(color: baseColor)),
              subtitle: Text('PrePora v1.0.0', style: TextStyle(color: dimColor, fontSize: 12)),
            ),
            const SizedBox(height: 8),
          ]),
        );
      }),
    );
  }

  void _showThemeDialog(BuildContext context) {
    final container = ProviderScope.containerOf(context);
    final themeMode = container.read(themeModeProvider.notifier);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Choose Theme', style: TextStyle(color: baseColor)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.light_mode_rounded, color: Colors.amber),
            title: Text('Light', style: TextStyle(color: baseColor)),
            onTap: () { themeMode.set(ThemeMode.light); Navigator.pop(d); },
          ),
          ListTile(
            leading: const Icon(Icons.dark_mode_rounded, color: Colors.blueGrey),
            title: Text('Dark', style: TextStyle(color: baseColor)),
            onTap: () { themeMode.set(ThemeMode.dark); Navigator.pop(d); },
          ),
          ListTile(
            leading: const Icon(Icons.settings_brightness_rounded, color: Colors.teal),
            title: Text('System', style: TextStyle(color: baseColor)),
            subtitle: Text('Follow device theme', style: TextStyle(color: dimColor, fontSize: 11)),
            onTap: () { themeMode.set(ThemeMode.system); Navigator.pop(d); },
          ),
        ]),
      ),
    );
  }

  Widget _buildBlockedScreen(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: const Color(0xFF0D001A),
      appBar: _buildAppBar(context, showFullMenu: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.gpp_bad_rounded, color: Colors.redAccent, size: 64),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Our system detected suspicious activity from your account',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.redAccent, fontSize: 15, height: 1.5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'If you believe this is a mistake, please contact the admin to restore access.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _handleFeedback(context),
                icon: const Icon(Icons.support_agent_rounded, color: Colors.white, size: 20),
                label: const Text('Contact Support', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4A148C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await FirebaseService.signOut();
                  if (context.mounted) context.go('/auth/login');
                },
                icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 20),
                label: const Text('Logout', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  String _userName = '';
  String _userEmail = '';

  Widget _buildPaymentBanner() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0D001A) : const Color(0xFFF5F0FF),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(children: [
            const SizedBox(height: 10),
            // Lock icon center top
            AnimatedBuilder(
              animation: _floatAnim,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, _floatAnim.value),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)]),
                    boxShadow: [BoxShadow(color: const Color(0xFF00B8D4).withValues(alpha: 0.4), blurRadius: 24, spreadRadius: 4)],
                  ),
                  child: const Icon(Icons.lock_outline_rounded, size: 48, color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 28),
            // Title
            ShaderMask(
              shaderCallback: (bounds) => const LinearGradient(colors: [Color(0xFFFFD700), Color(0xFFFF6B6B), Color(0xFF00E5FF)]).createShader(bounds),
              child: Text('PAID ACCESS', textAlign: TextAlign.center,
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900, color: isDark ? Colors.white : Colors.black87, letterSpacing: 2)),
            ),
            const SizedBox(height: 16),
            Text('Pay Rs.${_price.toStringAsFixed(0)} to get access',
              style: TextStyle(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.6), fontSize: 14)),
            const SizedBox(height: 24),
            // Account details card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: isDark
                    ? LinearGradient(colors: [Colors.purple.withValues(alpha: 0.2), Colors.blue.withValues(alpha: 0.15)])
                    : LinearGradient(colors: [Colors.purple.withValues(alpha: 0.05), Colors.blue.withValues(alpha: 0.03)]),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.1)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Send payment to:', style: TextStyle(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _bannerField('Account Owner', _accountTitle, Icons.person_rounded, Colors.orangeAccent),
                const SizedBox(height: 10),
                _bannerField('Account No', _accountNo, Icons.pin_rounded, Colors.cyanAccent),
                const SizedBox(height: 10),
                _bannerField('Bank Name', _bankName, Icons.account_balance_rounded, Colors.amber),
              ]),
            ),
            const SizedBox(height: 12),
            _bannerLine('Note: Fee is non-refundable after payment.', Icons.info_outline_rounded, Colors.redAccent, 13),
            const SizedBox(height: 20),
            // Field list card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: isDark
                    ? LinearGradient(colors: [Colors.green.withValues(alpha: 0.1), Colors.teal.withValues(alpha: 0.08)])
                    : LinearGradient(colors: [Colors.green.withValues(alpha: 0.04), Colors.teal.withValues(alpha: 0.02)]),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.1)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('After payment, submit feedback with:', style: TextStyle(color: (isDark ? Colors.white : Colors.black87).withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                _bannerField('Your Name', '______', Icons.badge_rounded, Colors.greenAccent),
                const SizedBox(height: 10),
                _bannerField('Your Email', '______', Icons.email_rounded, Colors.blueAccent),
                const SizedBox(height: 10),
                _bannerField('Account Owner', '______', Icons.person_rounded, Colors.orangeAccent),
                const SizedBox(height: 10),
                _bannerField('Account No', '______', Icons.pin_rounded, Colors.cyanAccent),
                const SizedBox(height: 10),
                _bannerField('Bank Name', '______', Icons.account_balance_rounded, Colors.amber),
                const SizedBox(height: 10),
                _bannerField('Receipt ID', '______', Icons.receipt_rounded, Colors.pinkAccent),
                const SizedBox(height: 10),
                _bannerField('City', '______', Icons.location_city_rounded, Colors.tealAccent),
                const SizedBox(height: 10),
                _bannerField('Province', '______', Icons.map_rounded, Colors.lightBlueAccent),
                const SizedBox(height: 10),
                _bannerField('Course / University / Field', '______', Icons.school_rounded, Colors.deepPurpleAccent),
              ]),
            ),
            const SizedBox(height: 12),
            _bannerLine('Your account will be verified within 24-48 hours after feedback submission.', Icons.access_time_rounded, Colors.yellowAccent, 13),
            const SizedBox(height: 24),
            // Submit feedback button
            GestureDetector(
              onTap: () => _handleFeedback(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)]),
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [BoxShadow(color: const Color(0xFF00B8D4).withValues(alpha: 0.3), blurRadius: 12, spreadRadius: 1)],
                ),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.feedback_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text('Submit Feedback', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ]),
              ),
            ),
            const SizedBox(height: 20),
            // Logout at bottom
            GestureDetector(
              onTap: () async {
                await FirebaseService.signOut();
                if (context.mounted) context.go('/auth/login');
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.redAccent.withValues(alpha: 0.5)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.logout_rounded, color: Colors.redAccent.shade200, size: 18),
                  const SizedBox(width: 8),
                  Text('Logout', style: TextStyle(color: Colors.redAccent.shade200, fontSize: 14)),
                ]),
              ),
            ),
            const SizedBox(height: 20),
          ]),
        ),
      ),
    );
  }

  void _handleFeedback(BuildContext ctx) async {
    final uid = FirebaseService.currentUser?.uid;
    if (uid == null) return;
    showDialog(context: context, builder: (_) => const Center(child: CircularProgressIndicator()), barrierDismissible: false);
    try {
      final isVerified = await FirebaseService.isStudentVerified(uid);
      if (!mounted) return;
      if (context.mounted) Navigator.pop(context);
      if (!mounted) return;
      if (isVerified) {
        _showFeedbackListDialog(context, uid);
        return;
      }
      final feedbacks = await FirebaseService.getStudentFeedbacksOnce(uid);
      if (!mounted) return;
      if (feedbacks.isEmpty) {
        _showFeedbackWithPaymentDialog(context);
      } else {
        _showFeedbackListDialog(context, uid);
      }
    } catch (e) {
      if (mounted && context.mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.redAccent));
      }
    }
  }

  void _showFeedbackWithPaymentDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final labelColor = isDark ? Colors.white38 : Colors.black54;
    final fillColor = isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04);
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final ownerCtrl = TextEditingController();
    final accNoCtrl = TextEditingController();
    final bankCtrl = TextEditingController();
    final receiptCtrl = TextEditingController();
    final cityCtrl = TextEditingController();
    final provinceCtrl = TextEditingController();
    final courseCtrl = TextEditingController();
    int selDay = DateTime.now().day;
    int selMonth = DateTime.now().month;
    int selYear = DateTime.now().year;
    int selHour = DateTime.now().hour > 12 ? DateTime.now().hour - 12 : (DateTime.now().hour == 0 ? 12 : DateTime.now().hour);
    int selMinute = DateTime.now().minute;
    bool isPM = DateTime.now().hour >= 12;
    String? errorMsg;
    showDialog(
      context: context,
      builder: (d) => StatefulBuilder(
        builder: (ctx, setDState) => AlertDialog(
          backgroundColor: bgColor,
          title: Text('Submit Feedback', style: TextStyle(color: baseColor)),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: nameCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'Your Name *', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 10),
              TextField(controller: emailCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'Your Email *', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 10),
              TextField(controller: ownerCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'Account Owner *', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 10),
              TextField(controller: accNoCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'Account No *', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 10),
              TextField(controller: bankCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'Bank Name *', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 10),
              TextField(controller: receiptCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'Receipt ID *', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 10),
              TextField(controller: cityCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'City', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 10),
              TextField(controller: provinceCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'Province', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 10),
              TextField(controller: courseCtrl, style: TextStyle(color: baseColor),
                onChanged: (_) { setDState(() => errorMsg = null); },
                decoration: InputDecoration(labelText: 'Course / University / Field', labelStyle: TextStyle(color: labelColor),
                  filled: true, fillColor: fillColor, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: Text('Date:', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13))),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: DropdownButtonFormField<int>(
                  value: selDay, dropdownColor: bgColor, isExpanded: true,
                  style: TextStyle(color: baseColor),
                  decoration: InputDecoration(labelText: 'Day', labelStyle: TextStyle(color: labelColor),
                    filled: true, fillColor: fillColor, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: List.generate(31, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                  onChanged: (v) => setDState(() { selDay = v ?? selDay; errorMsg = null; }),
                )),
                const SizedBox(width: 6),
                Expanded(child: DropdownButtonFormField<int>(
                  value: selMonth, dropdownColor: bgColor, isExpanded: true,
                  style: TextStyle(color: baseColor),
                  decoration: InputDecoration(labelText: 'Month', labelStyle: TextStyle(color: labelColor),
                    filled: true, fillColor: fillColor, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: [
                    for (int m = 1; m <= 12; m++)
                      DropdownMenuItem(value: m, child: Text([
                        'January', 'February', 'March', 'April', 'May', 'June',
                        'July', 'August', 'September', 'October', 'November', 'December'
                      ][m - 1])),
                  ],
                  onChanged: (v) => setDState(() { selMonth = v ?? selMonth; errorMsg = null; }),
                )),
                const SizedBox(width: 6),
                Expanded(child: DropdownButtonFormField<int>(
                  value: selYear, dropdownColor: bgColor, isExpanded: true,
                  style: TextStyle(color: baseColor),
                  decoration: InputDecoration(labelText: 'Year', labelStyle: TextStyle(color: labelColor),
                    filled: true, fillColor: fillColor, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: List.generate(10, (i) => DropdownMenuItem(value: 2020 + i, child: Text('${2020 + i}'))),
                  onChanged: (v) => setDState(() { selYear = v ?? selYear; errorMsg = null; }),
                )),
              ]),
              const SizedBox(height: 14),
              Align(alignment: Alignment.centerLeft, child: Text('Time:', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13))),
              const SizedBox(height: 6),
              Row(children: [
                Expanded(child: DropdownButtonFormField<int>(
                  value: selHour, dropdownColor: bgColor, isExpanded: true,
                  style: TextStyle(color: baseColor),
                  decoration: InputDecoration(labelText: 'Hour', labelStyle: TextStyle(color: labelColor),
                    filled: true, fillColor: fillColor, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: List.generate(12, (i) => DropdownMenuItem(value: i + 1, child: Text('${i + 1}'))),
                  onChanged: (v) => setDState(() { selHour = v ?? selHour; errorMsg = null; }),
                )),
                const SizedBox(width: 6),
                Expanded(child: DropdownButtonFormField<int>(
                  value: selMinute, dropdownColor: bgColor, isExpanded: true,
                  style: TextStyle(color: baseColor),
                  decoration: InputDecoration(labelText: 'Min', labelStyle: TextStyle(color: labelColor),
                    filled: true, fillColor: fillColor, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: List.generate(60, (i) => DropdownMenuItem(value: i, child: Text(i < 10 ? '0$i' : '$i'))),
                  onChanged: (v) => setDState(() { selMinute = v ?? selMinute; errorMsg = null; }),
                )),
                const SizedBox(width: 6),
                Expanded(child: DropdownButtonFormField<String>(
                  value: isPM ? 'PM' : 'AM', dropdownColor: bgColor, isExpanded: true,
                  style: TextStyle(color: baseColor),
                  decoration: InputDecoration(labelText: 'AM/PM', labelStyle: TextStyle(color: labelColor),
                    filled: true, fillColor: fillColor, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12), isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12))),
                  items: ['AM', 'PM'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
                  onChanged: (v) => setDState(() { isPM = v == 'PM'; errorMsg = null; }),
                )),
              ]),
              if (errorMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(errorMsg!, style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
                ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
            StatefulBuilder(builder: (ctx, setBtn) {
              var _sending = false;
              return ElevatedButton(
                onPressed: _sending ? null : () async {
                  if (_sending) return;
                  setBtn(() => _sending = true);
                  final missing = <String>[];
                  if (nameCtrl.text.trim().isEmpty) missing.add('Name');
                  if (emailCtrl.text.trim().isEmpty) missing.add('Email');
                  if (ownerCtrl.text.trim().isEmpty) missing.add('Account Owner');
                  if (accNoCtrl.text.trim().isEmpty) missing.add('Account No');
                  if (bankCtrl.text.trim().isEmpty) missing.add('Bank Name');
                  if (receiptCtrl.text.trim().isEmpty) missing.add('Receipt ID');
                  if (missing.isNotEmpty) {
                    setBtn(() => _sending = false);
                    setDState(() => errorMsg = 'Please fill all required fields: ${missing.join(', ')}');
                    return;
                  }
                  final months = ['January', 'February', 'March', 'April', 'May', 'June',
                      'July', 'August', 'September', 'October', 'November', 'December'];
                  final timeStr = '${selHour > 9 ? selHour : '0$selHour'}:${selMinute < 10 ? '0$selMinute' : '$selMinute'} ${isPM ? 'PM' : 'AM'}';
                  final dateStr = '${selDay < 10 ? '0$selDay' : '$selDay'} ${months[selMonth - 1]} $selYear';
                  await FirebaseService.submitFeedback(
                    'Name: ${nameCtrl.text.trim()}\nEmail: ${emailCtrl.text.trim()}\nOwner: ${ownerCtrl.text.trim()}\nAccNo: ${accNoCtrl.text.trim()}\nBank: ${bankCtrl.text.trim()}\nReceipt: ${receiptCtrl.text.trim()}\nCity: ${cityCtrl.text.trim()}\nProvince: ${provinceCtrl.text.trim()}\nCourse: ${courseCtrl.text.trim()}\nDate: $dateStr\nTime: $timeStr'
                  );
                  if (d.mounted) Navigator.pop(d);
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
                child: Text(_sending ? 'Sending...' : 'Send', style: const TextStyle(color: Colors.white)),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showFeedbackTextDialog(BuildContext context) {
    final ctrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: bgColor,
        title: Text('Submit Feedback', style: TextStyle(color: baseColor)),
        content: TextField(
          controller: ctrl, maxLines: 4,
          style: TextStyle(color: baseColor),
          decoration: InputDecoration(
            hintText: 'Write your feedback...', hintStyle: TextStyle(color: dimColor),
            filled: true, fillColor: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.04),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Cancel')),
          StatefulBuilder(builder: (ctx, setBtn) {
            var _sending = false;
            return ElevatedButton(
              onPressed: _sending ? null : () async {
                if (_sending) return;
                if (ctrl.text.trim().isEmpty) return;
                setBtn(() => _sending = true);
                await FirebaseService.submitFeedback(ctrl.text.trim());
                if (d.mounted) Navigator.pop(d);
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
              child: Text(_sending ? 'Sending...' : 'Send', style: const TextStyle(color: Colors.white)),
            );
          }),
        ],
      ),
    );
  }

  void _showFeedbackListDialog(BuildContext context, String uid) async {
    final feedbacks = await FirebaseService.getStudentFeedbacksOnce(uid);
    if (!context.mounted) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    final dimColor = isDark ? Colors.white38 : Colors.black54;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: const BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        var items = feedbacks;
        return DraggableScrollableSheet(
          expand: false,
          maxChildSize: 0.85,
          initialChildSize: 0.6,
          builder: (ctx, scrollCtrl) => Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(children: [
                Text('Contact Support', style: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.add, color: Color(0xFF00B8D4)), onPressed: () {
                  Navigator.pop(ctx);
                  _showFeedbackTextDialog(context);
                }),
                IconButton(icon: Icon(Icons.close, color: dimColor), onPressed: () => Navigator.pop(ctx)),
              ]),
            ),
            Divider(color: isDark ? Colors.white12 : Colors.black12),
            Expanded(
              child: items.isEmpty
                  ? Center(child: Text('No feedbacks', style: TextStyle(color: dimColor)))
                  : ListView.builder(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      itemBuilder: (context, i) {
                        final data = items[i];
                        final ticket = data['ticketNo'] as String? ?? '';
                        final msg = data['message'] as String? ?? '';
                        final status = data['status'] as String? ?? 'pending';
                        final time = (data['createdAt'] as Timestamp?)?.toDate();
                        final timeStr = time != null ? '${time.day}/${time.month}/${time.year} ${time.hour}:${time.minute.toString().padLeft(2, '0')}' : '';
                        final statusColor = status == 'completed' ? Colors.green : (status == 'rejected' ? Colors.red : (status == 'verified' ? Colors.teal : Colors.orange));
                        return Card(
                          color: (isDark ? Colors.white : Colors.black87).withValues(alpha: isDark ? 0.05 : 0.03),
                          margin: const EdgeInsets.only(bottom: 10),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Text('#$ticket', style: const TextStyle(color: Color(0xFF00B8D4), fontWeight: FontWeight.bold, fontSize: 13)),
                                const Spacer(),
                                Text(status.toUpperCase(), style: TextStyle(color: statusColor, fontSize: 11)),
                              ]),
                              const SizedBox(height: 8),
                              Text(msg, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 14)),
                              const SizedBox(height: 8),
                              Text(timeStr, style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 11)),
                            ]),
                          ),
                        );
                      },
                    ),
            ),
          ]),
        );
      }),
    );
  }

  void _rateApp(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF1A0533) : Colors.white;
    final baseColor = isDark ? Colors.white : Colors.black87;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: bgColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.star_rounded, color: Colors.amber, size: 24),
          SizedBox(width: 10),
          Text('Rate PrePora', style: TextStyle(fontWeight: FontWeight.bold)),
        ]),
        content: Text('Love using PrePora? Your rating helps us improve and reach more students!', style: TextStyle(color: baseColor.withValues(alpha: 0.8))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Not Now', style: TextStyle(color: Colors.grey))),
          ElevatedButton.icon(
            icon: const Icon(Icons.star_rounded, color: Colors.white, size: 18),
            label: const Text('Rate on Play Store'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.amber.shade700, foregroundColor: Colors.white),
            onPressed: () async {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Play Store link will open when published', style: TextStyle(color: Colors.white))),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _bannerLine(String text, IconData icon, Color iconColor, double fontSize) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: iconColor, size: fontSize + 2),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: TextStyle(color: baseColor.withValues(alpha: 0.9), fontSize: fontSize))),
      ]),
    );
  }

  Widget _bannerField(String label, String value, IconData icon, Color iconColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.white : Colors.black87;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, color: iconColor, size: 16),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(color: baseColor.withValues(alpha: 0.5), fontSize: 11)),
        Text(value, style: TextStyle(color: baseColor, fontSize: 15, fontWeight: FontWeight.w600)),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_isBlocked) return _buildBlockedScreen(context);
    if (_isPaidAccess && !_isVerified) return _buildPaymentBanner();
    if (!_hasStarted) return SizedBox.expand(child: _buildIntroScreen());
    return Stack(
      children: [
        _buildDashboard(context),
        if (_latestUpdateVersion != null && _latestUpdateVersion!.isNotEmpty)
          Positioned(
            top: 0, left: 0, right: 0,
            child: GestureDetector(
              onTap: () => _showUpdateDialog(context),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(colors: [Color(0xFF4A148C), Color(0xFF00B8D4)]),
                ),
                child: Row(children: [
                  const Icon(Icons.system_update_rounded, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Update v$_latestUpdateVersion available', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600))),
                  const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 14),
                ]),
              ),
            ),
          ),
      ],
    );
  }

  String? _latestUpdateVersion;
  String? _latestUpdateLink;
  String _currentAppVersion = '1.0.0';

  void _checkForUpdates() {
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _currentAppVersion = info.version);
    });
    FirebaseService.firestore.collection('app_updates').orderBy('createdAt', descending: true).limit(1).snapshots().listen((snap) {
      if (!mounted || snap.docs.isEmpty) return;
      final d = snap.docs.first.data() as Map<String, dynamic>;
      final version = d['version'] as String?;
      final link = d['link'] as String?;
      if (version != null && version.isNotEmpty && version != _currentAppVersion) {
        setState(() { _latestUpdateVersion = version; _latestUpdateLink = link; });
      }
    });
  }

  void _showUpdateDialog(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (d) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF1A0533) : Colors.white,
        title: Row(children: [
          const Icon(Icons.system_update_rounded, color: Colors.cyanAccent),
          const SizedBox(width: 8),
          Text('Update v$_latestUpdateVersion', style: TextStyle(color: isDark ? Colors.white : Colors.black87)),
        ]),
        content: Text('A new version of PrePora is available. Update now for the latest features and improvements.',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black54)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(d), child: const Text('Later', style: TextStyle(color: Colors.grey))),
          if (_latestUpdateLink != null && _latestUpdateLink!.isNotEmpty)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(d);
                context.push('/webview', extra: {'url': _latestUpdateLink, 'title': 'Update v$_latestUpdateVersion'});
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4A148C)),
              child: const Text('Update Now', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
    );
  }
}

class ShimmerText extends StatefulWidget {
  final String text;
  final TextStyle style;
  const ShimmerText({super.key, required this.text, required this.style});
  @override
  State<ShimmerText> createState() => _ShimmerTextState();
}

class _ShimmerTextState extends State<ShimmerText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat();
    _anim = Tween<double>(begin: -1, end: 2).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          colors: const [Colors.white, Color(0xFF00E5FF), Colors.white, Color(0xFF4A148C)],
          stops: [_anim.value, _anim.value + 0.15, _anim.value + 0.3, _anim.value + 0.45],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ).createShader(bounds),
        child: Text(widget.text, style: widget.style.copyWith(color: Colors.white)),
      ),
    );
  }
}

class _DashboardGrid extends StatefulWidget {
  const _DashboardGrid({Key? key}) : super(key: key);
  @override
  State<_DashboardGrid> createState() => _DashboardGridState();
}

class _DashboardGridState extends State<_DashboardGrid> {
  late final Stream<QuerySnapshot> _folderStream;

  @override
  void initState() {
    super.initState();
    _folderStream = FirebaseService.getAllFolders();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: _folderStream,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open_rounded, size: 80, color: isDark ? Colors.white12 : Colors.black12),
                const SizedBox(height: 16),
                Text('No folders available yet', style: TextStyle(color: isDark ? Colors.white38 : Colors.black45, fontSize: 16)),
                const SizedBox(height: 8),
                Text('Admin will add study folders soon', style: TextStyle(color: isDark ? Colors.white24 : Colors.black38, fontSize: 13)),
              ],
            ),
          );
        }
        final docs = snapshot.data!.docs.where((doc) {
          final d = doc.data() as Map<String, dynamic>;
          return d['invisible'] != true;
        }).toList();
        final colors = [Colors.purple, Colors.teal, Colors.blue, Colors.orange, Colors.pink, Colors.indigo, Colors.green, Colors.amber];
        final screenWidth = MediaQuery.of(context).size.width;
        final crossAxisCount = screenWidth > 900 ? 4 : (screenWidth > 600 ? 3 : 2);
        return GridView.builder(
          padding: const EdgeInsets.all(14),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount, crossAxisSpacing: 14, mainAxisSpacing: 14, childAspectRatio: screenWidth > 600 ? 1.1 : 0.95,
          ),
          itemCount: docs.length,
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final color = colors[index % colors.length];
            final isLocked = data['locked'] == true || data['updating'] == true;
            final folderId = docs[index].id;
            final isDark = Theme.of(context).brightness == Brightness.dark;
            final baseColor = isDark ? Colors.white : Colors.black87;
            final dimColor = isDark ? Colors.white38 : Colors.black54;
            return GestureDetector(
              onTap: isLocked ? null : () => context.push('/folders/$folderId'),
              child: Stack(
                children: [
                  GlassmorphicContainer(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Center(child: Icon(
                          Icons.folder_rounded,
                          size: 48, color: isLocked ? Colors.grey : color,
                        )),
                        const SizedBox(height: 6),
                        Text(
                          data['name'] ?? 'Folder',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: isLocked ? dimColor : baseColor),
                          textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        if (isLocked)
                          Center(child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                            child: const Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.lock_rounded, color: Colors.redAccent, size: 12),
                              SizedBox(width: 4),
                              Text('Locked', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ]),
                          ))
                        else
                          Text('${data['itemCount'] ?? 0} items', style: TextStyle(color: dimColor, fontSize: 12), textAlign: TextAlign.center),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SearchResult {
  final String title;
  final String folderId;
  final String? folderName;
  final String? contentId;
  final bool isFolder;
  final bool isSubfolder;
  final String? parentContentId;

  _SearchResult({
    required this.title,
    required this.folderId,
    this.folderName,
    this.contentId,
    required this.isFolder,
    this.isSubfolder = false,
    this.parentContentId,
  });
}

class _StudyRoomAnimation extends StatefulWidget {
  const _StudyRoomAnimation();

  @override
  State<_StudyRoomAnimation> createState() => _StudyRoomAnimationState();
}

class _StudyRoomAnimationState extends State<_StudyRoomAnimation>
    with TickerProviderStateMixin {
  Timer? _clockTimer;
  late int _hour, _minute, _second;
  late final AnimationController _breathController;
  late final AnimationController _lampController;

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) => _updateClock());

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _lampController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  void _updateClock() {
    final now = DateTime.now().toUtc().add(const Duration(hours: 5));
    _hour = now.hour % 12;
    _minute = now.minute;
    _second = now.second;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _breathController.dispose();
    _lampController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_breathController, _lampController]),
      builder: (context, _) {
        final secondAngle = (_second / 60) * 2 * math.pi;
        final minuteAngle = ((_minute + _second / 60) / 60) * 2 * math.pi;
        final hourAngle = ((_hour + _minute / 60) / 12) * 2 * math.pi;
        final breath = _breathController.value;
        final lampGlow = _lampController.value;

        return CustomPaint(
          size: const Size(300, 260),
          painter: _StudyRoomPainter(
            clockHourAngle: hourAngle,
            clockMinuteAngle: minuteAngle,
            clockSecondAngle: secondAngle,
            breathValue: breath,
            lampGlow: lampGlow,
            isDark: Theme.of(context).brightness == Brightness.dark,
          ),
        );
      },
    );
  }
}

class _StudyRoomPainter extends CustomPainter {
  final double clockHourAngle;
  final double clockMinuteAngle;
  final double clockSecondAngle;
  final double breathValue;
  final double lampGlow;
  final bool isDark;

  _StudyRoomPainter({
    required this.clockHourAngle,
    required this.clockMinuteAngle,
    required this.clockSecondAngle,
    required this.breathValue,
    required this.lampGlow,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final height = size.height;

    final floorPaint = Paint()
      ..color = isDark ? Colors.white10 : Colors.black12
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final primaryColor = isDark ? const Color(0xFFB388FF) : const Color(0xFF4A148C);
    final secondaryColor = const Color(0xFF00E5FF);

    // 1. Draw floor line
    canvas.drawLine(Offset(20, height - 20), Offset(width - 20, height - 20), floorPaint);

    // 2. Draw Wall Clock (top right)
    final clockCenter = Offset(width - 60, 60);
    const clockRadius = 24.0;

    final clockBgPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.03)
      ..style = PaintingStyle.fill;
    final clockOuterPaint = Paint()
      ..color = isDark ? Colors.white24 : Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(clockCenter, clockRadius, clockBgPaint);
    canvas.drawCircle(clockCenter, clockRadius, clockOuterPaint);

    final tickPaint = Paint()
      ..color = isDark ? Colors.white38 : Colors.black38
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    canvas.drawLine(clockCenter - const Offset(0, clockRadius - 4), clockCenter - const Offset(0, clockRadius - 8), tickPaint);
    canvas.drawLine(clockCenter + const Offset(0, clockRadius - 4), clockCenter + const Offset(0, clockRadius - 8), tickPaint);
    canvas.drawLine(clockCenter - const Offset(clockRadius - 4, 0), clockCenter - const Offset(clockRadius - 8, 0), tickPaint);
    canvas.drawLine(clockCenter + const Offset(clockRadius - 4, 0), clockCenter + const Offset(clockRadius - 8, 0), tickPaint);

    final hourHandPaint = Paint()
      ..color = isDark ? Colors.white70 : Colors.black87
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    final minuteHandPaint = Paint()
      ..color = isDark ? Colors.white70 : Colors.black87
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final secondHandPaint = Paint()
      ..color = secondaryColor
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final hourLen = clockRadius * 0.5;
    final minuteLen = clockRadius * 0.7;
    final secondLen = clockRadius * 0.8;
    final hourOffset = Offset(
      hourLen * math.sin(clockHourAngle),
      -hourLen * math.cos(clockHourAngle),
    );
    final minuteOffset = Offset(
      minuteLen * math.sin(clockMinuteAngle),
      -minuteLen * math.cos(clockMinuteAngle),
    );
    final secondOffset = Offset(
      secondLen * math.sin(clockSecondAngle),
      -secondLen * math.cos(clockSecondAngle),
    );
    canvas.drawLine(clockCenter, clockCenter + hourOffset, hourHandPaint);
    canvas.drawLine(clockCenter, clockCenter + minuteOffset, minuteHandPaint);
    canvas.drawLine(clockCenter, clockCenter + secondOffset, secondHandPaint);
    canvas.drawCircle(clockCenter, 2.5, Paint()..color = secondaryColor);

    // 3. Ergonomic Study Chair backrest
    final chairPaint = Paint()
      ..color = isDark ? Colors.white12 : Colors.black12
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    final chairMeshPaint = Paint()
      ..color = primaryColor.withOpacity(0.15)
      ..style = PaintingStyle.fill;

    final backrestPath = Path()
      ..moveTo(135, 175)
      ..lineTo(132, 115)
      ..quadraticBezierTo(150, 105, 168, 115)
      ..lineTo(165, 175)
      ..close();
    canvas.drawPath(backrestPath, chairMeshPaint);
    canvas.drawPath(backrestPath, chairPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTRB(115, 172, 185, 180),
        const Radius.circular(4),
      ),
      Paint()..color = isDark ? const Color(0xFF2D2D3D) : Colors.grey.shade300,
    );

    // 4. Student sitting with Breathing and Nodding animations
    final dy = breathValue * 2.5;
    final headNod = math.sin(breathValue * math.pi * 2) * 0.04;

    final skinPaint = Paint()
      ..color = const Color(0xFFFFCC80)
      ..style = PaintingStyle.fill;
    final hairPaint = Paint()
      ..color = const Color(0xFF3E2723)
      ..style = PaintingStyle.fill;
    final shirtGradient = LinearGradient(
      colors: [primaryColor, primaryColor.withOpacity(0.7)],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );
    final shirtPaint = Paint()
      ..shader = shirtGradient.createShader(const Rect.fromLTRB(128, 125, 172, 175))
      ..style = PaintingStyle.fill;

    final torsoPath = Path()
      ..moveTo(132, 172)
      ..lineTo(130, 138 + dy)
      ..quadraticBezierTo(150, 134 + dy, 170, 138 + dy)
      ..lineTo(168, 172)
      ..close();
    canvas.drawPath(torsoPath, shirtPaint);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(146, 128 + dy, 154, 138 + dy),
        const Radius.circular(2),
      ),
      skinPaint,
    );

    canvas.save();
    canvas.translate(150, 114 + dy);
    canvas.rotate(headNod);

    canvas.drawCircle(Offset.zero, 13, skinPaint);

    final hairPath = Path()
      ..moveTo(-14, -4)
      ..quadraticBezierTo(-8, -15, 0, -14)
      ..quadraticBezierTo(8, -15, 14, -4)
      ..quadraticBezierTo(6, -8, 0, -7)
      ..quadraticBezierTo(-6, -8, -14, -4)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    final headphonesPaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawArc(
      const Rect.fromLTRB(-14, -14, 14, 14),
      math.pi,
      math.pi,
      false,
      headphonesPaint,
    );
    final cupPaint = Paint()..color = secondaryColor..style = PaintingStyle.fill;
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(-16, -5, -12, 7), const Radius.circular(2)), cupPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTRB(12, -5, 16, 7), const Radius.circular(2)), cupPaint);

    canvas.restore();

    final armPaint = Paint()
      ..color = primaryColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(130, 138 + dy), const Offset(136, 178), armPaint);
    canvas.drawLine(Offset(170, 138 + dy), const Offset(164, 178), armPaint);

    // Chair column & base
    final metalPaint = Paint()
      ..color = isDark ? Colors.white30 : Colors.black38
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(const Offset(150, 180), const Offset(150, 218), metalPaint);
    canvas.drawLine(const Offset(150, 218), Offset(125, height - 20), metalPaint);
    canvas.drawLine(const Offset(150, 218), Offset(175, height - 20), metalPaint);
    final wheelPaint = Paint()..color = isDark ? Colors.white54 : Colors.black54;
    canvas.drawCircle(Offset(125, height - 20), 3.5, wheelPaint);
    canvas.drawCircle(Offset(175, height - 20), 3.5, wheelPaint);

    // 5. Study Table
    canvas.drawLine(Offset(70, 184), Offset(70, height - 20), metalPaint);
    canvas.drawLine(Offset(230, 184), Offset(230, height - 20), metalPaint);
    canvas.drawLine(Offset(70, height - 40), Offset(230, height - 40), Paint()
      ..color = isDark ? Colors.white10 : Colors.black.withOpacity(0.05)
      ..strokeWidth = 2);

    final tableTopGradient = LinearGradient(
      colors: isDark
          ? [const Color(0xFF1E1E2F), const Color(0xFF2D2D3D)]
          : [Colors.purple.shade50, Colors.deepPurple.shade100],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
    final tableTopPaint = Paint()
      ..shader = tableTopGradient.createShader(const Rect.fromLTRB(50, 174, 250, 184))
      ..style = PaintingStyle.fill;
    final tableBorderPaint = Paint()
      ..color = isDark ? Colors.white12 : Colors.black.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final tableRRect = RRect.fromRectAndRadius(
      const Rect.fromLTRB(50, 174, 250, 184),
      const Radius.circular(3),
    );
    canvas.drawRRect(tableRRect, tableTopPaint);
    canvas.drawRRect(tableRRect, tableBorderPaint);

    // 6. Open Book
    const bookCenter = Offset(150, 174);
    final bookPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final bookLinePaint = Paint()
      ..color = isDark ? Colors.grey.shade400 : Colors.grey.shade600
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final leftPage = Path()
      ..moveTo(bookCenter.dx, bookCenter.dy)
      ..lineTo(bookCenter.dx - 16, bookCenter.dy - 3)
      ..lineTo(bookCenter.dx - 16, bookCenter.dy - 7)
      ..lineTo(bookCenter.dx, bookCenter.dy - 4)
      ..close();
    final rightPage = Path()
      ..moveTo(bookCenter.dx, bookCenter.dy)
      ..lineTo(bookCenter.dx + 16, bookCenter.dy - 3)
      ..lineTo(bookCenter.dx + 16, bookCenter.dy - 7)
      ..lineTo(bookCenter.dx, bookCenter.dy - 4)
      ..close();

    canvas.drawPath(leftPage, bookPaint);
    canvas.drawPath(leftPage, bookLinePaint);
    canvas.drawPath(rightPage, bookPaint);
    canvas.drawPath(rightPage, bookLinePaint);

    canvas.drawLine(
      const Offset(150, 170),
      const Offset(150, 179),
      Paint()..color = Colors.redAccent..strokeWidth = 1.5,
    );

    // 7. Desk Lamp
    const lampBaseOffset = Offset(78, 174);
    final lampPaint = Paint()
      ..color = isDark ? Colors.white54 : const Color(0xFF4A148C)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    canvas.drawArc(
      Rect.fromLTWH(lampBaseOffset.dx - 8, lampBaseOffset.dy - 4, 16, 8),
      math.pi,
      math.pi,
      true,
      Paint()..color = isDark ? Colors.white30 : const Color(0xFF4A148C),
    );

    final lampStemPath = Path()
      ..moveTo(lampBaseOffset.dx, lampBaseOffset.dy - 2)
      ..quadraticBezierTo(74, 135, 96, 120);
    canvas.drawPath(lampStemPath, lampPaint);

    const lampHeadCenter = Offset(96, 120);
    canvas.save();
    canvas.translate(lampHeadCenter.dx, lampHeadCenter.dy);
    canvas.rotate(0.65);

    final shadePaint = Paint()
      ..color = isDark ? Colors.white70 : const Color(0xFF00B8D4)
      ..style = PaintingStyle.fill;
    canvas.drawArc(
      const Rect.fromLTRB(-8, -8, 8, 8),
      math.pi,
      math.pi,
      true,
      shadePaint,
    );
    canvas.drawCircle(Offset.zero, 3.5, Paint()..color = Colors.amberAccent);
    canvas.restore();

    // 8. Pulsing light cone
    final lightConePath = Path()
      ..moveTo(lampHeadCenter.dx, lampHeadCenter.dy)
      ..lineTo(105, 174)
      ..lineTo(195, 174)
      ..close();

    final lightGradient = LinearGradient(
      colors: [
        secondaryColor.withOpacity(0.35 * lampGlow),
        secondaryColor.withOpacity(0.01),
      ],
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
    );

    final lightPaint = Paint()
      ..shader = lightGradient.createShader(const Rect.fromLTRB(96, 120, 150, 174))
      ..style = PaintingStyle.fill;

    if (isDark) {
      lightPaint.blendMode = BlendMode.plus;
    }
    canvas.drawPath(lightConePath, lightPaint);

    canvas.drawCircle(
      const Offset(150, 174),
      20,
      Paint()
        ..shader = RadialGradient(
          colors: [
            secondaryColor.withOpacity(0.20 * lampGlow),
            Colors.transparent,
          ],
        ).createShader(const Rect.fromLTRB(130, 154, 170, 194))
        ..style = PaintingStyle.fill,
    );
  }

  @override
  bool shouldRepaint(covariant _StudyRoomPainter oldDelegate) {
    return oldDelegate.clockHourAngle != clockHourAngle ||
        oldDelegate.clockMinuteAngle != clockMinuteAngle ||
        oldDelegate.clockSecondAngle != clockSecondAngle ||
        oldDelegate.breathValue != breathValue ||
        oldDelegate.lampGlow != lampGlow ||
        oldDelegate.isDark != isDark;
  }
}
