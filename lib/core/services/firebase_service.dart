import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart' as fb_storage;
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthenticatedClient;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../firebase_options.dart';

class FirebaseService {
  static final FirebaseService _instance = FirebaseService._();
  FirebaseService._();

  static bool _initialized = false;
  static String? _cachedDeviceId;

  static const String supabaseUrl = 'https://zynfizrocesynbaguhtj.supabase.co';
  static const String serviceRoleKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5bmZpenJvY2VzeW5iYWd1aHRqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4MzY3MjkzOSwiZXhwIjoyMDk5MjQ4OTM5fQ.CdfQUkM_-O9lYZ8MIcJh8H1n_-SHIWUuwI8DE5HGdZU';

  /// Downloads a file from Supabase Storage using the REST API with service role auth.
  /// [bucketPath] format: "bucket_name/path/to/file"
  static Future<Uint8List> downloadSupabaseFile(String bucketPath) async {
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

  static FirebaseFirestore get firestore => FirebaseFirestore.instance;

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
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    await Supabase.initialize(
      url: 'https://zynfizrocesynbaguhtj.supabase.co',
      anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inp5bmZpenJvY2VzeW5iYWd1aHRqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM2NzI5MzksImV4cCI6MjA5OTI0ODkzOX0.uA8lHGv1Q7ax5WjGY5x5tFo9hxYDNhHzqOAO-Z0-fOo',
    );
    _initialized = true;
  }

  // ─── Auth ──────────────────────────────────────────────────────────────────────

  static Future<fb_auth.UserCredential?> signIn(String email, String password) async {
    try {
      final cred = await fb_auth.FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      if (cred.user != null) {
        final userDoc = await firestore.collection('users').doc(cred.user!.uid).get();
        final userData = userDoc.data() as Map<String, dynamic>?;
        final userRole = userData?['role'] as String?;
        if (userData?['blocked'] == true) {
          if (userRole == 'admin' || userRole == 'Assistant') {
            await firestore.collection('users').doc(cred.user!.uid).update({'blocked': false});
          } else {
            await fb_auth.FirebaseAuth.instance.signOut();
            throw Exception('BLOCKED');
          }
        }
        await storeSession(cred.user!.uid);
        final deviceId = await getDeviceId();
        await _trackLogin(cred.user!.uid, deviceId);
        await _updateStreak(cred.user!.uid);
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
  }) async {
    try {
      final cred = await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      final uid = cred.user!.uid;
      await storeSession(uid);
      await firestore.collection('users').doc(uid).set({
        'uid': uid,
        'name': name,
        'email': email.trim(),
        'role': role,
        'blocked': false,
        'verified': role == 'admin',
        'createdAt': FieldValue.serverTimestamp(),
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
      final userDoc = await firestore.collection('users').doc(user.uid).get();
      final role = (userDoc.data() as Map<String, dynamic>?)?['role'] as String?;
      final label = role == 'admin' ? 'Admin' : (role == 'Assistant' ? 'Assistant' : 'Student');
      await addAdminNotification('logout', '$label logged out: ${user.email}', relatedUid: user.uid);
    }
    await fb_auth.FirebaseAuth.instance.signOut();
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
      final doc = await firestore.collection('users').doc(uid).get();
      return doc.data()?['role'] as String?;
    } catch (_) {
      return null;
    }
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
      return await firestore.collection('users').doc(uid).get();
    } catch (_) {
      return null;
    }
  }

  static Future<String> getUserDisplayName(String uid) async {
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      return (doc.data() as Map<String, dynamic>?)?['name'] as String? ?? 'User';
    } catch (_) {
      return 'User';
    }
  }

  static Future<bool> isStudentBlocked(String uid) async {
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      return (doc.data() as Map<String, dynamic>?)?['blocked'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> isStudentVerified(String uid) async {
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      return (doc.data() as Map<String, dynamic>?)?['verified'] == true;
    } catch (_) {
      return false;
    }
  }

  static Future<void> toggleStudentBlocked(String uid, bool blocked) async {
    await firestore.collection('users').doc(uid).update({'blocked': blocked});
    if (blocked) {
      final snap = await firestore.collection('users').doc(uid).get();
      final email = (snap.data() as Map<String, dynamic>?)?['email'] as String? ?? uid;
      await addAdminNotification('blocked', 'Student account blocked: $email', relatedUid: uid);
    }
  }

  static Future<void> toggleStudentVerified(String uid, bool verified) async {
    await firestore.collection('users').doc(uid).update({'verified': verified});
  }

  static Future<List<Map<String, dynamic>>> getAllStudents() async {
    final snap = await firestore.collection('users').where('role', isEqualTo: 'student').get();
    return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
  }

  static Stream<QuerySnapshot> getAllAssistant() {
    return firestore.collection('users').where('role', isEqualTo: 'Assistant').snapshots();
  }

  static Future<void> deleteAssistantAccount(String uid) async {
    await firestore.collection('users').doc(uid).delete();
  }

  static Future<void> deleteUserFromAuth(String uid) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('deleteUser')
          .call({'uid': uid});
    } catch (e) {
      await firestore.collection('users').doc(uid).delete();
    }
  }

  static Future<void> deleteStudentCompletely(String uid) async {
    final feedbacks = await firestore.collection('feedbacks').where('uid', isEqualTo: uid).get();
    final batch = firestore.batch();
    for (final d in feedbacks.docs) { batch.delete(d.reference); }
    batch.delete(firestore.collection('users').doc(uid));
    await batch.commit();
    await deleteUserFromAuth(uid);
  }

  static Future<Map<String, String>?> createAssistantAccount(String name) async {
    final sanitizedName = name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '').replaceAll(RegExp(r'\s+'), '');
    final emailPrefix = sanitizedName.isNotEmpty ? sanitizedName : 'Assistant';
    final displayEmail = '$emailPrefix@Assistant.prepora';
    final password = 'Assistant123';
    try {
      final cred = await fb_auth.FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: displayEmail,
        password: password,
      );
      await cred.user?.updateDisplayName(name);
      await firestore.collection('users').doc(cred.user!.uid).set({
        'name': name,
        'email': displayEmail,
        'role': 'Assistant',
        'createdAt': FieldValue.serverTimestamp(),
      });
      await firestore.collection('Assistant_access').add({
        'uid': cred.user!.uid,
        'name': name,
        'createdAt': FieldValue.serverTimestamp(),
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

  // ─── Folders ───────────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getAllFolders() {
    return firestore.collection('folders').orderBy('createdAt', descending: false).snapshots();
  }

  static Future<String?> createRootFolder({required String name, String? icon, String? color}) async {
    final doc = await firestore.collection('folders').add({
      'name': name,
      'icon': icon ?? 'folder',
      'color': color ?? '#4A148C',
      'item_count': 0,
      'locked': false,
      'invisible': false,
      'updating': false,
      'group_link': null,
      'sort_order': 0,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  static Future<void> renameRootFolder(String folderId, String name) async {
    await firestore.collection('folders').doc(folderId).update({'name': name});
  }

  static Future<void> deleteRootFolder(String folderId) async {
    final contents = await firestore.collection('folders').doc(folderId).collection('contents').get();
    for (final c in contents.docs) {
      await c.reference.delete();
    }
    await firestore.collection('folders').doc(folderId).delete();
  }

  static Future<void> deleteFolder(String folderId) async {
    await deleteRootFolder(folderId);
  }

  static Future<void> toggleFolderLock(String folderId, String field, dynamic value) async {
    await firestore.collection('folders').doc(folderId).update({field: value});
  }

  /// Async: check content-level group_link first, fall back to root folder doc.
  /// Respects [inheritGroup] flag: if false on the content doc, skip folder fallback.
  static Future<String?> getGroupLinkForLevel(String folderId, {String? parentContentId}) async {
    if (parentContentId != null && parentContentId != 'root') {
      final contentDoc = await firestore.collection('folders').doc(folderId).collection('contents').doc(parentContentId).get();
      if (contentDoc.exists) {
        final data = contentDoc.data() as Map<String, dynamic>?;
        final link = data?['group_link'] as String?;
        final inherit = data?['inherit_group'] as bool? ?? true;
        if (link != null && link.isNotEmpty) return link;
        if (!inherit) return null;
      }
    }
    final folderDoc = await firestore.collection('folders').doc(folderId).get();
    if (folderDoc.exists) {
      final data = folderDoc.data() as Map<String, dynamic>?;
      final link = data?['group_link'] as String?;
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
      await firestore.collection('folders').doc(folderId).collection('contents').doc(parentContentId).update({
        'group_link': link,
        'inherit_group': inheritGroup,
      });
      if (inheritGroup) {
        await _propagateAllDescendants(folderId, parentContentId, link, true);
      }
    } else {
      await firestore.collection('folders').doc(folderId).update({
        'group_link': link,
        'inherit_group': inheritGroup,
      });
      if (inheritGroup) {
        await _propagateAllDescendants(folderId, null, link, true);
      }
    }
  }

  static Future<void> removeGroupLink(String folderId, {String? parentContentId}) async {
    if (parentContentId != null && parentContentId != 'root') {
      final doc = await firestore.collection('folders').doc(folderId).collection('contents').doc(parentContentId).get();
      final inherit = (doc.data() as Map<String, dynamic>?)?['inherit_group'] as bool? ?? true;
      await firestore.collection('folders').doc(folderId).collection('contents').doc(parentContentId).update({
        'group_link': null,
        'inherit_group': true,
      });
      if (inherit) {
        await _propagateAllDescendants(folderId, parentContentId, null, true);
      }
    } else {
      final folderDoc = await firestore.collection('folders').doc(folderId).get();
      final inherit = (folderDoc.data() as Map<String, dynamic>?)?['inherit_group'] as bool? ?? true;
      await firestore.collection('folders').doc(folderId).update({
        'group_link': null,
        'inherit_group': true,
      });
      if (inherit) {
        await _propagateAllDescendants(folderId, null, null, true);
      }
    }
  }

  static Future<void> _propagateAllDescendants(String folderId, String? startParentId, String? link, bool inheritGroup) async {
    final allDocs = await firestore
        .collection('folders').doc(folderId)
        .collection('contents')
        .get();
    if (allDocs.docs.isEmpty) return;
    final docMap = <String, Map<String, dynamic>>{};
    final parentMap = <String?, List<String>>{};
    for (final doc in allDocs.docs) {
      docMap[doc.id] = doc.data();
      final pid = doc.data()['parentContentId'] as String?;
      parentMap.putIfAbsent(pid, () => []).add(doc.id);
    }
    final toUpdate = <String>{};
    void collectDescendants(String id) {
      final children = parentMap[id];
      if (children == null) return;
      for (final childId in children) {
        if (toUpdate.add(childId)) {
          collectDescendants(childId);
        }
      }
    }
    if (startParentId == null) {
      for (final entry in parentMap.entries) {
        if (entry.key != null) {
          for (final childId in entry.value) {
            if (toUpdate.add(childId)) {
              collectDescendants(childId);
            }
          }
        }
      }
    } else {
      collectDescendants(startParentId);
    }
    if (toUpdate.isEmpty) return;
    final batch = firestore.batch();
    for (final id in toUpdate) {
      batch.update(
        firestore.collection('folders').doc(folderId).collection('contents').doc(id),
        {'group_link': link, 'inherit_group': inheritGroup},
      );
    }
    await batch.commit();
  }

  // ─── Folder Contents ───────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getContentsForFolder(String folderId) {
    return firestore
        .collection('folders')
        .doc(folderId)
        .collection('contents')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  static Future<String?> addFolderContent(String folderId, Map<String, dynamic> data) async {
    final doc = await firestore.collection('folders').doc(folderId).collection('contents').add({
      'createdAt': FieldValue.serverTimestamp(),
      ...data,
    });
    await firestore.collection('folders').doc(folderId).update({'item_count': FieldValue.increment(1)});
    return doc.id;
  }

  static Future<void> renameFolderContent(String folderId, String contentId, String name) async {
    await firestore.collection('folders').doc(folderId).collection('contents').doc(contentId).update({'name': name});
  }

  static Future<void> deleteFolderContent(String folderId, String contentId) async {
    await firestore.collection('folders').doc(folderId).collection('contents').doc(contentId).delete();
    await firestore.collection('folders').doc(folderId).update({'item_count': FieldValue.increment(-1)});
  }

  static Future<void> updateContentField(String folderId, String contentId, String field, dynamic value) async {
    await firestore.collection('folders').doc(folderId).collection('contents').doc(contentId).update({field: value});
  }

  static Future<void> grantContentAccess(String uid, String folderId, String contentId, String name) async {
    await firestore.collection('content_Assistant_access').add({
      'content_id': contentId,
      'folder_id': folderId,
      'user_id': uid,
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> revokeContentAccess(String uid, String folderId, String contentId) async {
    final snap = await firestore
        .collection('content_Assistant_access')
        .where('content_id', isEqualTo: contentId)
        .where('user_id', isEqualTo: uid)
        .get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
  }

  // ─── Notices ────────────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getNotices() {
    return firestore.collection('notices').orderBy('createdAt', descending: true).snapshots();
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
      final doc = await firestore.collection('notices').add({
        'title': title,
        'fileUrl': supabaseUrl,
        'fileType': fileType,
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    } catch (e) {
      // Fallback: just save the text notice without file
      final doc = await firestore.collection('notices').add({
        'title': title,
        'fileUrl': null,
        'fileType': 'text',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return doc.id;
    }
  }

  // ─── Notifications ─────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getNotificationsForUser(String uid, DateTime since) {
    return firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .where('createdAt', isGreaterThanOrEqualTo: since)
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  static Future<void> markStudentNotificationsRead(String uid) async {
    final snap = await firestore
        .collection('notifications')
        .where('uid', isEqualTo: uid)
        .get();
    final batch = firestore.batch();
    for (final d in snap.docs) {
      final data = d.data();
      if (data['read'] == false) {
        batch.update(d.reference, {'read': true});
      }
    }
    await batch.commit();
  }

  // ─── Admin Notifications ───────────────────────────────────────────────────────

  static Future<void> addAdminNotification(String type, String message, {String? relatedUid}) async {
    await firestore.collection('admin_notifications').add({
      'type': type,
      'message': message,
      'relatedUid': relatedUid,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Stream<QuerySnapshot> getAdminNotifications() {
    return firestore.collection('admin_notifications').orderBy('createdAt', descending: true).snapshots();
  }

  static Future<int> getAdminUnreadCount() async {
    final snap = await firestore.collection('admin_notifications').where('read', isEqualTo: false).get();
    return snap.docs.length;
  }

  static Future<void> markAdminNotificationsRead() async {
    final snap = await firestore.collection('admin_notifications').where('read', isEqualTo: false).get();
    final batch = firestore.batch();
    for (final d in snap.docs) {
      batch.update(d.reference, {'read': true});
    }
    await batch.commit();
  }

  static Future<void> clearAdminNotifications() async {
    final snap = await firestore.collection('admin_notifications').get();
    final batch = firestore.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }

  // ─── Login Tracking & Auto-Block ──────────────────────────────────────────────

  static Future<void> _trackLogin(String uid, String deviceId) async {
    final userDoc = await firestore.collection('users').doc(uid).get();
    final role = (userDoc.data() as Map<String, dynamic>?)?['role'] as String?;
    if (role == 'admin' || role == 'Assistant') return;
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(hours: 24));
    String deviceModel = 'Unknown';
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceModel = '${androidInfo.brand} ${androidInfo.model} (Android ${androidInfo.version.release})';
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceModel = '${iosInfo.model} (iOS ${iosInfo.systemVersion})';
      } else if (Platform.isWindows) {
        final windowsInfo = await deviceInfo.windowsInfo;
        deviceModel = 'Windows ${windowsInfo.buildNumber}';
      } else if (Platform.isMacOS) {
        final macInfo = await deviceInfo.macOsInfo;
        deviceModel = 'macOS ${macInfo.osRelease}';
      } else if (Platform.isLinux) {
        final linuxInfo = await deviceInfo.linuxInfo;
        deviceModel = 'Linux ${linuxInfo.name}';
      } else {
        deviceModel = 'Web Browser';
      }
    } catch (_) {}
    await firestore.collection('login_attempts').add({
      'uid': uid,
      'deviceId': deviceId,
      'deviceModel': deviceModel,
      'timestamp': now.toIso8601String(),
    });
    final all = await firestore.collection('login_attempts')
        .where('uid', isEqualTo: uid)
        .get();
    final recent = all.docs.where((d) {
      final ts = (d.data()['timestamp'] as String?) ?? '';
      return ts.compareTo(yesterday.toIso8601String()) >= 0;
    }).toList();
    final totalAttempts = recent.length;
    final uniqueDevices = recent.map((d) => d.data()['deviceId'] as String? ?? 'unknown').toSet().toList();
    final isMultiDevice = uniqueDevices.length > 1;
    final shouldBlock = (isMultiDevice && totalAttempts > 3) || (!isMultiDevice && totalAttempts > 6);
    if (!shouldBlock) return;
    final userData = userDoc.data() as Map<String, dynamic>?;
    if (userData?['verified'] != true) {
      await addAdminNotification('registration', 'Account not verified: ${userData?['email'] ?? uid}', relatedUid: uid);
    } else {
      await toggleStudentBlocked(uid, true);
    }
  }

  static Future<void> _updateStreak(String uid) async {
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      if (!doc.exists) return;
      final data = doc.data() as Map<String, dynamic>;
      final lastActive = data['lastActiveDate'] as String?;
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      if (lastActive == todayStr) return;

      int streak = data['streakCount'] as int? ?? 0;
      final yesterday = today.subtract(const Duration(days: 1));
      final yesterdayStr = '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';

      if (lastActive == yesterdayStr) {
        streak += 1;
      } else {
        streak = 1;
      }
      final totalDays = data['totalActiveDays'] as int? ?? 0;
      await firestore.collection('users').doc(uid).update({
        'lastActiveDate': todayStr,
        'streakCount': streak,
        'totalActiveDays': totalDays + 1,
      });
    } catch (_) {}
  }

  static Future<Map<String, dynamic>> getStreak(String uid) async {
    try {
      final doc = await firestore.collection('users').doc(uid).get();
      if (!doc.exists) return {'streakCount': 0, 'totalActiveDays': 0};
      final data = doc.data() as Map<String, dynamic>;
      return {
        'streakCount': data['streakCount'] as int? ?? 0,
        'totalActiveDays': data['totalActiveDays'] as int? ?? 0,
        'lastActiveDate': data['lastActiveDate'] as String? ?? '',
      };
    } catch (_) {
      return {'streakCount': 0, 'totalActiveDays': 0};
    }
  }

  static Future<String?> addNotification(String message, {String? folderId, Map<String, dynamic>? contentData}) async {
    if (contentData != null) {
      final locked = contentData['locked'] as bool? ?? false;
      final updating = contentData['updating'] as bool? ?? false;
      final invisible = contentData['invisible'] as bool? ?? false;
      if (locked || updating || invisible) return null;
    }
    if (folderId != null) {
      final folderDoc = await firestore.collection('folders').doc(folderId).get();
      if (folderDoc.exists) {
        final folderData = folderDoc.data() as Map<String, dynamic>?;
        if (folderData != null) {
          final folderLocked = folderData['locked'] as bool? ?? false;
          final folderInvisible = folderData['invisible'] as bool? ?? false;
          if (folderLocked || folderInvisible) return null;
        }
      }
    }
    final users = await firestore.collection('users').get();
    final batch = firestore.batch();
    for (final u in users.docs) {
      final ref = firestore.collection('notifications').doc();
      batch.set(ref, {
        'uid': u.id,
        'message': message,
        'folderId': folderId,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'type': folderId != null ? 'folder_update' : 'general',
      });
    }
    await batch.commit();
    return 'batch';
  }

  static Future<String?> addTargetedNotification(String uid, String message) async {
    final doc = await firestore.collection('notifications').add({
      'uid': uid,
      'message': message,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
      'type': 'targeted',
    });
    return doc.id;
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
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'pending',
          'viewed': false,
        };
      } else if (feedback is Map<String, dynamic>) {
        data = Map.from(feedback);
        data['createdAt'] ??= FieldValue.serverTimestamp();
        data['viewed'] ??= false;
      } else {
        return null;
      }
      final doc = await firestore.collection('feedbacks').add(data);
      final ticketNo = doc.id.substring(0, 6).toUpperCase();
      await doc.update({'ticketNo': ticketNo});
      final name = currentUser?.displayName ?? 'Unknown';
      await addAdminNotification('feedback', 'New Contact Support message from $name', relatedUid: currentUser?.uid);
      return doc.id;
    } finally {
      _submittingFeedback = false;
    }
  }

  static Future<List<Map<String, dynamic>>> getStudentFeedbacksOnce(String uid) async {
    final snap = await firestore
        .collection('feedbacks')
        .where('uid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .get();
    return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
  }

  static Stream<QuerySnapshot> getAllFeedbacks() {
    return firestore.collection('feedbacks').orderBy('createdAt', descending: true).snapshots();
  }

  static Future<int> getPendingFeedbackCount() async {
    final snap = await firestore.collection('feedbacks').where('status', isEqualTo: 'pending').get();
    return snap.docs.length;
  }

  static Future<void> updateFeedbackStatus(String id, String status) async {
    await firestore.collection('feedbacks').doc(id).update({'status': status});
  }

  static Future<void> updateFeedbackReply(String id, String reply) async {
    await firestore.collection('feedbacks').doc(id).update({'reply': reply});
  }

  // ─── Notes ─────────────────────────────────────────────────────────────────────

  static Future<DocumentSnapshot?> getNote(String lectureId) async {
    try {
      final uid = currentUser?.uid;
      if (uid == null) return null;
      return await firestore.collection('users').doc(uid).collection('notes').doc(lectureId).get();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveNote(String lectureId, String content, {String? lectureName}) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await firestore.collection('users').doc(uid).collection('notes').doc(lectureId).set({
      'content': content,
      'lectureName': lectureName ?? '',
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<List<Map<String, dynamic>>> getAllNotes() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('notes')
        .orderBy('updatedAt', descending: true)
        .get();
    return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
  }

  static Future<void> deleteNote(String id) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await firestore.collection('users').doc(uid).collection('notes').doc(id).delete();
  }

  static Future<void> renameNote(String id, String newName) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await firestore.collection('users').doc(uid).collection('notes').doc(id).update({'lectureName': newName});
  }

  // ─── Assistant Access ─────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getAssistantLoginsForFolder(String folderId) {
    return firestore
        .collection('Assistant_logins')
        .where('folderId', isEqualTo: folderId)
        .orderBy('timestamp', descending: true)
        .snapshots();
  }

  static Future<Map<String, List<String>>> getContentAccess(String uid) async {
    final snap = await firestore
        .collection('content_Assistant_access')
        .where('user_id', isEqualTo: uid)
        .get();
    final map = <String, List<String>>{};
    for (final d in snap.docs) {
      final data = d.data();
      final folderId = data['folder_id'] as String? ?? 'unknown';
      final contentId = data['content_id'] as String?;
      if (contentId != null) {
        map.putIfAbsent(folderId, () => []).add(contentId);
      }
    }
    return map;
  }

  static Future<void> grantAssistantAccess(String uid, String folderId, String name) async {
    await firestore.collection('Assistant_access').add({
      'uid': uid,
      'folderId': folderId,
      'name': name,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> revokeAssistantAccess(String uid, String folderId) async {
    final snap = await firestore
        .collection('Assistant_access')
        .where('uid', isEqualTo: uid)
        .where('folderId', isEqualTo: folderId)
        .get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
  }

  static Future<List<Map<String, dynamic>>> getAssistantFolderIds(String uid) async {
    final snap = await firestore
        .collection('Assistant_access')
        .where('uid', isEqualTo: uid)
        .get();
    return snap.docs.map((e) => {'id': e.id, 'folderId': e.data()['folderId']}).toList();
  }

  // ─── Settings ──────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> getSettings() async {
    final snap = await firestore.collection('settings').doc('general').get();
    return snap.data() ?? {};
  }

  static Future<void> updateSetting(String key, dynamic value) async {
    await firestore.collection('settings').doc('general').set({key: value}, SetOptions(merge: true));
  }

  // ─── AI Conversations ──────────────────────────────────────────────────────────

  static Future<String?> createConversation(String title) async {
    final uid = currentUser?.uid;
    if (uid == null) return null;
    final doc = await firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .add({'title': title, 'updatedAt': FieldValue.serverTimestamp()});
    return doc.id;
  }

  static Future<List<Map<String, dynamic>>> getConversations() async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .orderBy('updatedAt', descending: true)
        .get();
    return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
  }

  static Future<void> addMessage(String convId, String role, String content) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    final msgRef = firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(convId)
        .collection('messages');
    await msgRef.add({
      'role': role,
      'content': content,
      'timestamp': FieldValue.serverTimestamp(),
    });
    await firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(convId)
        .update({'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<List<Map<String, dynamic>>> getMessages(String convId) async {
    final uid = currentUser?.uid;
    if (uid == null) return [];
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('conversations')
        .doc(convId)
        .collection('messages')
        .orderBy('timestamp', descending: false)
        .get();
    return snap.docs.map((e) => {'id': e.id, ...e.data()}).toList();
  }

  static Future<void> deleteConversation(String convId) async {
    final uid = currentUser?.uid;
    if (uid == null) return;
    await firestore.collection('users').doc(uid).collection('conversations').doc(convId).delete();
  }

  // ─── App Updates ───────────────────────────────────────────────────────────────

  static Stream<QuerySnapshot> getAppUpdates() {
    return firestore.collection('app_updates').orderBy('createdAt', descending: true).snapshots();
  }
}

/// Minimal Supabase Storage compat class so existing code using `FirebaseService.storage.ref(...)` works.
class _SupabaseStorageService {
  _SupabaseStorageReference ref(String path) => _SupabaseStorageReference(path);
}

class _SupabaseStorageReference {
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

  Future<_SupabaseStorageReference> putData(Uint8List data, {fb_storage.SettableMetadata? metadata}) async {
    final uri = Uri.parse('${FirebaseService.supabaseUrl}/storage/v1/object/$_bucket/$_objectPath');
    final request = http.MultipartRequest('POST', uri)
      ..headers['Authorization'] = 'Bearer ${FirebaseService.serviceRoleKey}'
      ..files.add(http.MultipartFile.fromBytes('file', data, filename: _objectPath.split('/').last));
    if (metadata?.contentDisposition != null) {
      request.fields['metadata'] = jsonEncode({'Content-Disposition': metadata!.contentDisposition});
    }
    final client = http.Client();
    try {
      final response = await client.send(request).timeout(const Duration(minutes: 5));
      if (response.statusCode >= 400) {
        final body = await response.stream.bytesToString();
        throw Exception('Supabase upload failed ($fullPath): $body');
      }
    } finally {
      client.close();
    }
    return this;
  }

  Future<void> delete() async {
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
