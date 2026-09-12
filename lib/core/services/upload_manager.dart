import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'firebase_service.dart';

typedef UploadContentCallback = Future<void> Function(
  String folderId,
  String name,
  String downloadUrl,
  String? parentContentId,
);

class UploadManager extends ChangeNotifier {
  static final UploadManager instance = UploadManager._();
  UploadManager._();

  final Map<String, double> _progress = {};
  final Map<String, bool> _filePaused = {};
  final Set<String> _cancelledIds = {};
  List<Map<String, dynamic>> _queue = [];
  DateTime? _startTime;
  bool _isUploading = false;
  bool _isProcessing = false;
  Completer<void>? _pauseCompleter;
  UploadContentCallback? onContentSaved;
  void Function(Map<String, Map<String, int>> results)? onBatchComplete;
  int _idCounter = 0;

  Map<String, double> get progress => _progress;
  Map<String, bool> get filePaused => _filePaused;
  List<Map<String, dynamic>> get queue => _queue;
  DateTime? get startTime => _startTime;
  bool get isUploading => _isUploading;
  bool get isProcessing => _isProcessing;

  int get completedCount => _queue.where((q) => q['status'] == 'completed').length;
  int get totalCount => _queue.length;

  /// Restore failed metadata writes — retry any items that were stuck
  Future<void> restorePendingWrites() async {
    try {
      for (final item in _queue.where((q) => q['status'] == 'metadata_failed').toList()) {
        item['status'] = 'pending';
        item.remove('metadataError');
      }
      if (_queue.any((q) => q['status'] == 'pending')) {
        _startTime ??= DateTime.now();
        _isUploading = true;
        notifyListeners();
        if (!_isProcessing) _processQueue();
      }
    } catch (_) {}
  }

  List<Map<String, dynamic>> filesForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId).toList();

  int completedCountForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId && q['status'] == 'completed').length;

  int totalCountForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId).length;

  int uploadingCountForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId && q['status'] == 'uploading').length;

  Set<String> get activeFolderIds =>
      _queue.where((q) =>
              q['status'] == 'pending' ||
              q['status'] == 'uploading' ||
              q['status'] == 'metadata_failed')
          .map((q) => q['folderId'] as String).toSet();

  int totalBytesForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId).fold<int>(0, (sum, q) => sum + (q['totalBytes'] as int? ?? 0));

  int uploadedBytesForFolder(String folderId) {
    int total = 0;
    for (final q in _queue.where((q) => q['folderId'] == folderId)) {
      final totalB = q['totalBytes'] as int? ?? 0;
      if (q['status'] == 'completed' || q['status'] == 'cancelled' || q['status'] == 'metadata_failed') {
        total += totalB;
      } else if (q['status'] == 'uploading') {
        final fileId = q['id'] as String?;
        final p = fileId != null ? (_progress[fileId] ?? 0.0) : 0.0;
        total += (totalB * p).toInt();
      }
    }
    return total;
  }

  void startUpload({
    required String folderId,
    required String? parentContentId,
    required List<Map<String, dynamic>> files,
  }) {
    for (final f in files) {
      f['folderId'] = folderId;
      f['parentContentId'] = parentContentId;
      f['id'] = '${DateTime.now().millisecondsSinceEpoch}_${_idCounter++}';
    }
    _queue.addAll(files);
    _startTime ??= DateTime.now();
    _isUploading = true;
    SessionManager.setUploading(true);
    for (final q in files) {
      _filePaused[q['id'] as String] = false;
    }
    notifyListeners();
    _processQueue();
  }

  void updateProgress(String fileId, double value, int uploadedBytes) {
    _progress[fileId] = value;
    final item = _queue.where((q) => q['id'] == fileId).firstOrNull;
    if (item != null) {
      item['uploadedBytes'] = uploadedBytes;
    }
    notifyListeners();
  }

  void markCompleted(String fileId) {
    _progress.remove(fileId);
    final item = _queue.where((q) => q['id'] == fileId).firstOrNull;
    if (item != null) item['status'] = 'completed';
    notifyListeners();
  }

  void markFailed(String fileId, String error) {
    _progress.remove(fileId);
    final item = _queue.where((q) => q['id'] == fileId).firstOrNull;
    if (item != null) {
      item['status'] = 'failed';
      item['error'] = error;
    }
    notifyListeners();
  }

  void pauseFile(String fileId) {
    _filePaused[fileId] = true;
    notifyListeners();
  }

  void resumeFile(String fileId) {
    _filePaused[fileId] = false;
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
    _pauseCompleter = null;
    notifyListeners();
  }

  void cancelFile(String fileId) {
    _cancelledIds.add(fileId);
    _filePaused.remove(fileId);
    final item = _queue.where((q) => q['id'] == fileId).firstOrNull;
    if (item != null) {
      item['status'] = 'cancelled';
    }
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
    _pauseCompleter = null;
    _progress.remove(fileId);
    notifyListeners();
  }

  void resumePending() {
    if (!_isProcessing) _processQueue();
  }

  Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;
    try {
      while (true) {
        final pending = _queue.where((q) => q['status'] == 'pending').toList();
        if (pending.isEmpty) break;

        final item = pending.first;
        final id = item['id'] as String;
        final name = item['name'] as String;
        final folderId = item['folderId'] as String;
        final parentContentId = item['parentContentId'] as String?;

        // Wait while paused
        while (_filePaused[id] == true && !_cancelledIds.contains(id)) {
          final completer = Completer<void>();
          _pauseCompleter = completer;
          await completer.future;
        }
        // If cancelled while paused, skip
        if (_cancelledIds.contains(id)) {
          _cancelledIds.remove(id);
          continue;
        }

        item['status'] = 'uploading';
        item['uploadStartedAt'] = DateTime.now().millisecondsSinceEpoch;
        notifyListeners();

        String? downloadUrl;
        try {
          final bytes = item['bytes'] as Uint8List;
          downloadUrl = await FirebaseService.uploadFile(bytes, name, onProgress: (p) {
            if (_cancelledIds.contains(id)) return;
            updateProgress(id, p, ((item['totalBytes'] as int) * p).toInt());
          });
          item['url'] = downloadUrl;
        } catch (e) {
          if (!_cancelledIds.contains(id)) {
            markFailed(id, e.toString());
          }
          continue;
        }

        // Check if cancelled during upload
        if (_cancelledIds.contains(id)) {
          _cancelledIds.remove(id);
          continue;
        }

        // Metadata write with retry (up to 5 attempts with progressive delay)
        bool metadataWritten = false;
        for (int attempt = 1; attempt <= 5; attempt++) {
          if (_cancelledIds.contains(id)) break;
          try {
            item['status'] = 'writing_metadata';
            notifyListeners();
            if (onContentSaved != null) {
              await onContentSaved!.call(folderId, name, downloadUrl!, parentContentId);
            } else {
              final provider = await FirebaseService.getStorageProvider();
              final actualProvider = provider == 'both'
                  ? (downloadUrl!.contains('cloudinary.com') ? 'cloudinary' : 'supabase')
                  : provider;
              final data = <String, dynamic>{'type': 'file', 'name': name, 'url': downloadUrl, 'source': 'storage', 'provider': actualProvider};
              if (parentContentId != null) data['parentContentId'] = parentContentId;
              final newId = await FirebaseService.addFolderContent(folderId, data);
              if (newId == null) throw Exception('addFolderContent returned null');
            }
            metadataWritten = true;
            break;
          } catch (e) {
            if (attempt < 5) {
              item['metadataError'] = 'Attempt $attempt failed: $e';
              notifyListeners();
              await Future.delayed(Duration(seconds: attempt * 3));
            }
          }
        }

        if (_cancelledIds.contains(id)) {
          _cancelledIds.remove(id);
          continue;
        }

        if (metadataWritten) {
          markCompleted(id);
        } else {
          item['status'] = 'metadata_failed';
          item['metadataError'] = 'Upload succeeded but metadata save failed after 5 retries';
          _progress.remove(id);
          notifyListeners();
        }
      }
    } finally {
      _isProcessing = false;
      _cleanupFinished();
      notifyListeners();
    }
  }

  void _cleanupFinished() {
    final hasActive = _queue.any((q) => q['status'] == 'pending' || q['status'] == 'uploading' || q['status'] == 'writing_metadata');
    if (!hasActive) {
      final finishedFolders = <String, Map<String, int>>{};
      for (final q in _queue) {
        final fid = q['folderId'] as String;
        final bucket = finishedFolders.putIfAbsent(fid, () => {'completed': 0, 'failed': 0, 'cancelled': 0, 'metadata_failed': 0});
        final st = q['status'] as String;
        if (bucket.containsKey(st)) bucket[st] = bucket[st]! + 1;
      }
      _queue.removeWhere((q) => q['status'] == 'completed' || q['status'] == 'failed' || q['status'] == 'cancelled');
      if (_queue.isEmpty) {
        _isUploading = false;
        _startTime = null;
      }
      if (finishedFolders.isNotEmpty) {
        final cb = onBatchComplete;
        scheduleMicrotask(() => cb?.call(finishedFolders));
      }
    }
    if (!_isUploading) {
      SessionManager.setUploading(false);
    }
  }

  Future<void> retryMetadataFailed() async {
    for (final item in _queue.where((q) => q['status'] == 'metadata_failed').toList()) {
      item['status'] = 'pending';
      item.remove('metadataError');
    }
    _startTime ??= DateTime.now();
    _isUploading = true;
    notifyListeners();
    if (!_isProcessing) _processQueue();
  }

  Future<void> retryOneMetadata(String fileId) async {
    final item = _queue.where((q) => q['id'] == fileId && q['status'] == 'metadata_failed').firstOrNull;
    if (item != null) {
      item['status'] = 'pending';
      item.remove('metadataError');
      _startTime ??= DateTime.now();
      _isUploading = true;
      notifyListeners();
      if (!_isProcessing) _processQueue();
    }
  }

  List<Map<String, dynamic>> get metadataFailedItems =>
      _queue.where((q) => q['status'] == 'metadata_failed').toList();

  void cancelAll() {
    _isUploading = false;
    for (final q in _queue.where((q) => q['status'] == 'pending' || q['status'] == 'uploading')) {
      _cancelledIds.add(q['id'] as String);
      q['status'] = 'cancelled';
    }
    _progress.clear();
    _filePaused.clear();
    _startTime = null;
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
    _pauseCompleter = null;
    _cleanupFinished();
    notifyListeners();
  }

  void cancelFolder(String folderId) {
    for (final q in _queue.where((q) => q['folderId'] == folderId && (q['status'] == 'pending' || q['status'] == 'uploading'))) {
      _cancelledIds.add(q['id'] as String);
      q['status'] = 'cancelled';
    }
    _cleanupFinished();
    notifyListeners();
  }
}
