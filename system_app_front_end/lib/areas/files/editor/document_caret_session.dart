import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../model/object_embed_node.dart';
import './editor_key_handoff.dart';

/// Who owns typing: Super Editor on the document, or an embed [TextField].
enum DocumentCaretOwner {
  document,
  embed,
  transferring,
}

/// Enter/exit for atomic object blocks.
///
/// Default: SE caret sits on the embed as one block. Tab opens the object;
/// Escape returns the SE caret to that same block. Enter inserts a line under
/// the object (normal SE behavior).
class DocumentCaretSession {
  DocumentCaretSession({
    required Editor editor,
    required Document document,
    required MutableDocumentComposer composer,
    required FocusNode editorFocus,
  })  : _editor = editor,
        _document = document,
        _composer = composer,
        _editorFocus = editorFocus;

  Editor _editor;
  Document _document;
  MutableDocumentComposer _composer;
  final FocusNode _editorFocus;

  DocumentCaretOwner owner = DocumentCaretOwner.document;

  /// Embed node id while an inner field owns the caret (for Escape → block).
  String? activeEmbedNodeId;

  void bind({
    required Editor editor,
    required Document document,
    required MutableDocumentComposer composer,
  }) {
    _editor = editor;
    _document = document;
    _composer = composer;
  }

  /// Inner field focused — drop SE selection so two carets/IMEs do not fight.
  void adoptEmbed(String embedNodeId) {
    owner = DocumentCaretOwner.embed;
    activeEmbedNodeId = embedNodeId;
    _clearSelection();
  }

  void embedBlurred() {
    if (owner == DocumentCaretOwner.transferring) return;
    if (owner == DocumentCaretOwner.embed) {
      owner = DocumentCaretOwner.document;
      activeEmbedNodeId = null;
    }
  }

  void suppressDocumentSelectionWhileEmbedOwns() {
    if (owner != DocumentCaretOwner.embed) return;
    if (_composer.selection == null) return;
    _clearSelection();
  }

  /// Place SE caret on the embed block (atomic object line).
  void placeOnObjectLine(String embedNodeId) {
    final node = _document.getNodeById(embedNodeId);
    if (node is! ObjectEmbedNode) return;
    owner = DocumentCaretOwner.document;
    activeEmbedNodeId = null;
    _editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: embedNodeId,
            nodePosition: const UpstreamDownstreamNodePosition.upstream(),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    _editorFocus.requestFocus();
  }

  /// Leave an embed field: SE caret back on that object's block.
  void exitToObjectLine([String? embedNodeId]) {
    final id = embedNodeId ?? activeEmbedNodeId;
    if (id == null) return;
    owner = DocumentCaretOwner.transferring;
    // Next frame — Escape handoff; avoid runAfterKeystroke's keys-clear wait.
    runNextFrame(() {
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary != _editorFocus) {
        primary.unfocus();
      }
      placeOnObjectLine(id);
    });
  }

  void _clearSelection() {
    if (_composer.selection == null) return;
    _editor.execute([
      const ChangeSelectionRequest(
        null,
        SelectionChangeType.clearSelection,
        SelectionReason.userInteraction,
      ),
    ]);
  }
}
