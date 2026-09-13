import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Offline-aware caching service for Flutter web.
///
/// Rule: Online → always hit network (fresh data) → save to cache.
///       Offline → return stale cache.
class OfflineCacheService {
  static const _prefix = 'oc_';
  static const _tsPrefix = 'oct_';

  /// Check if device is online (web: navigator.onLine).
  static bool get isOnline {
    if (!kIsWeb) return true;
    try {
      return _checkOnlineWeb();
    } catch (_) {
      return true;
    }
  }

  // This will be called from dart:html — see _initOnlineCheck below
  static bool Function()? _onlineChecker;

  static bool _checkOnlineWeb() {
    if (_onlineChecker != null) return _onlineChecker!();
    return true;
  }

  /// Initialize with dart:html online checker (call once from main.dart).
  static void initOnlineCheck(bool Function() checker) {
    _onlineChecker = checker;
  }

  // ── Core read/write ────────────────────────────────────────────────

  static Future<void> put(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode(data));
      await prefs.setInt('$_tsPrefix$key', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<Map<String, dynamic>?> getStale(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<void> putList(String key, List<Map<String, dynamic>> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('$_prefix$key', jsonEncode(data));
      await prefs.setInt('$_tsPrefix$key', DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  static Future<List<Map<String, dynamic>>?> getListStale(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefix$key');
      if (raw == null) return null;
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  static Future<void> remove(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefix$key');
      await prefs.remove('$_tsPrefix$key');
    } catch (_) {}
  }

  // ── Convenience: save to cache ──────────────────────────────────

  static Future<void> cacheUser(String uid, Map<String, dynamic> userData) =>
      put('user_$uid', userData);

  static Future<void> cacheSettings(String id, Map<String, dynamic> settings) =>
      put('settings_$id', settings);

  static Future<void> cacheFolders(String projectId, List<Map<String, dynamic>> folders) =>
      putList('folders_$projectId', folders);

  static Future<void> cacheContents(String folderId, List<Map<String, dynamic>> contents) =>
      putList('contents_$folderId', contents);

  // ── Convenience: get stale (offline fallback) ───────────────────

  static Future<Map<String, dynamic>?> getCachedUser(String uid) =>
      getStale('user_$uid');

  static Future<Map<String, dynamic>?> getCachedSettings(String id) =>
      getStale('settings_$id');

  static Future<List<Map<String, dynamic>>?> getCachedFolders(String projectId) =>
      getListStale('folders_$projectId');

  static Future<List<Map<String, dynamic>>?> getCachedContents(String folderId) =>
      getListStale('contents_$folderId');

  // ── Network-first with offline fallback ─────────────────────────

  /// [fetcher] always runs when online. If offline or network fails, returns stale cache.
  static Future<Map<String, dynamic>?> networkFirst(
    String cacheKey,
    Future<Map<String, dynamic>> Function() fetcher,
  ) async {
    if (isOnline) {
      try {
        final data = await fetcher();
        await put(cacheKey, data);
        return data;
      } catch (_) {
        // Network error — fall through to stale
      }
    }
    return await getStale(cacheKey);
  }

  static Future<List<Map<String, dynamic>>?> networkFirstList(
    String cacheKey,
    Future<List<Map<String, dynamic>>> Function() fetcher,
  ) async {
    if (isOnline) {
      try {
        final data = await fetcher();
        await putList(cacheKey, data);
        return data;
      } catch (_) {}
    }
    return await getListStale(cacheKey);
  }

  static Future<void> clearAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (_) {}
  }
}
