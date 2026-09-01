import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../model/object_embed_node.dart';
import './editor_key_handoff.dart';

/// Who owns typing: Super Editor on the document, or an embed [TextField].
enum DocumentCaretOwner { document, embed, transferring }

/// Enter/exit for atomic object blocks.
///
/// Default: SE caret sits on the embed as one block. Shift+Enter opens the
/// object. Enter inside leaves (info) or advances; Escape leaves from any
/// inner field. Shift+Enter / ⌘Enter inside insert a newline. Enter on the
/// block inserts a line beside it.
class DocumentCaretSession {
  DocumentCaretSession({
    required Editor editor,
    required Document document,
    required MutableDocumentComposer composer,
    required FocusNode editorFocus,
  }) : _editor = editor,
       _composer = composer,
       _editorFocus = editorFocus {
    assert(identical(document, editor.document));
  }

  Editor _editor;
  MutableDocumentComposer _composer;
  final FocusNode _editorFocus;

  DocumentCaretOwner owner = DocumentCaretOwner.document;

  /// Embed node id while an inner field owns the caret (for Shift+Enter → block).
  String? activeEmbedNodeId;

  /// Always the editor's live document so insert/select and IME serialize agree.
  MutableDocument get _liveDoc => _editor.document;

  void bind({
    required Editor editor,
    required Document document,
    required MutableDocumentComposer composer,
  }) {
    assert(identical(document, editor.document));
    _editor = editor;
    _composer = composer;
  }

  /// Inner field focused — drop SE selection/focus so two carets/IMEs do not fight.
  void adoptEmbed(String embedNodeId) {
    final staying =
        owner == DocumentCaretOwner.embed && activeEmbedNodeId == embedNodeId;
    owner = DocumentCaretOwner.embed;
    activeEmbedNodeId = embedNodeId;
    if (_composer.selection != null) _clearSelection();
    if (staying) return;
    // Release Super Editor's focus node; otherwise the first keystroke often
    // lands in a half-attached IME (one Latin glyph) and then typing dies.
    if (_editorFocus.hasFocus) {
      _editorFocus.unfocus(
        disposition: UnfocusDisposition.previouslyFocusedChild,
      );
    }
  }

  /// Body owns typing. Call when the user clicks or right-clicks a paragraph
  /// (not an inner field). Pair with [BlockTextFocusRegistry.releaseLiveMark].
  void adoptDocument() {
    owner = DocumentCaretOwner.document;
    activeEmbedNodeId = null;
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
    // A click/right-click on a paragraph gives Super Editor primary focus.
    // Keep that selection and leave the object — do not swallow it.
    if (_editorFocus.hasPrimaryFocus) {
      adoptDocument();
      return;
    }
    _clearSelection();
  }

  /// True when [nodeId] is an atomic object block in the live document.
  bool isObjectEmbed(String nodeId) =>
      _liveDoc.getNodeById(nodeId) is ObjectEmbedNode;

  /// Place SE caret in a **text** paragraph after the object.
  ///
  /// Never leave the IME selection on a missing node — Super Editor's
  /// DocumentImeSerializer null-checks node lookup when the keyboard opens.
  void placeOnObjectLine(String embedNodeId) {
    if (_liveDoc.getNodeById(embedNodeId) is! ObjectEmbedNode) return;

    owner = DocumentCaretOwner.document;
    activeEmbedNodeId = null;
    final afterId = _ensureParagraphAfter(embedNodeId);
    if (!_selectTextNode(afterId)) return;
    _requestEditorFocusWhenSelectionIsLive(afterId);
  }

  /// Leave an embed field: SE caret after that object (keep writing below).
  void exitToObjectLine([String? embedNodeId]) {
    final id = embedNodeId ?? activeEmbedNodeId;
    if (id == null) return;
    owner = DocumentCaretOwner.transferring;

    runWhenKeyboardIdle(() {
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary != _editorFocus) {
        primary.unfocus();
      }

      runNextFrame(() {
        if (_liveDoc.getNodeById(id) == null) {
          owner = DocumentCaretOwner.document;
          activeEmbedNodeId = null;
          return;
        }
        owner = DocumentCaretOwner.document;
        activeEmbedNodeId = null;

        final afterId = _ensureParagraphAfter(id);
        if (!_selectTextNode(afterId)) return;
        _requestEditorFocusWhenSelectionIsLive(afterId);
      });
    });
  }

  /// Next text node after [embedNodeId], or a new empty paragraph there.
  String _ensureParagraphAfter(String embedNodeId) {
    final doc = _liveDoc;
    final index = doc.getNodeIndexById(embedNodeId);
    if (index >= 0 && index + 1 < doc.nodeCount) {
      final after = doc.getNodeAt(index + 1);
      if (after is TextNode) return after.id;
    }
    final newId = Editor.createNodeId();
    _editor.execute([
      InsertNodeAfterNodeRequest(
        existingNodeId: embedNodeId,
        newNode: ParagraphNode(id: newId, text: AttributedText()),
      ),
    ]);
    return newId;
  }

  bool _selectTextNode(String nodeId) {
    if (_liveDoc.getNodeById(nodeId) is! TextNode) {
      _clearSelection();
      return false;
    }
    _editor.execute([
      const ClearComposingRegionRequest(),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: nodeId,
            nodePosition: const TextNodePosition(offset: 0),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    return true;
  }

  /// Open SE IME only after the selection node exists in the live document.
  ///
  /// One extra frame lets a SuperEditor remount (after silent reload) finish
  /// wiring a fresh DocumentImeInputClient before SuperIme.openConnection.
  void _requestEditorFocusWhenSelectionIsLive(String nodeId) {
    runNextFrame(() {
      if (_liveDoc.getNodeById(nodeId) is! TextNode) {
        _clearSelection();
        return;
      }
      if (_composer.selection?.extent.nodeId != nodeId) {
        if (!_selectTextNode(nodeId)) return;
      }
      _editorFocus.requestFocus();
    });
  }

  void _clearSelection() {
    if (_composer.selection == null &&
        _composer.composingRegion.value == null) {
      return;
    }
    _editor.execute([
      const ClearComposingRegionRequest(),
      const ChangeSelectionRequest(
        null,
        SelectionChangeType.clearSelection,
        SelectionReason.userInteraction,
      ),
    ]);
  }
}
