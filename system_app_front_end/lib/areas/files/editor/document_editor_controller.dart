import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class DocumentEditorController {
  DocumentEditorController({
    required this.fileId,
    required this.insertAtBlock,
    required this.focusBlock,
    required this.flushPendingChanges,
  });

  final int fileId;
  final Future<void> Function(String action) insertAtBlock;
  final void Function(int blockIndex) focusBlock;
  final Future<void> Function() flushPendingChanges;
}

class DocumentEditorRegistry {
  DocumentEditorRegistry._();

  static final Listenable notifier = ValueNotifier<int>(0);
  static DocumentEditorController? active;
  static int? get activeFileId => active?.fileId;

  static void _notify() {
    (notifier as ValueNotifier<int>).value++;
  }

  static void register(DocumentEditorController controller) {
    active = controller;
    _notify();
  }

  static void unregister(int fileId) {
    if (active?.fileId == fileId) {
      active = null;
      _notify();
    }
  }

  static Future<void> flushActive() async {
    await active?.flushPendingChanges();
  }
}
