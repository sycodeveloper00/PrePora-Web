import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'firebase_service.dart';
import 'master_supabase_service.dart';
import 'supabase_read_service.dart';

/// Keep-alive service for user-added Supabase storage accounts (Assistant).
/// Runs independently of SupabaseReadService, pings ALL accounts every 24h
/// regardless of isActive toggle state. Toggle only controls uploads.
class StorageAccountKeepAliveService {
  StorageAccountKeepAliveService._();

  static Timer? _timer;
  static DateTime? _lastPingTime;
  static bool _lastPingSuccess = false;
  static const Duration _pingInterval = Duration(hours: 24);
  static const int _defaultStorageLimitMB = 1024;

  static DateTime? get lastPingTime => _lastPingTime;
  static bool get lastPingSuccess => _lastPingSuccess;

  /// Starts the keep-alive timer. Call once on app initialization.
  static void start() {
    _timer?.cancel();
    _pingAllStorageAccounts();
    _timer = Timer.periodic(_pingInterval, (_) => _pingAllStorageAccounts());
  }

  /// Stops the keep-alive timer.
  static void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Pings all assistant Supabase storage accounts.
  /// Continues pinging regardless of isActive toggle state.
  static Future<void> _pingAllStorageAccounts() async {
    bool anySuccess = false;

    // Ping Assistant Supabase Accounts
    try {
      final assistantAccounts = await FirebaseService.getAssistantSupabaseAccounts();
      for (final acc in assistantAccounts) {
        final result = await _pingStorageAccount(
          projectUrl: acc['projectUrl'] as String? ?? '',
          serviceKey: acc['serviceRoleKey'] as String? ?? '',
          accountId: acc['id'] as String? ?? '',
          projectType: 'assistant_storage',
          storageLimitMB: acc['storageLimitMB'] as int? ?? _defaultStorageLimitMB,
        );
        if (result.success) anySuccess = true;

        // Check storage limit and auto-switch if needed
        if (result.success && acc['isActive'] == true) {
          await _checkAndAutoSwitch(acc, result.currentUsageMB, 'assistant');
        }
      }
    } catch (e) {
      debugPrint('[StorageKeepAlive] Error pinging assistant accounts: $e');
    }

    _lastPingTime = DateTime.now();
    _lastPingSuccess = anySuccess;
  }

  /// Pings a single storage account and returns usage info.
  static Future<_PingResult> _pingStorageAccount({
    required String projectUrl,
    required String serviceKey,
    required String accountId,
    required String projectType,
    required int storageLimitMB,
  }) async {
    final start = DateTime.now();
    int currentUsageMB = 0;
    bool success = false;
    String? errorMessage;

    try {
      // Verify project is reachable
      final verifyUrl = '$projectUrl/storage/v1/bucket';
      final verifyResp = await http.get(
        Uri.parse(verifyUrl),
        headers: {
          'Authorization': 'Bearer $serviceKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (verifyResp.statusCode == 200) {
        success = true;

        // Get storage usage
        currentUsageMB = await _getStorageUsageMB(projectUrl, serviceKey);

        // Update currentUsageMB in Firestore
        await _updateAccountUsage(accountId, currentUsageMB, projectType);
      } else if (verifyResp.statusCode == 530) {
        errorMessage = 'Project paused (HTTP 530)';
      } else {
        errorMessage = 'HTTP ${verifyResp.statusCode}';
      }
    } catch (e) {
      errorMessage = e.toString();
    }

    final responseTime = DateTime.now().difference(start).inMilliseconds;
    final status = success ? 'success' : (errorMessage?.contains('530') == true ? 'paused_530' : 'failed');

    // Log to Supabase ping_log table
    await _logPingToSupabase(
      projectUrl: projectUrl,
      projectType: projectType,
      accountId: accountId,
      status: status,
      responseTimeMs: responseTime,
      errorMessage: errorMessage,
    );

    return _PingResult(
      success: success,
      currentUsageMB: currentUsageMB,
      responseTimeMs: responseTime,
      errorMessage: errorMessage,
    );
  }

  /// Gets storage usage in MB by listing objects in buckets.
  static Future<int> _getStorageUsageMB(String projectUrl, String serviceKey) async {
    try {
      int totalBytes = 0;
      for (final bucket in ['folder_files', 'notices']) {
        try {
          final listUri = Uri.parse('$projectUrl/storage/v1/object/list/$bucket');
          final listResp = await http.post(
            listUri,
            headers: {
              'Authorization': 'Bearer $serviceKey',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'prefix': '',
              'limit': 1000,
              'offset': 0,
              'sortBy': {'column': 'created_at', 'order': 'desc'}
            }),
          ).timeout(const Duration(seconds: 15));

          if (listResp.statusCode == 200) {
            final items = jsonDecode(listResp.body) as List<dynamic>;
            for (final item in items) {
              totalBytes += item['metadata']?['size'] as int? ?? 0;
            }
          }
        } catch (_) {}
      }
      return (totalBytes / (1024 * 1024)).round();
    } catch (_) {
      return 0;
    }
  }

  /// Updates the account's currentUsageMB in Firestore.
  static Future<void> _updateAccountUsage(String accountId, int usageMB, String projectType) async {
    try {
      await MasterSupabaseService.update('assistant_supabase', accountId, {
        'current_usage_mb': usageMB,
      });
      await FirebaseService.firestore.collection('assistant_supabase').doc(accountId).update({
        'currentUsageMB': usageMB,
      });
    } catch (_) {}
  }

  /// Checks if active account hit storage limit and auto-switches to next available.
  static Future<void> _checkAndAutoSwitch(Map<String, dynamic> activeAcc, int currentUsageMB, String type) async {
    // Support both snake_case (MasterSupabase) and camelCase (Firestore)
    final storageLimitMB = (activeAcc['storage_limit_mb'] as int?) ?? (activeAcc['storageLimitMB'] as int?) ?? _defaultStorageLimitMB;
    final autoSwitchEnabled = (activeAcc['auto_switch_enabled'] as bool?) ?? (activeAcc['autoSwitchEnabled'] as bool?) ?? true;

    if (!autoSwitchEnabled) return;
    if (currentUsageMB < storageLimitMB) return;

    debugPrint('[StorageKeepAlive] $type account ${activeAcc['id']} hit limit ($currentUsageMB MB >= $storageLimitMB MB)');

    // Deactivate current account
    try {
      await MasterSupabaseService.update('assistant_supabase', activeAcc['id'], {
        'is_active': false,
      });
      await FirebaseService.firestore.collection('assistant_supabase').doc(activeAcc['id']).update({
        'isActive': false,
      });
    } catch (e) {
      debugPrint('[StorageKeepAlive] Failed to deactivate account: $e');
      return;
    }

    // Find next available account
    final allAccounts = await FirebaseService.getAssistantSupabaseAccounts();

    Map<String, dynamic>? nextAccount;
    for (final acc in allAccounts) {
      if (acc['id'] == activeAcc['id']) continue;
      final isActive = (acc['is_active'] as bool?) ?? (acc['isActive'] as bool?) ?? false;
      if (!isActive) continue;
      final bucketStatus = (acc['bucket_status'] as String?) ?? (acc['bucketStatus'] as String?) ?? '';
      if (bucketStatus != 'ready') continue;

      final accLimit = (acc['storage_limit_mb'] as int?) ?? (acc['storageLimitMB'] as int?) ?? _defaultStorageLimitMB;
      final accUsage = (acc['current_usage_mb'] as num?)?.toInt() ?? (acc['currentUsageMB'] as num?)?.toInt() ?? 0;
      if (accUsage < accLimit) {
        nextAccount = acc;
        break;
      }
    }

    if (nextAccount != null) {
      try {
        await MasterSupabaseService.update('assistant_supabase', nextAccount!['id'], {
          'is_active': true,
        });
        await FirebaseService.firestore.collection('assistant_supabase').doc(nextAccount!['id']).update({
          'isActive': true,
        });
        await FirebaseService.reinitializeSupabase();
        debugPrint('[StorageKeepAlive] Auto-switched from ${activeAcc['id']} to ${nextAccount['id']}');
      } catch (e) {
        debugPrint('[StorageKeepAlive] Failed to activate next account: $e');
      }
    } else {
      debugPrint('[StorageKeepAlive] No available account to switch to for $type');
    }
  }

  /// Logs ping result to Supabase ping_log table.
  static Future<void> _logPingToSupabase({
    required String projectUrl,
    required String projectType,
    required String accountId,
    required String status,
    required int responseTimeMs,
    String? errorMessage,
  }) async {
    try {
      final data = {
        'project_url': projectUrl,
        'project_type': projectType,
        'account_id': accountId,
        'status': status,
        'response_time_ms': responseTimeMs,
        'error_message': errorMessage,
        'pinged_at': DateTime.now().toIso8601String(),
      };
      // Use first system project to write (has service role)
      await SupabaseReadService.writePrimary('supabase_ping_log', const Uuid().v4(), data);
    } catch (_) {}
  }
}

class _PingResult {
  final bool success;
  final int currentUsageMB;
  final int responseTimeMs;
  final String? errorMessage;

  _PingResult({
    required this.success,
    required this.currentUsageMB,
    required this.responseTimeMs,
    this.errorMessage,
  });
}