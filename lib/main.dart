import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:home_widget/home_widget.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_provider.dart';
import 'core/router/app_router.dart';
import 'core/services/firebase_service.dart';
import 'core/services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    HomeWidget.registerBackgroundCallback(backgroundCallback);
  }
  await FirebaseService.initialize();
  await _initStorage();
  runApp(const ProviderScope(child: PrePoraApp()));
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

class _AppLifecycleState extends State<_AppLifecycle> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService.initialize();
      NotificationService.checkAndNotify();
      if (kIsWeb && FirebaseService.currentUser != null) {
        NotificationService.startListeningForNotifications(FirebaseService.currentUser!.uid);
      }
    });
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
      child: MaterialApp.router(
        title: 'PrePora',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        routerConfig: AppRouter.router,
      ),
    );
  }
}
