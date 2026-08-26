/// Atomic object blocks: SE owns the caret on the embed; Shift+Enter opens it
/// and also leaves back to the SE block caret. Enter inserts a line under the object.
library;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../model/object_embed_node.dart';
import '../rich_text/formatted_text_field.dart';
import './document_caret_session.dart';
import './editor_key_handoff.dart';
import './embed_exit_scope.dart';

/// Ordered editable lines inside one object (title, body, tasks, cells, …).
abstract class EmbedCaretGateway {
  String get nodeId;
  int get lineCount;
  void focusLine(int index, {required bool fromAbove});
  void enterFromAbove();
  void enterFromBelow();

  /// Task lists only — enter Reorder Mode. No-op elsewhere.
  void beginTaskReorderMode() {}

  /// Tables only — insert a column after the current/last cell. No-op elsewhere.
  void addColumnAfterCurrent() {}

  /// Tables only — insert a row after the current/last cell. No-op elsewhere.
  void addRowAfterCurrent() {}

  /// Tables only — enter row Reorder Mode. No-op elsewhere.
  void beginTableReorderRows() {}

  /// Tables only — enter column Reorder Mode. No-op elsewhere.
  void beginTableReorderColumns() {}

  /// Chrome / block-level right-click: freeze the whole embed text as the mark
  /// (not a single line). No-op when the embed has no text field.
  void prepareObjectMenuMark() {}

  /// Phone arrow pad — stay inside this object (edges are no-ops).
  void nudgeInner(AxisDirection direction) {}
}

mixin EmbedLineGatewayMixin implements EmbedCaretGateway {
  @override
  void enterFromAbove() {
    if (lineCount <= 0) return;
    focusLine(0, fromAbove: true);
  }

  @override
  void enterFromBelow() {
    if (lineCount <= 0) return;
    focusLine(lineCount - 1, fromAbove: false);
  }

  @override
  void beginTaskReorderMode() {}

  @override
  void addColumnAfterCurrent() {}

  @override
  void addRowAfterCurrent() {}

  @override
  void beginTableReorderRows() {}

  @override
  void beginTableReorderColumns() {}

  @override
  void prepareObjectMenuMark() {}

  @override
  void nudgeInner(AxisDirection direction) {}
}

/// ↑/↓ within an embed only. At the first/last line, do nothing (Shift+Enter leaves).
void navigateEmbedLine({
  required int lineIndex,
  required int lineCount,
  required void Function(int index, {required bool fromAbove}) focusLine,
  required bool goingDown,
}) {
  if (lineCount <= 0) return;
  if (goingDown) {
    if (lineIndex < lineCount - 1) {
      focusLine(lineIndex + 1, fromAbove: true);
    }
    return;
  }
  if (lineIndex > 0) {
    focusLine(lineIndex - 1, fromAbove: false);
  }
}

void focusFieldLine(
  FocusNode focus,
  TextEditingController controller, {
  required bool fromAbove,
}) {
  _placeInnerCaret(controller, atStart: fromAbove);
  focus.requestFocus();
  // Super Editor may still be releasing the IME this frame (especially right
  // after insert + document reload). Re-claim focus once the tree settles so
  // Hebrew/Latin typing continues without a manual click. iOS also resets
  // the caret to 0 on a new field — put it back after the handoff.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!focus.canRequestFocus) return;
    if (!focus.hasFocus) focus.requestFocus();
    _placeInnerCaret(controller, atStart: fromAbove);
  });
}

void _placeInnerCaret(
  TextEditingController controller, {
  required bool atStart,
}) {
  final text = controller.text;
  if (text == imeEmptySentinel) {
    controller.selection = const TextSelection.collapsed(offset: 1);
    return;
  }
  controller.selection = TextSelection.collapsed(
    offset: atStart ? 0 : text.length,
  );
}

class EmbedCaretRegistry extends ChangeNotifier {
  final _gateways = <String, EmbedCaretGateway>{};

  void register(EmbedCaretGateway gateway) {
    _gateways[gateway.nodeId] = gateway;
  }

  void unregister(String nodeId) {
    _gateways.remove(nodeId);
  }

  EmbedCaretGateway? operator [](String nodeId) => _gateways[nodeId];
}

/// Registry + Shift+Enter leave → SE block caret.
class EmbedCaretScope extends InheritedWidget {
  const EmbedCaretScope({
    super.key,
    required this.registry,
    required this.onExitObject,
    required super.child,
  });

  final EmbedCaretRegistry registry;
  final void Function(String nodeId) onExitObject;

  static EmbedCaretScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<EmbedCaretScope>();
  }

  @override
  bool updateShouldNotify(EmbedCaretScope oldWidget) {
    return registry != oldWidget.registry ||
        onExitObject != oldWidget.onExitObject;
  }
}

/// Shift+Enter opens an object; Enter on an object inserts a paragraph below it.
class EmbedCaretPlugin extends SuperEditorPlugin {
  EmbedCaretPlugin({required this.registry, required this.caretSession})
    : _tapDelegate = _EmbedAwareTapDelegate(caretSession);

  final EmbedCaretRegistry registry;
  final DocumentCaretSession caretSession;
  final _EmbedAwareTapDelegate _tapDelegate;

  @override
  List<SuperEditorKeyboardAction> get keyboardActions => [_onEnter];

  /// Halts SE double-tap word-select while an embed owns the caret, and on
  /// chrome / non-text hits of an object block — otherwise SE tries to select
  /// the embed node, we clear via
  /// [DocumentCaretSession.suppressDocumentSelectionWhileEmbedOwns], then
  /// Super Editor null-checks `selectionNotifier.value!` and crashes. Inner
  /// fields keep Flutter word-select.
  @override
  List<ContentTapDelegate> get contentTapHandlers => [_tapDelegate];

  Map<String, SuperEditorSelectorHandler> get selectorHandlers {
    return {
      ...defaultEditorSelectorHandlers,
      MacOsSelectors.insertTab: indentListItem,
      MacOsSelectors.insertNewLine: (ctx) {
        if (HardwareKeyboard.instance.isShiftPressed) {
          tryEnterObject(ctx);
          return;
        }
        if (!tryInsertLineBelowObject(ctx)) {
          insertNewLine(ctx);
        }
      },
    };
  }

  ObjectEmbedNode? _embedAtCaret(SuperEditorContext editContext) {
    final selection = editContext.composer.selection;
    if (selection == null || !selection.isCollapsed) return null;
    final node = editContext.document.getNodeById(selection.extent.nodeId);
    return node is ObjectEmbedNode ? node : null;
  }

  /// Shift+Enter while SE caret is on an enterable embed → first inner line.
  bool tryEnterObject(SuperEditorContext editContext) {
    final node = _embedAtCaret(editContext);
    if (node == null) return false;
    final gateway = registry[node.id];
    if (gateway == null) return false;

    caretSession.adoptEmbed(node.id);
    // Next frame only — enter/leave is a distinct key from inner typing; waiting
    // for keys-clear (runAfterKeystroke) felt like a half-second stall.
    runNextFrame(() {
      caretSession.adoptEmbed(node.id);
      gateway.enterFromAbove();
    });
    return true;
  }

  /// Enter on an object block → empty paragraph underneath (keep writing).
  bool tryInsertLineBelowObject(SuperEditorContext editContext) {
    final node = _embedAtCaret(editContext);
    if (node == null) return false;

    final id = Editor.createNodeId();
    editContext.editor.execute([
      InsertNodeAfterNodeRequest(
        existingNodeId: node.id,
        newNode: ParagraphNode(id: id, text: AttributedText()),
      ),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: id,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.insertContent,
        SelectionReason.userInteraction,
      ),
    ]);
    return true;
  }

  ExecutionInstruction _onEnter({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    if (keyEvent is! KeyDownEvent && keyEvent is! KeyRepeatEvent) {
      return ExecutionInstruction.continueExecution;
    }
    if (keyEvent.logicalKey != LogicalKeyboardKey.enter &&
        keyEvent.logicalKey != LogicalKeyboardKey.numpadEnter) {
      return ExecutionInstruction.continueExecution;
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      return tryEnterObject(editContext)
          ? ExecutionInstruction.haltExecution
          : ExecutionInstruction.continueExecution;
    }
    return tryInsertLineBelowObject(editContext)
        ? ExecutionInstruction.haltExecution
        : ExecutionInstruction.continueExecution;
  }
}

/// Wraps embed content: Shift+Enter returns to the SE caret on this object.
class EmbedEditScope extends StatelessWidget {
  const EmbedEditScope({super.key, required this.nodeId, required this.child});

  final String nodeId;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void exit() {
      EmbedCaretScope.maybeOf(context)?.onExitObject(nodeId);
    }

    return EmbedExitScope(
      nodeId: nodeId,
      onExit: (_) => exit(),
      child: Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter, shift: true):
              _ExitObjectIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter, shift: true):
              _ExitObjectIntent(),
        },
        child: Actions(
          actions: {
            _ExitObjectIntent: CallbackAction<_ExitObjectIntent>(
              onInvoke: (_) {
                exit();
                return null;
              },
            ),
          },
          child: child,
        ),
      ),
    );
  }
}

class _ExitObjectIntent extends Intent {
  const _ExitObjectIntent();
}

class _EmbedAwareTapDelegate extends ContentTapDelegate {
  _EmbedAwareTapDelegate(this.caretSession);

  final DocumentCaretSession caretSession;

  @override
  TapHandlingInstruction onDoubleTap(DocumentTapDetails details) {
    if (caretSession.owner == DocumentCaretOwner.embed) {
      return TapHandlingInstruction.halt;
    }
    final pos = details.documentLayout.getDocumentPositionNearestToOffset(
      details.layoutOffset,
    );
    if (pos != null && caretSession.isObjectEmbed(pos.nodeId)) {
      return TapHandlingInstruction.halt;
    }
    return TapHandlingInstruction.continueHandling;
  }
}
