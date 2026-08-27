import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// TTL in-memory cache for non-user data (settings, folders, etc.)
class _TtlCache {
  final Duration ttl;
  final Map<String, _CacheEntry> _store = {};

  _TtlCache({this.ttl = const Duration(seconds: 30)});

  Map<String, dynamic>? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (DateTime.now().isAfter(entry.expiredAt)) {
      _store.remove(key);
      return null;
    }
    return entry.value;
  }

  void set(String key, Map<String, dynamic> value) {
    _store[key] = _CacheEntry(
      value: value,
      expiredAt: DateTime.now().add(ttl),
    );
  }

  void invalidate(String key) => _store.remove(key);
  void invalidateAll() => _store.clear();
}

class _CacheEntry {
  final Map<String, dynamic> value;
  final DateTime expiredAt;
  _CacheEntry({required this.value, required this.expiredAt});
}

/// Multi-project Supabase mirror with automatic failover.
///
/// Projects rotate when egress limit is hit or errors occur.
/// All 4 projects share the same schema — writes go to ALL, reads try
/// primary first then fall back to backups.
class SupabaseReadService {
  SupabaseReadService._();

  /// TTL cache for settings, folders, and other rarely-changing data
  static final _cache = _TtlCache(ttl: const Duration(seconds: 30));

  // ─── Project Config ────────────────────────────────────────────────────
  // Primary 1 (old) — resets 18 Sep 2026
  // Primary 2 — fresh
  // Backup 1 — fresh
  // Backup 2 — fresh

  // Failover order: P2 -> P3 -> P4 -> B1 -> B3 -> B4 -> P1 -> B2
  static const List<Map<String, String>> _projects = [
    {
      'name': 'Primary 2',
      'role': 'primary',
      'url': 'https://brqdxhqrsfxlvwgstuto.supabase.co',
      'anon': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJycWR4aHFyc2Z4bHZ3Z3N0dXRvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxNTY4MzMsImV4cCI6MjEwMjczMjgzM30.4djM6rSuAw3DFkKosHpYwkRKonHez9Y7TM0CTpoA6-o',
      'service': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImJycWR4aHFyc2Z4bHZ3Z3N0dXRvIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzE1NjgzMywiZXhwIjoyMTAyNzMyODMzfQ.gPkiuNGYAP_pJR1uSbAQWc25SyhmpwwgspJeFInXgWE',
    },
    {
      'name': 'Primary 3',
      'role': 'primary',
      'url': 'https://avzdjlwswulewgbciwyj.supabase.co',
      'anon': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF2emRqbHdzd3VsZXdnYmNpd3lqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcyMTA3MzEsImV4cCI6MjEwMjc4NjczMX0.YJpulLn6OFjD1iC3U87ElxUTQMhYHZNnEaQdS6wkTdg',
      'service': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImF2emRqbHdzd3VsZXdnYmNpd3lqIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzIxMDczMSwiZXhwIjoyMTAyNzg2NzMxfQ.xlnVp4yWL9Ptv0Y54aeXvFYN1MwTN5rI22Dy_0G7X-M',
    },
    {
      'name': 'Primary 4',
      'role': 'primary',
      'url': 'https://dneeqtkyyovsrbefbeyg.supabase.co',
      'anon': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRuZWVxdGt5eW92c3JiZWZiZXlnIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODczMzExMzQsImV4cCI6MjEwMjkwNzEzNH0.kZjtsXGOP0sTXLvSxsQjSbRNSny_91PYnBj0D3MhkTM',
      'service': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRuZWVxdGt5eW92c3JiZWZiZXlnIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzMzMTEzNCwiZXhwIjoyMTAyOTA3MTM0fQ.W9WJiBkwamdYlM124dUR8FwttYb503opPs4WaB2c2Ug',
    },
    {
      'name': 'Backup 1',
      'role': 'backup',
      'url': 'https://efxftqrdnlzqzyofcbxh.supabase.co',
      'anon': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmeGZ0cXJkbmx6cXp5b2ZjYnhoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODcxNTgwMjAsImV4cCI6MjEwMjczNDAyMH0.VOvLMUdrM3j9Fm1FucZfkMblZbHJxKbeMfcYCl-VPVQ',
      'service': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVmeGZ0cXJkbmx6cXp5b2ZjYnhoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzE1ODAyMCwiZXhwIjoyMTAyNzM0MDIwfQ._jFEeHO31gkVxnJQ3u-WCCFwSzkSttTYAVNQsnM857A',
    },
    {
      'name': 'Backup 3',
      'role': 'backup',
      'url': 'https://vllcbapmyldujxmqlrlu.supabase.co',
      'anon': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZsbGNiYXBteWxkdWp4bXFscmx1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODczMzExNjUsImV4cCI6MjEwMjkwNzE2NX0.gp5rEyAvcCSdx3tvX7v5L6-Ap38YNsY1x1Lpgcq7hZ0',
      'service': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZsbGNiYXBteWxkdWp4bXFscmx1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzMzMTE2NSwiZXhwIjoyMTAyOTA3MTY1fQ.yS6m34LpmhqKRTtw_Pew0y5SUHqoDD-6eZRrDNZdimc',
    },
    {
      'name': 'Backup 4',
      'role': 'backup',
      'url': 'https://ilbchsmxhtqeeqbljoyq.supabase.co',
      'anon': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlsYmNoc214aHRxZWVxYmxqb3lxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODczMzc4MjYsImV4cCI6MjEwMjkxMzgyNn0.VGP9NF7of8whCqLPBaYE1BRZTrHnXNv-irt470B3V7Y',
      'service': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlsYmNoc214aHRxZWVxYmxqb3lxIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzMzNzgyNiwiZXhwIjoyMTAyOTEzODI2fQ.aJ0Bcaw9MMbd8M1voaZjbKumlL2RjHHFcg_MbG5YHXk',
    },
    {
      'name': 'Primary 1',
      'role': 'primary',
      'url': 'https://rqedljcelpbkocsdbbyu.supabase.co',
      'anon': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJxZWRsamNlbHBia29jc2RiYnl1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1NTk3OTMsImV4cCI6MjEwMzEzNTc5M30.EZ3i4W9Bp0ja3Tsnqfbw2mq6qkRMC5lkLhyQLaK2zTs',
      'service': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJxZWRsamNlbHBia29jc2RiYnl1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzU1OTc5MywiZXhwIjoyMTAzMTM1NzkzfQ.b-yNIn1MJhzUYxTP_m94_AqpmAAUJXO63AMrSnBS54E',
    },
    {
      'name': 'Backup 2',
      'role': 'backup',
      'url': 'https://jlltinlyrcycofibztmk.supabase.co',
      'anon': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpsbHRpbmx5cmN5Y29maWJ6dG1rIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODc1NTkzMDgsImV4cCI6MjEwMzEzNTMwOH0.CZmWU4l7KYTcEfVJ7BWMXZXTj8u4d681KGxbDEb-7Fg',
      'service': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImpsbHRpbmx5cmN5Y29maWJ6dG1rIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4NzU1OTMwOCwiZXhwIjoyMTAzMTM1MzA4fQ.LK7X3bADuHS65_7rp1PY3YVq0RKmfnPu2ROEqqLlNfo',
    },
  ];

  static bool _enabled = true;

  /// Index of the currently active project (starts at 0 = Primary 2)
  static int _activeIndex = 0;

  /// Track consecutive failures per project to auto-skip
  static final List<int> _failCounts = List.filled(_projects.length, 0);

  /// Max failures before skipping to next project
  static const int _maxFailures = 3;

  /// Failover callback for admin notifications
  static Function(String projectName, String role, String error)? onFailover;

  /// Get the active project config
  static Map<String, String> get _active => _projects[_activeIndex];

  /// Get all project names + their status
  static List<Map<String, String>> get projectStatus {
    return List.generate(_projects.length, (i) {
      return {
        'name': _projects[i]['name']!,
        'role': _projects[i]['role']!,
        'active': i == _activeIndex ? 'true' : 'false',
        'failures': _failCounts[i].toString(),
      };
    });
  }

  /// Current active project name for UI display
  static String get activeProjectName => _active['name']!;

  // ─── Core Query with Failover ──────────────────────────────────────────

  static Uri _uri(String baseUrl, String anonKey, String table, [String? query]) =>
      Uri.parse('$baseUrl/rest/v1/$table${query != null ? '?$query' : ''}');

  static const int _pageSize = 5000;
  static const String _sel = 'select=id,data,*';

  /// Try a query against a specific project
  static Future<http.Response?> _tryQuery(
    String url, String anonKey, String table, String? query,
  ) async {
    try {
      if (query != null && query.contains('limit=')) {
        final res = await http
            .get(_uri(url, anonKey, table, query), headers: {
              'apikey': anonKey,
              'Authorization': 'Bearer $anonKey',
              'Content-Type': 'application/json',
            })
            .timeout(const Duration(seconds: 5));
        return (res.statusCode == 200 || res.statusCode == 206) ? res : null;
      }

      // Paginated query
      final all = <dynamic>[];
      var offset = 0;
      while (true) {
        final res = await http
            .get(_uri(url, anonKey, table, query), headers: {
              'apikey': anonKey,
              'Authorization': 'Bearer $anonKey',
              'Content-Type': 'application/json',
              'Prefer': 'count=exact',
              'Range': '$offset-${offset + _pageSize - 1}',
            })
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200 && res.statusCode != 206) return null;
        final rows = json.decode(res.body) as List<dynamic>;
        all.addAll(rows);
        final cr = res.headers['content-range'];
        int? total;
        if (cr != null) {
          final slash = cr.lastIndexOf('/');
          final t = slash != -1 ? cr.substring(slash + 1) : null;
          total = (t != null && t != '*') ? int.tryParse(t) : null;
        }
        if (rows.isEmpty || total == null || offset + rows.length >= total) break;
        offset += rows.length;
      }
      // Return a synthetic Response with the combined data
      return http.Response(json.encode(all), 200);
    } catch (_) {
      return null;
    }
  }

  // ─── Failover cooldown ──────────────────────────────────────────────────
  static DateTime? _lastFailoverTime;
  static String? _lastFailoverKey;
  static const Duration _failoverCooldown = Duration(minutes: 5);

  /// Query with automatic failover across projects.
  /// Starts from _activeIndex. Only failovers on ACTUAL failures (timeout/error),
  /// NOT on empty results. Empty = healthy project, just no data for that query.
  static Future<List<Map<String, dynamic>>?> _query(String table, [String? query]) async {
    if (!_enabled) return null;

    // Ensure query always has limit= to use simple path (avoids CORS preflight
    // issues with Range/Prefer headers in browser). Use 5000 to handle deep
    // hierarchies while staying on simple path.
    String q = query ?? '';
    if (!q.contains('limit=')) {
      q += q.isEmpty ? 'limit=5000' : '&limit=5000';
    }

    // Build try order: start from _activeIndex, then failover chain
    final tryOrder = <int>[];
    for (int attempt = 0; attempt < _projects.length; attempt++) {
      final idx = (_activeIndex + attempt) % _projects.length;
      tryOrder.add(idx);
    }

    List<Map<String, dynamic>>? bestResult;
    int consecutiveFailures = 0;

    for (final idx in tryOrder) {
      final p = _projects[idx];
      final res = await _tryQuery(p['url']!, p['anon']!, table, q);

      if (res != null && res.statusCode == 200) {
        final rows = json.decode(res.body) as List<dynamic>;
        final casted = rows.cast<Map<String, dynamic>>();

        if (casted.isNotEmpty) {
          if (_failCounts[idx] > 0) _failCounts[idx] = 0;
          consecutiveFailures = 0;
          return casted;
        }

        // Empty result — project is healthy, just no data. Continue to next project.
        bestResult ??= casted;
        consecutiveFailures = 0;
        continue;
      }

      // Actual failure (timeout/error/non-200) — only failover from the active project
      _failCounts[idx]++;
      consecutiveFailures++;

      // Give up after 3 consecutive project failures to avoid long startup hangs
      if (consecutiveFailures >= 3 && bestResult != null) break;

      if (idx == _activeIndex && _failCounts[idx] >= _maxFailures) {
        final nextIdx = (idx + 1) % _projects.length;
        final oldName = p['name']!;
        final oldRole = p['role']!;
        final newName = _projects[nextIdx]['name']!;
        final failKey = '$oldName->$newName';

        // Cooldown: don't notify again within 5 minutes for the same transition
        final now = DateTime.now();
        final canNotify = _lastFailoverKey != failKey ||
            _lastFailoverTime == null ||
            now.difference(_lastFailoverTime!) > _failoverCooldown;

        _activeIndex = nextIdx;
        _lastFailoverTime = now;
        _lastFailoverKey = failKey;

        if (canNotify) {
          onFailover?.call(
            oldName, oldRole,
            'Egress/error limit reached — switched to $newName',
          );
        }
      }
    }

    // All projects returned empty or failed — return bestResult (may be empty)
    return bestResult;
  }

  /// Polls a mirror query every [interval], emitting the rows as
  /// `{ 'id': id, ...data }` maps. On transient failure, preserves last known data.
  static Stream<List<Map<String, dynamic>>> _poll(
    String table,
    String? query, {
    Duration interval = const Duration(seconds: 10),
  }) async* {
    String? lastKey;
    List<Map<String, dynamic>> lastList = const [];
    while (true) {
      final rows = await _query(table, query);
      if (rows != null) {
        final list = rows.map((r) => _flatten(r)).toList();
        final key = json.encode(list);
        if (key != lastKey) {
          lastKey = key;
          lastList = list;
          yield list;
        }
      } else {
        // Transient failure — preserve last known data instead of yielding empty
        // Only re-emit if we previously had data (first poll still yields empty)
        if (lastList.isNotEmpty) {
          // Don't yield — keep showing previous data
        } else {
          yield const [];
        }
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

  // ─── Typed columns per table (for writes that must also set columns) ──
  // Only columns that ACTUALLY exist as typed columns in the DB schema.
  // Fields like 'order', 'title', 'viewed', 'session_id' etc. live ONLY
  // inside the data JSONB and must NOT be listed here — sending them as
  // typed columns causes the entire UPSERT to fail with PGRST204.
  static const Map<String, List<String>> _typedColumns = {
    'users': ['role', 'email', 'name', 'blocked', 'verified', 'free_trial_active', 'free_trial_ends_at', 'last_login'],
    'folders': ['name', 'invisible', 'restrict_chat'],
    'contents': ['folder_id', 'parent_content_id', 'name', 'type', 'url', 'group_link'],
    'web_sessions': ['uid', 'status', 'last_active', 'web_browser'],
    'login_attempts': ['uid', 'device_id', 'device_model', 'timestamp'],
    'notifications': ['uid', 'read', 'message', 'type'],
    'admin_notifications': ['read', 'message', 'type', 'created_at'],
    'notices': ['title', 'file_type', 'added_by'],
    'feedbacks': ['uid', 'status', 'message', 'reply'],
    'settings': [],
    'app_updates': ['version', 'link'],
    'student_activities': ['uid', 'started_at'],
    'assistant_access': ['uid', 'folder_id'],
    'content_assistant_access': ['user_id', 'folder_id', 'content_id'],
    'assistant_logins': ['folder_id', 'uid', 'name', 'timestamp'],
    'login_history': ['uid', 'device', 'ip', 'timestamp'],
    'ai_api_keys': ['api_key', 'base_url', 'model', 'provider', 'is_active'],
    'notes': ['uid', 'content', 'lecture_name', 'updated_at'],
    'conversations': ['uid', 'title', 'last_message', 'updated_at'],
    'messages': ['conversation_id', 'role', 'content', 'timestamp'],
  };

  /// Maps common camelCase callers send to snake_case DB columns
  static const Map<String, String> _columnAlias = {
    'createdAt': 'created_at',
    'updatedAt': 'updated_at',
    'deviceId': 'device_id',
    'deviceModel': 'device_model',
    'startedAt': 'started_at',
    'folderId': 'folder_id',
    'parentContentId': 'parent_content_id',
    'youtubeUrl': 'youtube_url',
    'groupLink': 'group_link',
    'inheritGroup': 'inherit_group',
    'sortOrder': 'sort_order',
    'itemCount': 'item_count',
    'fileType': 'file_type',
    'addedBy': 'added_by',
    'freeTrialActive': 'free_trial_active',
    'freeTrialEndsAt': 'free_trial_ends_at',
    'lastActiveDate': 'last_active_date',
    'streakCount': 'streak_count',
    'totalActiveDays': 'total_active_days',
    'lastLogin': 'last_login',
    'streakBest': 'streak_best',
    'webBrowser': 'web_browser',
    'userEmail': 'user_email',
    'userRole': 'user_role',
    'androidDeviceId': 'android_device_id',
    'disconnectedAt': 'disconnected_at',
    'userId': 'user_id',
    'contentId': 'content_id',
    'apiKey': 'api_key',
    'baseUrl': 'base_url',
    'isActive': 'is_active',
    'accountTitle': 'account_title',
    'accountNo': 'account_no',
    'bankName': 'bank_name',
    'lectureName': 'lecture_name',
    'lastMessage': 'last_message',
    'conversationId': 'conversation_id',
  };

  /// Build the upsert body: id + data JSONB + matching typed columns
  static Map<String, dynamic> _buildBody(String table, String id, Map<String, dynamic> data) {
    final typed = _typedColumns[table] ?? const [];
    final body = <String, dynamic>{'id': id, 'data': data};
    for (final entry in data.entries) {
      final snakeKey = _columnAlias[entry.key] ?? entry.key;
      if (typed.contains(snakeKey)) {
        body[snakeKey] = entry.value;
      }
    }
    return body;
  }

  // ─── Service Role Query (for writes to ALL projects) ───────────────────

  /// Sanitize a value for JSON encoding — converts Timestamp/DateTime/etc.
  /// to ISO strings so json.encode doesn't throw.
  static dynamic _sanitize(dynamic v) {
    if (v == null || v is num || v is String || v is bool) return v;
    if (v is DateTime) return v.toIso8601String();
    // cloud_firestore Timestamp — has .toDate()
    try {
      if (v.runtimeType.toString() == 'Timestamp') {
        final dt = (v as dynamic).toDate() as DateTime;
        return dt.toIso8601String();
      }
    } catch (_) {}
    if (v is Map) return v.map((k, val) => MapEntry(k, _sanitize(val)));
    if (v is List) return v.map(_sanitize).toList();
    return v.toString();
  }

  /// Execute a write against ALL projects using service role key.
  /// Returns true if at least one succeeded.
  static Future<bool> _writeAll(String table, String id, Map<String, dynamic> data, {bool delete = false}) async {
    bool anySuccess = false;
    final futures = <Future>[];
    for (final p in _projects) {
      futures.add(Future(() async {
        try {
          if (delete) {
            final encodedId = Uri.encodeComponent(id);
            final url = '${p['url']!}/rest/v1/$table?id=eq.$encodedId';
            final res = await http.delete(Uri.parse(url), headers: {
              'apikey': p['service']!,
              'Authorization': 'Bearer ${p['service']!}',
              'Prefer': 'return=minimal',
            }).timeout(const Duration(seconds: 10));
            // ignore: avoid_print
            print('[WRITE_ALL] DELETE ${p['name']} $table/$id status=${res.statusCode}');
            if (res.statusCode < 300) anySuccess = true;
          } else {
            final headers = {
              'apikey': p['service']!,
              'Authorization': 'Bearer ${p['service']!}',
              'Content-Type': 'application/json',
              'Prefer': 'resolution=merge-duplicates,return=minimal',
            };
            final body = _buildBody(table, id, data);
            final sanitized = _sanitize(body);
            final res = await http.post(
              Uri.parse('${p['url']!}/rest/v1/$table'),
              headers: headers,
              body: json.encode(sanitized),
            ).timeout(const Duration(seconds: 10));
            // ignore: avoid_print
            print('[WRITE_ALL] UPSERT ${p['name']} $table/$id status=${res.statusCode} body=${json.encode(sanitized).length}chars${res.statusCode >= 400 ? " err=${res.body.substring(0, res.body.length.clamp(0, 200))}" : ""}');
            if (res.statusCode < 300) anySuccess = true;
          }
        } catch (e) {
          // ignore: avoid_print
          print('[WRITE_ALL] CATCH ${p['name']} $table/$id error=$e');
        }
      }));
    }
    await Future.wait(futures);
    // ignore: avoid_print
    print('[WRITE_ALL] DONE $table/$id anySuccess=$anySuccess');
    return anySuccess;
  }

  /// Write to ALL projects (called by firebase_service._mirrorWrite)
  static Future<bool> writeToAll(String table, String id, Map<String, dynamic> data, {bool delete = false}) async {
    return await _writeAll(table, id, data, delete: delete);
  }

  /// Write to the primary project only and return whether it succeeded.
  /// Used by updateSetting/updateAiApiKey for reliable single-project writes.
  static Future<bool> writePrimary(String table, String id, Map<String, dynamic> data, {bool delete = false}) async {
    final p = _projects.first;
    try {
      if (delete) {
        final encodedId = Uri.encodeComponent(id);
        final url = '${p['url']!}/rest/v1/$table?id=eq.$encodedId';
        final res = await http.delete(Uri.parse(url), headers: {
          'apikey': p['service']!,
          'Authorization': 'Bearer ${p['service']!}',
          'Prefer': 'return=minimal',
        }).timeout(const Duration(seconds: 10));
        return res.statusCode < 300;
      } else {
        final headers = {
          'apikey': p['service']!,
          'Authorization': 'Bearer ${p['service']!}',
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates,return=representation',
        };
        final body = _buildBody(table, id, data);
        final res = await http.post(
          Uri.parse('${p['url']!}/rest/v1/$table'),
          headers: headers,
          body: json.encode(body),
        ).timeout(const Duration(seconds: 10));
        return res.statusCode < 300;
      }
    } catch (_) {
      return false;
    }
  }

  /// Read from the primary project only using service role key (bypasses RLS).
  static Future<Map<String, dynamic>?> readPrimary(String table, String id) async {
    final p = _projects.first;
    try {
      final res = await http
          .get(_uri(p['url']!, p['service']!, table, 'id=eq.$id&limit=1&$_sel'), headers: {
            'apikey': p['service']!,
            'Authorization': 'Bearer ${p['service']!}',
            'Content-Type': 'application/json',
          })
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final rows = json.decode(res.body) as List<dynamic>;
      if (rows.isEmpty) return null;
      return _flatten(rows.first);
    } catch (_) {
      return null;
    }
  }

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
    // Check TTL cache first
    final cached = _cache.get('settings:$id');
    if (cached != null) return cached;
    final rows = await _query('settings', 'id=eq.$id&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    final flat = _flatten(rows.first);
    _cache.set('settings:$id', flat);
    return flat;
  }

  /// Invalidate settings cache so next read fetches fresh data.
  static void invalidateSettingsCache() => _cache.invalidateAll();

  // ─── supabase accounts (mirrored into the settings table) ────────────────

  static Future<Map<String, dynamic>?> getActiveSupabaseAccount() async {
    final rows = await _query('settings', 'id=like.supabase_account:%&$_sel');
    if (rows == null || rows.isEmpty) return null;
    for (final r in rows) {
      final flat = _flatten(r);
      if (flat['isActive'] == true) return flat;
    }
    return null;
  }

  static Future<Map<String, dynamic>?> getActiveAssistantSupabaseAccount(String assistantUid) async {
    final rows = await _query('settings', 'id=like.assistant_supabase:%&$_sel');
    if (rows == null || rows.isEmpty) return null;
    for (final r in rows) {
      final flat = _flatten(r);
      if (flat['assistantUid'] == assistantUid && flat['isActive'] == true) return flat;
    }
    return null;
  }

  // ─── folders ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getFolders() async {
    final rows = await _query('folders', '$_sel&order=created_at.asc');
    if (rows == null) return null;
    final list = rows.map(_flatten).toList();
    list.sort((a, b) {
      final ao = a['sortOrder'] as int?;
      final bo = b['sortOrder'] as int?;
      if (ao != null && bo != null) return ao.compareTo(bo);
      if (ao != null) return -1;
      if (bo != null) return 1;
      return 0;
    });
    return list;
  }

  static Stream<List<Map<String, dynamic>>> streamFolders({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('folders', '$_sel&order=created_at.asc', interval: interval).map((list) {
      list.sort((a, b) {
        final ao = a['sortOrder'] as int?;
        final bo = b['sortOrder'] as int?;
        if (ao != null && bo != null) return ao.compareTo(bo);
        if (ao != null) return -1;
        if (bo != null) return 1;
        return 0;
      });
      return list;
    });
  }

  static Future<Map<String, dynamic>?> getFolder(String id) async {
    final rows = await _query('folders', 'id=eq.$id&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  // ─── contents ─────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getFolderContents(
    String folderId, {
    String? parentContentId,
    bool fetchAll = false,
  }) async {
    var q = 'folder_id=eq.$folderId&$_sel&order=created_at.asc';
    if (!fetchAll) {
      if (parentContentId != null) {
        q += '&parent_content_id=eq.$parentContentId';
      } else {
        q += '&parent_content_id=is.null';
      }
    }
    final rows = await _query('contents', q);
    if (rows == null) return null;
    final list = rows.map(_flatten).toList();
    list.sort((a, b) {
      final ao = a['order'] as int?;
      final bo = b['order'] as int?;
      if (ao != null && bo != null) return ao.compareTo(bo);
      if (ao != null) return -1;
      if (bo != null) return 1;
      final ac = a['createdAt'] as String? ?? '';
      final bc = b['createdAt'] as String? ?? '';
      return ac.compareTo(bc);
    });
    return list;
  }

  static Stream<List<Map<String, dynamic>>> streamContents(
    String folderId, {
    String? parentContentId,
    Duration interval = const Duration(seconds: 10),
  }) {
    var q = 'folder_id=eq.$folderId&$_sel&order=created_at.asc';
    if (parentContentId != null) {
      q += '&parent_content_id=eq.$parentContentId';
    } else {
      q += '&parent_content_id=is.null';
    }
    return _poll('contents', q, interval: interval).map((list) {
      list.sort((a, b) {
        final ao = a['order'] as int?;
        final bo = b['order'] as int?;
        if (ao != null && bo != null) return ao.compareTo(bo);
        if (ao != null) return -1;
        if (bo != null) return 1;
        final ac = a['createdAt'] as String? ?? '';
        final bc = b['createdAt'] as String? ?? '';
        return ac.compareTo(bc);
      });
      return list;
    });
  }

  static Future<Map<String, dynamic>?> getContent(String folderId, String contentId) async {
    final rows = await _query('contents', 'folder_id=eq.$folderId&id=eq.$contentId&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  // ─── notices ──────────────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getNotices() async {
    final rows = await _query('notices', '$_sel&order=created_at.desc');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
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

  static Future<List<Map<String, dynamic>>?> getAllFeedbacks() async {
    final rows = await _query('feedbacks', '$_sel&order=id.desc');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamPendingFeedbacks({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('feedbacks', 'status=eq.pending&$_sel&order=id.desc', interval: interval);
  }

  static Future<List<Map<String, dynamic>>?> getFeedbacksForUser(String uid) async {
    final rows = await _query('feedbacks', 'uid=eq.$uid&$_sel&order=id.desc');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  // ─── student_activities ───────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamStudentActivities(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('student_activities', 'uid=eq.$uid&$_sel', interval: interval);
  }

  static Future<List<Map<String, dynamic>>?> getStudentActivities(String uid) async {
    final rows = await _query('student_activities', 'uid=eq.$uid&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  // ─── assistant_access ─────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getAssistantFolderAccess(String uid) async {
    final rows = await _query('assistant_access', 'uid=eq.$uid&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<Set<String>> getAssistantFolderIds(String folderId) async {
    final rows = await _query('assistant_access', 'folder_id=eq.$folderId&select=uid');
    if (rows == null) return {};
    return rows.map((r) => r['uid'] as String? ?? '').where((u) => u.isNotEmpty).toSet();
  }

  // ─── content_assistant_access ─────────────────────────────────────────────

  static Future<Set<String>> getUidsWithFolderAccess(String folderId) async {
    final rows = await _query('content_assistant_access', 'folder_id=eq.$folderId&select=user_id');
    if (rows == null) return {};
    return rows.map((r) => r['user_id'] as String? ?? '').where((u) => u.isNotEmpty).toSet();
  }

  static Future<Set<String>> getUidsWithContentAccess(String contentId, {String? folderId}) async {
    var q = 'content_id=eq.$contentId&select=user_id';
    if (folderId != null) q = 'folder_id=eq.$folderId&content_id=eq.$contentId&select=user_id';
    final rows = await _query('content_assistant_access', q);
    if (rows == null) return {};
    return rows.map((r) => r['user_id'] as String? ?? '').where((u) => u.isNotEmpty).toSet();
  }

  // ─── assistant_logins ─────────────────────────────────────────────────────

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

  static Future<Map<String, dynamic>?> getNote(String lectureId, String uid) async {
    final rows = await _query('notes', 'id=eq.$lectureId&uid=eq.$uid&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  // ─── app_updates ──────────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamAppUpdates({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('app_updates', '$_sel&order=created_at.desc', interval: interval);
  }

  // ─── web_sessions / login attempts ────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamLoginAttempts({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('login_attempts', '$_sel&order=timestamp.desc', interval: interval);
  }

  static Stream<List<Map<String, dynamic>>> streamLoginHistory(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('login_history', 'uid=eq.$uid&$_sel&order=timestamp.desc', interval: interval);
  }

  static Future<List<Map<String, dynamic>>?> getLoginAttemptsForUser(String uid) async {
    final rows = await _query('login_attempts', 'uid=eq.$uid&$_sel&order=timestamp.desc&limit=100');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getWebSessionsForUser(String uid) async {
    final rows = await _query('web_sessions', 'uid=eq.$uid&$_sel&order=created_at.desc&limit=50');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getConnectedSessions(String uid) async {
    final rows = await _query('web_sessions', 'uid=eq.$uid&status=eq.connected&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getTargetedNotifications(String uid) async {
    final rows = await _query('notifications', 'uid=eq.$uid&type=eq.targeted&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  // ─── cloudinary accounts (mirrored into settings table) ──────────────────

  static Future<List<Map<String, dynamic>>?> getCloudinaryAccounts() async {
    final rows = await _query('settings', 'id=eq.cloudinary_accounts&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getAssistantCloudinaryAccounts() async {
    final rows = await _query('settings', 'id=like.assistant_cloudinary_%&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getSupabaseAccounts() async {
    final rows = await _query('settings', 'id=like.supabase_account:%&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<List<Map<String, dynamic>>?> getAssistantSupabaseAccounts() async {
    final rows = await _query('settings', 'id=like.assistant_supabase:%&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  // ─── AI API keys ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getAiApiKeyById(String id) async {
    final rows = await _query('ai_api_keys', 'id=eq.$id&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  static Future<List<Map<String, dynamic>>?> getAiApiKeys() async {
    final rows = await _query('ai_api_keys', '$_sel&order=created_at.asc');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Future<Map<String, dynamic>?> getActiveAiApiKey() async {
    final rows = await _query('ai_api_keys', '$_sel');
    if (rows == null || rows.isEmpty) return null;
    for (final r in rows) {
      final flat = _flatten(r);
      if (flat['isActive'] == true) return flat;
    }
    return null;
  }

  // ─── users (extra) ───────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getAllUsers() async {
    final rows = await _query('users', '$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  // ─── content access ──────────────────────────────────────────────────────

  static Future<Map<String, List<String>>> getContentAccess(String uid) async {
    final rows = await _query('content_assistant_access', 'user_id=eq.$uid&select=folder_id,content_id');
    if (rows == null) return {};
    final map = <String, List<String>>{};
    for (final r in rows) {
      final folderId = r['folder_id'] as String? ?? '';
      final contentId = r['content_id'] as String? ?? '';
      if (folderId.isNotEmpty) {
        map.putIfAbsent(folderId, () => []).add(contentId);
      }
    }
    return map;
  }

  // ─── feedback extras ─────────────────────────────────────────────────────

  static Future<int> getPendingFeedbackCount() async {
    final rows = await _query('feedbacks', 'status=eq.pending&select=id');
    if (rows == null) return -1;
    return rows.length;
  }

  static Stream<List<Map<String, dynamic>>> streamAllFeedbacks({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('feedbacks', '$_sel&order=id.desc', interval: interval);
  }

  // ─── notifications extras ────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>?> getUnreadAdminNotifications() async {
    final rows = await _query('admin_notifications', 'read=eq.false&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  /// Delete ALL admin notifications across all projects.
  static Future<void> clearAllAdminNotifications() async {
    final rows = await _query('admin_notifications', 'select=id');
    if (rows == null || rows.isEmpty) return;
    final ids = rows.map((r) => r['id'] as String).where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    final futures = ids.map((id) => _writeAll('admin_notifications', id, {}, delete: true));
    await Future.wait(futures);
  }

  /// Delete only login/logout/registration notifications (Login Details tab).
  static Future<void> clearLoginNotifications() async {
    const types = {'login', 'logout', 'registration'};
    final rows = await _query('admin_notifications', 'select=id,type');
    if (rows == null || rows.isEmpty) return;
    final ids = rows
        .where((r) => types.contains(r['type']))
        .map((r) => r['id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    final futures = ids.map((id) => _writeAll('admin_notifications', id, {}, delete: true));
    await Future.wait(futures);
  }

  /// Delete only NON-login notifications (bell icon Clear All).
  static Future<void> clearNonLoginAdminNotifications() async {
    const skipTypes = {'login', 'logout', 'registration'};
    final rows = await _query('admin_notifications', 'select=id,type');
    if (rows == null || rows.isEmpty) return;
    final ids = rows
        .where((r) => !skipTypes.contains(r['type']))
        .map((r) => r['id'] as String)
        .where((id) => id.isNotEmpty)
        .toList();
    if (ids.isEmpty) return;
    final futures = ids.map((id) => _writeAll('admin_notifications', id, {}, delete: true));
    await Future.wait(futures);
  }

  static Future<List<Map<String, dynamic>>?> getUnreadNotificationsForUser(String uid) async {
    final rows = await _query('notifications', 'uid=eq.$uid&read=eq.false&$_sel');
    if (rows == null) return null;
    return rows.map(_flatten).toList();
  }

  static Stream<List<Map<String, dynamic>>> streamTargetedNotificationsForUser(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('notifications', 'uid=eq.$uid&type=eq.targeted&$_sel', interval: interval);
  }

  // ─── web sessions extras ─────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getWebSession(String sessionId) async {
    final rows = await _query('web_sessions', 'id=eq.$sessionId&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return null;
    return _flatten(rows.first);
  }

  static Stream<Map<String, dynamic>?> streamWebSession(
    String sessionId, {
    Duration interval = const Duration(seconds: 5),
  }) {
    return _poll('web_sessions', 'id=eq.$sessionId&$_sel', interval: interval).map((list) => list.isEmpty ? null : list.first);
  }

  static Stream<List<Map<String, dynamic>>> streamWebSessionsForUser(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('web_sessions', 'uid=eq.$uid&$_sel&order=created_at.desc', interval: interval);
  }

  // ─── login attempts stream ───────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamLoginAttemptsForUser(
    String uid, {
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('login_attempts', 'uid=eq.$uid&$_sel&order=timestamp.desc', interval: interval);
  }

  // ─── notices stream ──────────────────────────────────────────────────────

  static Stream<List<Map<String, dynamic>>> streamNotices({
    Duration interval = const Duration(seconds: 10),
  }) {
    return _poll('notices', '$_sel&order=created_at.desc', interval: interval);
  }

  // ─── FOP allowed emails ──────────────────────────────────────────────────
  // Stored in settings table as: { id: 'fop_allowed_emails', data: { emails: [...] } }

  static Future<Set<String>> getFopAllowedEmails() async {
    final rows = await _query('settings', 'id=eq.fop_allowed_emails&limit=1&$_sel');
    if (rows == null || rows.isEmpty) return {};
    final flat = _flatten(rows.first);
    final emails = flat['emails'];
    if (emails is List) return emails.cast<String>().map((e) => e.toLowerCase()).toSet();
    return {};
  }

  static Future<bool> addFopEmail(String email) async {
    final current = await getFopAllowedEmails();
    if (current.contains(email.toLowerCase())) return true;
    current.add(email.toLowerCase());
    final data = {'emails': current.toList()};
    final ok = await _writeAll('settings', 'fop_allowed_emails', data);
    if (ok) _cache.invalidateAll();
    return ok;
  }

  static Future<bool> removeFopEmail(String email) async {
    final current = await getFopAllowedEmails();
    current.remove(email.toLowerCase());
    final data = {'emails': current.toList()};
    final ok = await _writeAll('settings', 'fop_allowed_emails', data);
    if (ok) _cache.invalidateAll();
    return ok;
  }

  // ─── Keep-Alive Pinger ───────────────────────────────────────────────────
  // Pings all 4 Supabase projects every 6h to prevent free-tier pause.

  static Timer? _keepAliveTimer;
  static DateTime? _lastPingTime;
  static bool _lastPingSuccess = false;

  static DateTime? get lastPingTime => _lastPingTime;
  static bool get lastPingSuccess => _lastPingSuccess;

  static void startKeepAlive() {
    _keepAliveTimer?.cancel();
    _pingAllProjects();
    _keepAliveTimer = Timer.periodic(const Duration(hours: 6), (_) => _pingAllProjects());
  }

  static Future<void> _pingAllProjects() async {
    bool anySuccess = false;
    for (final project in _projects) {
      try {
        final url = '${project['url']}/rest/v1/settings?select=id&limit=1';
        final resp = await http.get(
          Uri.parse(url),
          headers: {
            'apikey': project['anon']!,
            'Authorization': 'Bearer ${project['anon']}',
          },
        ).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) anySuccess = true;
      } catch (_) {}
    }
    _lastPingTime = DateTime.now();
    _lastPingSuccess = anySuccess;
  }

  static Future<Map<String, int>> getDatabaseStats() async {
    final tables = [
      'users', 'folders', 'contents', 'notifications',
      'conversations', 'messages', 'ai_api_keys',
      'web_sessions', 'login_attempts', 'student_activities',
      'feedbacks', 'admin_notifications', 'assistant_access',
      'login_history', 'settings', 'notes',
    ];
    final result = <String, int>{};
    for (final table in tables) {
      try {
        final resp = await http.get(
          Uri.parse('${_projects[0]['url']}/rest/v1/$table?select=id'),
          headers: {
            'apikey': _projects[0]['anon']!,
            'Authorization': 'Bearer ${_projects[0]['anon']}',
            'Range': '0-0',
            'Prefer': 'count=exact',
          },
        ).timeout(const Duration(seconds: 8));
        final contentRange = resp.headers['content-range'] ?? '';
        if (contentRange.contains('/')) {
          final total = int.tryParse(contentRange.split('/').last);
          if (total != null) result[table] = total;
        }
      } catch (_) {}
    }
    return result;
  }
}
