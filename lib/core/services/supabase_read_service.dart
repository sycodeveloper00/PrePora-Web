import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Dedicated READ-ONLY mirror for Firestore data hosted on a separate Supabase
/// project. This layer bypasses the Firestore free-tier read quota entirely:
/// reads that used to hit Firestore now hit this Supabase via its anon key.
///
/// STORAGE is untouched — the existing Storage-Settings Supabase accounts and
/// `Supabase.instance.client` keep working exactly as before.
///
/// The mirror is populated by dual-writes (Firestore + Supabase) and by the
/// backfill script. If the mirror has no data yet, callers fall back to
/// Firestore as before.
class SupabaseReadService {
  SupabaseReadService._();

  static const String _baseUrl = 'https://qluwnxsmnxvvqoiejtbr.supabase.co';
  static const String _anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFsdXdueHNtbnh2dnFvaWVqdGJyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcwMDAzNTEsImV4cCI6MjEwMjU3NjM1MX0.lYGxH02Kb0qS2Lm46Mc5lQoOyd7VR1-6WWSBA2TXfr8';

  static bool _enabled = true;

  static const Map<String, String> _headers = {
    'apikey': _anonKey,
    'Authorization': 'Bearer $_anonKey',
    'Content-Type': 'application/json',
  };

  static Uri _uri(String table, [String? query]) =>
      Uri.parse('$_baseUrl/rest/v1/$table${query != null ? '?$query' : ''}');

  /// Generic row query. Returns null on error/empty so callers can fall back.
  static Future<List<Map<String, dynamic>>?> _query(String table, [String? query]) async {
    if (!_enabled) return null;
    try {
      final res = await http
          .get(_uri(table, query), headers: _headers)
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return null;
      final rows = json.decode(res.body) as List<dynamic>;
      return rows.cast<Map<String, dynamic>>();
    } catch (_) {
      return null;
    }
  }

  /// Polls a mirror query every [interval], emitting the rows as
  /// `{ 'id': id, ...data }` maps. Emits an empty list when the mirror errors.
  /// Only emits when the data actually changed, so StreamBuilders don't rebuild
  /// on every poll tick.
  static Stream<List<Map<String, dynamic>>> _poll(
    String table,
    String? query, {
    Duration interval = const Duration(seconds: 10),
  }) async* {
    String? lastKey;
    while (true) {
      final rows = await _query(table, query);
      final list = (rows ?? const []).map((r) => _flatten(r)).toList();
      final key = json.encode(list);
      if (key != lastKey) {
        lastKey = key;
        yield list;
      }
      await Future.delayed(interval);
    }
  }

  /// Merges a row's `data` jsonb column (if present) with its scalar columns.
  static Map<String, dynamic> _flatten(Map<String, dynamic> r) {
    final data = (r['data'] as Map<String, dynamic>?) ?? const <String, dynamic>{};
    final flat = <String, dynamic>{'id': r['id']};
    flat.addAll(data);
    for (final entry in r.entries) {
      if (entry.key == 'id' || entry.key == 'data') continue;
      if (entry.value != null) flat[entry.key] = entry.value;
    }
    return flat;
  }

  static const String _sel = 'select=id,data,*';

  // ─── users ────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUser(String uid) async {
    final rows = await _query('users', 'id=eq.$uid&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  static Future<List<Map<String, dynamic>>?> getUsersByRole(String role) async {
    final rows = await _query('users', 'role=eq.$role&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getUsersWhere(String filter) async {
    final rows = await _query('users', '$filter&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamUsersByRole(
    String role, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('users', 'role=eq.$role&$_sel', interval: interval);
  }

  // ─── settings ─────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getSettings(String id) async {
    final rows = await _query('settings', 'id=eq.$id&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  // ─── supabase accounts (mirrored into the settings table) ────────────────

  /// Returns the active global Supabase storage account. `supabase_accounts`
  /// rows are mirrored into `settings` with id `supabase_account:<docId>`.
  static Future<Map<String, dynamic>?> getActiveSupabaseAccount() async {
    final rows = await _query('settings', 'id=like.supabase_account.%&$_sel');
    if (rows == null || rows.isEmpty) return null;
    for (final r in rows) {
      final flat = _flatten(r);
      if (flat['isActive'] == true) return flat;
    }
    return null;
  }

  /// Returns the active assistant-specific storage account (mirrored into
  /// `settings` with id `assistant_supabase:<docId>`).
  static Future<Map<String, dynamic>?> getActiveAssistantSupabaseAccount(String assistantUid) async {
    final rows = await _query('settings', 'id=like.assistant_supabase.%&$_sel');
    if (rows == null || rows.isEmpty) return null;
    for (final r in rows) {
      final flat = _flatten(r);
      if (flat['assistantUid'] == assistantUid && flat['isActive'] == true) return flat;
    }
    return null;
  }

  // ─── folders ──────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamFolders({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('folders', '$_sel&order=created_at.asc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamContents(
    String folderId, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('contents', 'folder_id=eq.$folderId&$_sel', interval: interval);
  }

  static Future<Map<String, dynamic>?> getFolder(String folderId) async {
    final rows = await _query('folders', 'id=eq.$folderId&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  static Future<Map<String, dynamic>?> getContent(String folderId, String contentId) async {
    final rows = await _query('contents', 'id=eq.$contentId&folder_id=eq.$folderId&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  // ─── notices ──────────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamNotices({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('notices', '$_sel&order=created_at.desc', interval: interval);
  }

  // ─── notifications ────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamNotifications(
    String uid,
    DateTime since, {
    Duration interval = const Duration(seconds: 10),
  }) {
    final iso = since.toUtc().toIso8601String();
    return _poll('notifications', 'uid=eq.$uid&created_at=gte.$iso&$_sel&order=created_at.desc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamAdminNotifications({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('admin_notifications', '$_sel&order=created_at.desc', interval: interval);
  }

  static Future<int> getAdminUnreadCount() async {
    final rows = await _query('admin_notifications', 'read=eq.false&select=id');
    if (rows == null) return -1;
    return rows.length;
  }

  // ─── feedbacks ────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getFeedbacksForUser(String uid) async {
    final rows = await _query('feedbacks', 'uid=eq.$uid&$_sel&order=created_at.desc');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamAllFeedbacks({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('feedbacks', '$_sel&order=created_at.desc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamPendingFeedbacks({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('feedbacks', 'status=eq.pending&$_sel&order=created_at.desc', interval: interval);
  }

  static Future<int> getPendingFeedbackCount() async {
    final rows = await _query('feedbacks', 'status=eq.pending&select=id');
    if (rows == null) return -1;
    return rows.length;
  }

  // ─── student activities ───────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamStudentActivities(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('student_activities', 'uid=eq.$uid&$_sel', interval: interval);
  }

  // ─── assistant access ─────────────────────────────────────────────────────

  static Future<Set<String>?> getUidsWithFolderAccess(String folderId) async {
    final rows = await _query('assistant_access', 'folder_id=eq.$folderId&select=uid');
    if (rows == null) return null;
    return rows.map((r) => (r['uid'] as String?) ?? '').where((u) => u.isNotEmpty).toSet();
  }

  static Future<List<Map<String, dynamic>>?> getAssistantFolderAccess(String uid) async {
    final rows = await _query('assistant_access', 'uid=eq.$uid&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<Map<String, List<String>>> getContentAccess(String uid) async {
    final rows = await _query('content_assistant_access', 'user_id=eq.$uid&select=folder_id,content_id');
    if (rows == null) return const {};
    final map = <String, List<String>>{};
    for (final r in rows) {
      final folderId = r['folder_id'] as String? ?? 'unknown';
      final contentId = r['content_id'] as String?;
      if (contentId != null) {
        map.putIfAbsent(folderId, () => []).add(contentId);
      }
    }
    return map;
  }

  static Future<Set<String>?> getUidsWithContentAccess(String folderId, String contentId) async {
    final rows = await _query(
        'content_assistant_access', 'folder_id=eq.$folderId&content_id=eq.$contentId&select=user_id');
    if (rows == null) return null;
    return rows.map((r) => (r['user_id'] as String?) ?? '').where((u) => u.isNotEmpty).toSet();
  }

  static Stream<List<Map<String, dynamic>>> streamAssistantLogins(
    String folderId, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('assistant_logins', 'folder_id=eq.$folderId&$_sel&order=timestamp.desc', interval: interval);
  }

  // ─── conversations / messages / notes ─────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getConversations(String uid) async {
    final rows = await _query('conversations', 'uid=eq.$uid&$_sel&order=updated_at.desc');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getMessages(String convId) async {
    final rows = await _query('messages', 'conversation_id=eq.$convId&$_sel&order=timestamp.asc');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getNotes(String uid) async {
    final rows = await _query('notes', 'uid=eq.$uid&$_sel&order=updated_at.desc');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<Map<String, dynamic>?> getNote(String uid, String lectureId) async {
    final rows = await _query('notes', 'id=eq.$lectureId&uid=eq.$uid&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  // ─── AI keys ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getActiveAiApiKey() async {
    final rows = await _query('ai_api_keys', 'is_active=eq.true&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  static Future<List<Map<String, dynamic>>?> getAiApiKeys() async {
    final rows = await _query('ai_api_keys', '$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  // ─── app updates / web sessions / login history ───────────────────────────

  static Stream<List<Map<String, dynamic>>> streamAppUpdates({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('app_updates', '$_sel&order=created_at.desc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamWebSessions({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('web_sessions', '$_sel&order=created_at.desc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamLoginAttempts({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('login_attempts', '$_sel&order=created_at.desc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamNotificationsAdmin({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('notifications', '$_sel&order=created_at.desc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamLoginHistory(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('login_history', 'uid=eq.$uid&$_sel&order=timestamp.desc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamLoginAttemptsForUser(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('login_attempts', 'uid=eq.$uid&$_sel&order=timestamp.desc&limit=100', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamWebSessionsForUser(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('web_sessions', 'uid=eq.$uid&$_sel&order=created_at.desc&limit=50', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamTargetedNotificationsForUser(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('notifications', 'uid=eq.$uid&type=eq.targeted&$_sel', interval: interval);
  }

  // ─── web session (QR link flow) ───────────────────────────────────────────

  static Future<Map<String, dynamic>?> getWebSession(String sessionId) async {
    final rows = await _query('web_sessions', 'id=eq.$sessionId&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  /// A user's connected web sessions (mirror) for the disconnect flow.
  static Future<List<Map<String, dynamic>>?> getConnectedSessions(String uid) async {
    final rows = await _query('web_sessions', 'uid=eq.$uid&status=eq.connected&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  /// Polls a single web session every few seconds so the web app detects an
  /// Android-side disconnect quickly — without a live Firestore listener
  /// (which burns the read quota).
  static Stream<Map<String, dynamic>?> streamWebSession(
    String sessionId, {
    Duration interval = const Duration(seconds: 5),
  }) async* {
    String? lastKey;
    while (true) {
      final rows = await _query('web_sessions', 'id=eq.$sessionId&limit=1&$_sel');
      final flat = (rows == null || rows.isEmpty) ? null : _flatten(rows.first);
      final key = json.encode(flat);
      if (key != lastKey) {
        lastKey = key;
        yield flat;
      }
      await Future.delayed(interval);
    }
  }

  /// Toggle the mirror on/off (used if the mirror ever needs disabling).
  static void setEnabled(bool value) => _enabled = value;
}
