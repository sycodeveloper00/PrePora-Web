import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Master Supabase client — handles ALL Firestore-migrated data.
/// This client reads/writes to the "master" Supabase account where
/// settings, AI keys, accounts, etc. are stored.
///
/// Unlike the storage Supabase accounts (failover chain), this is a
/// SINGLE dedicated project for admin/metadata data.
class MasterSupabaseService {
  MasterSupabaseService._();

  // ─── Master Account Credentials (hardcoded — anon key is public) ────────────
  static const String _masterUrl = 'https://ybiviymuxubvloqjngfu.supabase.co';
  static const String _masterAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InliaXZpeW11eHVidmxvcWpuZ2Z1Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODkzNzI0MzksImV4cCI6MjEwNDk0ODQzOX0.2__dxf4r6cWnG5TLxqTymDLtFbP9fkZJzC8fkOY9VXc';
  static const String masterServiceKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InliaXZpeW11eHVidmxvcWpuZ2Z1Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc4OTM3MjQzOSwiZXhwIjoyMTA0OTQ4NDM5fQ.kIoWInC-ZDNsPx6xpCACO0ee2Kfer7jMBRCtAQv_8gQ';

  static bool _initialized = false;
  static SupabaseClient? _client;

  static SupabaseClient get client {
    if (_client == null) throw StateError('MasterSupabaseService not initialized');
    return _client!;
  }

  static String get url => _masterUrl;
  static String get anonKey => _masterAnonKey;

  /// Initialize the master Supabase client (call once at startup, before runApp).
  static Future<void> init() async {
    if (_initialized) return;
    try {
      _client = SupabaseClient(_masterUrl, _masterAnonKey);
      _initialized = true;
      debugPrint('[MasterSupabase] Initialized: $_masterUrl');
    } catch (e) {
      debugPrint('[MasterSupabase] Init failed: $e');
    }
  }

  // ─── Generic CRUD ──────────────────────────────────────────────────────────

  /// Read all rows from a table with optional query string.
  static Future<List<Map<String, dynamic>>> read(String table, {String? query}) async {
    try {
      var builder = client.from(table).select();
      if (query != null) {
        // Parse simple query: 'field=eq.value&field2=eq.value2'
        final parts = query.split('&');
        for (final part in parts) {
          final eqIdx = part.indexOf('=');
          if (eqIdx == -1) continue;
          final field = part.substring(0, eqIdx);
          final val = part.substring(eqIdx + 1);
          if (val.startsWith('eq.')) {
            builder = builder.eq(field, val.substring(3));
          } else if (val.startsWith('gt.')) {
            builder = builder.gt(field, val.substring(3));
          } else if (val.startsWith('lt.')) {
            builder = builder.lt(field, val.substring(3));
          } else if (val.startsWith('gte.')) {
            builder = builder.gte(field, val.substring(4));
          } else if (val.startsWith('lte.')) {
            builder = builder.lte(field, val.substring(4));
          } else if (val.startsWith('like.')) {
            builder = builder.like(field, val.substring(5));
          } else if (val.startsWith('in.(')) {
            final list = val.substring(4, val.length - 1).split(',');
            builder = builder.inFilter(field, list);
          } else {
            builder = builder.eq(field, val);
          }
        }
      }
      final data = await builder.timeout(const Duration(seconds: 10));
      return (data as List<dynamic>).cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[MasterSupabase] read($table) failed: $e');
      return [];
    }
  }

  /// Read one row by id.
  static Future<Map<String, dynamic>?> readById(String table, String id) async {
    try {
      final data = await client.from(table).select().eq('id', id).maybeSingle();
      return data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[MasterSupabase] readById($table, $id) failed: $e');
      return null;
    }
  }

  /// Read single row matching a filter.
  static Future<Map<String, dynamic>?> readSingle(String table, {required String field, required String value}) async {
    try {
      final data = await client.from(table).select().eq(field, value).maybeSingle();
      return data as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[MasterSupabase] readSingle($table) failed: $e');
      return null;
    }
  }

  /// Upsert a row (insert or update by id).
  static Future<bool> upsert(String table, Map<String, dynamic> data) async {
    try {
      await client.from(table).upsert(data).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] upsert($table) failed: $e');
      return false;
    }
  }

  /// Insert a row and return the generated id.
  static Future<String?> insert(String table, Map<String, dynamic> data) async {
    try {
      final result = await client.from(table).insert(data).select('id').single();
      return result['id'] as String?;
    } catch (e) {
      debugPrint('[MasterSupabase] insert($table) failed: $e');
      return null;
    }
  }

  /// Update a row by id.
  static Future<bool> update(String table, String id, Map<String, dynamic> data) async {
    try {
      await client.from(table).update(data).eq('id', id).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] update($table, $id) failed: $e');
      return false;
    }
  }

  /// Delete a row by id.
  static Future<bool> delete(String table, String id) async {
    try {
      await client.from(table).delete().eq('id', id).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] delete($table, $id) failed: $e');
      return false;
    }
  }

  /// Delete rows matching a filter.
  static Future<bool> deleteWhere(String table, {required String field, required String value}) async {
    try {
      await client.from(table).delete().eq(field, value).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] deleteWhere($table) failed: $e');
      return false;
    }
  }

  /// Update rows matching a filter.
  static Future<bool> updateWhere(String table, {required String filterField, required String filterValue, required Map<String, dynamic> data}) async {
    try {
      await client.from(table).update(data).eq(filterField, filterValue).timeout(const Duration(seconds: 10));
      return true;
    } catch (e) {
      debugPrint('[MasterSupabase] updateWhere($table) failed: $e');
      return false;
    }
  }

  /// Stream changes for a table (realtime subscription).
  static Stream<List<Map<String, dynamic>>> stream(String table, {String? filterField, String? filterValue}) {
    final controller = StreamController<List<Map<String, dynamic>>>.broadcast();

    Future<void> fetch() async {
      try {
        var builder = client.from(table).select();
        if (filterField != null && filterValue != null) {
          builder = builder.eq(filterField, filterValue);
        }
        final data = await builder.timeout(const Duration(seconds: 10));
        controller.add((data as List<dynamic>).cast<Map<String, dynamic>>());
      } catch (e) {
        controller.add([]);
      }
    }

    fetch();

    final channel = client
        .channel('master_$table')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: table,
          callback: (_) => fetch(),
        )
        .subscribe();

    controller.onCancel = () {
      client.removeChannel(channel);
      controller.close();
    };

    return controller.stream;
  }
}
