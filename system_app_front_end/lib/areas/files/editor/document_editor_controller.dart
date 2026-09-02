import 'package:flutter/painting.dart';

import '../../../shared/utils/frame_safe_notifier.dart';
import './editor_key_handoff.dart';
import '../rich_text/block_text_focus.dart';

class DocumentEditorController {
  DocumentEditorController({
    required this.fileId,
    required this.insertAtBlock,
    required this.focusBlock,
    required this.flushPendingChanges,
    this.focusedTaskId,
    this.markedTextForAgent,
    this.applyTextAction,
    this.toggleMoveMode,
    this.toggleEmbedReorder,
    this.restoreWritingFocus,
    this.dismissLiveMark,
    this.isFocused,
    this.isPrimaryFocused,
    this.canEnterObject,
    this.canLeaveObject,
    this.enterObject,
    this.leaveObject,
    this.nudgeObjectCaret,
  });

  final int fileId;
  final Future<void> Function(String action) insertAtBlock;
  final void Function(int blockIndex) focusBlock;
  final Future<void> Function() flushPendingChanges;

  /// Task under the caret in this file, if any (for view-assign shortcut).
  final int? Function()? focusedTaskId;

  /// Selection, or caret line when nothing is marked — for agent hints.
  final String? Function()? markedTextForAgent;

  /// Bold / italic / clipboard / emoji when the document caret has focus.
  final Future<void> Function(String action)? applyTextAction;

  /// Toggle object Move Mode for the caret / last-interacted embed.
  final VoidCallback? toggleMoveMode;

  /// ⌘O while the Super Editor caret is on a task list or table block.
  /// Returns true when that embed handled the shortcut.
  final bool Function()? toggleEmbedReorder;

  /// Put the keyboard back after chrome (arrange, reorder, Move Mode) stole it.
  final VoidCallback? restoreWritingFocus;

  /// Tap-outside: drop the live mark so it does not stay painted without focus.
  final VoidCallback? dismissLiveMark;

  /// True while this file's Super Editor focus node owns the keyboard
  /// (including when a descendant object field has it).
  final bool Function()? isFocused;

  /// True only when Super Editor itself is the primary focus — not an
  /// inner object field. Emoji insert uses this so `hasFocus` on the
  /// parent does not steal inserts from the open object.
  final bool Function()? isPrimaryFocused;

  /// Phone: Shift+Enter has no key. The bottom bar offers these instead.
  final bool Function()? canEnterObject;
  final bool Function()? canLeaveObject;
  final VoidCallback? enterObject;
  final VoidCallback? leaveObject;

  /// Phone: move inside the open object, or to the next block when on it.
  final void Function(AxisDirection direction)? nudgeObjectCaret;
}

/// Tracks every open file editor. Inserts go to the **last claimed** file —
/// the one the user last clicked or typed in — not whichever mounted last.
class DocumentEditorRegistry {
  DocumentEditorRegistry._();

  /// Editors unregister from `dispose`, so this cannot rebuild its listeners
  /// on the spot — the insert bar and both shells listen to it, and they are
  /// being unmounted in the same frame.
  static final FrameSafeNotifier notifier = FrameSafeNotifier();

  /// Phone object enter/leave pill — caret moved onto or off an object.
  static final FrameSafeNotifier objectGateNotifier = FrameSafeNotifier();

  static final Map<int, DocumentEditorController> _byFile = {};

  static DocumentEditorController? active;
  static int? get activeFileId => active?.fileId;

  /// Pointer for `hints.selected_text` — never a full file body.
  static const agentSelectedTextMaxChars = 4000;

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

  /// After a dialog or mode that stole the keyboard — wait until keys are up.
  static void restoreActiveWritingFocus() {
    runWhenKeyboardIdle(() {
      final target = active ?? (_byFile.isEmpty ? null : _byFile.values.first);
      target?.restoreWritingFocus?.call();
    });
  }

  /// Tap-outside dismissed the keyboard — drop the mark too.
  static void dismissLiveMarkOnOutsideTap() {
    if (BlockTextFocusRegistry.isInMenuSession) return;
    active?.dismissLiveMark?.call();
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

  /// Pointer for `hints.selected_text` — never a full file body.
  /// Marked span, or the caret line when nothing is marked.
  static AgentMarkedText? activeMarkedTextForAgent({
    int maxChars = agentSelectedTextMaxChars,
  }) {
    final raw = active?.markedTextForAgent?.call()?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (raw.length <= maxChars) {
      return AgentMarkedText(text: raw);
    }
    return AgentMarkedText(
      text: raw.substring(0, maxChars),
      truncated: true,
    );
  }

  /// Freeze embed marks and read `selected_text` before a dialog steals focus.
  static AgentMarkedText? captureMarkedTextForAgent({
    int maxChars = agentSelectedTextMaxChars,
  }) {
    BlockTextFocusRegistry.capturePendingMark();
    return activeMarkedTextForAgent(maxChars: maxChars);
  }
}

/// Marked span (or caret line) clipped to [DocumentEditorRegistry.agentSelectedTextMaxChars].
class AgentMarkedText {
  const AgentMarkedText({required this.text, this.truncated = false});

  final String text;
  final bool truncated;
}
