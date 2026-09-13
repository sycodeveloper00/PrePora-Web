import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart' as fb_storage;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'supabase_read_service.dart';
import 'clorabase_service.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../firebase_options.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  FirebaseService._();

  static bool _initialized = false;
  static String? _cachedDeviceId;
  static String? cachedRole;
  static Timer? _tokenWatchdog;
  static StreamSubscription<fb_auth.User?>? _authStateSub;
  static bool _tokenWatchdogStarted = false;

  static String supabaseUrl = '';
  static String serviceRoleKey = '';
  static String _supabaseAnonKey = '';

  static String cleanTitle(String name) {
    var cleaned = name.replaceFirst(RegExp(r'^\d+_'), '');
    cleaned = cleaned.replaceFirst(RegExp(r'^\d{10,13}_'), '');
    cleaned = cleaned.trim();
    if (cleaned.isEmpty) cleaned = name;
    return cleaned;
  }

  /// Downloads a file from Supabase Storage using the REST API with service role auth.
  /// [bucketPath] format: "bucket_name/path/to/file"
  static Future<Uint8List> downloadSupabaseFile(String bucketPath) async {
    if (kIsWeb) {
      final proxyUrl = '/api/download-file?url=${Uri.encodeComponent('$supabaseUrl/storage/v1/object/$bucketPath')}';
      final response = await http.get(Uri.parse(proxyUrl), headers: {
        'Authorization': 'Bearer $serviceRoleKey',
      }).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw Exception('Supabase download failed ($bucketPath): ${response.statusCode}');
      }
      return response.bodyBytes;
    }
    final uri = Uri.parse('$supabaseUrl/storage/v1/object/$bucketPath');
    final response = await http.get(
      uri,
      headers: {'Authorization': 'Bearer $serviceRoleKey'},
    ).timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw Exception('Supabase download failed ($bucketPath): ${response.statusCode}');
    }
    return response.bodyBytes;
  }

  static fb_auth.User? get currentUser => fb_auth.FirebaseAuth.instance.currentUser;

  static SupabaseClient get supabase => Supabase.instance.client;

  static Future<String> getDeviceId() async {
    if (_cachedDeviceId != null) return _cachedDeviceId!;
    final prefs = await SharedPreferences.getInstance();
    const key = 'device_uuid';
    String? id = prefs.getString(key);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(key, id);
    }
    _cachedDeviceId = id;
    return id;
  }

  static FirebaseService get instance => _instance;

  static Future<void> initialize() async {
    if (_initialized) return;
    // Fast path: load cached Supabase credentials from SharedPreferences (instant)
    await _loadCachedSupabaseAccountAsync();
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform).timeout(const Duration(seconds: 5));
    } catch (_) {}
    // Background: refresh active account from Supabase (non-blocking if cache exists)
    if (supabaseUrl.isEmpty) {
      try {
        await _loadActiveSupabaseAccount().timeout(const Duration(seconds: 3));
        _saveCachedSupabaseAccount();
      } catch (_) {}
    } else {
      // Already cached — refresh in background (don't block startup)
      _loadActiveSupabaseAccount().then((_) => _saveCachedSupabaseAccount()).catchError((_) {});
    }
    if (supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
      try {
        await Supabase.initialize(url: supabaseUrl, anonKey: _supabaseAnonKey).timeout(const Duration(seconds: 3));
      } catch (_) {}
    }
    _initialized = true;
  }

  static Future<void> _loadCachedSupabaseAccountAsync() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final url = prefs.getString('cached_supabase_url') ?? '';
      final key = prefs.getString('cached_supabase_service_key') ?? '';
      final anon = prefs.getString('cached_supabase_anon_key') ?? '';
      if (url.isNotEmpty && key.isNotEmpty && anon.isNotEmpty) {
        supabaseUrl = url;
        serviceRoleKey = key;
        _supabaseAnonKey = anon;
      }
    } catch (_) {}
  }

  static Future<void> _saveCachedSupabaseAccount() async {
    try {
      if (supabaseUrl.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_supabase_url', supabaseUrl);
      await prefs.setString('cached_supabase_service_key', serviceRoleKey);
      await prefs.setString('cached_supabase_anon_key', _supabaseAnonKey);
    } catch (_) {}
  }

  /// Keeps the Firebase ID token fresh so long-lived Firestore streams don't
  /// silently fail when the token expires (~1h). Also redirects to login the
  /// moment the auth session dies anywhere in the app.
  static void startTokenWatchdog({VoidCallback? onSessionExpired}) {
    if (_tokenWatchdogStarted) return;
    _tokenWatchdogStarted = true;
    _authStateSub = fb_auth.FirebaseAuth.instance.idTokenChanges().listen((user) {
      if (user == null) {
        if (onSessionExpired != null) onSessionExpired();
      }
    });
    _tokenWatchdog = Timer.periodic(const Duration(minutes: 10), (_) async {
      try {
        final user = fb_auth.FirebaseAuth.instance.currentUser;
        if (user != null) await user.getIdToken(true);
      } catch (_) {}
    });
  }

  static void stopTokenWatchdog() {
    _tokenWatchdog?.cancel();
    _tokenWatchdog = null;
    _authStateSub?.cancel();
    _authStateSub = null;
    _tokenWatchdogStarted = false;
  }

  static Future<void> _loadActiveSupabaseAccount() async {
    try {
      final mirror = await SupabaseReadService.getActiveSupabaseAccount();
      if (mirror != null && (mirror['serviceRoleKey'] as String? ?? '').isNotEmpty) {
        supabaseUrl = mirror['projectUrl'] as String? ?? '';
        serviceRoleKey = mirror['serviceRoleKey'] as String? ?? '';
        _supabaseAnonKey = mirror['anonKey'] as String? ?? '';
      }
    } catch (_) {}
  }

  /// Loads the active Supabase account assigned to a specific assistant so that
  /// assistants use their OWN storage buckets instead of the global one.
  /// Returns true when an assistant-specific account was found and applied.
  static Future<bool> _loadActiveAssistantSupabaseAccount(String assistantUid) async {
    try {
      final mirror = await SupabaseReadService.getActiveAssistantSupabaseAccount(assistantUid);
      if (mirror != null && (mirror['serviceRoleKey'] as String? ?? '').isNotEmpty) {
        supabaseUrl = mirror['projectUrl'] as String? ?? '';
        serviceRoleKey = mirror['serviceRoleKey'] as String? ?? '';
        _supabaseAnonKey = mirror['anonKey'] as String? ?? '';
        return true;
      }
    } catch (_) {}
    return false;
  }

  /// Selects the correct Supabase account at runtime for the signed-in user:
  /// assistants use their own active `assistant_supabase` account (falling back
  /// to the global one), everyone else uses the global `supabase_accounts`.
  static Future<void> selectStorageAccountForUser(String uid) async {
    try {
      Map<String, dynamic>? userData;
      try { userData = await SupabaseReadService.getUser(uid); } catch (_) {}
      final role = userData?['role'] as String? ?? '';
      if (role == 'Assistant' || role == 'assistant') {
        final ok = await _loadActiveAssistantSupabaseAccount(uid);
        if (ok) {
          await reinitializeSupabase();
          return;
        }
      }
      await _loadActiveSupabaseAccount();
      await reinitializeSupabase();
    } catch (_) {
      await _loadActiveSupabaseAccount();
      await reinitializeSupabase();
    }
  }

  static Future<void> reinitializeSupabase() async {
    await _loadActiveSupabaseAccount();
    _saveCachedSupabaseAccount();
    if (supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
      try {
        await Supabase.initialize(url: supabaseUrl, anonKey: _supabaseAnonKey);
      } catch (e) {
        print('[reinitializeSupabase] Failed: $e');
      }
    }
  }

  // ─── Auth ──────────────────────────────────────────────────────────────────────

  static Future<fb_auth.UserCredential?> signIn(String email, String password) async {
    try {
      final cred = await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (cred.user != null) {
        Map<String, dynamic>? userData;
        try {
          userData = await SupabaseReadService.getUser(cred.user!.uid);
        } catch (_) {}
        final userRole = userData?['role'] as String?;
        if (userData?['blocked'] == true) {
          if (userRole == 'admin' || userRole == 'Assistant') {
            await _mirrorWrite('users', cred.user!.uid, {'blocked': false});
          } else {
            await fb_auth.FirebaseAuth.instance.signOut();
            throw Exception('BLOCKED');
          }
        }
        await storeSession(cred.user!.uid);
        final deviceId = await getDeviceId();
        await _trackLogin(cred.user!.uid, deviceId);
        await updateStreak(cred.user!.uid);
        final label = userRole == 'admin' ? 'Admin' : (userRole == 'Assistant' ? 'Assistant' : 'Student');
        await addAdminNotification('login', '$label logged in: ${cred.user!.email}', relatedUid: cred.user!.uid);
      }
      return cred;
    } on fb_auth.FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Sign in failed');
    }
  }

  static Future<fb_auth.UserCredential?> signUp(
    String name,
    String email,
    String password, {
    String role = 'student',
    String gender = '',
  }) async {
    try {
      final cred = await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      final uid = cred.user!.uid;
      await storeSession(uid);
      await _mirrorWrite('users', uid, {
        'uid': uid,
        'name': name,
        'email': email.trim(),
        'password': password,
        'role': role,
        'gender': gender,
        'blocked': false,
        'verified': role == 'admin',
        'createdAt': DateTime.now().toIso8601String(),
        'termsAccepted': false,
      });
      await addAdminNotification('registration', 'New student registered: $name ($email)', relatedUid: uid);
      return cred;
    } on fb_auth.FirebaseAuthException catch (e) {
      throw Exception(e.message ?? 'Sign up failed');
    }
  }

  static Future<void> signOut() async {
    final user = fb_auth.FirebaseAuth.instance.currentUser;
    if (user != null) {
      Map<String, dynamic>? userData;
      try { userData = await SupabaseReadService.getUser(user.uid); } catch (_) {}
      final role = userData?['role'] as String?;
      final label = role == 'admin' ? 'Admin' : (role == 'Assistant' ? 'Assistant' : 'Student');
      await addAdminNotification('logout', '$label logged out: ${user.email}', relatedUid: user.uid);
    }
    await fb_auth.FirebaseAuth.instance.signOut();
    cachedRole = null;
    SessionManager.stop();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('uid');
  }

  static Future<void> storeSession(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uid', uid);
  }

  static Future<bool> verifySession(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('uid') == uid;
  }

  static Future<void> sendPasswordReset(String email) async {
    await fb_auth.FirebaseAuth.instance.sendPasswordResetEmail(email: email.trim());
  }

  // ─── User Data ─────────────────────────────────────────────────────────────────

  static Future<String?> getUserRole(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror['role'] as String?;
    } catch (_) {}
    return null;
  }

  static Future<String?> getCachedUserRole(String uid) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role_$uid');
  }

  static Future<void> cacheUserRole(String uid, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('role_$uid', role);
  }

  static Future<DocumentSnapshot?> getUser(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return _MirrorDocumentSnapshot(mirror);
    } catch (_) {}
    return null;
  }

  static Future<String> getUserDisplayName(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror['name'] as String? ?? 'User';
    } catch (_) {}
    return 'User';
  }

  static Future<bool> isStudentBlocked(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror['blocked'] == true;
    } catch (_) {}
    return false;
  }

  static Future<bool> isStudentVerified(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror['verified'] == true;
    } catch (_) {}
    return false;
  }

  static Future<void> toggleStudentBlocked(String uid, bool blocked) async {
    await _mirrorWrite('users', uid, {'blocked': blocked});
    if (blocked) {
      Map<String, dynamic>? userData;
      try { userData = await SupabaseReadService.getUser(uid); } catch (_) {}
      final email = userData?['email'] as String? ?? uid;
      await addAdminNotification('blocked', 'Student account blocked: $email', relatedUid: uid);
    }
    await addTargetedNotification(uid, blocked
        ? 'Your account has been blocked by the administrator. Contact support for help.'
        : 'Your account has been unblocked. You can now access all features.');
  }

  static Future<void> toggleStudentVerified(String uid, bool verified, {double? paidAmount}) async {
    final data = <String, dynamic>{'verified': verified};
    if (paidAmount != null && paidAmount > 0) data['paidAmount'] = paidAmount;
    await _mirrorWrite('users', uid, data);
    await addTargetedNotification(uid, verified
        ? 'Your account has been verified! You now have full access to all content.'
        : 'Your account verification has been removed. Contact support for details.');
    if (verified) {
      _removeTrialNotificationsForUser(uid);
    }
  }

  static void _removeTrialNotificationsForUser(String uid) async {
    try {
      final notifs = await SupabaseReadService.getTargetedNotifications(uid);
      if (notifs == null || notifs.isEmpty) return;
      for (final n in notifs) {
        final msg = n['message'] as String? ?? '';
        if (msg.contains('free trial') || msg.contains('Free trial') || msg.contains('trial expires')) {
          final id = n['id'] as String?;
          if (id != null) await SupabaseReadService.writeToAll('notifications', id, {}, delete: true);
        }
      }
    } catch (_) {}
  }

  /// Returns the free-trial state for a student: `{active, endsAt}` where
  /// `endsAt` is a DateTime? or null when no trial has ever been started.
  static Future<Map<String, dynamic>> getFreeTrial(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) {
        final active = mirror['freeTrialActive'] == true;
        final endsAt = mirror['freeTrialEndsAt'];
        final endDate = endsAt is String ? DateTime.tryParse(endsAt)?.toLocal() : (endsAt is DateTime ? endsAt.toLocal() : null);
        return {'active': active, 'endsAt': endDate};
      }
    } catch (_) {}
    return {'active': false, 'endsAt': null};
  }

  /// Returns the trial end time currently applied to unverified students (the
  /// most recent `freeTrialEndsAt` among active trials), or null when no
  /// student is on an active free trial. Used by the admin countdown tile.
  static Future<DateTime?> getActiveTrialEndTime() async {
    try {
      List<Map<String, dynamic>>? students;
      try {
        students = await SupabaseReadService.getUsersWhere('role=eq.student&free_trial_active=eq.true');
      } catch (_) {}
      DateTime? latest;
      if (students != null && students.isNotEmpty) {
        for (final data in students) {
          if (data['verified'] == true) continue;
          final endsAt = data['free_trial_ends_at'] ?? data['freeTrialEndsAt'];
          final d = endsAt is DateTime ? endsAt : (endsAt is String ? DateTime.tryParse(endsAt) : null);
          final local = d?.toLocal();
          if (local != null && (latest == null || local.isAfter(latest))) latest = local;
        }
        return latest;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Starts a free trial for every UNVERIFIED student ending at the given
  /// [end] date/time (preserves minutes — no truncation).
  /// Returns the number of students the trial was applied to.
  static Future<int> startFreeTrialForAll({required DateTime end}) async {
    final isoEnd = end.toUtc().toIso8601String();
    List<Map<String, dynamic>>? students;
    try { students = await SupabaseReadService.getUsersByRole('student'); } catch (_) {}
    final mirrorWrites = <Future>[];
    int count = 0;
    if (students != null && students.isNotEmpty) {
      for (final data in students) {
        if (data['verified'] == true) continue;
        final id = data['id'] as String? ?? '';
        if (id.isEmpty) continue;
        mirrorWrites.add(_mirrorWrite('users', id, {
          ...data,
          'freeTrialActive': true,
          'freeTrialEndsAt': isoEnd,
          'free_trial_active': true,
          'free_trial_ends_at': isoEnd,
        }));
        count++;
      }
    }
    if (count > 0) {
      try { await Future.wait(mirrorWrites); } catch (_) {}
    }
    return count;
  }

  /// Server-side check: if this student's free trial has expired, flips the
  /// global `settings/general.paidAccess` to true (same as the manual admin
  /// toggle) and clears the student's own trial flag. Runs server-side via the
  /// free-tier Vercel `/api` endpoint (no paid Cloud Functions required).
  static Future<bool> expireFreeTrial(String uid) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return false;
      final res = await http.post(
        Uri.parse('https://prepora-web.vercel.app/api/expire-trial'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken}),
      );
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['flipped'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllStudents() async {
    try {
      final mirror = await SupabaseReadService.getUsersByRole('student');
      if (mirror != null) return mirror;
    } catch (_) {}
    return [];
  }

  /// Admin-only: changes a student/assistant password via the free-tier Vercel
  /// `/api` endpoint (server verifies the caller is an admin).
  static Future<bool> updateUserPassword(String uid, String newPassword) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return false;
      final res = await http.post(
        Uri.parse('https://prepora-web.vercel.app/api/update-password'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken, 'uid': uid, 'newPassword': newPassword}),
      );
      if (res.statusCode != 200) return false;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Returns the stored plaintext password for a user (set at account creation).
  /// Used by admins to show the current password in the change-password dialog.
  static Future<String> getUserStoredPassword(String uid) async {
    try {
      final data = await SupabaseReadService.getUser(uid);
      if (data == null) return '';
      return (data['password'] as String?) ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Notification settings stored in Firestore so admins can tweak titles/bodies
  /// and enable/disable notifications WITHOUT changing app code.
  /// Doc: settings/notification_config
  static Future<Map<String, dynamic>> getNotificationConfig() async {
    const defaults = <String, dynamic>{
      'streakEnabled': true,
      'streakTitle': 'Time to study!',
      'streakBody': 'Your learning journey is waiting. Open PrePora and continue where you left off.',
      'webReminderEnabled': true,
      'web24Title': 'Daily Streak',
      'web24Body': 'You missed a day! Open PrePora to keep your streak alive.',
      'web72Title': 'Long time no see!',
      'web72Body': "We miss you! Come back to continue your study streak.",
    };
    try {
      final mirror = await SupabaseReadService.getSettings('notification_config');
      if (mirror != null) return {...defaults, ...mirror};
    } catch (_) {}
    return defaults;
  }

  static Stream<QuerySnapshot> getAllAssistant() {
    return SupabaseReadService.streamUsersByRole('Assistant').map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<void> deleteAssistantAccount(String uid) async {
    await _mirrorWrite('users', uid, const {}, delete: true);
  }

  static Future<void> deleteUserFromAuth(String uid) async {
    try {
      final idToken = await fb_auth.FirebaseAuth.instance.currentUser?.getIdToken();
      if (idToken == null) return;
      await http.post(
        Uri.parse('https://prepora-web.vercel.app/api/delete-user'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'idToken': idToken, 'uid': uid}),
      );
    } catch (_) {}
  }

  static Future<void> deleteStudentCompletely(String uid) async {
    await deleteUserFromAuth(uid);
  }

  static Future<Map<String, String>?> createAssistantAccount(String name) async {
    final sanitizedName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').replaceAll(RegExp(r'\s+'), '');
    final emailPrefix = sanitizedName.isNotEmpty ? sanitizedName : 'assistant';
    final displayEmail = '$emailPrefix@assistant.prepora';
    final passwordName = name.replaceAll(RegExp(r'\s+'), '');
    final password = '${passwordName[0].toUpperCase()}${passwordName.substring(1).toLowerCase()}123';
    try {
      final cred = await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: displayEmail,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      final uid = cred.user!.uid;
      await _mirrorWrite('users', uid, {
        'uid': uid,
        'name': name,
        'email': displayEmail,
        'password': password,
        'role': 'Assistant',
        'createdAt': DateTime.now().toIso8601String(),
      });
      final accessId = 'aa_${DateTime.now().millisecondsSinceEpoch}';
      await _mirrorWrite('assistant_access', accessId, {
        'uid': uid,
        'name': name,
        'createdAt': DateTime.now().toIso8601String(),
      });
      return {'email': displayEmail, 'password': password, 'name': name};
    } catch (e) {
      throw Exception('Failed to create Assistant account: ${e.toString()}');
    }
  }

  // ─── Supabase Storage Helpers ──────────────────────────────────────────────────

  static Future<String> uploadFileToSupabase(String bucket, String path, dynamic file) async {
    if (kIsWeb) {
      throw UnsupportedError('File upload not supported on web via this method');
    }
    await supabase.storage.from(bucket).upload(path, file as File);
    final url = supabase.storage.from(bucket).getPublicUrl(path);
    return url;
  }

  static Future<String> uploadBytesToSupabase(String bucket, String path, Uint8List bytes) async {
    await supabase.storage.from(bucket).uploadBinary(path, bytes);
    final url = supabase.storage.from(bucket).getPublicUrl(path);
    return url;
  }

  static Future<void> deleteFromSupabase(String bucket, String path) async {
    await supabase.storage.from(bucket).remove([path]);
  }

  // ─── FAKE Supabase Storage compat for notices ─────────────────────────────────
  static _SupabaseStorageService get storage => _SupabaseStorageService();

  // ─── Storage Provider Setting ──────────────────────────────────────────────────
  static const String _storageProviderKey = 'storage_provider';
  static String _cachedStorageProvider = 'supabase';

  static Future<String> getStorageProvider() async {
    // SharedPreferences is the ABSOLUTE source of truth.
    // No background sync from Supabase — Supabase may have stale data from
    // another session or partially-failed writes, which would overwrite the
    // user's explicit choice.
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('cached_storage_provider');
      if (saved != null && saved.isNotEmpty) {
        _cachedStorageProvider = saved;
        return _cachedStorageProvider;
      }
    } catch (_) {}

    // Only if SharedPreferences is empty (first launch), seed from Supabase
    try {
      final settings = await getSettings();
      final provider = settings[_storageProviderKey] as String?;
      if (provider != null &&
          (provider == 'supabase' || provider == 'cloudinary' || provider == 'both' || provider == 'clorabase' || provider == 'supabase_clorabase')) {
        _cachedStorageProvider = provider;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('cached_storage_provider', provider);
        } catch (_) {}
      }
    } catch (_) {}
    return _cachedStorageProvider;
  }

  static Future<void> setStorageProvider(String provider) async {
    _cachedStorageProvider = provider;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('cached_storage_provider', provider);
    } catch (_) {}
    // Do NOT call updateSetting here — it reads stale Supabase data and can
    // overwrite the user's fresh choice. SharedPreferences is the source of truth.
    // Background sync to Supabase is optional and non-blocking.
    try {
      final current = await SupabaseReadService.getSettings('general');
      final data = Map<String, dynamic>.from(current ?? {});
      data[_storageProviderKey] = provider;
      SupabaseReadService.writeToAll('settings', 'general', data);
    } catch (_) {}
  }

  // ─── Cloudinary Multi-Account Upload ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getCloudinaryAccounts() async {
    try {
      final rows = await SupabaseReadService.getCloudinaryAccounts();
      if (rows != null && rows.isNotEmpty) return rows;
    } catch (_) {}
    return [];
  }

  static Future<String> addCloudinaryAccount(String cloudName, String uploadPreset, {bool isActive = true, int storageLimitMB = 25600}) async {
    final docId = 'ca_${DateTime.now().millisecondsSinceEpoch}';
    if (isActive) {
      final existing = await getCloudinaryAccounts();
      if (existing != null) {
        for (final acc in existing) {
          final aid = acc['id'] as String? ?? '';
          if (aid.isNotEmpty && acc['isActive'] == true) {
            await _mirrorWrite('settings', aid, {'isActive': false});
          }
        }
      }
    }
    await _mirrorWrite('settings', docId, {
      'cloudName': cloudName.trim(),
      'uploadPreset': uploadPreset.trim(),
      'isActive': isActive,
      'storageLimitMB': storageLimitMB,
      'currentUsageMB': 0,
      'autoSwitchEnabled': true,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<void> updateCloudinaryAccount(String id, {String? cloudName, String? uploadPreset, bool? isActive, int? storageLimitMB, int? currentUsageMB, bool? autoSwitchEnabled}) async {
    if (id.isEmpty) return;
    if (isActive == true) {
      final existing = await getCloudinaryAccounts();
      if (existing != null) {
        for (final acc in existing) {
          final aid = acc['id'] as String? ?? '';
          if (aid.isNotEmpty && aid != id && acc['isActive'] == true) {
            await _mirrorWrite('settings', aid, {'isActive': false});
          }
        }
      }
    }
    final data = <String, dynamic>{};
    if (cloudName != null) data['cloudName'] = cloudName.trim();
    if (uploadPreset != null) data['uploadPreset'] = uploadPreset.trim();
    if (isActive != null) data['isActive'] = isActive;
    if (storageLimitMB != null) data['storageLimitMB'] = storageLimitMB;
    if (currentUsageMB != null) data['currentUsageMB'] = currentUsageMB;
    if (autoSwitchEnabled != null) data['autoSwitchEnabled'] = autoSwitchEnabled;
    await _mirrorWrite('settings', id, data);
  }

  static Future<void> deleteCloudinaryAccount(String id) async {
    if (id.isEmpty) return;
    await _mirrorWrite('settings', id, {}, delete: true);
  }

  static Future<String> uploadToCloudinary(Uint8List bytes, String filename) async {
    final accounts = await getCloudinaryAccounts();
    final active = accounts.firstWhere((a) => a['isActive'] == true, orElse: () => {});

    if (active.isEmpty) {
      throw Exception('No active Cloudinary account. Go to Admin Settings \u2192 Storage Provider \u2192 Cloudinary \u2192 Add Account.');
    }

    final cloudName = active['cloudName'] as String;
    final uploadPreset = active['uploadPreset'] as String;

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/raw/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = uploadPreset;
    request.fields['resource_type'] = 'raw';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(const Duration(minutes: 15));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('Cloudinary upload failed ($cloudName): ${streamed.statusCode} $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final secureUrl = decoded['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('No URL returned from Cloudinary ($cloudName)');
      }
      return secureUrl;
    } finally {
      client.close();
    }
  }

  // ─── Assistant Cloudinary Accounts ───────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAssistantCloudinaryAccounts() async {
    try {
      final rows = await SupabaseReadService.getAssistantCloudinaryAccounts();
      if (rows != null && rows.isNotEmpty) return rows;
    } catch (_) {}
    return [];
  }

  static Future<String> addAssistantCloudinaryAccount({
    required String assistantUid,
    required String assistantName,
    required String cloudName,
    required String uploadPreset,
  }) async {
    final docId = 'ac_${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('settings', 'assistant_cloudinary_$docId', {
      'assistantUid': assistantUid,
      'assistantName': assistantName,
      'cloudName': cloudName.trim(),
      'uploadPreset': uploadPreset.trim(),
      'isActive': true,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<void> updateAssistantCloudinaryAccount(String id, {String? cloudName, String? uploadPreset, bool? isActive}) async {
    if (isActive == true) {
      await _mirrorWrite('settings', 'assistant_cloudinary_$id', {'isActive': true});
    } else if (isActive == false) {
      await _mirrorWrite('settings', 'assistant_cloudinary_$id', {'isActive': false});
    }
    if (cloudName != null || uploadPreset != null) {
      final data = <String, dynamic>{};
      if (cloudName != null) data['cloudName'] = cloudName.trim();
      if (uploadPreset != null) data['uploadPreset'] = uploadPreset.trim();
      await _mirrorWrite('settings', 'assistant_cloudinary_$id', data);
    }
  }

  static Future<void> deleteAssistantCloudinaryAccount(String id) async {
    await _mirrorWrite('settings', 'assistant_cloudinary_$id', {}, delete: true);
  }

  // ─── Clorabase Multi-Account Upload ────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getClorabaseAccounts() async {
    try {
      final rows = await SupabaseReadService.getClorabaseAccounts();
      if (rows != null && rows.isNotEmpty) return rows;
    } catch (_) {}
    return [];
  }

  static Future<String> addClorabaseAccount(String githubUsername, String githubToken, String projectName, {String? repoName, bool isActive = true, int storageLimitMB = 1024}) async {
    final docId = 'cb_${DateTime.now().millisecondsSinceEpoch}';
    if (isActive) {
      final existing = await getClorabaseAccounts();
      if (existing != null) {
        for (final acc in existing) {
          final aid = acc['id'] as String? ?? '';
          if (aid.isNotEmpty && acc['isActive'] == true) {
            await _mirrorWrite('settings', aid, {'isActive': false});
          }
        }
      }
    }
    await _mirrorWrite('settings', docId, {
      'githubUsername': githubUsername.trim(),
      'githubToken': githubToken.trim(),
      'projectName': projectName.trim(),
      if (repoName != null && repoName.isNotEmpty) 'repoName': repoName.trim(),
      'isActive': isActive,
      'storageLimitMB': storageLimitMB,
      'currentUsageMB': 0,
      'autoSwitchEnabled': true,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<void> updateClorabaseAccount(String id, {String? githubUsername, String? githubToken, String? projectName, String? repoName, bool? isActive, int? storageLimitMB, int? currentUsageMB, bool? autoSwitchEnabled}) async {
    if (id.isEmpty) return;
    if (isActive == true) {
      final existing = await getClorabaseAccounts();
      if (existing != null) {
        for (final acc in existing) {
          final aid = acc['id'] as String? ?? '';
          if (aid.isNotEmpty && aid != id && acc['isActive'] == true) {
            await _mirrorWrite('settings', aid, {'isActive': false});
          }
        }
      }
    }
    final data = <String, dynamic>{};
    if (githubUsername != null) data['githubUsername'] = githubUsername.trim();
    if (githubToken != null) data['githubToken'] = githubToken.trim();
    if (projectName != null) data['projectName'] = projectName.trim();
    if (repoName != null) data['repoName'] = repoName.trim();
    if (isActive != null) data['isActive'] = isActive;
    if (storageLimitMB != null) data['storageLimitMB'] = storageLimitMB;
    if (currentUsageMB != null) data['currentUsageMB'] = currentUsageMB;
    if (autoSwitchEnabled != null) data['autoSwitchEnabled'] = autoSwitchEnabled;
    await _mirrorWrite('settings', id, data);
  }

  static Future<void> deleteClorabaseAccount(String id) async {
    if (id.isEmpty) return;
    await _mirrorWrite('settings', id, {}, delete: true);
  }

  static Future<String> uploadToClorabase(Uint8List bytes, String filename) async {
    final accounts = await getClorabaseAccounts();
    final active = accounts.firstWhere((a) => a['isActive'] == true, orElse: () => {});

    if (active.isEmpty) {
      throw Exception('No active Clorabase account. Go to Admin Settings \u2192 Storage Provider \u2192 Clorabase \u2192 Add Account.');
    }

    final githubUsername = active['githubUsername'] as String;
    final githubToken = active['githubToken'] as String;
    final projectName = active['projectName'] as String;
    final repoName = active['repoName'] as String?;

    return await ClorabaseService.uploadFile(
      username: githubUsername,
      token: githubToken,
      project: projectName,
      bytes: bytes,
      filename: filename,
      repoName: repoName,
    );
  }

  // ─── Assistant Clorabase Accounts ─────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAssistantClorabaseAccounts() async {
    try {
      final rows = await SupabaseReadService.getAssistantClorabaseAccounts();
      if (rows != null && rows.isNotEmpty) return rows;
    } catch (_) {}
    return [];
  }

  static Future<String> addAssistantClorabaseAccount({
    required String assistantUid,
    required String assistantName,
    required String githubUsername,
    required String githubToken,
    required String projectName,
    String? repoName,
  }) async {
    final docId = 'acb_${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('settings', 'assistant_clorabase_$docId', {
      'assistantUid': assistantUid,
      'assistantName': assistantName,
      'githubUsername': githubUsername.trim(),
      'githubToken': githubToken.trim(),
      'projectName': projectName.trim(),
      if (repoName != null && repoName.isNotEmpty) 'repoName': repoName.trim(),
      'isActive': true,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<void> updateAssistantClorabaseAccount(String id, {String? githubUsername, String? githubToken, String? projectName, String? repoName, bool? isActive}) async {
    if (isActive == true) {
      await _mirrorWrite('settings', 'assistant_clorabase_$id', {'isActive': true});
    } else if (isActive == false) {
      await _mirrorWrite('settings', 'assistant_clorabase_$id', {'isActive': false});
    }
    if (githubUsername != null || githubToken != null || projectName != null || repoName != null) {
      final data = <String, dynamic>{};
      if (githubUsername != null) data['githubUsername'] = githubUsername.trim();
      if (githubToken != null) data['githubToken'] = githubToken.trim();
      if (projectName != null) data['projectName'] = projectName.trim();
      if (repoName != null) data['repoName'] = repoName.trim();
      await _mirrorWrite('settings', 'assistant_clorabase_$id', data);
    }
  }

  static Future<void> deleteAssistantClorabaseAccount(String id) async {
    await _mirrorWrite('settings', 'assistant_clorabase_$id', {}, delete: true);
  }

  // ─── Assistant Supabase Accounts ──────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAssistantSupabaseAccounts() async {
    try {
      final rows = await SupabaseReadService.getAssistantSupabaseAccounts();
      if (rows != null && rows.isNotEmpty) return rows;
    } catch (_) {}
    return [];
  }

  static Future<String> addAssistantSupabaseAccount({
    required String assistantUid,
    required String assistantName,
    required String projectUrl,
    required String serviceRoleKey,
    required String anonKey,
    int storageLimitMB = 1024,
    bool autoSwitchEnabled = true,
  }) async {
    final docId = 'as_${DateTime.now().millisecondsSinceEpoch}';
    final bucketResult = await _autoCreateBuckets(projectUrl.trim(), serviceRoleKey.trim());
    await _mirrorWrite('settings', 'assistant_supabase:$docId', {
      'assistantUid': assistantUid,
      'assistantName': assistantName,
      'projectUrl': projectUrl.trim(),
      'serviceRoleKey': serviceRoleKey.trim(),
      'anonKey': anonKey.trim(),
      'bucketStatus': bucketResult['status'],
      'failedBuckets': bucketResult['failedBuckets'],
      'isActive': true,
      'storageLimitMB': storageLimitMB,
      'autoSwitchEnabled': autoSwitchEnabled,
      'currentUsageMB': 0,
      'createdAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<void> updateAssistantSupabaseAccount(String id, {String? projectUrl, String? serviceRoleKey, String? anonKey, bool? isActive, int? storageLimitMB, bool? autoSwitchEnabled}) async {
    // When activating an assistant account, deactivate ALL other accounts for the same assistant first
    if (isActive == true) {
      try {
        final all = await SupabaseReadService.getAssistantSupabaseAccounts();
        if (all != null) {
          for (final acc in all) {
            final accId = acc['id'] as String?;
            if (accId == null || accId == id) continue;
            if (acc['isActive'] == true) {
              final existingOther = await SupabaseReadService.getSettings('assistant_supabase:$accId') ?? {};
              await _mirrorWrite('settings', 'assistant_supabase:$accId', {...existingOther, 'isActive': false});
            }
          }
        }
      } catch (_) {}
    }
    try {
      final existing = await SupabaseReadService.getSettings('assistant_supabase:$id') ?? {};
      await _mirrorWrite('settings', 'assistant_supabase:$id', {
        ...existing,
        if (projectUrl != null) 'projectUrl': projectUrl.trim(),
        if (serviceRoleKey != null) 'serviceRoleKey': serviceRoleKey.trim(),
        if (anonKey != null) 'anonKey': anonKey.trim(),
        if (isActive != null) 'isActive': isActive,
        if (storageLimitMB != null) 'storageLimitMB': storageLimitMB,
        if (autoSwitchEnabled != null) 'autoSwitchEnabled': autoSwitchEnabled,
      });
      SupabaseReadService.invalidateSettingsCache();
    } catch (_) {}
  }

  static Future<void> deleteAssistantSupabaseAccount(String id) async {
    await _mirrorWrite('settings', 'assistant_supabase:$id', const {}, delete: true);
  }

  static Future<Map<String, dynamic>> retryAssistantSupabaseBuckets(String accountId) async {
    final existing = await SupabaseReadService.getSettings('assistant_supabase:$accountId');
    if (existing == null) return {'status': 'error', 'error': 'Account not found'};
    final projectUrl = existing['projectUrl'] as String;
    final serviceKey = existing['serviceRoleKey'] as String;
    final result = await _autoCreateBuckets(projectUrl, serviceKey);
    await _mirrorWrite('settings', 'assistant_supabase:$accountId', {
      'bucketStatus': result['status'],
      'failedBuckets': result['failedBuckets'],
    });
    return result;
  }

  static Future<String> getActiveCloudinaryAccountName() async {
    try {
      final accounts = await getCloudinaryAccounts();
      final active = accounts.firstWhere((a) => a['isActive'] == true, orElse: () => {});
      if (active.isEmpty) return 'supabase';
      return active['cloudName'] as String? ?? 'cloudinary';
    } catch (_) {
      return 'supabase';
    }
  }

  // ─── Supabase Multi-Account ────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getSupabaseAccounts() async {
    try {
      final rows = await SupabaseReadService.getSupabaseAccounts();
      if (rows != null && rows.isNotEmpty) return rows;
    } catch (_) {}
    return [];
  }

  static String get _supabaseProxyUrl => 'https://prepora-web.vercel.app/api/supabase-proxy';

  static Future<Map<String, dynamic>> _supabaseProxy(String action, String projectUrl, String serviceKey, {String? bucketName}) async {
    final body = <String, dynamic>{'action': action, 'projectUrl': projectUrl, 'serviceKey': serviceKey};
    if (bucketName != null) body['bucketName'] = bucketName;
    final response = await http.post(Uri.parse(_supabaseProxyUrl), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body)).timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw Exception('Proxy returned HTTP ${response.statusCode}');
    }
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  static Future<Map<String, dynamic>> verifySupabaseCredentials(String projectUrl, String serviceKey) async {
    try {
      final result = await _supabaseProxy('verify', projectUrl, serviceKey);
      // Include details in error message for better diagnostics
      if (result['valid'] != true && result['details'] != null) {
        result['error'] = '${result['error']} (${result['details']})';
      }
      return result;
    } catch (e) {
      return {'valid': false, 'error': 'Connection failed: $e'};
    }
  }

  static Future<Map<String, dynamic>> _autoCreateBuckets(String projectUrl, String serviceKey) async {
    final results = <String, String>{};
    for (final bucket in ['folder_files', 'notices']) {
      bool exists = false;
      // Try proxy first
      try {
        final check = await _supabaseProxy('check_bucket', projectUrl, serviceKey, bucketName: bucket);
        if (check['exists'] == true) { results[bucket] = 'ready'; continue; }
      } catch (_) {}
      // Proxy failed — try direct Supabase API fallback
      try {
        final r = await http.get(
          Uri.parse('${projectUrl.trim()}/storage/v1/bucket/$bucket'),
          headers: {'Authorization': 'Bearer ${serviceKey.trim()}'},
        ).timeout(const Duration(seconds: 15));
        exists = r.statusCode == 200;
      } catch (_) {}
      if (exists) { results[bucket] = 'ready'; continue; }
      // Bucket doesn't exist — try creating via proxy
      try {
        final create = await _supabaseProxy('create_bucket', projectUrl, serviceKey, bucketName: bucket);
        if (create['ok'] == true) { results[bucket] = 'ready'; continue; }
      } catch (_) {}
      // Try creating directly
      try {
        final r = await http.post(
          Uri.parse('${projectUrl.trim()}/storage/v1/bucket'),
          headers: {'Authorization': 'Bearer ${serviceKey.trim()}', 'Content-Type': 'application/json'},
          body: jsonEncode({'id': bucket, 'public': true}),
        ).timeout(const Duration(seconds: 15));
        results[bucket] = (r.statusCode == 200 || r.statusCode == 201 || r.statusCode == 409) ? 'ready' : 'failed';
      } catch (_) {
        results[bucket] = 'failed';
      }
    }
    final failed = results.entries.where((e) => e.value == 'failed').map((e) => e.key).toList();
    final allReady = failed.isEmpty;
    return {'status': allReady ? 'ready' : (failed.length == 2 ? 'failed' : 'partial'), 'failedBuckets': failed};
  }

  static Future<String> addSupabaseAccount(String projectUrl, String serviceRoleKey, String anonKey, {bool isActive = true, int storageLimitMB = 1024, bool autoSwitchEnabled = true, String name = '', String email = '', String projectName = ''}) async {
    final docId = 'sa_${DateTime.now().millisecondsSinceEpoch}';
    final bucketResult = await _autoCreateBuckets(projectUrl.trim(), serviceRoleKey.trim());
    await _mirrorWrite('settings', 'supabase_account:$docId', {
      'projectUrl': projectUrl.trim(),
      'serviceRoleKey': serviceRoleKey.trim(),
      'anonKey': anonKey.trim(),
      'bucketStatus': bucketResult['status'],
      'failedBuckets': bucketResult['failedBuckets'],
      'isActive': isActive,
      'storageLimitMB': storageLimitMB,
      'autoSwitchEnabled': autoSwitchEnabled,
      'currentUsageMB': 0,
      'name': name.trim(),
      'email': email.trim(),
      'projectName': projectName.trim(),
      'createdAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<void> updateSupabaseAccount(String id, {String? projectUrl, String? serviceRoleKey, String? anonKey, bool? isActive, int? storageLimitMB, bool? autoSwitchEnabled, String? name, String? email, String? projectName}) async {
    if (isActive == true) {
      try {
        final all = await SupabaseReadService.getSupabaseAccounts();
        if (all != null) {
          final deactivateFutures = <Future>[];
          for (final acc in all) {
            final accId = acc['id'] as String?;
            if (accId == null || accId == id) continue;
            if (acc['isActive'] == true) {
              // Use the account data we already have — never wipe fields
              final deactivateData = Map<String, dynamic>.from(acc);
              deactivateData['isActive'] = false;
              deactivateFutures.add(_mirrorWrite('settings', accId, deactivateData));
            }
          }
          await Future.wait(deactivateFutures);
        }
      } catch (e) {
        print('[updateSupabaseAccount] Failed to deactivate others: $e');
      }
    }
    final existing = await SupabaseReadService.getSettings(id) ?? {};
    final merged = <String, dynamic>{
      ...existing,
      if (projectUrl != null) 'projectUrl': projectUrl.trim(),
      if (serviceRoleKey != null) 'serviceRoleKey': serviceRoleKey.trim(),
      if (anonKey != null) 'anonKey': anonKey.trim(),
      if (isActive != null) 'isActive': isActive,
      if (storageLimitMB != null) 'storageLimitMB': storageLimitMB,
      if (autoSwitchEnabled != null) 'autoSwitchEnabled': autoSwitchEnabled,
      if (name != null) 'name': name.trim(),
      if (email != null) 'email': email.trim(),
      if (projectName != null) 'projectName': projectName.trim(),
    };
    await _mirrorWrite('settings', id, merged);
    SupabaseReadService.invalidateSettingsCache();
  }

  static Future<void> deleteSupabaseAccount(String id) async {
    await _mirrorWrite('settings', id, const {}, delete: true);
  }

  static Future<Map<String, dynamic>> getStorageUsage(String projectUrl, String serviceKey) async {
    try {
      final result = await _supabaseProxy('storage_usage', projectUrl, serviceKey);
      return {'usedBytes': result['totalBytes'] ?? 0, 'fileCount': result['fileCount'] ?? 0};
    } catch (_) {
      return {'usedBytes': 0, 'fileCount': 0};
    }
  }

  // ─── FOP Allowed Emails ──────────────────────────────────────────────────
  static Set<String> _cachedFopEmails = {};

  static Set<String> get cachedFopEmails => _cachedFopEmails;

  static Future<Set<String>> getFopAllowedEmails() async {
    if (_cachedFopEmails.isNotEmpty) return _cachedFopEmails;
    try {
      final emails = await SupabaseReadService.getFopAllowedEmails();
      _cachedFopEmails = emails;
      return emails;
    } catch (_) {}
    return {};
  }

  static void invalidateFopEmailsCache() => _cachedFopEmails = {};

  // ─── AI API Keys ───────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getAiApiKeys() async {
    try {
      final mirror = await SupabaseReadService.getAiApiKeys();
      if (mirror != null) return mirror;
    } catch (_) {}
    return [];
  }

  static Future<Map<String, dynamic>?> getActiveAiApiKey() async {
    final mirrorKey = await SupabaseReadService.getActiveAiApiKey();
    if (mirrorKey != null) return mirrorKey;
    return null;
  }

  /// Mirrors an AI key row into the read-mirror Supabase (best effort — never
  /// throws, so Firestore remains the source of truth even if mirroring fails).
  static Future<void> _mirrorAiApiKey({
    required String id,
    required Map<String, dynamic> data,
    bool? isActive,
  }) async {
    try {
      final merged = <String, dynamic>{...data};
      if (isActive != null) merged['isActive'] = isActive;
      await SupabaseReadService.writeToAll('ai_api_keys', id, merged);
    } catch (_) {}
  }

  /// Best-effort dual-write of a Firestore doc into the read-mirror Supabase.
  /// Never throws. Plain values only (no FieldValue/Timestamp sentinels).
  static Future<void> mirrorWrite(String table, String id, Map<String, dynamic> data, {bool? delete}) async {
    try {
      await SupabaseReadService.writeToAll(table, id, data, delete: delete == true);
    } catch (_) {}
  }

  static Future<void> _mirrorWrite(String table, String id, Map<String, dynamic> data, {bool? delete}) =>
      mirrorWrite(table, id, data, delete: delete);

  /// Best-effort bulk mirror delete across all Supabase projects.
  /// Never throws — the mirror is only a read cache; Firestore stays canonical.
  static Future<void> _mirrorBulk(String table, String action, {Map<String, dynamic>? filter}) async {
    if (filter == null || filter.isEmpty) return;
    try {
      await SupabaseReadService.bulkDeleteWhere(table, filter);
    } catch (_) {}
  }

  /// Public web_sessions mirror write (used by link-web / disconnect flows).
  static Future<void> mirrorWebSession(String sessionId, Map<String, dynamic> data, {bool? delete}) =>
      _mirrorWrite('web_sessions', sessionId, data, delete: delete);

  /// Polls a single web session from the mirror so disconnects are detected
  /// quickly even while the Firestore read quota is exhausted.
  static Stream<Map<String, dynamic>?> streamWebSessionDoc(String sessionId) =>
      SupabaseReadService.streamWebSession(sessionId);

  /// Mirror-first read of a single web session.
  static Future<Map<String, dynamic>?> getWebSessionDoc(String sessionId) async {
    try {
      final mirror = await SupabaseReadService.getWebSession(sessionId);
      if (mirror != null) return mirror;
    } catch (_) {}
    return null;
  }

  /// Mirror-first list of a user's connected web sessions.
  static Future<List<Map<String, dynamic>>> getConnectedSessions(String uid) async {
    try {
      final mirror = await SupabaseReadService.getConnectedSessions(uid);
      if (mirror != null) return mirror;
    } catch (_) {}
    return [];
  }

  /// Marks every connected web session of [uid] as disconnected in
  /// the mirror (so other tabs / the admin panel detect it immediately).
  static Future<void> disconnectWebSessions(String uid) async {
    final sessions = await getConnectedSessions(uid);
    final now = DateTime.now();
    for (final s in sessions) {
      final id = s['id'] as String?;
      if (id == null || id.isEmpty) continue;
      await mirrorWebSession(id, {'status': 'disconnected', 'disconnectedAt': now.toIso8601String()});
    }
  }

  static Future<String> addAiApiKey({
    required String name,
    required String provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    List<String>? models,
    bool isActive = false,
  }) async {
    final data = <String, dynamic>{
      'name': name.trim(),
      'provider': provider.trim(),
      'baseUrl': baseUrl.trim(),
      'apiKey': apiKey.trim(),
      'model': model.trim(),
      'isActive': isActive,
      'createdAt': DateTime.now().toIso8601String(),
    };
    if (models != null && models.isNotEmpty) {
      data['models'] = models.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
    }
    final docId = 'aik_${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('ai_api_keys', docId, data);
    await _mirrorAiApiKey(id: docId, data: data, isActive: isActive);
    return docId;
  }

  static Future<void> updateAiApiKey(String id, {String? name, String? provider, String? baseUrl, String? apiKey, String? model, List<String>? models, bool? isActive}) async {
    // Read existing data first to prevent JSONB overwrite
    Map<String, dynamic>? existing;
    try { existing = await SupabaseReadService.getAiApiKeyById(id); } catch (_) {}
    final data = Map<String, dynamic>.from(existing ?? {});
    if (name != null) data['name'] = name.trim();
    if (provider != null) data['provider'] = provider.trim();
    if (baseUrl != null) data['baseUrl'] = baseUrl.trim();
    if (apiKey != null) data['apiKey'] = apiKey.trim();
    if (model != null) data['model'] = model.trim();
    if (models != null) data['models'] = models.map((m) => m.trim()).where((m) => m.isNotEmpty).toList();
    if (isActive != null) data['isActive'] = isActive;
    if (data.isNotEmpty) {
      await _mirrorWrite('ai_api_keys', id, data);
      await _mirrorAiApiKey(id: id, data: data, isActive: isActive);
      if (isActive == true) await _deactivateOtherAiApiKeys(id);
    }
  }

  static Future<void> _deactivateOtherAiApiKeys(String exceptId) async {
    try {
      final keys = await SupabaseReadService.getAiApiKeys();
      if (keys == null) return;
      for (final k in keys) {
        final kid = k['id'] as String?;
        if (kid == null || kid == exceptId) continue;
        if (k['isActive'] == true) {
          // Read existing data first to preserve all fields
          Map<String, dynamic>? existing;
          try { existing = await SupabaseReadService.getAiApiKeyById(kid); } catch (_) {}
          final merged = Map<String, dynamic>.from(existing ?? k);
          merged['isActive'] = false;
          await _mirrorWrite('ai_api_keys', kid, merged);
          await _mirrorAiApiKey(id: kid, data: merged, isActive: false);
        }
      }
    } catch (_) {}
  }

  static Future<void> deleteAiApiKey(String id) async {
    await _mirrorWrite('ai_api_keys', id, const {}, delete: true);
  }

  static Future<Map<String, dynamic>> retryBucketCreation(String accountId) async {
    final existing = await SupabaseReadService.getSettings(accountId);
    if (existing == null) return {'status': 'error', 'error': 'Account not found'};
    final projectUrl = existing['projectUrl'] as String;
    final serviceKey = existing['serviceRoleKey'] as String;
    if (projectUrl.isEmpty || serviceKey.isEmpty) {
      return {'status': 'error', 'error': 'Account data incomplete (missing projectUrl or serviceRoleKey)'};
    }
    final result = await _autoCreateBuckets(projectUrl, serviceKey);
    // Merge with existing data so we don't lose projectUrl, serviceRoleKey, etc.
    await _mirrorWrite('settings', accountId, {
      ...existing,
      'bucketStatus': result['status'],
      'failedBuckets': result['failedBuckets'],
    });
    return result;
  }

  /// Directly verify if buckets exist — bypasses proxy, uses Supabase API directly
  static Future<Map<String, dynamic>> verifyBucketsExist(String projectUrl, String serviceKey) async {
    final results = <String, String>{};
    for (final bucket in ['folder_files', 'notices']) {
      try {
        final r = await http.get(
          Uri.parse('${projectUrl.trim()}/storage/v1/bucket/$bucket'),
          headers: {'Authorization': 'Bearer ${serviceKey.trim()}'},
        ).timeout(const Duration(seconds: 15));
        results[bucket] = r.statusCode == 200 ? 'ready' : 'missing';
      } catch (_) {
        results[bucket] = 'unknown';
      }
    }
    final missing = results.entries.where((e) => e.value == 'missing').map((e) => e.key).toList();
    final unknown = results.entries.where((e) => e.value == 'unknown').map((e) => e.key).toList();
    final failed = results.entries.where((e) => e.value == 'missing').map((e) => e.key).toList();
    if (unknown.isNotEmpty && missing.isEmpty) {
      return {'status': 'unknown', 'results': results, 'failedBuckets': <String>[]};
    }
    final allReady = missing.isEmpty;
    return {'status': allReady ? 'ready' : (failed.length == 2 ? 'failed' : 'partial'), 'results': results, 'failedBuckets': failed};
  }

  static Future<String> getActiveSupabaseAccountName() async {
    try {
      final accounts = await getSupabaseAccounts();
      final active = accounts.firstWhere((a) => a['isActive'] == true, orElse: () => {});
      if (active.isEmpty) return '';
      return active['projectUrl'] as String? ?? '';
    } catch (_) {
      return '';
    }
  }

  static Future<String> uploadFile(Uint8List bytes, String filename, {void Function(double)? onProgress, String? forceProvider}) async {
    final provider = forceProvider ?? await getStorageProvider();

    // Pre-upload storage limit check for Supabase providers
    if (provider == 'supabase' || provider == 'both' || provider == 'supabase_clorabase') {
      final switchResult = await _checkStorageAndSwitchIfNeeded();
      if (switchResult['switched'] == true) {
        // Storage was full, auto-switched to next account
      }
    }

    if (provider == 'both') {
      if (bytes.length <= 10 * 1024 * 1024) {
        try {
          return await _uploadViaCloudinary(bytes, filename);
        } catch (_) {
          // If Supabase upload fails due to storage limit, try switching account
          try {
            return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
          } catch (e) {
            if (e.toString().contains('storage') || e.toString().contains('limit') || e.toString().contains('quota')) {
              final switched = await _checkStorageAndSwitchIfNeeded(forceSwitch: true);
              if (switched['switched'] == true) {
                return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
              }
            }
            rethrow;
          }
        }
      } else {
        try {
          return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
        } catch (e) {
          if (e.toString().contains('storage') || e.toString().contains('limit') || e.toString().contains('quota')) {
            final switched = await _checkStorageAndSwitchIfNeeded(forceSwitch: true);
            if (switched['switched'] == true) {
              return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
            }
          }
          rethrow;
        }
      }
    }

    if (provider == 'cloudinary') {
      return await _uploadViaCloudinary(bytes, filename);
    }

    if (provider == 'clorabase') {
      return await _uploadViaClorabase(bytes, filename);
    }

    if (provider == 'supabase_clorabase') {
      return await _uploadViaClorabase(bytes, filename);
    }

    // Default: Supabase
    try {
      return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
    } catch (e) {
      if (e.toString().contains('storage') || e.toString().contains('limit') || e.toString().contains('quota')) {
        final switched = await _checkStorageAndSwitchIfNeeded(forceSwitch: true);
        if (switched['switched'] == true) {
          return await _uploadViaSupabase(bytes, filename, onProgress: onProgress);
        }
      }
      rethrow;
    }
  }

  /// Check if active Supabase account has storage available, switch if needed
  static Future<Map<String, dynamic>> _checkStorageAndSwitchIfNeeded({bool forceSwitch = false}) async {
    try {
      final accounts = await getSupabaseAccounts();
      final activeAcc = accounts.firstWhere((a) => a['isActive'] == true, orElse: () => {});

      if (activeAcc.isEmpty) return {'switched': false, 'reason': 'no_active_account'};

      final storageLimitMB = activeAcc['storageLimitMB'] as int? ?? 1024;
      final autoSwitchEnabled = activeAcc['autoSwitchEnabled'] as bool? ?? true;
      // Trigger switch 10 MB before the limit (proactive), not at the limit
      final thresholdMB = storageLimitMB - 10;

      // Try to get current storage usage from the active account
      final projectUrl = activeAcc['projectUrl'] as String? ?? '';
      final serviceKey = activeAcc['serviceRoleKey'] as String? ?? '';
      int realUsageMB = activeAcc['currentUsageMB'] as int? ?? 0;

      if (projectUrl.isNotEmpty && serviceKey.isNotEmpty) {
        try {
          final usage = await getStorageUsage(projectUrl, serviceKey);
          final realUsageBytes = usage['usedBytes'] as int? ?? 0;
          realUsageMB = (realUsageBytes / (1024 * 1024)).round();
          await _mirrorWrite('settings', activeAcc['id'], {'currentUsageMB': realUsageMB});
        } catch (_) {}
      }

      final isNearLimit = realUsageMB >= thresholdMB || forceSwitch;

      if (isNearLimit) {
        if (!autoSwitchEnabled && !forceSwitch) return {'switched': false, 'reason': 'auto_switch_disabled'};

        // Find next available account with enough free space
        for (final acc in accounts) {
          if (acc['id'] == activeAcc['id']) continue;
          if (acc['isActive'] == true) continue;
          if (acc['bucketStatus'] != 'ready') continue;

          final nextUsage = acc['currentUsageMB'] as int? ?? 0;
          final nextLimit = acc['storageLimitMB'] as int? ?? 1024;
          final nextFreeMB = nextLimit - nextUsage;
          // Skip accounts that are also near-full (need at least 50 MB free)
          if (nextFreeMB < 50) continue;

          // Switch to this account — preserve ALL existing fields
          final switchAccData = Map<String, dynamic>.from(acc);
          switchAccData['isActive'] = true;
          // Deactivate the old account too — preserve its fields
          final oldAccData = Map<String, dynamic>.from(activeAcc);
          oldAccData['isActive'] = false;
          await Future.wait([
            _mirrorWrite('settings', acc['id'], switchAccData),
            _mirrorWrite('settings', activeAcc['id'], oldAccData),
          ]);
          await reinitializeSupabase();
          return {'switched': true, 'newAccount': acc['id']};
        }

        return {'switched': false, 'reason': 'no_available_account'};
      }
    } catch (_) {}
    return {'switched': false, 'reason': 'check_failed'};
  }

  static Future<String> _uploadViaCloudinary(Uint8List bytes, String filename) async {
    final user = currentUser;
    if (user != null) {
      final role = await getUserRole(user.uid);
      if (role == 'Assistant') {
        return await _uploadToAssistantCloudinary(user.uid, bytes, filename);
      }
    }
    return await uploadToCloudinary(bytes, filename);
  }

  static Future<String> _uploadViaClorabase(Uint8List bytes, String filename) async {
    final user = currentUser;
    if (user != null) {
      final role = await getUserRole(user.uid);
      if (role == 'Assistant') {
        return await _uploadToAssistantClorabase(user.uid, bytes, filename);
      }
    }
    return await uploadToClorabase(bytes, filename);
  }

  static Future<String> _uploadViaSupabase(Uint8List bytes, String filename, {void Function(double)? onProgress}) async {
    final storageName = '${DateTime.now().millisecondsSinceEpoch}_$filename';
    final ref = storage.ref('folder_files/$storageName');
    await ref.putData(bytes, metadata: fb_storage.SettableMetadata(contentDisposition: 'inline; filename="$filename"'), onProgress: onProgress);
    return ref.getDownloadURL();
  }

  static Future<String> _uploadToAssistantCloudinary(String assistantUid, Uint8List bytes, String filename) async {
    List<Map<String, dynamic>>? accounts;
    try { accounts = await SupabaseReadService.getAssistantCloudinaryAccounts(); } catch (_) {}
    final match = accounts?.firstWhere(
      (a) => a['assistantUid'] == assistantUid && a['isActive'] == true,
      orElse: () => {},
    );
    if (match == null || match.isEmpty) {
      return await uploadToCloudinary(bytes, filename);
    }

    final cloudName = match['cloudName'] as String;
    final uploadPreset = match['uploadPreset'] as String;

    final uri = Uri.parse('https://api.cloudinary.com/v1_1/$cloudName/raw/upload');
    final request = http.MultipartRequest('POST', uri);
    request.fields['upload_preset'] = uploadPreset;
    request.fields['resource_type'] = 'raw';
    request.files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));

    final client = http.Client();
    try {
      final streamed = await client.send(request).timeout(const Duration(minutes: 15));
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw Exception('Assistant Cloudinary upload failed ($cloudName): ${streamed.statusCode} $body');
      }
      final decoded = jsonDecode(body) as Map<String, dynamic>;
      final secureUrl = decoded['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('No URL returned from Cloudinary ($cloudName)');
      }
      return secureUrl;
    } finally {
      client.close();
    }
  }

  static Future<String> _uploadToAssistantClorabase(String assistantUid, Uint8List bytes, String filename) async {
    List<Map<String, dynamic>>? accounts;
    try { accounts = await SupabaseReadService.getAssistantClorabaseAccounts(); } catch (_) {}
    final match = accounts?.firstWhere(
      (a) => a['assistantUid'] == assistantUid && a['isActive'] == true,
      orElse: () => {},
    );
    if (match == null || match.isEmpty) {
      return await uploadToClorabase(bytes, filename);
    }

    final githubUsername = match['githubUsername'] as String;
    final githubToken = match['githubToken'] as String;
    final projectName = match['projectName'] as String;
    final repoName = match['repoName'] as String?;

    return await ClorabaseService.uploadFile(
      username: githubUsername,
      token: githubToken,
      project: projectName,
      bytes: bytes,
      filename: filename,
      repoName: repoName,
    );
  }

  // ─── Folders ───────────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getAllFolders() {
    return SupabaseReadService.streamFolders()
        .map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<String?> createRootFolder({required String name, String? icon, String? color}) async {
    final docId = 'fld_${DateTime.now().millisecondsSinceEpoch}';
    final folderData = {
      'name': name,
      'icon': icon ?? 'folder',
      'color': color ?? '#4A148C',
      'item_count': 0,
      'locked': false,
      'invisible': false,
      'updating': false,
      'group_link': null,
      'sort_order': 0,
      'createdAt': DateTime.now().toIso8601String(),
    };
    // Supabase ONLY — Firestore mirror removed
    final ok = await SupabaseReadService.writeToAll('folders', docId, folderData);
    if (!ok) return null;
    return docId;
  }

  static Future<void> renameRootFolder(String folderId, String name) async {
    Map<String, dynamic>? existing;
    try { existing = await SupabaseReadService.getFolder(folderId); } catch (_) {}
    final merged = <String, dynamic>{...?existing, 'name': name};
    await _mirrorWrite('folders', folderId, merged);
  }

  static Future<void> deleteRootFolder(String folderId) async {
    await _deleteAllContentsRecursive(folderId, 'contents');
    await _deleteAllContentsRecursive(folderId, 'content');
    await _mirrorWrite('folders', folderId, const {}, delete: true);
  }

  static Future<void> _deleteAllContentsRecursive(String folderId, String subcollection) async {
    // Supabase-only: recursively delete ALL contents (children, grandchildren, etc.)
    try {
      // 1. Fetch ALL contents in this folder (fetchAll = no parent_content_id filter)
      final allContents = await SupabaseReadService.getFolderContents(folderId, fetchAll: true);
      if (allContents == null || allContents.isEmpty) return;

      // 2. For each subfolder, recursively delete its children first (deepest first)
      for (final item in allContents) {
        if (item['type'] == 'subfolder') {
          await _deleteSubfolderChildrenRecursive(folderId, item['id'] as String, '');
        }
      }

      // 3. Now delete all items (they have no children left)
      for (final item in allContents) {
        await SupabaseReadService.writeToAll('contents', item['id'] as String, const {}, delete: true);
      }
    } catch (_) {}
  }

  static Future<void> deleteFolder(String folderId) async {
    await deleteRootFolder(folderId);
  }

  static Future<void> toggleFolderLock(String folderId, String field, dynamic value) async {
    Map<String, dynamic>? existing;
    try { existing = await SupabaseReadService.getFolder(folderId); } catch (_) {}
    final merged = <String, dynamic>{...?existing, field: value};
    await _mirrorWrite('folders', folderId, merged);
  }

  /// Async: check content-level group_link first, fall back to root folder doc.
  /// Respects [inheritGroup] flag: if false on the content doc, skip folder fallback.
  static Future<String?> getGroupLinkForLevel(String folderId, {String? parentContentId}) async {
    if (parentContentId != null && parentContentId != 'root') {
      Map<String, dynamic>? data;
      try { data = await SupabaseReadService.getContent(folderId, parentContentId); } catch (_) {}
      if (data != null) {
        final link = data['group_link'] as String?;
        final inherit = data['inherit_group'] as bool? ?? true;
        if (link != null && link.isNotEmpty) return link;
        if (!inherit) return null;
      }
    }
    Map<String, dynamic>? folderData;
    try { folderData = await SupabaseReadService.getFolder(folderId); } catch (_) {}
    if (folderData != null) {
      final link = folderData['group_link'] as String?;
      if (link != null && link.isNotEmpty) return link;
    }
    return null;
  }

  /// Sync read from already-fetched folder data (falls back to root doc).
  static String? getGroupLink(dynamic folderData, {String? parentContentId}) {
    if (folderData == null) return null;
    Map<String, dynamic> data;
    if (folderData is DocumentSnapshot) {
      data = folderData.data() as Map<String, dynamic>? ?? {};
    } else {
      data = folderData as Map<String, dynamic>;
    }
    if (parentContentId != null && parentContentId != 'root') {
      final link = data['group_link'] as String?;
      final inherit = data['inherit_group'] as bool? ?? true;
      if (link != null && link.isNotEmpty) return link;
      if (!inherit) return null;
    }
    return data['group_link'] as String?;
  }

  static Future<void> setGroupLink(String folderId, String link, {String? parentContentId, bool inheritGroup = true}) async {
    if (parentContentId != null && parentContentId != 'root') {
      // Read-merge-write to preserve existing JSONB fields
      Map<String, dynamic>? existing;
      try { existing = await SupabaseReadService.getContent(folderId, parentContentId); } catch (_) {}
      final merged = <String, dynamic>{
        if (existing != null) ...existing,
        'folderId': folderId,
        'group_link': link,
        'inherit_group': inheritGroup,
      };
      await _mirrorWrite('contents', parentContentId, merged);
      if (inheritGroup) {
        await _propagateAllDescendants(folderId, parentContentId, link, true);
      }
    } else {
      // Read-merge-write to preserve existing JSONB fields
      Map<String, dynamic>? existing;
      try { existing = await SupabaseReadService.getFolder(folderId); } catch (_) {}
      final merged = <String, dynamic>{
        if (existing != null) ...existing,
        'group_link': link,
        'inherit_group': inheritGroup,
      };
      await _mirrorWrite('folders', folderId, merged);
      if (inheritGroup) {
        await _propagateAllDescendants(folderId, null, link, true);
      }
    }
  }

  static Future<void> removeGroupLink(String folderId, {String? parentContentId}) async {
    if (parentContentId != null && parentContentId != 'root') {
      Map<String, dynamic>? data;
      try { data = await SupabaseReadService.getContent(folderId, parentContentId); } catch (_) {}
      final inherit = data?['inherit_group'] as bool? ?? true;
      // Read-merge-write to preserve existing JSONB fields
      final merged = <String, dynamic>{
        if (data != null) ...data,
        'folderId': folderId,
        'group_link': null,
        'inherit_group': true,
      };
      await _mirrorWrite('contents', parentContentId, merged);
      if (inherit) {
        await _propagateAllDescendants(folderId, parentContentId, null, true);
      }
    } else {
      Map<String, dynamic>? folderData;
      try { folderData = await SupabaseReadService.getFolder(folderId); } catch (_) {}
      final inherit = folderData?['inherit_group'] as bool? ?? true;
      // Read-merge-write to preserve existing JSONB fields
      final merged = <String, dynamic>{
        if (folderData != null) ...folderData,
        'group_link': null,
        'inherit_group': true,
      };
      await _mirrorWrite('folders', folderId, merged);
      if (inherit) {
        await _propagateAllDescendants(folderId, null, null, true);
      }
    }
  }

  static Future<void> _propagateAllDescendants(String folderId, String? startParentId, String? link, bool inheritGroup) async {
    try {
      if (startParentId != null) {
        // Propagate into a specific content subtree
        final children = await SupabaseReadService.getFolderContents(folderId, parentContentId: startParentId, fetchAll: true);
        if (children != null) {
          for (final child in children) {
            await SupabaseReadService.writeToAll('contents', child['id'] as String, {
              'group_link': link,
              'inherit_group': inheritGroup,
              'folderId': folderId,
            });
            if (child['type'] == 'subfolder') {
              await _propagateAllDescendants(folderId, child['id'] as String, link, inheritGroup);
            }
          }
        }
      } else {
        // Propagate from root of the folder
        final allContents = await SupabaseReadService.getFolderContents(folderId, fetchAll: true);
        if (allContents != null) {
          for (final item in allContents) {
            await SupabaseReadService.writeToAll('contents', item['id'] as String, {
              'group_link': link,
              'inherit_group': inheritGroup,
              'folderId': folderId,
            });
          }
        }
      }
    } catch (_) {}
  }

  // ─── Folder Contents ───────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getContentsForFolder(String folderId) {
    return SupabaseReadService.streamContents(folderId)
        .map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<String?> addFolderContent(String folderId, Map<String, dynamic> data) async {
    final docId = 'cnt_${DateTime.now().millisecondsSinceEpoch}';
    final payload = {
      'folderId': folderId,
      ...data,
      'createdAt': DateTime.now().toIso8601String(),
    };
    // Retry up to 5 times with progressive delay (for weak internet)
    for (int attempt = 1; attempt <= 5; attempt++) {
      final ok = await SupabaseReadService.writeToAll('contents', docId, payload);
      if (ok) return docId;
      if (attempt < 5) await Future.delayed(Duration(seconds: attempt * 2));
    }
    return null;
  }

  static Future<void> renameFolderContent(String folderId, String contentId, String name) async {
    Map<String, dynamic>? existing;
    try { existing = await SupabaseReadService.getContent(folderId, contentId); } catch (_) {}
    final merged = <String, dynamic>{...?existing, 'name': name, 'folderId': folderId};
    await _mirrorWrite('contents', contentId, merged);
  }

  static Future<void> deleteFolderContent(String folderId, String contentId) async {
    // First, check if this is a subfolder and delete its children recursively
    try {
      final content = await SupabaseReadService.getContent(folderId, contentId);
      if (content != null && content['type'] == 'subfolder') {
        await _deleteSubfolderChildrenRecursive(folderId, contentId, '');
      }
    } catch (_) {}
    await _mirrorWrite('contents', contentId, const {}, delete: true);
  }

  static Future<void> _deleteSubfolderChildrenRecursive(String folderId, String parentContentId, String subcollection) async {
    // Recursively delete all children of a subfolder
    try {
      final children = await SupabaseReadService.getFolderContents(folderId, parentContentId: parentContentId);
      if (children != null) {
        for (final child in children) {
          if (child['type'] == 'subfolder') {
            await _deleteSubfolderChildrenRecursive(folderId, child['id'] as String, subcollection);
          }
          await SupabaseReadService.writeToAll('contents', child['id'] as String, const {}, delete: true);
        }
      }
    } catch (_) {}
  }

  static Future<void> updateContentField(String folderId, String contentId, String field, dynamic value) async {
    Map<String, dynamic>? existing;
    try { existing = await SupabaseReadService.getContent(folderId, contentId); } catch (_) {}
    final merged = <String, dynamic>{...?existing, field: value, 'folderId': folderId};
    await _mirrorWrite('contents', contentId, merged);
  }

  static Future<void> grantContentAccess(String uid, String folderId, String contentId, String name) async {
    final docId = 'ca_${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('content_assistant_access', docId, {
      'userId': uid,
      'folderId': folderId,
      'contentId': contentId,
      'name': name,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> revokeContentAccess(String uid, String folderId, String contentId) async {
    await _mirrorBulk('content_assistant_access', 'delete_filter', filter: {'user_id': uid, 'content_id': contentId});
  }

  // ─── Notices ────────────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getNotices() {
    return SupabaseReadService.streamNotices().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<String?> addNotice(String title, String? fileUrl, String fileType) async {
    try {
      // If file is a local file path, upload to Supabase Storage
      String? supabaseUrl = fileUrl;
      if (!kIsWeb && fileUrl != null && (fileUrl.startsWith('/') || fileUrl.startsWith('file://'))) {
        final file = File(fileUrl.replaceFirst('file://', ''));
        final ext = fileUrl.split('.').last;
        final fileName = 'notices/${DateTime.now().millisecondsSinceEpoch}.$ext';
        supabaseUrl = await uploadFileToSupabase('notices', fileName, file);
      }
      final docId = 'nt_${DateTime.now().millisecondsSinceEpoch}';
      final userName = currentUser?.displayName ?? 'Admin';
      await _mirrorWrite('notices', docId, {
        'title': title,
        'fileUrl': supabaseUrl,
        'fileType': fileType,
        'addedBy': userName,
        'createdAt': DateTime.now().toIso8601String(),
        'isPinned': false,
      });
      return docId;
    } catch (e) {
      print('[addNotice] Supabase write failed: $e');
      return null;
    }
  }

  // ─── Notifications ─────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getNotificationsForUser(String uid, DateTime since) {
    return SupabaseReadService.streamNotifications(uid, since).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<void> markStudentNotificationsRead(String uid) async {
    List<Map<String, dynamic>>? unread;
    try { unread = await SupabaseReadService.getUnreadNotificationsForUser(uid); } catch (_) {}
    if (unread != null && unread.isNotEmpty) {
      for (final row in unread) {
        final id = row['id'] as String?;
        if (id != null && id.isNotEmpty) {
          await _mirrorWrite('notifications', id, {
            ...row,
            'read': true,
          });
        }
      }
    }
  }

  // ─── Admin Notifications ───────────────────────────────────────────────────────

  static Future<void> addAdminNotification(String type, String message, {String? relatedUid}) async {
    final id = 'n${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('admin_notifications', id, {
      'type': type,
      'message': message,
      'relatedUid': relatedUid,
      'read': false,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static Stream<QuerySnapshot> getAdminNotifications() {
    return SupabaseReadService.streamAdminNotifications().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<int> getAdminUnreadCount() async {
    try {
      final mirror = await SupabaseReadService.getAdminUnreadCount();
      if (mirror >= 0) return mirror;
    } catch (_) {}
    return 0;
  }

  static Future<void> markAdminNotificationsRead() async {
    try {
      List<Map<String, dynamic>>? unread;
      try { unread = await SupabaseReadService.getUnreadAdminNotifications(); } catch (_) {}
      if (unread != null && unread.isNotEmpty) {
        for (final row in unread) {
          final id = row['id'] as String?;
          if (id != null && id.isNotEmpty) {
            await _mirrorWrite('admin_notifications', id, {
              ...row,
              'read': true,
            });
          }
        }
      }
    } catch (_) {}
  }

  static Future<void> clearAdminNotifications() async {
    await SupabaseReadService.clearNonLoginAdminNotifications();
  }

  static Future<void> clearLoginNotifications() async {
    await SupabaseReadService.clearLoginNotifications();
  }

  // ─── Login Tracking & Auto-Block ──────────────────────────────────────────────

  static Future<void> _trackLogin(String uid, String deviceId) async {
    try {
      final now = DateTime.now();
      final iso = now.toIso8601String();
      var deviceModel = 'Web Browser';
      if (kIsWeb) {
        try {
          final info = await DeviceInfoPlugin().webBrowserInfo;
          final browserName = info.browserName.name;
          deviceModel = browserName;
        } catch (_) {}
      } else {
        try {
          final info = await DeviceInfoPlugin().androidInfo;
          deviceModel = '${info.manufacturer} ${info.model}';
        } catch (_) {}
      }
      final docId = 'la_${DateTime.now().millisecondsSinceEpoch}';
      await _mirrorWrite('login_attempts', docId, {
        'uid': uid,
        'deviceId': deviceId,
        'deviceModel': deviceModel,
        'timestamp': iso,
        'createdAt': DateTime.now().toIso8601String(),
      });
      try {
        final loginHistoryData = {
          'uid': uid,
          'timestamp': DateTime.now().toIso8601String(),
          'device': deviceModel,
          'deviceId': deviceId,
          'ip': '',
        };
        await _mirrorWrite('login_history', '${uid}_${now.millisecondsSinceEpoch}', loginHistoryData);
      } catch (_) {}
    } catch (_) {}
  }

  static Future<void> updateStreak(String uid) async {
    try {
      Map<String, dynamic>? data;
      try {
        data = await SupabaseReadService.getUser(uid);
      } catch (_) {}
      if (data == null) return;
      final lastActive = (data['lastActiveDate'] as String?) ?? (data['last_active_date'] as String?) ?? '';
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      if (lastActive == todayStr) return;

      int streak = (data['streakCount'] as int?) ?? (data['streak_count'] as int?) ?? (data['streak'] as int?) ?? 0;
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      if (lastActive == yesterdayStr) {
        streak += 1;
      } else {
        streak = 1;
      }
      final totalDays = (data['totalActiveDays'] as int?) ?? (data['total_active_days'] as int?) ?? 0;
      int streakBest = (data['streakBest'] as int?) ?? (data['streak_best'] as int?) ?? 0;
      if (streak > streakBest) streakBest = streak;
      // Read existing JSONB data so we don't destroy name/email/etc
      Map<String, dynamic>? existingData;
      try {
        existingData = await SupabaseReadService.readPrimary('users', uid);
      } catch (_) {}
      final mergedData = <String, dynamic>{
        if (existingData != null) ...existingData,
        'lastActiveDate': todayStr,
        'streakCount': streak,
        'totalActiveDays': totalDays + 1,
        'streakBest': streakBest,
        'lastLogin': today.toIso8601String(),
      };
      await _mirrorWrite('users', uid, mergedData);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getStreak(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) {
        final lastActive = (mirror['lastActiveDate'] as String?) ?? (mirror['last_active_date'] as String?) ?? '';
        int streakCount = (mirror['streakCount'] as int?) ?? (mirror['streak_count'] as int?) ?? (mirror['streak'] as int?) ?? 0;
        final today = DateTime.now();
        final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
        final yesterday = today.subtract(const Duration(days: 1));
        final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
        if (lastActive != todayStr && lastActive != yesterdayStr) {
          streakCount = 0;
        }
        return {
          'streakCount': streakCount,
          'totalActiveDays': (mirror['totalActiveDays'] as int?) ?? (mirror['total_active_days'] as int?) ?? 0,
          'lastActiveDate': lastActive,
        };
      }
    } catch (_) {}
    return {'streakCount': 0, 'totalActiveDays': 0};
  }

  static Future<bool> _isAnyAncestorRestricted(String folderId, String? contentId) async {
    if (contentId == null) return false;
    try {
      Map<String, dynamic>? data;
      try { data = await SupabaseReadService.getContent(folderId, contentId); } catch (_) {}
      if (data == null) return false;
      final locked = data['locked'] as bool? ?? false;
      final invisible = data['invisible'] as bool? ?? false;
      final updating = data['updating'] as bool? ?? false;
      if (locked || invisible || updating) return true;
      final parentContentId = data['parentContentId'] as String?;
      if (parentContentId != null) {
        return _isAnyAncestorRestricted(folderId, parentContentId);
      }
    } catch (_) {}
    return false;
  }

  static Future<bool> _isNotificationBlocked(String? folderId, String? parentContentId, Map<String, dynamic>? contentData) async {
    if (contentData != null) {
      final locked = contentData['locked'] as bool? ?? false;
      final updating = contentData['updating'] as bool? ?? false;
      final invisible = contentData['invisible'] as bool? ?? false;
      if (locked || updating || invisible) return true;
    }
    if (folderId != null) {
      Map<String, dynamic>? folderData;
      try { folderData = await SupabaseReadService.getFolder(folderId); } catch (_) {}
      if (folderData != null) {
        final folderLocked = folderData['locked'] as bool? ?? false;
        final folderInvisible = folderData['invisible'] as bool? ?? false;
        final folderUpdating = folderData['updating'] as bool? ?? false;
        if (folderLocked || folderInvisible || folderUpdating) return true;
      }
      if (parentContentId != null) {
        if (await _isAnyAncestorRestricted(folderId, parentContentId)) return true;
      }
    }
    return false;
  }

  static Future<String?> addNotification(String message, {String? folderId, String? parentContentId, Map<String, dynamic>? contentData}) async {
    if (await _isNotificationBlocked(folderId, parentContentId, contentData)) return null;
    List<Map<String, dynamic>>? users;
    try { users = await SupabaseReadService.getAllUsers(); } catch (_) {}
    final mirrorWrites = <Future>[];
    if (users != null && users.isNotEmpty) {
      for (final u in users) {
        final uid = u['id'] as String? ?? '';
        if (uid.isEmpty) continue;
        final notifId = 'nf_${DateTime.now().millisecondsSinceEpoch}_$uid';
        mirrorWrites.add(_mirrorWrite('notifications', notifId, {
          'uid': uid,
          'message': message,
          'folderId': folderId,
          'read': false,
          'createdAt': DateTime.now().toIso8601String(),
          'type': folderId != null ? 'folder_update' : 'general',
        }));
      }
    }
    try { await Future.wait(mirrorWrites); } catch (_) {}
    return 'batch';
  }

  static Future<String?> addTargetedNotification(String uid, String message, {String? folderId, String? parentContentId, Map<String, dynamic>? contentData}) async {
    if (await _isNotificationBlocked(folderId, parentContentId, contentData)) return null;
    final docId = 'tn_${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('notifications', docId, {
      'uid': uid,
      'message': message,
      'read': false,
      'createdAt': DateTime.now().toIso8601String(),
      'type': 'targeted',
    });
    return docId;
  }

  /// Broadcasts a notification to every student (role == 'student').
  static Future<int> addNotificationToAllStudents(String message) async {
    List<Map<String, dynamic>>? students;
    try { students = await SupabaseReadService.getUsersByRole('student'); } catch (_) {}
    final mirrorWrites = <Future>[];
    int count = 0;
    if (students != null && students.isNotEmpty) {
      for (final s in students) {
        final uid = s['id'] as String? ?? '';
        if (uid.isEmpty) continue;
        final notifId = 'sn_${DateTime.now().millisecondsSinceEpoch}_$uid';
        mirrorWrites.add(_mirrorWrite('notifications', notifId, {
          'uid': uid,
          'message': message,
          'read': false,
          'createdAt': DateTime.now().toIso8601String(),
          'type': 'general',
        }));
        count++;
      }
    }
    try { await Future.wait(mirrorWrites); } catch (_) {}
    return count;
  }

  // ─── Student Activity Tracking ───────────────────────────────────────────────

  static Future<String> logActivity({
    required String uid,
    required String name,
    required String type,
    required String folderPath,
    String? contentId,
  }) async {
    final docId = 'act_${DateTime.now().millisecondsSinceEpoch}';
    await SupabaseReadService.writeToAll('student_activities', docId, {
      'uid': uid,
      'name': name,
      'type': type,
      'folderPath': folderPath,
      if (contentId != null) 'contentId': contentId,
      'startedAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<void> endActivity(String activityId) async {
    try {
      Map<String, dynamic>? existing;
      try {
        existing = await SupabaseReadService.readPrimary('student_activities', activityId);
      } catch (_) {}
      final merged = <String, dynamic>{
        if (existing != null) ...existing,
        'endedAt': DateTime.now().toIso8601String(),
      };
      await SupabaseReadService.writeToAll('student_activities', activityId, merged);
    } catch (_) {}
  }

  static Stream<QuerySnapshot> getStudentActivities(String uid) {
    return SupabaseReadService.streamStudentActivities(uid).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<Map<String, dynamic>?> getUserData(String uid) async {
    try {
      final mirror = await SupabaseReadService.getUser(uid);
      if (mirror != null) return mirror;
    } catch (_) {}
    try {
      final fallback = await SupabaseReadService.readPrimary('users', uid);
      if (fallback != null) return fallback;
    } catch (_) {}
    return null;
  }

  static Future<List<Map<String, dynamic>>> getStudentFeedbacks(String uid) async {
    try {
      final mirror = await SupabaseReadService.getFeedbacksForUser(uid);
      if (mirror != null) return mirror;
    } catch (_) {}
    return [];
  }

  // ─── Feedback ──────────────────────────────────────────────────────────────────

  static bool _submittingFeedback = false;

  static Future<String?> submitFeedback(dynamic feedback) async {
    if (_submittingFeedback) return null;
    _submittingFeedback = true;
    try {
      Map<String, dynamic> data;
      if (feedback is String) {
        data = {
          'message': feedback,
          'uid': currentUser?.uid ?? '',
          'student_name': currentUser?.displayName ?? '',
          'createdAt': DateTime.now().toIso8601String(),
          'status': 'pending',
          'viewed': false,
        };
      } else if (feedback is Map<String, dynamic>) {
        data = Map.from(feedback);
        data['createdAt'] ??= DateTime.now().toIso8601String();
        data['viewed'] ??= false;
      } else {
        return null;
      }
      final docId = 'fb_${DateTime.now().millisecondsSinceEpoch}';
      final ticketNo = docId.substring(0, 6).toUpperCase();
      final mirrorData = Map<String, dynamic>.from(data);
      mirrorData['ticketNo'] = ticketNo;
      // Supabase FIRST — check if write succeeded
      final ok = await SupabaseReadService.writeToAll('feedbacks', docId, mirrorData);
      if (!ok) return null;
      final name = currentUser?.displayName ?? 'Unknown';
      await addAdminNotification('feedback', 'New Contact Support message from $name', relatedUid: currentUser?.uid);
      return docId;
    } finally {
      _submittingFeedback = false;
    }
  }

  static Future<List<Map<String, dynamic>>> getStudentFeedbacksOnce(String uid) async {
    try {
      final mirror = await SupabaseReadService.getFeedbacksForUser(uid);
      if (mirror != null) return mirror;
    } catch (_) {}
    return [];
  }

  static Stream<QuerySnapshot> getAllFeedbacks() {
    return SupabaseReadService.streamAllFeedbacks().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Stream<QuerySnapshot> getPendingFeedbacks() {
    return SupabaseReadService.streamPendingFeedbacks().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<int> getPendingFeedbackCount() async {
    try {
      final mirror = await SupabaseReadService.getPendingFeedbackCount();
      if (mirror >= 0) return mirror;
    } catch (_) {}
    return 0;
  }

  static Future<void> updateFeedbackStatus(String id, String status) async {
    Map<String, dynamic>? existing;
    try { existing = await SupabaseReadService.readPrimary('feedbacks', id); } catch (_) {}
    final merged = <String, dynamic>{
      if (existing != null) ...existing,
      'status': status,
    };
    await _mirrorWrite('feedbacks', id, merged);
  }

  static Future<void> updateFeedbackReply(String id, String reply) async {
    Map<String, dynamic>? existing;
    try { existing = await SupabaseReadService.readPrimary('feedbacks', id); } catch (_) {}
    final merged = <String, dynamic>{
      if (existing != null) ...existing,
      'reply': reply,
    };
    await _mirrorWrite('feedbacks', id, merged);
  }

  // ─── Notes ─────────────────────────────────────────────────────────────────────

  static Future<DocumentSnapshot?> getNote(String lectureId) async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) return null;
      final mirror = await SupabaseReadService.getNote(lectureId, uid);
      if (mirror != null) return _MirrorDocumentSnapshot(mirror);
    } catch (e) {
      print('[getNote] Supabase read failed: $e');
    }
    return null;
  }

  static Future<bool> saveNote(String lectureId, String content, {String? lectureName, String? source, String? pdfUrl}) async {
    final uid = currentUser?.uid;
    if (uid == null) return false;
    try {
      final ok = await SupabaseReadService.writeToAll('notes', lectureId, {
        'uid': uid,
        'content': content,
        'lectureName': lectureName ?? '',
        'source': source ?? 'notepad',
        'pdfUrl': pdfUrl ?? '',
        'updatedAt': DateTime.now().toIso8601String(),
      });
      print('[saveNote] writeToAll returned: $ok');
      return ok;
    } catch (e) {
      print('[saveNote] Supabase write failed: $e');
      return false;
    }
  }

  static Future<List<Map<String, dynamic>>> getAllNotes() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    
    for (int i = 0; i < 3; i++) {
      try {
        final mirror = await SupabaseReadService.getNotes(uid);
        if (mirror != null && mirror.isNotEmpty) return mirror;
      } catch (e) {
        print('[getAllNotes] Supabase read attempt ${i + 1} failed: $e');
      }
      if (i < 2) await Future.delayed(const Duration(milliseconds: 300));
    }
    return [];
  }

  static Future<void> deleteNote(String id) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await SupabaseReadService.writeToAll('notes', id, const {}, delete: true);
  }

  static Future<void> renameNote(String id, String newName) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    // Read-merge-write to preserve existing JSONB fields (content, etc.)
    Map<String, dynamic>? existing;
    try { existing = await SupabaseReadService.getNote(id, uid); } catch (_) {}
    final merged = <String, dynamic>{
      if (existing != null) ...existing,
      'uid': uid,
      'lectureName': newName,
      'updatedAt': DateTime.now().toIso8601String(),
    };
    await SupabaseReadService.writeToAll('notes', id, merged);
  }

  // ─── Assistant Access ─────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getAssistantLoginsForFolder(String folderId) {
    return SupabaseReadService.streamAssistantLogins(folderId).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<Map<String, List<String>>> getContentAccess(String uid) async {
    try {
      final map = await SupabaseReadService.getContentAccess(uid);
      if (map.isNotEmpty) return map;
    } catch (_) {}
    return {};
  }

  static Future<void> grantAssistantAccess(String uid, String folderId, String name) async {
    final docId = 'aa_${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('assistant_access', docId, {
      'uid': uid,
      'folderId': folderId,
      'name': name,
      'createdAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<void> revokeAssistantAccess(String uid, String folderId) async {
    await _mirrorBulk('assistant_access', 'delete_filter', filter: {'uid': uid, 'folder_id': folderId});
    await _mirrorBulk('content_assistant_access', 'delete_filter', filter: {'user_id': uid, 'folder_id': folderId});
  }

  static Future<List<Map<String, dynamic>>> getAssistantFolderIds(String uid) async {
    try {
      final mirror = await SupabaseReadService.getAssistantFolderAccess(uid);
      if (mirror != null) {
        return mirror.map((e) => {'id': e['id'], 'folderId': e['folder_id'] ?? e['folderId']}).toList();
      }
    } catch (_) {}
    return [];
  }

  static Future<Set<String>> getUidsWithFolderAccess(String folderId) async {
    try {
      final mirror = await SupabaseReadService.getUidsWithFolderAccess(folderId);
      if (mirror != null) return mirror;
    } catch (_) {}
    return {};
  }

  static Future<Set<String>> getUidsWithContentAccess(String folderId, String contentId) async {
    try {
      final mirror = await SupabaseReadService.getUidsWithContentAccess(contentId, folderId: folderId);
      if (mirror != null) return mirror;
    } catch (_) {}
    return {};
  }

  // ─── Settings ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSettings() async {
    try {
      final mirror = await SupabaseReadService.getSettings('general');
      if (mirror != null) return mirror;
    } catch (_) {}
    return {};
  }

  static Future<void> updateSetting(String key, dynamic value) async {
    SupabaseReadService.invalidateSettingsCache();
    final current = await SupabaseReadService.getSettings('general');
    final data = Map<String, dynamic>.from(current ?? {});
    data[key] = value;
    // ignore: avoid_print
    print('[UPDATE_SETTING] key=$key value=$value writeData.keys=${data.keys.toList()}');

    // 1) Primary write — synchronous, guaranteed to land on one project
    bool writeOk = false;
    try {
      writeOk = await SupabaseReadService.writePrimary('settings', 'general', data);
      // ignore: avoid_print
      print('[UPDATE_SETTING] writePrimary completed success=$writeOk');
    } catch (e) {
      // ignore: avoid_print
      print('[UPDATE_SETTING] writePrimary ERROR: $e');
    }

    // 2) Background sync to remaining projects (fire-and-forget)
    SupabaseReadService.writeToAll('settings', 'general', data);

    SupabaseReadService.invalidateSettingsCache();
    // Verify read-back
    try {
      final verify = await SupabaseReadService.getSettings('general');
      // ignore: avoid_print
      print('[UPDATE_SETTING] verify read: ${verify != null ? "key=$key=${verify[key]}" : "NULL"}');
    } catch (e) {
      // ignore: avoid_print
      print('[UPDATE_SETTING] verify ERROR: $e');
    }
  }

  // ─── AI Conversations ──────────────────────────────────────────────────────────

  static Future<String?> createConversation(String title) async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    final docId = 'conv_${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('conversations', docId, {
      'uid': uid,
      'title': title,
      'updatedAt': DateTime.now().toIso8601String(),
    });
    return docId;
  }

  static Future<List<Map<String, dynamic>>> getConversations() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final mirror = await SupabaseReadService.getConversations(uid);
      if (mirror != null) return mirror;
    } catch (_) {}
    return [];
  }

  static Future<void> addMessage(String convId, String role, String content) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    final msgId = 'msg_${DateTime.now().millisecondsSinceEpoch}';
    await _mirrorWrite('messages', msgId, {
      'conversationId': convId,
      'uid': uid,
      'role': role,
      'content': content,
      'timestamp': DateTime.now().toIso8601String(),
    });
    await _mirrorWrite('conversations', convId, {
      'uid': uid,
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  static Future<List<Map<String, dynamic>>> getMessages(String convId) async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    try {
      final mirror = await SupabaseReadService.getMessages(convId);
      if (mirror != null) return mirror;
    } catch (_) {}
    return [];
  }

  static Future<void> deleteConversation(String convId) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await _mirrorWrite('conversations', convId, {}, delete: true);
  }

  // ─── App Updates ───────────────────────────────────────────────────────────────

  /// The current app version shown in the UI (kept in sync with pubspec.yaml).
  static const String appVersion = '32.1.13';

  static Stream<QuerySnapshot> getAppUpdates() {
    return SupabaseReadService.streamAppUpdates().map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Stream<QuerySnapshot> getLoginHistory(String uid) {
    return SupabaseReadService.streamLoginHistory(uid).map((rows) => _MirrorQuerySnapshot(rows));
  }

  /// Supabase-only single-folder read (returns an adapter snapshot so callers
  /// that expect a [DocumentSnapshot] keep working without a Firestore read).
  static Future<DocumentSnapshot> getFolderDoc(String folderId) async {
    try {
      final mirror = await SupabaseReadService.getFolder(folderId);
      if (mirror != null) return _MirrorDocumentSnapshot(mirror);
    } catch (_) {}
    return _MirrorDocumentSnapshot({'id': folderId});
  }

  static Stream<QuerySnapshot> getContentsStream(String folderId, {String? parentContentId}) {
    return SupabaseReadService.streamContents(folderId, parentContentId: parentContentId)
        .map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Future<Map<String, dynamic>?> getContentDoc(String folderId, String contentId) async {
    try {
      final mirror = await SupabaseReadService.getContent(folderId, contentId);
      if (mirror != null) return mirror;
    } catch (_) {}
    return null;
  }

  static Stream<QuerySnapshot> getLoginAttemptsForUser(String uid) {
    return SupabaseReadService.streamLoginAttemptsForUser(uid).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Stream<QuerySnapshot> getWebSessionsForUser(String uid) {
    return SupabaseReadService.streamWebSessionsForUser(uid).map((rows) => _MirrorQuerySnapshot(rows));
  }

  static Stream<QuerySnapshot> getTargetedNotificationsForUser(String uid) {
    return SupabaseReadService.streamTargetedNotificationsForUser(uid).map((rows) => _MirrorQuerySnapshot(rows));
  }
}

/// Minimal Supabase Storage compat class so existing code using `FirebaseService.storage.ref(...)` works.
class _SupabaseStorageService {
  _SupabaseStorageReference ref(String path) => _SupabaseStorageReference(path);
}class _SupabaseStorageReference {
  final String fullPath;
  _SupabaseStorageReference(this.fullPath);

  _SupabaseStorageReference get ref => this;

  String get name => fullPath.split('/').last;

  String get _bucket => fullPath.contains('/') ? fullPath.split('/').first : 'notices';
  String get _objectPath => fullPath.contains('/') ? fullPath.substring(fullPath.indexOf('/') + 1) : fullPath;

  Future<String> getDownloadURL() async {
    return '${FirebaseService.supabaseUrl}/storage/v1/object/public/$_bucket/$_objectPath';
  }

  Future<void> putFile(dynamic file) async {
    if (kIsWeb) throw UnsupportedError('putFile not supported on web');
    final bytes = await (file as File).readAsBytes();
    await putData(bytes);
  }

  Future<_SupabaseStorageReference> putData(Uint8List data, {fb_storage.SettableMetadata? metadata, void Function(double progress)? onProgress}) async {
    final filename = _objectPath.split('/').last;
    onProgress?.call(0.1);

    if (kIsWeb) {
      if (FirebaseService.supabaseUrl.isEmpty || FirebaseService.serviceRoleKey.isEmpty) {
        await FirebaseService.reinitializeSupabase();
      }
      if (FirebaseService.supabaseUrl.isEmpty || FirebaseService.serviceRoleKey.isEmpty) {
        throw Exception('Supabase not configured. Please check your internet connection and try again.');
      }

      final uri = Uri.parse('${FirebaseService.supabaseUrl}/storage/v1/object/$_bucket/$_objectPath');
      final client = http.Client();
      try {
        final request = http.MultipartRequest('POST', uri);
        request.headers['Authorization'] = 'Bearer ${FirebaseService.serviceRoleKey}';
        request.headers['apikey'] = FirebaseService.serviceRoleKey;
        request.files.add(http.MultipartFile.fromBytes('file', data, filename: filename));
        if (metadata?.contentDisposition != null) {
          request.fields['metadata'] = jsonEncode({'Content-Disposition': metadata!.contentDisposition});
        }
        onProgress?.call(0.3);
        final streamed = await client.send(request).timeout(const Duration(minutes: 10));
        final body = await streamed.stream.bytesToString();
        if (streamed.statusCode >= 400) {
          throw Exception('Supabase upload failed ($fullPath): $body');
        }
        onProgress?.call(1.0);
      } finally {
        client.close();
      }
    } else {
      final uri = Uri.parse('${FirebaseService.supabaseUrl}/storage/v1/object/$_bucket/$_objectPath');
      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer ${FirebaseService.serviceRoleKey}';
      request.files.add(http.MultipartFile.fromBytes('file', data, filename: filename));
      if (metadata?.contentDisposition != null) {
        request.fields['metadata'] = jsonEncode({'Content-Disposition': metadata!.contentDisposition});
      }
      onProgress?.call(0.5);
      final client = http.Client();
      try {
        final streamed = await client.send(request).timeout(const Duration(minutes: 5));
        if (streamed.statusCode >= 400) {
          final body = await streamed.stream.bytesToString();
          throw Exception('Supabase upload failed ($fullPath): $body');
        }
        await streamed.stream.bytesToString();
        onProgress?.call(1.0);
      } finally {
        client.close();
      }
    }
    return this;
  }

  Future<void> delete() async {
    if (kIsWeb) {
      final proxyUri = Uri.parse('/api/upload-file');
      final response = await http.post(
        proxyUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'supabaseUrl': FirebaseService.supabaseUrl,
          'bucket': _bucket,
          'path': _objectPath,
          '_method': 'DELETE',
          'auth': 'Bearer ${FirebaseService.serviceRoleKey}',
        }),
      );
      if (response.statusCode >= 400) {
        throw Exception('Supabase delete failed ($fullPath): ${response.body}');
      }
    } else {
      final uri = Uri.parse('${FirebaseService.supabaseUrl}/storage/v1/object/$_bucket/$_objectPath');
      final request = http.Request('DELETE', uri)
        ..headers['Authorization'] = 'Bearer ${FirebaseService.serviceRoleKey}';
      final streamed = await request.send();
      if (streamed.statusCode >= 400) {
        final body = await streamed.stream.bytesToString();
        throw Exception('Supabase delete failed ($fullPath): $body');
      }
    }
  }
}

class SessionManager {
  static Duration _timeout = const Duration(minutes: 20);
  static String _redirectPath = '/auth/login';
  static Timer? _timer;
  static DateTime? _lastActivity;
  static VoidCallback? onExpired;
  static bool _isPaused = false;
  static bool _isUploading = false;

  static DateTime? get lastActivity => _lastActivity;
  static Duration get timeout => _timeout;

  static void configure({Duration? timeout, String? redirectPath}) {
    if (timeout != null) _timeout = timeout;
    if (redirectPath != null) _redirectPath = redirectPath;
  }

  static String get redirectPath => _redirectPath;

  static void start({VoidCallback? onExpiredCallback}) {
    onExpired = onExpiredCallback;
    _lastActivity = DateTime.now();
    _isPaused = false;
    _isUploading = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  static void reset() {
    _lastActivity = DateTime.now();
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _lastActivity = null;
    _isPaused = false;
    _isUploading = false;
  }

  static void pause() {
    _isPaused = true;
    _timer?.cancel();
    _timer = null;
  }

  static void resume() {
    if (_lastActivity == null || onExpired == null) return;
    final elapsed = DateTime.now().difference(_lastActivity!);
    if (elapsed >= _timeout) {
      stop();
      onExpired?.call();
      return;
    }
    _isPaused = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  static void setUploading(bool uploading) {
    _isUploading = uploading;
    if (uploading) {
      _lastActivity = DateTime.now();
      _timer?.cancel();
      _timer = null;
    } else {
      _lastActivity = DateTime.now();
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
    }
  }

  static void _check() {
    if (_lastActivity == null || _isPaused || _isUploading) return;
    if (DateTime.now().difference(_lastActivity!) >= _timeout) {
      stop();
      onExpired?.call();
    }
  }
}

/// Lightweight [DocumentSnapshot] adapter backed by a mirror (Supabase) row so
/// code that expects a `DocumentSnapshot` can keep working without a Firestore
/// read. Only `id` / `exists` / `data()` are needed by the app's callers.
class _MirrorDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _MirrorDocumentSnapshot(this._data);

  final Map<String, dynamic> _data;

  static const Set<String> _dateKeys = {
    'createdAt', 'updatedAt', 'timestamp', 'startedAt', 'lastLogin',
    'lastActive', 'expiresAt', 'lastMessageAt', 'created_at', 'updated_at',
  };

  /// Mirror rows store dates as ISO strings; callers expect a [Timestamp].
  /// Convert any date-keyed string that parses into a real [Timestamp] so UI
  /// code such as `d['createdAt'] as Timestamp` stops crashing.
  static Map<String, dynamic>? _convertDates(Map<String, dynamic>? src) {
    if (src == null) return null;
    final out = <String, dynamic>{};
    for (final e in src.entries) {
      var v = e.value;
      if (_dateKeys.contains(e.key) && v is String) {
        final dt = DateTime.tryParse(v);
        if (dt != null) v = Timestamp.fromDate(dt);
      }
      out[e.key] = v;
    }
    return out;
  }

  @override
  String get id => _data['id'] as String? ?? '';

  @override
  DocumentReference<Map<String, dynamic>> get reference =>
      throw UnsupportedError('reference not available on mirror snapshot');

  @override
  SnapshotMetadata get metadata => throw UnsupportedError('metadata not available on mirror snapshot');

  @override
  bool get exists => true;

  @override
  Map<String, dynamic>? data() => _convertDates(_data);

  @override
  dynamic get(Object field) => _data[field];

  @override
  dynamic operator [](Object field) => _data[field];
}

/// [QueryDocumentSnapshot] adapter for mirror rows.
class _MirrorQueryDocumentSnapshot extends _MirrorDocumentSnapshot
    implements QueryDocumentSnapshot<Map<String, dynamic>> {
  _MirrorQueryDocumentSnapshot(super.data);

  @override
  bool get exists => true;

  @override
  Map<String, dynamic> data() => _MirrorDocumentSnapshot._convertDates(_data) ?? _data;
}

/// [QuerySnapshot] adapter so existing `StreamBuilder<QuerySnapshot>` widgets
/// keep working against mirror (Supabase) rows without any UI changes.
class _MirrorQuerySnapshot implements QuerySnapshot<Map<String, dynamic>> {
  _MirrorQuerySnapshot(this._rows);

  final List<Map<String, dynamic>> _rows;

  @override
  List<QueryDocumentSnapshot<Map<String, dynamic>>> get docs =>
      _rows.map((r) => _MirrorQueryDocumentSnapshot(r)).toList();

  @override
  List<DocumentChange<Map<String, dynamic>>> get docChanges {
    // Polls re-emit full lists; flag rows created within the last 30s as
    // "added" so the admin feedback-notification logic keeps working.
    final now = DateTime.now();
    return [
      for (var i = 0; i < _rows.length; i++)
        if (_isRecent(_rows[i]['createdAt'] ?? _rows[i]['created_at'], now))
          _MirrorDocumentChange(
            type: DocumentChangeType.added,
            oldIndex: -1,
            newIndex: i,
            doc: _MirrorQueryDocumentSnapshot(_rows[i]),
          ),
    ];
  }

  @override
  SnapshotMetadata get metadata =>
      throw UnsupportedError('metadata not available on mirror snapshot');

  @override
  int get size => _rows.length;

  static bool _isRecent(dynamic value, DateTime now) {
    final d = _mirrorToDate(value);
    return d != null && now.difference(d).inSeconds < 30;
  }
}

class _MirrorDocumentChange implements DocumentChange<Map<String, dynamic>> {
  _MirrorDocumentChange({
    required this.type,
    required this.oldIndex,
    required this.newIndex,
    required this.doc,
  });

  @override
  final DocumentChangeType type;

  @override
  final int oldIndex;

  @override
  final int newIndex;

  @override
  final DocumentSnapshot<Map<String, dynamic>> doc;
}

/// Parses a mirror date (ISO string, [Timestamp], or [DateTime]) to [DateTime].
DateTime? _mirrorToDate(dynamic value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is Timestamp) return value.toDate();
  if (value is String) {
    try {
      return DateTime.parse(value).toLocal();
    } catch (_) {
      return null;
    }
  }
  return null;
}
