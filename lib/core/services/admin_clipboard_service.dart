import 'package:flutter/material.dart';

enum ClipboardAction { copy, cut }

class ClipboardItem {
  final String id;
  final String name;
  final String type; // 'folder', 'content', 'lecture', 'mocktest', 'file'
  final String? parentFolderId;
  final Map<String, dynamic>? data;
  final ClipboardAction action;

  ClipboardItem({
    required this.id,
    required this.name,
    required this.type,
    this.parentFolderId,
    this.data,
    required this.action,
  });
}

class AdminClipboardService {
  static final AdminClipboardService instance = AdminClipboardService._();
  AdminClipboardService._();

  ClipboardItem? _copiedItem;
  final ValueNotifier<ClipboardItem?> clipboardNotifier = ValueNotifier(null);

  ClipboardItem? get copiedItem => _copiedItem;
  bool get hasItem => _copiedItem != null;
  bool get isCut => _copiedItem?.action == ClipboardAction.cut;

  void copy(String id, String name, String type, {String? parentFolderId, Map<String, dynamic>? data}) {
    _copiedItem = ClipboardItem(
      id: id,
      name: name,
      type: type,
      parentFolderId: parentFolderId,
      data: data,
      action: ClipboardAction.copy,
    );
    clipboardNotifier.value = _copiedItem;
  }

  void cut(String id, String name, String type, {String? parentFolderId, Map<String, dynamic>? data}) {
    _copiedItem = ClipboardItem(
      id: id,
      name: name,
      type: type,
      parentFolderId: parentFolderId,
      data: data,
      action: ClipboardAction.cut,
    );
    clipboardNotifier.value = _copiedItem;
  }

  void clear() {
    _copiedItem = null;
    clipboardNotifier.value = null;
  }

  String getDuplicateName(String originalName) {
    if (originalName.contains('(Copy)')) {
      final baseName = originalName.replaceAll(RegExp(r'\s*\(Copy(\s*\d+)?\)$'), '');
      return '$baseName (Copy 2)';
    }
    return '$originalName (Copy)';
  }
}
