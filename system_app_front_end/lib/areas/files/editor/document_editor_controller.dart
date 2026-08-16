import '../../../shared/utils/frame_safe_notifier.dart';

class DocumentEditorController {
  DocumentEditorController({
    required this.fileId,
    required this.insertAtBlock,
    required this.focusBlock,
    required this.flushPendingChanges,
    this.focusedTaskId,
    this.markedTextForAgent,
  });

  final int fileId;
  final Future<void> Function(String action) insertAtBlock;
  final void Function(int blockIndex) focusBlock;
  final Future<void> Function() flushPendingChanges;

  /// Task under the caret in this file, if any (for view-assign shortcut).
  final int? Function()? focusedTaskId;

  /// Selection, or caret line/paragraph when nothing is marked — for agent hints.
  final String? Function()? markedTextForAgent;
}

/// Tracks every open file editor. Inserts go to the **last claimed** file —
/// the one the user last clicked or typed in — not whichever mounted last.
class DocumentEditorRegistry {
  DocumentEditorRegistry._();

  /// Editors unregister from `dispose`, so this cannot rebuild its listeners
  /// on the spot — the insert bar and both shells listen to it, and they are
  /// being unmounted in the same frame.
  static final FrameSafeNotifier notifier = FrameSafeNotifier();

  static final Map<int, DocumentEditorController> _byFile = {};

  static DocumentEditorController? active;
  static int? get activeFileId => active?.fileId;

  static void register(DocumentEditorController controller) {
    _byFile[controller.fileId] = controller;
    // Keep the previously claimed file active when another pane mounts.
    if (active == null || active!.fileId == controller.fileId) {
      active = controller;
    }
    notifier.notify();
  }

  /// Call when the user focuses or clicks inside a file so inserts land there.
  static void claim(int fileId) {
    final controller = _byFile[fileId];
    if (controller == null) return;
    if (identical(active, controller)) return;
    active = controller;
    notifier.notify();
  }

  static void unregister(int fileId) {
    _byFile.remove(fileId);
    if (active?.fileId == fileId) {
      active = _byFile.isEmpty ? null : _byFile.values.last;
      notifier.notify();
    }
  }

  static Future<void> flushActive() async {
    await active?.flushPendingChanges();
  }

  /// Tiny pointer for `hints.selected_text` — never a full file body.
  static String? activeMarkedTextForAgent({int maxChars = 400}) {
    final raw = active?.markedTextForAgent?.call()?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.length <= maxChars) return raw;
    return raw.substring(0, maxChars);
  }
}
