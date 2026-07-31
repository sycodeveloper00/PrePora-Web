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
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/folders/presentation/folder_details_screen.dart';
import '../../features/ai_tutor/presentation/ai_chat_screen.dart';
import '../../features/test_practice/presentation/test_practice_screen.dart';
import '../../features/lectures/presentation/video_player_screen.dart';
import '../../features/pdf_reader/presentation/pdf_reader_screen.dart';
import '../../features/admin/presentation/admin_dashboard_screen.dart';
import '../../features/admin/presentation/admin_control_panel_screen.dart';
import '../../features/assistant/presentation/assistant_dashboard_screen.dart';
import '../../features/universities/presentation/university_directory_screen.dart';
import '../../features/notepad/presentation/notepad_screen.dart';
import '../../features/notepad/presentation/notes_list_screen.dart';
import '../../features/notices/presentation/admin_notice_screen.dart';
import '../../features/notices/presentation/student_notice_screen.dart';
import '../../features/feedback/presentation/student_feedback_screen.dart';
import '../../features/feedback/presentation/admin_feedback_screen.dart';
import '../../features/media_player/presentation/media_player_screen.dart';
import '../../features/image_viewer/presentation/image_viewer_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/settings/presentation/admin_settings_screen.dart';
import '../../features/webview/presentation/webview_screen.dart';
import '../../features/splash_onboarding/presentation/splash_screen.dart';
import '../../features/notifications/presentation/admin_notifications_screen.dart';
import '../../features/student/presentation/student_progress_screen.dart';
import '../../features/link_web/presentation/link_web_screen.dart';

enum WebDomain { preporaWeb, adminPrepora, assistantPrepora, unknown }

WebDomain _detectDomain() {
  if (!kIsWeb) return WebDomain.unknown;
  try {
    final host = Uri.base.host;
    if (host.contains('admin-prepora')) return WebDomain.adminPrepora;
    if (host.contains('assistant-prepora')) return WebDomain.assistantPrepora;
    if (host.contains('prepora-web')) return WebDomain.preporaWeb;
  } catch (_) {}
  return WebDomain.unknown;
}

final WebDomain _currentDomain = _detectDomain();

class AuthGuard {
  static String? _cachedUserRole;

  static void setUserRole(String? role) => _cachedUserRole = role;

  static String? guard(BuildContext context, GoRouterState state) {
    final path = state.matchedLocation;

    if (_currentDomain == WebDomain.preporaWeb) {
      if (path == '/link-web') return null;
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

    if (path == '/link-web' || path == '/splash' || path == '/auth/login' || path == '/auth/signup' || path == '/auth/forgot-password' || path == '/auth/reset-password' || path == '/terms') return null;

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
    if (_currentDomain == WebDomain.preporaWeb) return '/link-web';
    return '/link-web';
  }

  static final GoRouter router = GoRouter(
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

      GoRoute(path: '/dashboard', builder: (c, s) => const DashboardScreen()),
      GoRoute(
        path: '/folders/:id/sub/:contentId',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return FolderDetailsScreen(
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
      GoRoute(
        path: '/folders/:id',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return FolderDetailsScreen(
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
      GoRoute(path: '/ai_tutor', builder: (c, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return AiChatScreen(folderContext: extra?['folderContext'] as String?);
      }),
      GoRoute(
        path: '/notepad/:lectureId',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return NotepadScreen(
            lectureId: s.pathParameters['lectureId']!,
            lectureName: extra?['name'] as String? ?? 'Lecture',
          );
        },
      ),
      GoRoute(path: '/terms', builder: (c, s) => const TermsAcceptScreen()),
      GoRoute(path: '/notes', builder: (c, s) => const NotesListScreen()),
      GoRoute(path: '/admin/notices', builder: (c, s) => const AdminNoticeScreen()),
      GoRoute(path: '/admin/feedbacks', builder: (c, s) => const AdminFeedbackScreen()),
      GoRoute(path: '/admin/control-panel', builder: (c, s) => const AdminControlPanelScreen()),
      GoRoute(path: '/student/notices', builder: (c, s) => const StudentNoticeScreen()),
      GoRoute(path: '/student/feedbacks', builder: (c, s) => const StudentFeedbackScreen()),
      GoRoute(path: '/student/progress', builder: (c, s) => const StudentProgressScreen()),
      GoRoute(
        path: '/media_player',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return MediaPlayerScreen(
            url: extra?['url'] as String? ?? '',
            title: extra?['title'] as String? ?? 'Media',
            isAudio: extra?['isAudio'] as bool? ?? false,
          );
        },
      ),
      GoRoute(
        path: '/image_viewer',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return ImageViewerScreen(
            url: extra?['url'] as String? ?? '',
            title: extra?['title'] as String? ?? 'Image',
          );
        },
      ),
      GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      GoRoute(path: '/admin/settings', builder: (c, s) => const AdminSettingsScreen()),
      GoRoute(path: '/practice/:id', builder: (c, s) => TestPracticeScreen(testId: s.pathParameters['id']!)),
      GoRoute(
        path: '/lectures/:id',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return VideoPlayerScreen(
            videoId: s.pathParameters['id']!,
            lectureName: extra?['folderName'] as String? ?? extra?['name'] as String? ?? 'Lecture',
            folderId: extra?['folderId'] as String?,
            parentContentId: extra?['parentContentId'] as String?,
          );
        },
      ),
      GoRoute(
        path: '/pdf_reader/view',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return PdfReaderScreen(
            documentId: extra?['url'] as String? ?? '',
            folderId: extra?['folderId'] as String?,
            parentContentId: extra?['parentContentId'] as String?,
          );
        },
      ),
      GoRoute(path: '/admin', builder: (c, s) {
        final extra = s.extra as Map<String, dynamic>?;
        return AdminDashboardScreen(
          studentUid: extra?['studentUid'] as String?,
          studentName: extra?['studentName'] as String?,
        );
      }),
      GoRoute(
        path: '/assistant',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AssistantDashboardScreen(
            folderIds: extra?['folderIds'] as List<String>?,
            assistantName: extra?['assistantName'] as String?,
          );
        },
      ),
      GoRoute(path: '/universities', builder: (c, s) => const UniversityDirectoryScreen()),
      GoRoute(
        path: '/webview',
        builder: (c, s) {
          final extra = s.extra as Map<String, dynamic>?;
          return AppWebViewScreen(
            url: extra?['url'] as String?,
            html: extra?['html'] as String?,
            title: extra?['title'] as String? ?? 'Viewer',
            folderId: extra?['folderId'] as String?,
            parentContentId: extra?['parentContentId'] as String?,
            isMockTest: extra?['isMockTest'] as bool? ?? false,
          );
        },
      ),
    ],
  );
}
