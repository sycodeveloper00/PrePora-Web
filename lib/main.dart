import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'dart:html' as html;
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/firebase_service.dart';
import 'core/services/supabase_read_service.dart';
import 'core/services/storage_account_keep_alive.dart';
import 'core/services/notification_service.dart';
import 'core/services/offline_cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Init online checker for OfflineCacheService
  if (kIsWeb) {
    OfflineCacheService.initOnlineCheck(() => html.window.navigator.onLine ?? true);
  }
  if (!kIsWeb) {
    HomeWidget.registerBackgroundCallback(backgroundCallback);
  }
  // Init SharedPreferences FIRST (needed by FirebaseService cache)
  await _initStorage();
  try {
    await FirebaseService.initialize().timeout(const Duration(seconds: 8));
  } catch (_) {}
  SupabaseReadService.onFailover = (projectName, role, error) async {
    try {
      final lastNotifTime = html.window.localStorage['last_failover_notif'];
      if (lastNotifTime != null) {
        final last = DateTime.tryParse(lastNotifTime);
        if (last != null && DateTime.now().difference(last).inMinutes < 30) return;
      }
      html.window.localStorage['last_failover_notif'] = DateTime.now().toIso8601String();
      await FirebaseService.addAdminNotification(
        'supabase_failover',
        '$role project "$projectName" failed: $error',
      );
    } catch (_) {}
  };
  // Pre-load FOP allowed emails for router guard (async → cached)
  if (kIsWeb) {
    FirebaseService.getFopAllowedEmails();
  }
  runApp(const ProviderScope(child: PrePoraApp()));
  SupabaseReadService.startKeepAlive();
  StorageAccountKeepAliveService.start();
}

@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  WidgetsFlutterBinding.ensureInitialized();
  await FirebaseService.initialize();
  await _initStorage();
}

Future<void> _initStorage() async {
  if (kIsWeb) {
    await SharedPreferences.getInstance();
  } else {
    await Hive.initFlutter();
    await Hive.openBox('settings');
  }
}

class _AppLifecycle extends StatefulWidget {
  final Widget child;
  const _AppLifecycle({required this.child});
  @override
  State<_AppLifecycle> createState() => _AppLifecycleState();
}

class _AppLifecycleState extends State<_AppLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.initialize();
      NotificationService.checkAndNotify();
      if (kIsWeb && FirebaseService.currentUser != null) {
        NotificationService.startListeningForNotifications(FirebaseService.currentUser!.uid);
        _autoExpireTrial();
      }
    _startSessionIfAdminOrAssistant();
    _startWebActivityListeners();
    FirebaseService.startTokenWatchdog(onSessionExpired: () {
        SessionManager.stop();
        AppRouter.router.go('/auth/login');
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      SessionManager.pause();
    } else if (state == AppLifecycleState.resumed) {
      SessionManager.resume();
    }
  }

  void _startWebActivityListeners() {
    if (!kIsWeb) return;
    html.window.addEventListener('wheel', (_) => SessionManager.reset());
    html.window.addEventListener('scroll', (_) => SessionManager.reset());
    html.window.addEventListener('touchstart', (_) => SessionManager.reset());
    html.document.addEventListener('visibilitychange', (_) {
      if (html.document.visibilityState == 'visible') {
        SessionManager.resume();
      } else {
        SessionManager.pause();
      }
    });
  }

  void _startSessionIfAdminOrAssistant() async {
    final user = FirebaseService.currentUser;
    if (user == null) return;
    String? role = FirebaseService.cachedRole;
    role ??= await FirebaseService.getUserRole(user.uid);
    FirebaseService.cachedRole = role;
    final host = Uri.base.host;
    final isFopDomain = host.contains('prepora-web-fop');
    final isQrDomain = host.contains('prepora-web') && !isFopDomain;
    final isAdmin = role == 'admin' || role == 'Assistant';
    SessionManager.configure(
      timeout: isAdmin
          ? (isQrDomain ? const Duration(hours: 1) : const Duration(minutes: 20))
          : const Duration(hours: 1),
      redirectPath: isQrDomain ? '/link-web' : '/auth/login',
    );
    SessionManager.start(onExpiredCallback: () async {
      html.window.localStorage['session_expired_by_inactivity'] = 'true';
      final uid = FirebaseService.currentUser?.uid;
      if (uid != null) {
        try {
          await FirebaseService.addTargetedNotification(uid, 'Web app disconnected due to no activity found');
        } catch (_) {}
      }
      AppRouter.router.go(SessionManager.redirectPath);
      await Future.delayed(const Duration(milliseconds: 500));
      await FirebaseService.signOut();
    });
  }

  void _autoExpireTrial() async {
    try {
      final uid = FirebaseService.currentUser?.uid;
      if (uid == null) return;
      final user = await SupabaseReadService.getUser(uid);
      if (user == null) return;
      final trialActive = user['freeTrialActive'] == true;
      final endsAt = user['freeTrialEndsAt'];
      final trialEnd = endsAt is String ? DateTime.tryParse(endsAt) : null;
      final trialExpired = trialActive && trialEnd != null && trialEnd.isBefore(DateTime.now());
      if (!trialExpired) return;
      final settings = await SupabaseReadService.getSettings('general');
      final paidAccess = settings?['paidAccess'] as bool? ?? false;
      if (!paidAccess) {
        await FirebaseService.updateSetting('paidAccess', true);
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class PrePoraApp extends ConsumerWidget {
  const PrePoraApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return _AppLifecycle(
      child: Listener(
        onPointerDown: (_) => SessionManager.reset(),
        onPointerMove: (_) => SessionManager.reset(),
        child: Focus(
          autofocus: true,
          onKey: (node, event) {
            SessionManager.reset();
            return KeyEventResult.ignored;
          },
          child: MaterialApp.router(
            title: 'PrePora',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: themeMode,
            routerConfig: AppRouter.router,
          ),
        ),
      ),
    );
  }
}
