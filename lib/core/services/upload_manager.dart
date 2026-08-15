import 'dart:async';
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

  List<Map<String, dynamic>> filesForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId).toList();

  int completedCountForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId && q['status'] == 'completed').length;

  int totalCountForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId).length;

  int uploadingCountForFolder(String folderId) =>
      _queue.where((q) => q['folderId'] == folderId && q['status'] == 'uploading').length;

  Set<String> get activeFolderIds =>
      _queue.where((q) => q['status'] == 'pending' || q['status'] == 'uploading')
          .map((q) => q['folderId'] as String).toSet();

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

  Future<void> pauseFile(String fileId) async {
    _filePaused[fileId] = true;
    _pauseCompleter = Completer<void>();
    notifyListeners();
    await _pauseCompleter!.future;
  }

  void resumeFile(String fileId) {
    _filePaused[fileId] = false;
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
    _pauseCompleter = null;
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

        while (_filePaused[id] == true) {
          await Future.delayed(const Duration(milliseconds: 200));
        }

        item['status'] = 'uploading';
        item['uploadStartedAt'] = DateTime.now().millisecondsSinceEpoch;
        notifyListeners();

        String? downloadUrl;
        try {
          final bytes = item['bytes'] as Uint8List;
          downloadUrl = await FirebaseService.uploadFile(bytes, name, onProgress: (p) {
            updateProgress(id, p, ((item['totalBytes'] as int) * p).toInt());
          });
          markCompleted(id);
          item['url'] = downloadUrl;
        } catch (e) {
          markFailed(id, e.toString());
          continue;
        }

        try {
          await onContentSaved?.call(folderId, name, downloadUrl!, parentContentId);
        } catch (_) {}
      }
    } finally {
      _isProcessing = false;
      _cleanupFinished();
      notifyListeners();
    }
  }

  void _cleanupFinished() {
    final hasActive = _queue.any((q) => q['status'] == 'pending' || q['status'] == 'uploading');
    if (!hasActive) {
      final finishedFolders = <String, Map<String, int>>{};
      for (final q in _queue) {
        final fid = q['folderId'] as String;
        final bucket = finishedFolders.putIfAbsent(fid, () => {'completed': 0, 'failed': 0, 'cancelled': 0});
        final st = q['status'] as String;
        if (bucket.containsKey(st)) bucket[st] = bucket[st]! + 1;
      }
      _queue.removeWhere((q) => q['status'] == 'completed' || q['status'] == 'failed');
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
  void cancelAll() {
    _isUploading = false;
    _queue = [];
    _progress.clear();
    _filePaused.clear();
    _startTime = null;
    if (_pauseCompleter != null && !_pauseCompleter!.isCompleted) {
      _pauseCompleter!.complete();
    }
    _pauseCompleter = null;
    notifyListeners();
  }

  void cancelFolder(String folderId) {
    _queue.removeWhere((q) => q['folderId'] == folderId && q['status'] == 'pending');
    notifyListeners();
  }
}
