import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import '../services/firebase_service.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/signup_screen.dart';
import '../../features/auth/presentation/forgot_password_screen.dart';
import '../../features/auth/presentation/reset_password_screen.dart';
import '../../features/auth/presentation/terms_accept_screen.dart';
import '../../features/splash_onboarding/presentation/splash_screen.dart';
import '../../features/link_web/presentation/link_web_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/notepad/presentation/notes_list_screen.dart';

// Deferred imports — heavy screens loaded on-demand to reduce initial bundle
import '../../features/dashboard/presentation/dashboard_screen.dart' deferred as dash_deferred;
import '../../features/folders/presentation/folder_details_screen.dart' deferred as folder_deferred;
import '../../features/ai_tutor/presentation/ai_chat_screen.dart' deferred as ai_deferred;
import '../../features/test_practice/presentation/test_practice_screen.dart' deferred as test_deferred;
import '../../features/lectures/presentation/video_player_screen.dart' deferred as video_deferred;
import '../../features/pdf_reader/presentation/pdf_reader_screen.dart' deferred as pdf_deferred;
import '../../features/admin/presentation/admin_dashboard_screen.dart' deferred as admin_dash_deferred;
import '../../features/admin/presentation/admin_control_panel_screen.dart' deferred as admin_panel_deferred;
import '../../features/assistant/presentation/assistant_dashboard_screen.dart' deferred as assist_dash_deferred;
import '../../features/universities/presentation/university_directory_screen.dart' deferred as uni_deferred;
import '../../features/notepad/presentation/notepad_screen.dart' deferred as notepad_deferred;
import '../../features/notices/presentation/admin_notice_screen.dart' deferred as admin_notice_deferred;
import '../../features/notices/presentation/student_notice_screen.dart' deferred as student_notice_deferred;
import '../../features/feedback/presentation/student_feedback_screen.dart' deferred as student_feedback_deferred;
import '../../features/feedback/presentation/admin_feedback_screen.dart' deferred as admin_feedback_deferred;
import '../../features/media_player/presentation/media_player_screen.dart' deferred as media_deferred;
import '../../features/image_viewer/presentation/image_viewer_screen.dart' deferred as image_deferred;
import '../../features/settings/presentation/admin_settings_screen.dart' deferred as admin_settings_deferred;
import '../../features/settings/presentation/storage_settings_screen.dart' deferred as storage_settings_deferred;
import '../../features/settings/presentation/ai_api_keys_screen.dart' deferred as ai_keys_deferred;
import '../../features/webview/presentation/webview_screen.dart' deferred as webview_deferred;
import '../../features/student/presentation/student_progress_screen.dart' deferred as student_progress_deferred;
import '../../features/admin/presentation/admin_fop_emails_screen.dart' deferred as admin_fop_deferred;
import '../../features/deep_link/presentation/short_link_resolver.dart' deferred as shortlink_deferred;

enum WebDomain { preporaWeb, adminPrepora, assistantPrepora, preporaWebFop, unknown }

/// Wraps a deferred-loaded widget with a loading placeholder while the library loads.
class _DeferredRoute extends StatefulWidget {
  final Future<void> Function() loadLibrary;
  final Widget Function() builder;
  const _DeferredRoute({required this.loadLibrary, required this.builder});
  @override
  State<_DeferredRoute> createState() => _DeferredRouteState();
}

class _DeferredRouteState extends State<_DeferredRoute> {
  bool _loaded = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      await widget.loadLibrary();
      if (mounted) setState(() => _loaded = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text('Failed to load page', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              ElevatedButton(onPressed: () => setState(() { _error = null; _load(); }), child: const Text('Retry')),
            ],
          ),
        ),
      );
    }
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return widget.builder();
  }
}

WebDomain _detectDomain() {
  if (!kIsWeb) return WebDomain.unknown;
  try {
    final host = Uri.base.host;
    if (host.contains('admin-prepora')) return WebDomain.adminPrepora;
    if (host.contains('assistant-prepora')) return WebDomain.assistantPrepora;
    if (host.contains('prepora-web-fop')) return WebDomain.preporaWebFop;
    if (host.contains('prepora-coral')) return WebDomain.preporaWeb;
    if (host.contains('prepora-web')) return WebDomain.preporaWeb;
  } catch (_) {}
  return WebDomain.unknown;
}

final WebDomain _currentDomain = _detectDomain();

class AuthGuard {
  static String? _cachedUserRole;

  static void setUserRole(String? role) => _cachedUserRole = role;

  static Future<String?> guard(BuildContext context, GoRouterState state) async {
    final path = state.matchedLocation;

    if (_currentDomain == WebDomain.preporaWeb) {
      if (path == '/link-web') return null;
      if (path.startsWith('/s/')) return null;
      if (path == '/auth/login' || path == '/auth/signup' || path == '/auth/forgot-password') return '/link-web';

      try {
        final user = fb_auth.FirebaseAuth.instance.currentUser;
        if (user == null) return '/link-web';
      } catch (_) {
        return '/link-web';
      }

      if (path == '/auth/reset-password') return null;
      return null;
    }

    if (_currentDomain == WebDomain.adminPrepora) {
      if (path == '/auth/login' || path == '/auth/forgot-password' || path == '/auth/reset-password') return null;

      try {
        final user = FirebaseService.currentUser;
        if (user == null) return '/auth/login';

        final role = _cachedUserRole ?? FirebaseService.cachedRole;
        if (role == null) return '/auth/login';
        if (role != 'admin') return '/auth/login';
      } catch (_) {
        return '/auth/login';
      }

      if (path == '/auth/signup') return '/admin';
      return null;
    }

    if (_currentDomain == WebDomain.assistantPrepora) {
      if (path == '/auth/login' || path == '/auth/forgot-password' || path == '/auth/reset-password') return null;

      try {
        final user = FirebaseService.currentUser;
        if (user == null) return '/auth/login';

        final role = _cachedUserRole ?? FirebaseService.cachedRole;
        if (role == null) return '/auth/login';
        if (role != 'Assistant') return '/auth/login';
      } catch (_) {
        return '/auth/login';
      }

      if (path == '/auth/signup') return '/assistant';
      return null;
    }

    if (_currentDomain == WebDomain.preporaWebFop) {
      if (path == '/auth/login' || path == '/auth/forgot-password' || path == '/auth/reset-password') return null;

      try {
        final user = FirebaseService.currentUser;
        if (user == null) return '/auth/login';

        final email = user.email?.toLowerCase() ?? '';
        var allowedEmails = FirebaseService.cachedFopEmails;
        // If cache is empty, load with timeout to avoid race condition on cold start
        if (allowedEmails.isEmpty) {
          try {
            allowedEmails = await FirebaseService.getFopAllowedEmails()
                .timeout(const Duration(seconds: 5));
          } catch (_) {}
        }
        // Only block if we have a loaded list AND email is not in it
        // If cache is still empty, allow access (user was verified at login)
        if (allowedEmails.isNotEmpty && !allowedEmails.contains(email)) {
          FirebaseService.signOut();
          return '/auth/login';
        }
      } catch (_) {
        return '/auth/login';
      }
      return null;
    }

    if (path == '/link-web' || path == '/splash' || path == '/auth/login' || path == '/auth/signup' || path == '/auth/forgot-password' || path == '/auth/reset-password' || path == '/terms' || path.startsWith('/s/')) return null;

    try {
      final user = FirebaseService.currentUser;
      if (user == null) return '/auth/login';

      final role = _cachedUserRole ?? FirebaseService.cachedRole;
      if (role == null) return null;
      if (path.startsWith('/admin') && role != 'admin') return '/auth/login';
      if (path == '/assistant' && role != 'Assistant') return '/auth/login';
    } catch (_) {
      return '/auth/login';
    }

    return null;
  }
}

class AppRouter {
  static String get _initialLocation {
    if (_currentDomain == WebDomain.adminPrepora) return '/auth/login';
    if (_currentDomain == WebDomain.assistantPrepora) return '/auth/login';
    if (_currentDomain == WebDomain.preporaWebFop) return '/auth/login';
    if (_currentDomain == WebDomain.preporaWeb) return '/link-web';
    return '/link-web';
  }

  static final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

  static final GoRouter router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: _initialLocation,
    redirect: AuthGuard.guard,
    routes: <RouteBase>[
      GoRoute(path: '/splash', builder: (c, s) => const SplashScreen()),
      GoRoute(path: '/link-web', builder: (c, s) => const LinkWebScreen()),
      GoRoute(path: '/auth/login', builder: (c, s) => const LoginScreen()),
      GoRoute(path: '/auth/signup', builder: (c, s) => const SignupScreen()),
      GoRoute(path: '/auth/forgot-password', builder: (c, s) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/auth/reset-password',
        builder: (c, s) {
          final token = s.uri.queryParameters['token'];
          return ResetPasswordScreen(token: token);
        },
      ),

      GoRoute(path: '/dashboard', builder: (c, s) => _DeferredRoute(
        loadLibrary: dash_deferred.loadLibrary,
        builder: () => dash_deferred.DashboardScreen(),
      )),
      GoRoute(
        path: '/folders/:id/sub/:contentId',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: folder_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return folder_deferred.FolderDetailsScreen(
              key: ValueKey('/folders/${s.pathParameters['id']!}/sub/${s.pathParameters['contentId']!}'),
              folderId: s.pathParameters['id']!,
              parentContentId: s.pathParameters['contentId']!,
              canEdit: extra?['canEdit'] as bool? ?? false,
              canManage: extra?['canManage'] as bool? ?? false,
              isAdmin: extra?['isAdmin'] as bool? ?? false,
              targetStudentUid: extra?['targetStudentUid'] as String?,
              assistantContentAccess: extra?['assistantContentAccess'] is List
                  ? (extra!['assistantContentAccess'] as List).cast<String>().toSet()
                  : null,
            );
          },
        ),
      ),
      GoRoute(
        path: '/folders/:id',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: folder_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return folder_deferred.FolderDetailsScreen(
              key: ValueKey('/folders/${s.pathParameters['id']!}'),
              folderId: s.pathParameters['id']!,
              canEdit: extra?['canEdit'] as bool? ?? false,
              canManage: extra?['canManage'] as bool? ?? false,
              isAdmin: extra?['isAdmin'] as bool? ?? false,
              targetStudentUid: extra?['targetStudentUid'] as String?,
              assistantContentAccess: extra?['assistantContentAccess'] is List
                  ? (extra!['assistantContentAccess'] as List).cast<String>().toSet()
                  : null,
              parentContentId: extra?['parentContentId'] as String?,
            );
          },
        ),
      ),
      GoRoute(path: '/ai_tutor', builder: (c, s) => _DeferredRoute(
        loadLibrary: ai_deferred.loadLibrary,
        builder: () {
          final extra = s.extra as Map<String, dynamic>?;
          return ai_deferred.AiChatScreen(folderContext: extra?['folderContext'] as String?);
        },
      )),
      GoRoute(
        path: '/notepad/:lectureId',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: notepad_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return notepad_deferred.NotepadScreen(
              lectureId: s.pathParameters['lectureId']!,
              lectureName: extra?['name'] as String? ?? 'Lecture',
            );
          },
        ),
      ),
      GoRoute(path: '/terms', builder: (c, s) => const TermsAcceptScreen()),
      GoRoute(path: '/notes', builder: (c, s) => const NotesListScreen()),
      GoRoute(path: '/admin/notices', builder: (c, s) => _DeferredRoute(
        loadLibrary: admin_notice_deferred.loadLibrary,
        builder: () => admin_notice_deferred.AdminNoticeScreen(),
      )),
      GoRoute(path: '/admin/feedbacks', builder: (c, s) => _DeferredRoute(
        loadLibrary: admin_feedback_deferred.loadLibrary,
        builder: () => admin_feedback_deferred.AdminFeedbackScreen(),
      )),
      GoRoute(path: '/admin/control-panel', builder: (c, s) => _DeferredRoute(
        loadLibrary: admin_panel_deferred.loadLibrary,
        builder: () => admin_panel_deferred.AdminControlPanelScreen(),
      )),
      GoRoute(path: '/student/notices', builder: (c, s) => _DeferredRoute(
        loadLibrary: student_notice_deferred.loadLibrary,
        builder: () => student_notice_deferred.StudentNoticeScreen(),
      )),
      GoRoute(path: '/student/feedbacks', builder: (c, s) => _DeferredRoute(
        loadLibrary: student_feedback_deferred.loadLibrary,
        builder: () => student_feedback_deferred.StudentFeedbackScreen(),
      )),
      GoRoute(path: '/student/progress', builder: (c, s) => _DeferredRoute(
        loadLibrary: student_progress_deferred.loadLibrary,
        builder: () => student_progress_deferred.StudentProgressScreen(),
      )),
      GoRoute(
        path: '/media_player',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: media_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return media_deferred.MediaPlayerScreen(
              url: extra?['url'] as String? ?? '',
              title: extra?['title'] as String? ?? 'Media',
              isAudio: extra?['isAudio'] as bool? ?? false,
            );
          },
        ),
      ),
      GoRoute(
        path: '/image_viewer',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: image_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return image_deferred.ImageViewerScreen(
              url: extra?['url'] as String? ?? '',
              title: extra?['title'] as String? ?? 'Image',
            );
          },
        ),
      ),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/admin/settings', builder: (c, s) => _DeferredRoute(
        loadLibrary: admin_settings_deferred.loadLibrary,
        builder: () => admin_settings_deferred.AdminSettingsScreen(),
      )),
      GoRoute(path: '/admin/storage-settings', builder: (c, s) => _DeferredRoute(
        loadLibrary: storage_settings_deferred.loadLibrary,
        builder: () => storage_settings_deferred.StorageSettingsScreen(),
      )),
      GoRoute(path: '/admin/ai-api-keys', builder: (c, s) => _DeferredRoute(
        loadLibrary: ai_keys_deferred.loadLibrary,
        builder: () => ai_keys_deferred.AiApiKeysScreen(),
      )),
      GoRoute(path: '/admin/fop-emails', builder: (c, s) => _DeferredRoute(
        loadLibrary: admin_fop_deferred.loadLibrary,
        builder: () => admin_fop_deferred.AdminFopEmailsScreen(),
      )),
      GoRoute(path: '/practice/:id', builder: (c, s) => _DeferredRoute(
        loadLibrary: test_deferred.loadLibrary,
        builder: () => test_deferred.TestPracticeScreen(testId: s.pathParameters['id']!),
      )),
      GoRoute(
        path: '/lectures/:id',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: video_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return video_deferred.VideoPlayerScreen(
              videoId: s.pathParameters['id']!,
              lectureName: extra?['name'] as String? ?? 'Lecture',
              subFolderName: extra?['folderName'] as String?,
              folderId: extra?['folderId'] as String?,
              parentContentId: extra?['parentContentId'] as String?,
            );
          },
        ),
      ),
      GoRoute(
        path: '/pdf_reader/view',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: pdf_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return pdf_deferred.PdfReaderScreen(
              documentId: extra?['url'] as String? ?? '',
              folderId: extra?['folderId'] as String?,
              parentContentId: extra?['parentContentId'] as String?,
              title: extra?['title'] as String?,
            );
          },
        ),
      ),
      GoRoute(path: '/admin', builder: (c, s) => _DeferredRoute(
        loadLibrary: admin_dash_deferred.loadLibrary,
        builder: () {
          final extra = s.extra as Map<String, dynamic>?;
          return admin_dash_deferred.AdminDashboardScreen(
            studentUid: extra?['studentUid'] as String?,
            studentName: extra?['studentName'] as String?,
          );
        },
      )),
      GoRoute(
        path: '/assistant',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: assist_dash_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return assist_dash_deferred.AssistantDashboardScreen(
              folderIds: extra?['folderIds'] as List<String>?,
              assistantName: extra?['assistantName'] as String?,
            );
          },
        ),
      ),
      GoRoute(path: '/universities', builder: (c, s) => _DeferredRoute(
        loadLibrary: uni_deferred.loadLibrary,
        builder: () => uni_deferred.UniversityDirectoryScreen(),
      )),
      GoRoute(
        path: '/webview',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: webview_deferred.loadLibrary,
          builder: () {
            final extra = s.extra as Map<String, dynamic>?;
            return webview_deferred.AppWebViewScreen(
              url: extra?['url'] as String?,
              html: extra?['html'] as String?,
              title: extra?['title'] as String? ?? 'Viewer',
              folderId: extra?['folderId'] as String?,
              parentContentId: extra?['parentContentId'] as String?,
              isMockTest: extra?['isMockTest'] as bool? ?? false,
            );
          },
        ),
      ),
      GoRoute(
        path: '/s/:shortId/:slug',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: shortlink_deferred.loadLibrary,
          builder: () => shortlink_deferred.ShortLinkResolver(
            shortId: s.pathParameters['shortId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: '/s/:shortId',
        builder: (c, s) => _DeferredRoute(
          loadLibrary: shortlink_deferred.loadLibrary,
          builder: () => shortlink_deferred.ShortLinkResolver(
            shortId: s.pathParameters['shortId'] ?? '',
          ),
        ),
      ),
    ],
  );
}
