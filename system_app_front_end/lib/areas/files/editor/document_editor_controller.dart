import '../../../shared/utils/frame_safe_notifier.dart';

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

  /// Editors unregister from `dispose`, so this cannot rebuild its listeners
  /// on the spot — the insert bar and both shells listen to it, and they are
  /// being unmounted in the same frame.
  static final FrameSafeNotifier notifier = FrameSafeNotifier();

  static DocumentEditorController? active;
  static int? get activeFileId => active?.fileId;

  static void register(DocumentEditorController controller) {
    active = controller;
    notifier.notify();
  }

  static void unregister(int fileId) {
    if (active?.fileId == fileId) {
      active = null;
      notifier.notify();
    }
  }

  static Future<void> flushActive() async {
    await active?.flushPendingChanges();
  }
}
