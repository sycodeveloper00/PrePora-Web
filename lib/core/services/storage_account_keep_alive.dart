import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'firebase_service.dart';
import 'supabase_read_service.dart';

/// Keep-alive service for user-added Supabase storage accounts (Admin + Assistant).
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

  /// Pings all admin and assistant Supabase storage accounts.
  /// Continues pinging regardless of isActive toggle state.
  static Future<void> _pingAllStorageAccounts() async {
    bool anySuccess = false;

    // Ping Admin Supabase Accounts
    try {
      final adminAccounts = await FirebaseService.getSupabaseAccounts();
      for (final acc in adminAccounts) {
        final result = await _pingStorageAccount(
          projectUrl: acc['projectUrl'] as String? ?? '',
          serviceKey: acc['serviceRoleKey'] as String? ?? '',
          accountId: acc['id'] as String? ?? '',
          projectType: 'admin_storage',
          storageLimitMB: acc['storageLimitMB'] as int? ?? _defaultStorageLimitMB,
        );
        if (result.success) anySuccess = true;
        
        // Check storage limit and auto-switch if needed
        if (result.success && acc['isActive'] == true) {
          await _checkAndAutoSwitch(acc, result.currentUsageMB, 'admin');
        }
      }
    } catch (e) {
      print('[StorageKeepAlive] Error pinging admin accounts: $e');
    }

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
      print('[StorageKeepAlive] Error pinging assistant accounts: $e');
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
      final verifyUrl = '$projectUrl/rest/v1/settings?select=id&limit=1';
      final verifyResp = await http.get(
        Uri.parse(verifyUrl),
        headers: {
          'apikey': serviceKey,
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

  /// Gets storage usage in MB via the supabase-proxy endpoint.
  static Future<int> _getStorageUsageMB(String projectUrl, String serviceKey) async {
    try {
      final proxyUrl = _getProxyUrl();
      final response = await http.post(
        Uri.parse(proxyUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'action': 'storage_usage',
          'projectUrl': projectUrl,
          'serviceKey': serviceKey,
        }),
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final totalBytes = data['totalBytes'] as int? ?? 0;
        return (totalBytes / (1024 * 1024)).round();
      }
    } catch (_) {}
    return 0;
  }

  /// Updates the account's currentUsageMB in Firestore.
  static Future<void> _updateAccountUsage(String accountId, int usageMB, String projectType) async {
    try {
      final collection = projectType == 'admin_storage' ? 'settings' : 'settings';
      final docId = projectType == 'admin_storage' 
          ? accountId 
          : accountId; // assistant_supabase:$id format
      
      await FirebaseService.mirrorWrite(collection, docId, {
        'currentUsageMB': usageMB,
      });
    } catch (_) {}
  }

  /// Checks if active account hit storage limit and auto-switches to next available.
  static Future<void> _checkAndAutoSwitch(Map<String, dynamic> activeAcc, int currentUsageMB, String type) async {
    final storageLimitMB = activeAcc['storageLimitMB'] as int? ?? _defaultStorageLimitMB;
    final autoSwitchEnabled = activeAcc['autoSwitchEnabled'] as bool? ?? true;
    
    if (!autoSwitchEnabled) return;
    if (currentUsageMB < storageLimitMB) return;

    print('[StorageKeepAlive] $type account ${activeAcc['id']} hit limit ($currentUsageMB MB >= $storageLimitMB MB)');

    // Deactivate current account
    try {
      if (type == 'admin') {
        await FirebaseService.updateSupabaseAccount(activeAcc['id'], isActive: false);
      } else {
        await FirebaseService.updateAssistantSupabaseAccount(activeAcc['id'], isActive: false);
      }
    } catch (e) {
      print('[StorageKeepAlive] Failed to deactivate account: $e');
      return;
    }

    // Find next available account
    final allAccounts = type == 'admin' 
        ? await FirebaseService.getSupabaseAccounts()
        : await FirebaseService.getAssistantSupabaseAccounts();

    Map<String, dynamic>? nextAccount;
    for (final acc in allAccounts) {
      if (acc['id'] == activeAcc['id']) continue;
      if (acc['isActive'] == true) continue;
      if (acc['bucketStatus'] != 'ready') continue;
      
      final accLimit = acc['storageLimitMB'] as int? ?? _defaultStorageLimitMB;
      final accUsage = acc['currentUsageMB'] as int? ?? 0;
      if (accUsage < accLimit) {
        nextAccount = acc;
        break;
      }
    }

    if (nextAccount != null) {
      try {
        if (type == 'admin') {
          await FirebaseService.updateSupabaseAccount(nextAccount!['id'], isActive: true);
        } else {
          await FirebaseService.updateAssistantSupabaseAccount(nextAccount!['id'], isActive: true);
        }
        await FirebaseService.reinitializeSupabase();
        
        // Notify admin
        await _notifyAutoSwitch(
          fromUrl: activeAcc['projectUrl'] as String? ?? '',
          toUrl: nextAccount!['projectUrl'] as String? ?? '',
          type: type,
        );
        print('[StorageKeepAlive] Auto-switched from ${activeAcc['id']} to ${nextAccount['id']}');
      } catch (e) {
        print('[StorageKeepAlive] Failed to activate next account: $e');
      }
    } else {
      // No available account - notify admin
      await _notifyNoAvailableAccount(activeAcc['projectUrl'] as String? ?? '', type);
      print('[StorageKeepAlive] No available account to switch to for $type');
    }
  }

  /// Sends admin notification about auto-switch.
  static Future<void> _notifyAutoSwitch({
    required String fromUrl,
    required String toUrl,
    required String type,
  }) async {
    final fromDisplay = fromUrl.replaceFirst('https://', '');
    final toDisplay = toUrl.replaceFirst('https://', '');
    await FirebaseService.addAdminNotification(
      'storage_auto_switch',
      '$type storage auto-switched: $fromDisplay → $toDisplay (storage limit reached)',
    );
  }

  /// Notifies admin when no account available to switch to.
  static Future<void> _notifyNoAvailableAccount(String fromUrl, String type) async {
    final fromDisplay = fromUrl.replaceFirst('https://', '');
    await FirebaseService.addAdminNotification(
      'storage_no_account',
      '$type storage limit reached for $fromDisplay — no available account to switch to. Uploads will fail.',
    );
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

  static String _getProxyUrl() {
    final host = Uri.base.host;
    if (host.contains('vercel.app')) return 'https://prepora-web.vercel.app/api/supabase-proxy';
    return '/api/supabase-proxy';
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