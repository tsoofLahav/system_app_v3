import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../objects/data/image_payload.dart';
import '../../objects/data/object_embed.dart';
import '../../objects/data/table_payload.dart';
import '../../objects/data/task.dart';
import '../../objects/links/add_connection_dialog.dart';
import '../../objects/tags/assign_object_tags_dialog.dart';
import '../../objects/tasks/task_zones.dart';
import '../../objects/views/assign_task_view_dialog.dart';
import '../../ui/app_color_palettes.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ux/shell/app_bottom_bar.dart';
import '../data/app_file.dart';
import '../model/document_text_codec.dart';
import '../model/marker_super_editor_bridge.dart';
import '../model/object_embed_node.dart';
import '../rich_text/block_text_actions.dart';
import '../rich_text/block_text_focus.dart';
import '../rich_text/document_context_menu.dart';
import '../rich_text/list_text_parse.dart';
import '../rich_text/rtl/rtl.dart';
import '../rich_text/text_links.dart';
import '../../../shared/utils/platform_text.dart';
import '../../production_agent/lookalike_review_dialog.dart';
import '../../production_agent/pending_review_service.dart';
import '../../ux/topic/topic_appearance.dart';
import './document_caret_session.dart';
import './document_editor_controller.dart';
import './document_hunks.dart';
import './document_secondary_tap.dart';
import './document_three_way.dart';
import './edit_conflict.dart';
import './editor_key_handoff.dart';
import './embed_caret_bridge.dart';
import './embed_move_bubble.dart';
import '../../ux/shell/dismiss_focus_on_outside_tap.dart';
import './embeds/image_display_size.dart';
import './embeds/object_design_dialog.dart';
import './embeds/object_look.dart';
import './cmd_click_link_handler.dart';
import './file_editor_keyboard_actions.dart';
import './object_embed_component.dart';
import './phone_mark_toolbar.dart';
import './selection_background_phase.dart';
import './super_editor_mark.dart';
import './visual_ios_handles_layer.dart';

/// Super Editor's overlays, with a caret only while this pane has primary
/// focus (and is the claimed file).
///
/// A pane keeps its selection when it loses focus — the marking is what every
/// action runs on — so hiding the caret is the only thing that stops a blinking
/// cursor after the keyboard closes.
List<SuperEditorLayerBuilder> documentOverlayBuilders({
  required bool withCaret,
}) => [
  for (final builder in defaultSuperEditorDocumentOverlayBuilders)
    if (builder is SuperEditorIosHandlesDocumentLayerBuilder)
      _PaneCaretLayerBuilder(
        const VisualIosHandlesDocumentLayerBuilder(),
        visible: withCaret,
      )
    else if (_drawsCursor(builder))
      _PaneCaretLayerBuilder(builder, visible: withCaret)
    else
      builder,
];

/// The default overlays that put a cursor on screen: the desktop caret, and the
/// iOS / Android handle layers, which draw the caret on their platform.
bool _drawsCursor(SuperEditorLayerBuilder builder) =>
    builder is DefaultCaretOverlayBuilder ||
    builder is SuperEditorIosHandlesDocumentLayerBuilder ||
    builder is SuperEditorAndroidHandlesDocumentLayerBuilder;

/// One of Super Editor's cursor layers, or an empty layer in its place.
///
/// The layer stays in the list either way: `ContentLayers` matches overlays by
/// index and never deactivates one past the end of a shorter list, so a removed
/// layer would go on painting. Styling the caret away does not work either — the
/// blink controller writes its own alpha over the colour, so a transparent caret
/// comes back opaque black.
class _PaneCaretLayerBuilder implements SuperEditorLayerBuilder {
  const _PaneCaretLayerBuilder(this.builder, {required this.visible});

  final SuperEditorLayerBuilder builder;
  final bool visible;

  @override
  ContentLayerWidget build(
    BuildContext context,
    SuperEditorContext editContext,
  ) => visible
      ? builder.build(context, editContext)
      : const ContentLayerProxyWidget(child: SizedBox.shrink());
}

/// No OS autocorrect / suggestion bar — those run on every iOS keystroke.
const kFileEditorImeConfiguration = SuperEditorImeConfiguration(
  enableAutocorrect: false,
  enableSuggestions: false,
);

/// File editor surface backed by Super Editor + v4 marker-text persistence.
class SuperDocumentEditor extends StatefulWidget {
  const SuperDocumentEditor({
    super.key,
    required this.file,
    required this.state,
    this.embeds = const [],
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;

  @override
  State<SuperDocumentEditor> createState() => _SuperDocumentEditorState();
}

class _SuperDocumentEditorState extends State<SuperDocumentEditor> {
  late MutableDocument _doc;
  late MutableDocumentComposer _composer;
  late Editor _editor;
  late CommonEditorOperations _docOps;
  late FocusNode _focusNode;
  final _docLayoutKey = GlobalKey();

  Timer? _saveTimer;
  var _dirty = false;
  var _conflictOpen = false;
  final _phoneObjectGate = PhoneObjectGateSignal();
  String? _lastSavedJson;
  var _applyingRemote = false;
  var _snappingComposerGraphemes = false;
  Offset? _bidiDragDownGlobal;

  /// Object ids currently present as embed nodes — used to cascade-delete
  /// when Super Editor removes a pointer without going through [_deleteObject].
  var _trackedObjectIds = <int>{};
  String? _moveModeNodeId;
  OverlayEntry? _moveBubbleEntry;
  List<ObjectEmbed>? _embedsSnapshot;
  late final VisibleSelectionPlugin _visibleSelectionPlugin;
  late final EmbedCaretRegistry _embedCaretRegistry;
  late final EmbedCaretPlugin _embedCaretPlugin;
  late final SuperEditorVisualCaretPlugin _visualCaretPlugin;
  late final DocumentCaretSession _caretSession;
  late final SuperEditorIosControlsController _iosControls;
  var _phoneCaretMenuWanted = false;

  /// Bumped when [_reloadFromStored] swaps [Editor]. Forces a full SuperEditor
  /// remount so DocumentImeInputClient is disposed — SE's didUpdateWidget
  /// recreates the client without disposing the old one, which then serializes
  /// the dead document against the shared composer selection (Escape crash).
  var _superEditorEpoch = 0;

  /// Paint a caret only while this pane is claimed *and* has primary focus.
  /// A collapsed selection can stay (the marking is what actions run on) —
  /// the caret is what has to go when the keyboard closes.
  var _showCaret = false;
  var _embedFocusGen = 0;

  /// Tight constant gap between blocks (Enter creates a new paragraph).
  static const _blockGap = AppSpacing.blockGap;

  /// Opaque wash — translucent paints are easy to miss on dense Hebrew glyphs,
  /// and SE's beneath-layer highlight is unreliable for RTL (see
  /// [VisibleSelectionPlugin]).
  static final _selectionFill = Color.alphaBlend(
    AppColors.primary.withValues(alpha: 0.34),
    AppColors.noteTop,
  );

  AppFile get _currentFile =>
      widget.state.fileById(widget.file.id) ?? widget.file;

  List<ObjectEmbed> get _embeds =>
      widget.state.embedsByFileId[widget.file.id] ??
      _embedsSnapshot ??
      widget.embeds;

  @override
  void initState() {
    super.initState();
    _embedsSnapshot =
        widget.state.embedsByFileId[widget.file.id] ?? widget.embeds;
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChanged);
    _composer = MutableDocumentComposer();
    _doc = markerTextToMutableDocument(_currentFile.documentJson);
    _editor = createDefaultDocumentEditor(
      document: _doc,
      composer: _composer,
      isHistoryEnabled: true,
    );
    _visibleSelectionPlugin = VisibleSelectionPlugin(color: _selectionFill);
    _embedCaretRegistry = EmbedCaretRegistry();
    _caretSession = DocumentCaretSession(
      editor: _editor,
      document: _doc,
      composer: _composer,
      editorFocus: _focusNode,
    );
    _embedCaretPlugin = EmbedCaretPlugin(
      registry: _embedCaretRegistry,
      caretSession: _caretSession,
    );
    _visualCaretPlugin = SuperEditorVisualCaretPlugin(
      ambient: TextDirection.ltr,
    );
    _docOps = CommonEditorOperations(
      editor: _editor,
      document: _doc,
      composer: _composer,
      documentLayoutResolver: () =>
          _docLayoutKey.currentState as DocumentLayout,
    );
    _iosControls = SuperEditorIosControlsController(
      handleColor: AppColors.primary,
      toolbarBuilder: (context, key, focalPoint) => PhoneIosMarkToolbar(
        focalPoint: focalPoint,
        strings: widget.state.strings,
        onCut: () {
          _phoneCaretMenuWanted = false;
          _iosControls.hideToolbar();
          unawaited(_handleTextMenuAction('text:cut'));
        },
        onCopy: () {
          _phoneCaretMenuWanted = false;
          _iosControls.hideToolbar();
          unawaited(_handleTextMenuAction('text:copy'));
        },
        onPaste: () {
          _phoneCaretMenuWanted = false;
          _iosControls.hideToolbar();
          unawaited(_handleTextMenuAction('text:paste'));
        },
        onMore: _onPhoneMore,
      ),
    );
    _iosControls.handleBeingDragged.addListener(_syncPhoneMarkToolbar);
    _doc.addListener(_onDocumentChange);
    _composer.selectionNotifier.addListener(_onComposerSelection);
    _lastSavedJson = _currentFile.documentJson;
    _trackedObjectIds = _objectIdsInDocument();
    widget.state.addListener(_onAppStateChanged);
    DocumentEditorRegistry.notifier.addListener(_onClaimedPaneChanged);
    BlockTextFocusRegistry.menuSessionListenable.addListener(
      _onMenuSessionChanged,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DocumentEditorRegistry.register(
        DocumentEditorController(
          fileId: widget.file.id,
          insertAtBlock: _insertAtBlock,
          focusBlock: (_) {},
          flushPendingChanges: _flushPendingChanges,
          focusedTaskId: _focusedTaskId,
          markedTextForAgent: _markedTextForAgent,
          applyTextAction: _handleTextMenuAction,
          toggleMoveMode: _toggleMoveModeFromShortcut,
          toggleEmbedReorder: _toggleEmbedReorderFromShortcut,
          restoreWritingFocus: _restoreWritingFocus,
          dismissLiveMark: _dismissLiveMark,
          isFocused: () => _focusNode.hasFocus,
          isPrimaryFocused: () => _focusNode.hasPrimaryFocus,
          canEnterObject: _canEnterObject,
          canLeaveObject: _canLeaveObject,
          enterObject: _enterObjectFromPhone,
          leaveObject: _leaveObjectFromPhone,
          nudgeObjectCaret: _nudgeObjectCaretFromPhone,
          isDirty: () => _fileHasUnsaved,
        ),
      );
      unawaited(_loadEmbedsQuietly());
      unawaited(_migrateLegacyTablesIfNeeded());
      _tryFocusPendingFile();
    });
  }

  @override
  void dispose() {
    _removeMoveBubble();
    _saveTimer?.cancel();
    UnsavedEmbedEdits.fileConflictPending = false;
    unawaited(_flushPendingChanges());
    DocumentEditorRegistry.notifier.removeListener(_onClaimedPaneChanged);
    BlockTextFocusRegistry.menuSessionListenable.removeListener(
      _onMenuSessionChanged,
    );
    DocumentEditorRegistry.unregister(widget.file.id);
    widget.state.removeListener(_onAppStateChanged);
    _doc.removeListener(_onDocumentChange);
    _composer.selectionNotifier.removeListener(_onComposerSelection);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _iosControls.handleBeingDragged.removeListener(_syncPhoneMarkToolbar);
    _iosControls.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasPrimaryFocus) {
      _claimFile();
      // Descendant object fields also make [_focusNode.hasFocus] true — only
      // primary focus means the body owns writing. Forget the object mark.
      if (!BlockTextFocusRegistry.isInMenuSession) {
        BlockTextFocusRegistry.releaseLiveMark();
        _caretSession.adoptDocument();
      }
      BlockTextFocusRegistry.noteEmojiPickerDocumentFocus();
      _syncPhoneMarkToolbar();
    } else {
      _phoneCaretMenuWanted = false;
      _iosControls.hideToolbar();
    }
    _syncCaretVisibility();
    _bumpPhoneObjectGate();
  }

  void _onComposerSelection() {
    final wasEmbed = _caretSession.owner == DocumentCaretOwner.embed;
    _caretSession.suppressDocumentSelectionWhileEmbedOwns();
    if (wasEmbed && _caretSession.owner == DocumentCaretOwner.document) {
      BlockTextFocusRegistry.releaseLiveMark();
    }
    _snapComposerGraphemes();
    _bumpPhoneObjectGate();
    _syncPhoneMarkToolbar();
  }

  /// Phone: the little Cut/Copy/Paste bar follows the mark, not only the
  /// gesture that created it (double-tap / long-press / handle-up can miss
  /// `showToolbar` when the LeaderLink is not ready yet). A collapsed caret
  /// still shows it after a double-tap so Paste works on an empty spot.
  void _syncPhoneMarkToolbar() {
    if (!phoneMarksWithHandlesOnly) return;
    if (BlockTextFocusRegistry.isInMenuSession) {
      _iosControls.hideToolbar();
      return;
    }
    if (_caretSession.owner == DocumentCaretOwner.embed) {
      _iosControls.hideToolbar();
      return;
    }
    if (_iosControls.handleBeingDragged.value != null) {
      _iosControls.hideToolbar();
      return;
    }
    if (!_focusNode.hasPrimaryFocus) return;
    final sel = _composer.selection;
    final show = sel != null && (!sel.isCollapsed || _phoneCaretMenuWanted);
    if (show) {
      // Next frame: selection leaders (toolbar focal point) exist then.
      // Super Editor also hides the bar on a collapsed double-tap — we
      // re-show after that.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final live = _composer.selection;
        if (live != null &&
            (!live.isCollapsed || _phoneCaretMenuWanted) &&
            _focusNode.hasPrimaryFocus &&
            _caretSession.owner != DocumentCaretOwner.embed &&
            !BlockTextFocusRegistry.isInMenuSession &&
            _iosControls.handleBeingDragged.value == null) {
          _iosControls.showToolbar();
        }
      });
    } else {
      _iosControls.hideToolbar();
    }
  }

  void _onPhoneBodyTextTap() {
    _phoneCaretMenuWanted = false;
    _takeDocumentWriting();
  }

  void _onPhoneBodyDoubleTap() {
    _phoneCaretMenuWanted = true;
    _syncPhoneMarkToolbar();
  }

  /// A mark that splits an emoji surrogate pair crashes Super Editor layout.
  void _snapComposerGraphemes() {
    if (_snappingComposerGraphemes) return;
    final sel = _composer.selection;
    if (sel == null) return;
    final next = snapDocumentSelection(_doc, sel);
    if (next == sel) return;
    _snappingComposerGraphemes = true;
    _composer.setSelectionWithReason(next, SelectionReason.userInteraction);
    _snappingComposerGraphemes = false;
  }

  void _bumpPhoneObjectGate() {
    if (!isPhoneLayout) return;
    if (!_phoneObjectGate.shouldNotify(
      canEnter: _canEnterObject(),
      canLeave: _canLeaveObject(),
    )) {
      return;
    }
    DocumentEditorRegistry.objectGateNotifier.notify();
  }

  bool _canEnterObject() {
    if (_caretSession.owner == DocumentCaretOwner.embed) return false;
    final selection = _composer.selection;
    if (selection == null || !selection.isCollapsed) return false;
    return _doc.getNodeById(selection.extent.nodeId) is ObjectEmbedNode;
  }

  bool _canLeaveObject() =>
      _caretSession.owner == DocumentCaretOwner.embed &&
      _caretSession.activeEmbedNodeId != null;

  void _enterObjectFromPhone() {
    if (!_canEnterObject()) return;
    final nodeId = _composer.selection!.extent.nodeId;
    final gateway = _embedCaretRegistry[nodeId];
    if (gateway == null) return;
    _caretSession.adoptEmbed(nodeId);
    runWhenKeyboardIdle(() {
      runNextFrame(() {
        _caretSession.adoptEmbed(nodeId);
        gateway.enterFromAbove();
        _bumpPhoneObjectGate();
      });
    });
  }

  void _leaveObjectFromPhone() {
    final id = _caretSession.activeEmbedNodeId;
    if (id == null) return;
    _exitEmbedObject(id);
    _bumpPhoneObjectGate();
  }

  void _nudgeObjectCaretFromPhone(AxisDirection direction) {
    if (_canLeaveObject()) {
      final id = _caretSession.activeEmbedNodeId;
      if (id == null) return;
      _embedCaretRegistry[id]?.nudgeInner(direction);
      return;
    }
    if (!_canEnterObject()) return;
    if (direction == AxisDirection.left || direction == AxisDirection.right) {
      return;
    }
    final selection = _composer.selection;
    if (selection == null) return;
    final index = _doc.getNodeIndexById(selection.extent.nodeId);
    if (index < 0) return;
    final next = direction == AxisDirection.down ? index + 1 : index - 1;
    if (next < 0 || next >= _doc.nodeCount) return;
    final node = _doc.getNodeAt(next);
    if (node == null) return;
    _editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: node.id,
            nodePosition: node.beginningPosition,
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    _focusNode.requestFocus();
    _bumpPhoneObjectGate();
  }

  /// Caret visibility, and one live mark: a pane that is no longer claimed
  /// drops its selection so it cannot leak into agent hints or stay painted.
  void _onClaimedPaneChanged() {
    if (DocumentEditorRegistry.activeFileId != widget.file.id) {
      if (_composer.selection != null) {
        _composer.clearSelection();
      }
      if (BlockTextFocusRegistry.markBelongsTo(_ownsFocusNode)) {
        BlockTextFocusRegistry.releaseLiveMark();
      }
    }
    _syncCaretVisibility();
  }

  /// Right-click expands the caret line for the menu. When that menu closes
  /// because writing moved to another file or object, drop the leftover wash.
  void _onMenuSessionChanged() {
    if (BlockTextFocusRegistry.isInMenuSession) {
      _iosControls.hideToolbar();
      return;
    }
    _syncPhoneMarkToolbar();
    if (DocumentEditorRegistry.activeFileId != widget.file.id) {
      if (_composer.selection != null) {
        _composer.clearSelection();
      }
      return;
    }
    if (_caretSession.owner == DocumentCaretOwner.embed ||
        !_focusNode.hasPrimaryFocus) {
      final sel = _composer.selection;
      if (sel != null && !sel.isCollapsed) {
        _composer.clearSelection();
      }
    }
  }

  bool _ownsFocusNode(FocusNode node) {
    final ctx = node.context;
    if (ctx == null || !ctx.mounted) return false;
    return ctx.findAncestorStateOfType<_SuperDocumentEditorState>() == this;
  }

  void _syncCaretVisibility() {
    if (!mounted) return;
    final show =
        _focusNode.hasPrimaryFocus &&
        _caretSession.owner != DocumentCaretOwner.embed &&
        DocumentEditorRegistry.activeFileId == widget.file.id;
    if (show == _showCaret) return;
    setState(() => _showCaret = show);
  }

  void _onDocumentChange(DocumentChangeLog changeLog) {
    if (_applyingRemote) return;
    final live = _objectIdsInDocument();
    final removed = _trackedObjectIds.difference(live);
    _trackedObjectIds = live;
    _dirty = true;
    _scheduleSave();
    if (removed.isNotEmpty) {
      unawaited(_cascadeDeleteRemovedObjects(removed));
    }
  }

  Set<int> _objectIdsInDocument() {
    final ids = <int>{};
    for (var i = 0; i < _doc.nodeCount; i++) {
      final node = _doc.getNodeAt(i);
      if (node is ObjectEmbedNode) ids.add(node.objectId);
    }
    return ids;
  }

  /// SE selection Backspace/Delete/Cut drops the node only — still must
  /// DELETE the object row (diagram + agent text stay clean).
  Future<void> _cascadeDeleteRemovedObjects(Set<int> ids) async {
    for (final id in ids) {
      try {
        await widget.state.deleteObjectEmbed(id);
      } catch (_) {
        // Best-effort; file PATCH also purges unreferenced embeds.
      }
    }
  }

  void _onAppStateChanged() {
    final embeds = widget.state.embedsByFileId[widget.file.id];
    if (embeds != null && !identical(embeds, _embedsSnapshot) && mounted) {
      final prev = _embedsSnapshot;
      // Always track the latest list identity. Payload-only patches (table/info
      // typing) replace the list without needing a Super Editor rebuild — those
      // remounts mid-KeyDown desync HardwareKeyboard ("already pressed").
      final structural = _embedsStructurallyChanged(prev, embeds);
      _embedsSnapshot = embeds;
      if (structural) {
        _scheduleEmbedStructureRebuild();
      }
    }
    final remote = _currentFile.documentJson;
    if (remote != _lastSavedJson) {
      _handleRemoteDocument(remote);
    }
    _tryFocusPendingObject();
    _tryFocusPendingFile();
  }

  bool get _fileHasUnsaved =>
      _dirty || UnsavedEmbedEdits.anyDirtyConflictsWith(_embeds);

  void _handleRemoteDocument(String? remote) {
    final local = mutableDocumentToMarkerText(_doc);
    final decision = decideRemoteEdit(
      localDirty: _fileHasUnsaved,
      inboundEqualsLocal: remote == local,
      inboundEqualsBaseline: remote == _lastSavedJson,
    );
    switch (decision) {
      case RemoteEditDecision.ignore:
        if (remote == local) {
          _lastSavedJson = remote;
          _dirty = false;
        }
        return;
      case RemoteEditDecision.takeRemote:
        _saveTimer?.cancel();
        _dirty = false;
        _scheduleRemoteDocumentReload(remote);
        return;
      case RemoteEditDecision.ask:
        UnsavedEmbedEdits.fileConflictPending = true;
        _mergeOrReviewRemote(remote);
        return;
    }
  }

  void _mergeOrReviewRemote(String? remote) {
    if (_conflictOpen || remote == null) {
      UnsavedEmbedEdits.fileConflictPending = false;
      return;
    }
    runWhenKeyboardIdle(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _conflictOpen) return;
        unawaited(_runThreeWay(remote));
      });
    });
  }

  Future<void> _runThreeWay(String remote) async {
    final local = mutableDocumentToMarkerText(_doc);
    final base = _lastSavedJson ?? local;
    final result = threeWayMarkerText(
      base: base,
      local: local,
      server: remote,
    );
    if (!result.hasConflicts) {
      UnsavedEmbedEdits.fileConflictPending = false;
      _applyMergedDocument(
        result.merged,
        persist: result.merged != remote,
      );
      return;
    }

    final hunks = buildHunks(result.localSided, result.serverSided);
    if (hunks.isEmpty) {
      UnsavedEmbedEdits.fileConflictPending = false;
      _applyMergedDocument(result.localSided, persist: true);
      return;
    }

    _conflictOpen = true;
    try {
      if (!mounted) return;
      final detail = widget.state.selectedDetail;
      await LookalikeReviewDialog.show(
        context,
        pending: PendingReview(
          id: 0,
          fileId: widget.file.id,
          oldAgentText: result.localSided,
          newAgentText: result.serverSided,
          hunks: hunks,
        ),
        strings: widget.state.strings,
        fileName: _currentFile.name,
        topicAccent:
            detail == null ? null : TopicAppearance.accentFor(detail.topic),
        onFinish: (decisions) async {
          final merged = mergeHunkTexts(
            result.localSided,
            result.serverSided,
            decisions,
          );
          if (merged == null) {
            throw StateError('every hunk must have accept or reject');
          }
          _applyMergedDocument(merged, persist: true);
        },
        onDiscard: () async {
          _applyMergedDocument(result.localSided, persist: true);
        },
      );
    } finally {
      _conflictOpen = false;
      UnsavedEmbedEdits.fileConflictPending = false;
    }
  }

  void _applyMergedDocument(String json, {required bool persist}) {
    runWhenKeyboardIdle(() {
      if (!mounted) return;
      _saveTimer?.cancel();
      _reloadFromStored(json);
      if (!persist) return;
      unawaited(
        widget.state.updateFile(_currentFile, {
          'document_json': json,
        }, notify: false),
      );
    });
  }

  void _scheduleRemoteDocumentReload(String? json) {
    if (!mounted) return;
    void apply() {
      if (!mounted) return;
      final latest = _currentFile.documentJson;
      if (latest == _lastSavedJson) return;
      _reloadFromStored(latest);
    }

    runWhenKeyboardIdle(apply);
  }

  /// Ids/types/order changed — not mere payload/title text patches.
  static bool _embedsStructurallyChanged(
    List<ObjectEmbed>? prev,
    List<ObjectEmbed> next,
  ) {
    if (prev == null) return true;
    if (prev.length != next.length) return true;
    for (var i = 0; i < prev.length; i++) {
      if (prev[i].id != next[i].id || prev[i].type != next[i].type) {
        return true;
      }
    }
    return false;
  }

  void _scheduleEmbedStructureRebuild() {
    if (!mounted) return;
    runWhenKeyboardIdle(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  Future<void> _loadEmbedsQuietly() async {
    await widget.state.loadEmbedsForFile(widget.file.id, notify: false);
    if (!mounted) return;
    final prev = _embedsSnapshot;
    final next = widget.state.embedsByFileId[widget.file.id];
    _embedsSnapshot = next;
    // Task/cell saves refresh the cache. Rebuilding Super Editor for that
    // kills the IME after the first letter (phone has no keys-down guard).
    if (next != null && _embedsStructurallyChanged(prev, next)) {
      _scheduleEmbedStructureRebuild();
    }
  }

  void _tryFocusPendingObject() {
    final pending = widget.state.pendingFocusObjectId;
    if (pending == null) return;
    final hit = _embeds.where((e) => e.id == pending).firstOrNull;
    if (hit == null) return;
    widget.state.takePendingFocusObjectId();
    final nodeId = ObjectEmbedNode.idFor(pending);
    if (_doc.getNodeById(nodeId) == null) return;
    // Enter the object field — never leave an IME caret on the embed block.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _embedCaretRegistry[nodeId]?.enterFromAbove();
    });
  }

  void _tryFocusPendingFile() {
    final pending = widget.state.pendingFocusFileId;
    if (pending == null || pending != widget.file.id) return;
    widget.state.takePendingFocusFileId();
    runWhenKeyboardIdle(() {
      runNextFrame(() {
        if (!mounted) return;
        _placeCaretAtDocumentEnd();
      });
    });
  }

  /// End of the last block — opening a topic, or a tap in the empty pane.
  void _placeCaretAtDocumentEnd() {
    DocumentEditorRegistry.claim(widget.file.id);
    _takeDocumentWriting();
    if (_doc.nodeCount > 0) {
      final node = _doc.getNodeAt(_doc.nodeCount - 1);
      if (node != null) {
        _editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: node.id,
                nodePosition: node.endPosition,
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
      }
    }
    _focusNode.requestFocus();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) unawaited(_flushPendingChanges());
    });
  }

  Future<void> _flushPendingChanges() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    final json = mutableDocumentToMarkerText(_doc);
    if (json == _lastSavedJson) {
      _dirty = false;
      return;
    }
    await widget.state.updateFile(_currentFile, {
      'document_json': json,
    }, notify: false);
    _lastSavedJson = json;
    _dirty = false;
  }

  ObjectEmbed? _lookup(int objectId) =>
      _embeds.where((e) => e.id == objectId).firstOrNull;

  int? _focusedTaskId() {
    final fromField = BlockTextFocusRegistry.activeTaskId;
    if (fromField != null) return fromField;
    final sel = _composer.selection;
    if (sel == null) return null;
    final node = _doc.getNodeById(sel.extent.nodeId);
    if (node is! ObjectEmbedNode || node.objectType != 'task_list') {
      return null;
    }
    final embed = _lookup(node.objectId);
    if (embed == null) return null;
    final tasks = TaskZones.fromTasks(embed.tasks ?? const <Task>[]).all;
    return tasks.isEmpty ? null : tasks.first.id;
  }

  /// Marked span, or the caret line when unmarked — `hints.selected_text`.
  String? _markedTextForAgent() {
    final seSel = _composer.selection;
    final embedLive = BlockTextFocusRegistry.activeFocusNode?.hasFocus == true;
    // Prefer an embed mark only while that field owns typing, or after
    // tap-outside left no Super Editor selection. A leftover object field
    // must not win once the body has a mark.
    if ((embedLive || seSel == null) &&
        BlockTextFocusRegistry.markBelongsTo(_ownsFocusNode)) {
      final embedMark = BlockTextFocusRegistry.resolveMark();
      if (embedMark.isValid) {
        final text = embedMark.text.trim();
        if (text.isNotEmpty) return text;
      }
    }

    final sel = caretLineSelection(_doc, seSel);
    if (sel == null) return null;
    if (!sel.isCollapsed) {
      final text = _plainTextInDocumentSelection(sel).trim();
      return text.isEmpty ? null : text;
    }
    final node = _doc.getNodeById(sel.extent.nodeId);
    if (node is ObjectEmbedNode) {
      return DocumentTextCodec.pointerLine(node.objectId, node.objectType);
    }
    return null;
  }

  String _plainTextInDocumentSelection(DocumentSelection selection) {
    final selectedNodes = _doc.getNodesInside(selection.base, selection.extent);
    final buffer = StringBuffer();
    for (var i = 0; i < selectedNodes.length; i++) {
      final selectedNode = selectedNodes[i];
      late final dynamic nodeSelection;
      if (i == 0) {
        final baseSelectionPosition = selectedNode.id == selection.base.nodeId
            ? selection.base.nodePosition
            : selection.extent.nodePosition;
        final extentSelectionPosition = selectedNodes.length > 1
            ? selectedNode.endPosition
            : selection.extent.nodePosition;
        nodeSelection = selectedNode.computeSelection(
          base: baseSelectionPosition,
          extent: extentSelectionPosition,
        );
      } else if (i == selectedNodes.length - 1) {
        final nodePosition = selectedNode.id == selection.base.nodeId
            ? selection.base.nodePosition
            : selection.extent.nodePosition;
        nodeSelection = selectedNode.computeSelection(
          base: selectedNode.beginningPosition,
          extent: nodePosition,
        );
      } else {
        nodeSelection = selectedNode.computeSelection(
          base: selectedNode.beginningPosition,
          extent: selectedNode.endPosition,
        );
      }
      final nodeContent = selectedNode.copyContent(nodeSelection);
      if (nodeContent == null) continue;
      if (buffer.isNotEmpty) buffer.writeln();
      if (selectedNode is ListItemNode) {
        final ordered = selectedNode.type == ListItemType.ordered;
        final indent = '  ' * selectedNode.indent;
        final index = _listFenceIndex(selectedNode);
        buffer.write(
          '$indent${listItemClipboardPrefix(ordered: ordered, index: index)}$nodeContent',
        );
      } else {
        buffer.write(nodeContent);
      }
    }
    return buffer.toString();
  }

  int _listFenceIndex(ListItemNode item) {
    var index = 0;
    for (var i = 0; i < _doc.nodeCount; i++) {
      final node = _doc.getNodeAt(i);
      if (node is! ListItemNode || node.type != item.type) {
        index = 0;
        continue;
      }
      if (node.id == item.id) return index;
      index++;
    }
    return 0;
  }

  Future<void> _insertAtBlock(String action) async {
    await _flushPendingChanges();
    DocumentEditorRegistry.claim(widget.file.id);

    if (action == 'list' || action == 'bullet_list') {
      if (_convertSelectionToList()) {
        _focusNode.requestFocus();
        return;
      }
    }

    final seInsertIndex = _insertIndexFromSelection();

    if (action == 'task_list' ||
        action == 'info' ||
        action == 'image' ||
        action == 'graph' ||
        action == 'table') {
      final markerGap = markerGapIndexForNodeIndex(_doc, seInsertIndex);
      await _insertObject(action, markerGap);
      return;
    }

    if (action == 'list' || action == 'bullet_list') {
      final id = Editor.createNodeId();
      _editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: seInsertIndex,
          newNode: ListItemNode.unordered(id: id, text: AttributedText()),
        ),
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: id,
              nodePosition: const TextNodePosition(offset: 0),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
      _focusNode.requestFocus();
    }
  }

  int _insertIndexFromSelection() {
    final sel = _composer.selection;
    if (sel == null) return _doc.nodeCount;
    final node = _doc.getNodeById(sel.extent.nodeId);
    if (node == null) return _doc.nodeCount;
    final index = _doc.getNodeIndexById(node.id);
    if (index < 0) return _doc.nodeCount;

    if (node is TextNode) {
      final pos = sel.extent.nodePosition;
      if (pos is TextNodePosition) {
        if (pos.offset <= 0) return index;
        if (pos.offset >= node.text.length) return index + 1;
        // Split mid-text, insert after the first half.
        final newId = Editor.createNodeId();
        _editor.execute([
          SplitParagraphRequest(
            nodeId: node.id,
            splitPosition: TextPosition(offset: pos.offset),
            newNodeId: newId,
            replicateExistingMetadata: false,
          ),
        ]);
        final afterSplit = _doc.getNodeIndexById(node.id);
        return afterSplit + 1;
      }
    }
    return index + 1;
  }

  /// Marked text (or the caret line) becomes one bullet per newline.
  /// Returns false when there is nothing to convert (empty caret / already a list).
  bool _convertSelectionToList({bool ordered = false}) {
    _expandCollapsedToCaretLine();
    final sel = _composer.selection;
    if (sel == null) return false;
    final nodes = _doc.getNodesInside(sel.base, sel.extent);
    if (nodes.isEmpty) return false;
    if (nodes.any((n) => n is ObjectEmbedNode)) return false;
    if (nodes.every((n) => n is ListItemNode)) return false;

    final texts = listItemTextsFromMarkedText(
      _plainTextInDocumentSelection(sel),
    );
    if (texts.isEmpty) return false;

    final firstIndex = _doc.getNodeIndexById(nodes.first.id);
    if (firstIndex < 0) return false;
    final items = listItemsFromPlainLines(texts, ordered: ordered);
    final last = items.last;
    _editor.execute([
      for (final node in nodes.reversed) DeleteNodeRequest(nodeId: node.id),
      for (var i = 0; i < items.length; i++)
        InsertNodeAtIndexRequest(nodeIndex: firstIndex + i, newNode: items[i]),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: last.id,
            nodePosition: last.endPosition,
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
    return true;
  }

  Future<void> _pasteInDocument() async {
    final raw = await getClipboardText();
    if (raw == null) return;
    if (_composer.selection == null) return;
    if (!clipboardLooksLikeList(raw)) {
      _docOps.paste();
      return;
    }
    if (!_composer.selection!.isCollapsed) {
      _docOps.deleteSelection(TextAffinity.downstream);
    }
    final items = listItemsFromClipboard(raw);
    if (items.isEmpty) return;
    final sel = _composer.selection;
    if (sel == null) return;
    final current = _doc.getNodeById(sel.extent.nodeId);
    var index = current == null
        ? _doc.nodeCount
        : _doc.getNodeIndexById(current.id);
    if (index < 0) index = _doc.nodeCount;
    final replaceEmpty =
        current is TextNode && current.text.toPlainText().trim().isEmpty;
    if (!replaceEmpty) {
      final pos = sel.extent.nodePosition;
      if (pos is TextNodePosition && pos.offset > 0) {
        index += 1;
      }
    }
    final last = items.last;
    _editor.execute([
      if (replaceEmpty) DeleteNodeRequest(nodeId: current.id),
      for (var i = 0; i < items.length; i++)
        InsertNodeAtIndexRequest(nodeIndex: index + i, newNode: items[i]),
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: last.id,
            nodePosition: last.endPosition,
          ),
        ),
        SelectionChangeType.insertContent,
        SelectionReason.userInteraction,
      ),
    ]);
  }

  Future<void> _insertObject(String type, int blockIndex) async {
    var apiType = type;
    Map<String, dynamic>? payload;
    if (type == 'graph') {
      // Graph is a table with chart quality (pointer still [GRAPH id]).
      apiType = 'table';
      payload = TableObjectPayload.emptyChart();
    } else if (type == 'image') {
      payload = {'url': '', 'caption': ''};
    } else if (type == 'table') {
      payload = TableObjectPayload.empty();
    }

    // Persist current SE doc first so server insert lands on current markers.
    _dirty = true;
    await _flushPendingChanges();

    final embed = await widget.state.createObjectInDocument(
      _currentFile,
      type: apiType,
      title: apiType == 'info' ? '' : null,
      body: apiType == 'info' ? '' : null,
      payload: payload,
      blockIndex: blockIndex,
    );

    // Silent reload — a shell-wide notify mid-handoff remounts fields and
    // desyncs the IME after the first character.
    final updated = await widget.state.reloadFile(
      widget.file.id,
      notify: false,
    );
    final nodeId = ObjectEmbedNode.idFor(embed.id);
    _embedsSnapshot = widget.state.embedsByFileId[widget.file.id];
    _reloadFromStored(updated.documentJson);
    // After remount, put the caret *inside* the object (enter-equivalent).
    // Images have no inner field — fall back to the block caret (after it).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _enterNewObject(nodeId);
      });
    });
  }

  void _enterNewObject(String nodeId) {
    runWhenKeyboardIdle(() {
      bool tryEnter(EmbedCaretGateway gateway) {
        if (gateway.lineCount <= 0) return false;
        _caretSession.adoptEmbed(nodeId);
        gateway.enterFromAbove();
        return true;
      }

      final gateway = _embedCaretRegistry[nodeId];
      if (gateway != null && tryEnter(gateway)) {
        _bumpPhoneObjectGate();
        return;
      }
      // Task-list surface may register one frame later than the embed host.
      runNextFrame(() {
        if (!mounted) return;
        final late = _embedCaretRegistry[nodeId];
        if (late != null && tryEnter(late)) {
          _bumpPhoneObjectGate();
          return;
        }
        _caretSession.placeOnObjectLine(nodeId);
        _bumpPhoneObjectGate();
      });
    });
  }

  void _reloadFromStored(String? json) {
    _applyingRemote = true;
    _doc.removeListener(_onDocumentChange);
    // Drop any selection before swapping documents — shared composer notifies
    // the still-mounted (old) SuperEditor/IME during the swap otherwise.
    _composer.clearSelection();
    final next = markerTextToMutableDocument(json);
    // Replace nodes in place via editor reset pattern: rebuild editor.
    _editor = createDefaultDocumentEditor(
      document: next,
      composer: _composer,
      isHistoryEnabled: true,
    );
    _doc = next;
    _caretSession.bind(editor: _editor, document: _doc, composer: _composer);
    _docOps = CommonEditorOperations(
      editor: _editor,
      document: _doc,
      composer: _composer,
      documentLayoutResolver: () =>
          _docLayoutKey.currentState as DocumentLayout,
    );
    _doc.addListener(_onDocumentChange);
    _lastSavedJson = json;
    _dirty = false;
    _trackedObjectIds = _objectIdsInDocument();
    _applyingRemote = false;
    // Remount SuperEditor so the prior DocumentImeInputClient is disposed.
    _superEditorEpoch++;
    if (mounted) setState(() {});
  }

  Future<void> _migrateLegacyTablesIfNeeded() async {
    final fences = legacyTableFencesIn(_doc);
    if (fences.isEmpty) return;

    await _flushPendingChanges();
    for (final fence in List<LegacyTableFenceNode>.from(fences)) {
      final index = _doc.getNodeIndexById(fence.id);
      if (index < 0) continue;
      final embed = await widget.state.createObjectInDocument(
        _currentFile,
        type: 'table',
        payload: TableObjectPayload.fromRowStrings(fence.rows),
        blockIndex: index,
      );
      // Server inserts a pointer; remove the legacy fence by reloading.
      // createObjectInDocument already inserted — but fence may still be in
      // stored text. Strip fence by rewriting from SE after replace.
      _editor.execute([
        ReplaceNodeRequest(
          existingNodeId: fence.id,
          newNode: ObjectEmbedNode(
            id: ObjectEmbedNode.idFor(embed.id),
            objectId: embed.id,
            objectType: 'table',
          ),
        ),
      ]);
      // Server also inserted a pointer — reload and dedupe.
      final updated = await widget.state.reloadFile(widget.file.id);
      var body = DocumentTextCodec.stripHeader(updated.documentJson);
      // Remove duplicate pointer / leftover fence for this object.
      final pointer = DocumentTextCodec.pointerLine(embed.id, 'table');
      final parts = body
          .split(RegExp(r'\n\n+'))
          .where((p) => p.trim().isNotEmpty)
          .toList();
      final cleaned = <String>[];
      var seenPointer = false;
      for (final p in parts) {
        final t = p.trim();
        if (DocumentTextCodec.pointerRe.hasMatch(t) &&
            t.contains('id="${embed.id}"')) {
          if (seenPointer) continue;
          seenPointer = true;
          cleaned.add(pointer);
          continue;
        }
        if (DocumentTextCodec.classifyTopLevel(t).kind ==
            MarkerPartKind.table) {
          // Drop the migrated fence.
          continue;
        }
        cleaned.add(p);
      }
      if (!seenPointer) {
        cleaned.insert(index.clamp(0, cleaned.length), pointer);
      }
      final wrapped = DocumentTextCodec.wrap(cleaned.join('\n\n'));
      await widget.state.updateFile(_currentFile, {'document_json': wrapped});
      _reloadFromStored(wrapped);
    }
    await widget.state.loadEmbedsForFile(widget.file.id);
  }

  Future<void> _deleteObject(int objectId) async {
    await _flushPendingChanges();
    // Drop from the tracked set first so [_onDocumentChange] does not
    // double-DELETE after the node is removed.
    _trackedObjectIds = {..._trackedObjectIds}..remove(objectId);
    final nodeId = ObjectEmbedNode.idFor(objectId);
    final index = _doc.getNodeIndexById(nodeId);
    String? resumeId;
    if (index >= 0 && index + 1 < _doc.nodeCount) {
      resumeId = _doc.getNodeAt(index + 1)?.id;
    } else if (index > 0) {
      resumeId = _doc.getNodeAt(index - 1)?.id;
    }
    await widget.state.deleteObjectEmbed(objectId);
    if (_doc.getNodeById(nodeId) != null) {
      _editor.execute([DeleteNodeRequest(nodeId: nodeId)]);
    }
    _trackedObjectIds = _objectIdsInDocument();
    _dirty = true;
    await _flushPendingChanges();
    _caretSession.owner = DocumentCaretOwner.document;
    _caretSession.activeEmbedNodeId = null;
    // Embed list notify remounts remaining objects next frame — land the
    // document caret after that so the keyboard stays a writing session.
    runWhenKeyboardIdle(() {
      runNextFrame(() {
        runNextFrame(() {
          if (!mounted) return;
          final id = resumeId;
          if (id == null || _doc.getNodeById(id) == null) {
            _bumpPhoneObjectGate();
            return;
          }
          final node = _doc.getNodeById(id);
          if (node == null) return;
          _editor.execute([
            ChangeSelectionRequest(
              DocumentSelection.collapsed(
                position: DocumentPosition(
                  nodeId: node.id,
                  nodePosition: node.beginningPosition,
                ),
              ),
              SelectionChangeType.placeCaret,
              SelectionReason.userInteraction,
            ),
          ]);
          _focusNode.requestFocus();
          _bumpPhoneObjectGate();
        });
      });
    });
  }

  Future<void> _onPayloadChanged(
    int objectId,
    Map<String, dynamic> payload,
  ) async {
    await widget.state.updateObjectPayload(objectId, payload);
    _replaceEmbedPayload(objectId, payload);
  }

  ObjectEmbedNode? _nextImageNode(int objectId) {
    final index = _doc.getNodeIndexById(ObjectEmbedNode.idFor(objectId));
    if (index < 0 || index + 1 >= _doc.nodeCount) return null;
    final next = _doc.getNodeAt(index + 1);
    if (next is! ObjectEmbedNode) return null;
    final embed = _lookup(next.objectId);
    if (embed == null || embed.type != 'image') return null;
    return next;
  }

  bool _canMergeImageWithNext(int objectId) => _nextImageNode(objectId) != null;

  Future<void> _mergeImageWithNext(int objectId) async {
    final nextNode = _nextImageNode(objectId);
    final keeper = _lookup(objectId);
    final absorbed = nextNode == null ? null : _lookup(nextNode.objectId);
    if (keeper == null || absorbed == null) return;
    final merged = ImageObjectPayload.merge(keeper.payload, absorbed.payload);
    await _onPayloadChanged(objectId, merged);
    await _deleteObject(absorbed.id);
    if (mounted) setState(() {});
  }

  void _replaceEmbedPayload(int objectId, Map<String, dynamic> payload) {
    final list = _embedsSnapshot;
    if (list == null) return;
    _embedsSnapshot = [
      for (final embed in list)
        if (embed.id == objectId) embed.copyWith(payload: payload) else embed,
    ];
  }

  void _onMoveModeChanged(String? nodeId) {
    setState(() => _moveModeNodeId = nodeId);
    // Overlay after this frame so the editor has layout for the anchor.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncMoveBubble();
    });
  }

  void _moveEmbedToIndex(String nodeId, int targetIndex) {
    final current = _doc.getNodeIndexById(nodeId);
    if (current < 0) return;
    final dest = targetIndex.clamp(0, _doc.nodeCount);
    if (dest == current || dest == current + 1) return;
    _editor.execute([
      MoveNodeRequest(
        nodeId: nodeId,
        newIndex: dest > current ? dest - 1 : dest,
      ),
    ]);
    // Stay in Move Mode so the user can keep nudging with the bubble.
    _dirty = true;
    _scheduleSave();
    _rebuildAfterEmbedMove();
  }

  void _rebuildAfterEmbedMove() {
    void apply() {
      if (!mounted) return;
      _moveBubbleEntry?.markNeedsBuild();
      setState(() {});
    }

    // Arrow-key nudge fires while a key is down. Rebuilding Super Editor
    // mid-KeyDown desyncs HardwareKeyboard.
    runWhenKeyboardIdle(apply);
  }

  void _endMoveMode() {
    if (_moveModeNodeId == null) return;
    final movedId = _moveModeNodeId!;
    _moveModeNodeId = null;
    // Drop the bubble after keys are up so its FocusNode is not disposed
    // mid-KeyDown (Enter / Esc).
    runWhenKeyboardIdle(() {
      if (!mounted) return;
      _removeMoveBubble();
      setState(() {});
      DocumentEditorRegistry.claim(widget.file.id);
      final node = _doc.getNodeById(movedId);
      if (node != null) {
        _editor.execute([
          ChangeSelectionRequest(
            DocumentSelection.collapsed(
              position: DocumentPosition(
                nodeId: node.id,
                nodePosition: node.beginningPosition,
              ),
            ),
            SelectionChangeType.placeCaret,
            SelectionReason.userInteraction,
          ),
        ]);
      }
      _focusNode.requestFocus();
    });
  }

  void _restoreWritingFocus() {
    runWhenKeyboardIdle(() {
      DocumentEditorRegistry.claim(widget.file.id);
      final embedFocus = BlockTextFocusRegistry.activeFocusNode;
      if (embedFocus != null &&
          embedFocus.canRequestFocus &&
          embedFocus.context != null) {
        embedFocus.requestFocus();
        return;
      }
      _focusNode.requestFocus();
    });
  }

  /// Tap-outside: hide the caret and drop the live mark (body + object fields).
  void _dismissLiveMark() {
    if (BlockTextFocusRegistry.isInMenuSession) return;
    if (_composer.selection != null) {
      _composer.clearSelection();
    }
    BlockTextFocusRegistry.releaseLiveMark();
    _caretSession.adoptDocument();
    _syncCaretVisibility();
  }

  void _nudgeMoveEmbed({required bool up}) {
    final id = _moveModeNodeId;
    if (id == null) return;
    final i = _doc.getNodeIndexById(id);
    if (i < 0) return;
    if (up) {
      if (i > 0) _moveEmbedToIndex(id, i - 1);
    } else if (i + 1 < _doc.nodeCount) {
      _moveEmbedToIndex(id, i + 2);
    }
  }

  /// Super Editor still has IME focus until the bubble steals it — own arrows
  /// / Enter / Esc so they do not move the caret or insert a line.
  ExecutionInstruction _handleMoveModeKey({
    required SuperEditorContext editContext,
    required KeyEvent keyEvent,
  }) {
    if (_moveModeNodeId == null || !embedMoveModeConsumes(keyEvent)) {
      return ExecutionInstruction.continueExecution;
    }
    switch (embedMoveKeyCommand(keyEvent)) {
      case EmbedMoveKeyCommand.moveUp:
        _nudgeMoveEmbed(up: true);
      case EmbedMoveKeyCommand.moveDown:
        _nudgeMoveEmbed(up: false);
      case EmbedMoveKeyCommand.done:
        _endMoveMode();
      case null:
        break;
    }
    return ExecutionInstruction.haltExecution;
  }

  void _removeMoveBubble() {
    _moveBubbleEntry?.remove();
    _moveBubbleEntry = null;
  }

  void _syncMoveBubble() {
    final moveId = _moveModeNodeId;
    if (moveId == null) {
      _removeMoveBubble();
      return;
    }
    final moveIndex = _doc.getNodeIndexById(moveId);
    if (moveIndex < 0) {
      _removeMoveBubble();
      return;
    }
    if (_moveBubbleEntry != null) {
      _moveBubbleEntry!.markNeedsBuild();
      return;
    }
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;
    final anchor = embedMoveBubbleAnchor(context);
    _moveBubbleEntry = OverlayEntry(
      builder: (overlayContext) {
        final id = _moveModeNodeId;
        if (id == null) return const SizedBox.shrink();
        final index = _doc.getNodeIndexById(id);
        if (index < 0) return const SizedBox.shrink();
        return EmbedMoveBubble(
          // Key keeps drag position / outside-arm across markNeedsBuild.
          key: const ValueKey('embed-move-bubble'),
          anchorGlobal: anchor,
          canMoveUp: index > 0,
          canMoveDown: index + 1 < _doc.nodeCount,
          onMoveUp: () => _nudgeMoveEmbed(up: true),
          onMoveDown: () => _nudgeMoveEmbed(up: false),
          onDone: _endMoveMode,
        );
      },
    );
    overlay.insert(_moveBubbleEntry!);
  }

  void _claimFile() => DocumentEditorRegistry.claim(widget.file.id);

  void _onEmbedInnerFocusChanged(String? nodeId) {
    if (nodeId != null) {
      _embedFocusGen++;
      final already =
          _caretSession.owner == DocumentCaretOwner.embed &&
          _caretSession.activeEmbedNodeId == nodeId;
      _claimFile();
      _caretSession.adoptEmbed(nodeId);
      if (!already) _bumpPhoneObjectGate();
      return;
    }
    // Field-to-field move inside one object briefly reports no inner focus.
    // Blurring now closes the IME; wait one frame in case the next field
    // takes over.
    final gen = _embedFocusGen;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || gen != _embedFocusGen) return;
      if (BlockTextFocusRegistry.isInEmojiPickerSession) return;
      _caretSession.embedBlurred();
      if (!BlockTextFocusRegistry.isInMenuSession) {
        BlockTextFocusRegistry.releaseLiveMark();
      }
      _bumpPhoneObjectGate();
    });
  }

  void _exitEmbedObject(String nodeId) {
    _caretSession.exitToObjectLine(nodeId);
  }

  /// Full stylesheet (not layered on defaults) — defaults use maxWidth 640 and
  /// 24px paragraph gaps, which look wrong in a file pane.
  Stylesheet get _stylesheet {
    final para = AppTypography.documentParagraphStyle;
    final viewPadding = MediaQuery.paddingOf(context);
    final topPresentationInset = isPhoneLayout
        ? viewPadding.top +
            AppBottomBarMetrics.phoneSegmentHeight +
            AppBottomBarMetrics.phoneOmbreFade * 0.75 +
            AppSpacing.xs
        : 0.0;
    final bottomPresentationInset = isPhoneLayout
        ? AppBottomBarMetrics.phoneFileEndBreath(
            MediaQuery.sizeOf(context).height,
          )
        : 0.0;
    return Stylesheet(
      documentPadding: EdgeInsets.only(
        top: topPresentationInset,
        bottom: bottomPresentationInset,
      ),
      inlineTextStyler: (attributions, existing) {
        var style = defaultInlineTextStyler(attributions, existing);
        for (final attribution in attributions) {
          if (attribution is LinkAttribution) {
            style = style.copyWith(
              color: AppColors.descriptionLink,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.descriptionLink,
              decorationThickness: 1,
            );
          }
        }
        return style;
      },
      rules: [
        StyleRule(
          BlockSelector.all,
          (doc, node) => {
            Styles.maxWidth: double.infinity,
            Styles.padding: const CascadingPadding.symmetric(horizontal: 0),
            // Follow paragraph direction (RTL.md) — not absolute left/right.
            Styles.textAlign: TextAlign.start,
            Styles.textStyle: para,
          },
        ),
        StyleRule(
          const BlockSelector('paragraph'),
          (doc, node) => {
            Styles.padding: const CascadingPadding.only(top: _blockGap),
          },
        ),
        StyleRule(
          const BlockSelector('paragraph').first(),
          (doc, node) => {Styles.padding: const CascadingPadding.only(top: 0)},
        ),
        StyleRule(
          const BlockSelector('listItem'),
          (doc, node) => {
            Styles.padding: const CascadingPadding.only(top: _blockGap),
            Styles.textStyle: AppTypography.listItemStyle,
          },
        ),
        StyleRule(
          const BlockSelector('objectEmbed'),
          (doc, node) => {
            Styles.padding: CascadingPadding.only(
              top: isPhoneLayout ? AppSpacing.md : AppSpacing.sm,
            ),
          },
        ),
        StyleRule(
          const BlockSelector('header1'),
          (doc, node) => {
            Styles.padding: const CascadingPadding.only(top: AppSpacing.md),
            Styles.textStyle: AppTypography.documentHeadingStyle(1),
          },
        ),
        StyleRule(
          const BlockSelector('header2'),
          (doc, node) => {
            Styles.padding: const CascadingPadding.only(top: AppSpacing.sm),
            Styles.textStyle: AppTypography.documentHeadingStyle(2),
          },
        ),
        StyleRule(
          const BlockSelector('header3'),
          (doc, node) => {
            Styles.padding: const CascadingPadding.only(top: AppSpacing.sm),
            Styles.textStyle: AppTypography.documentHeadingStyle(3),
          },
        ),
        StyleRule(
          BlockSelector.all.last(),
          (doc, node) => {
            Styles.padding: const CascadingPadding.only(bottom: AppSpacing.lg),
          },
        ),
      ],
    );
  }

  SelectionStyles get _selectionStyles =>
      SelectionStyles(selectionColor: _selectionFill);

  /// Position under a global pointer — safe when Super Editor is a sliver.
  DocumentPosition? _positionAtGlobalOffset(Offset global) {
    final layout = _docLayoutKey.currentState as DocumentLayout?;
    if (layout == null) return null;
    try {
      final local = layout.getDocumentOffsetFromAncestorOffset(global);
      return layout.getDocumentPositionNearestToOffset(local) ??
          layout.getDocumentPositionAtOffset(local);
    } catch (_) {
      return null;
    }
  }

  /// Node under a global pointer — safe when Super Editor is a sliver.
  DocumentNode? _nodeAtGlobalOffset(Offset global) {
    final pos = _positionAtGlobalOffset(global);
    if (pos == null) return null;
    return _doc.getNodeById(pos.nodeId);
  }

  /// Right-click aims at the pointer. An existing mark is kept only when the
  /// click is inside it.
  void _aimCaretAtPointer(Offset global) {
    final layout = _docLayoutKey.currentState as DocumentLayout?;
    if (layout == null) return;
    DocumentPosition? pos;
    try {
      final local = layout.getDocumentOffsetFromAncestorOffset(global);
      pos = bidiDocumentPosition(
        document: _doc,
        layout: layout,
        layoutOffset: local,
        globalOffset: global,
        paddingGoesToLineEnd: true,
      );
    } catch (_) {
      pos = _positionAtGlobalOffset(global);
    }
    if (pos == null) return;
    final sel = _composer.selection;
    if (sel != null && !sel.isCollapsed && sel.containsPosition(_doc, pos)) {
      return;
    }
    _editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(position: pos),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
      const ClearComposingRegionRequest(),
    ]);
  }

  void _onBidiMarkPointerDown(PointerDownEvent event) {
    if ((event.buttons & kPrimaryButton) == 0) return;
    if (event.kind == PointerDeviceKind.trackpad) return;
    _bidiDragDownGlobal = event.position;
  }

  void _onBidiMarkPointerMove(PointerMoveEvent event) {
    if (phoneMarksWithHandlesOnly) return;
    final down = _bidiDragDownGlobal;
    if (down == null) return;
    if ((event.buttons & kPrimaryButton) == 0) return;
    if (event.kind == PointerDeviceKind.trackpad) return;
    if (_caretSession.owner == DocumentCaretOwner.embed) return;
    if (!_focusNode.hasPrimaryFocus) return;
    if ((event.position - down).distance <= kTouchSlop) return;
    _applyBidiDragSelection(down: down, current: event.position);
  }

  void _clearBidiMarkPointer() {
    _bidiDragDownGlobal = null;
  }

  void _applyBidiDragSelection({
    required Offset down,
    required Offset current,
  }) {
    final layout = _docLayoutKey.currentState as DocumentLayout?;
    if (layout == null) return;
    try {
      final downLocal = layout.getDocumentOffsetFromAncestorOffset(down);
      final currentLocal = layout.getDocumentOffsetFromAncestorOffset(current);
      final extent = bidiDocumentPosition(
        document: _doc,
        layout: layout,
        layoutOffset: currentLocal,
        globalOffset: current,
        paddingGoesToLineEnd: false,
      );
      if (extent == null) return;
      final DocumentPosition basePos;
      if (HardwareKeyboard.instance.isShiftPressed) {
        basePos =
            _composer.selection?.base ??
            bidiDocumentPosition(
              document: _doc,
              layout: layout,
              layoutOffset: downLocal,
              globalOffset: down,
              paddingGoesToLineEnd: false,
            ) ??
            extent;
      } else {
        final fromDown = bidiDocumentPosition(
          document: _doc,
          layout: layout,
          layoutOffset: downLocal,
          globalOffset: down,
          paddingGoesToLineEnd: false,
        );
        if (fromDown == null) return;
        basePos = fromDown;
      }
      final next = DocumentSelection(base: basePos, extent: extent);
      if (_composer.selection == next) return;
      _editor.execute([
        ChangeSelectionRequest(
          next,
          SelectionChangeType.expandSelection,
          SelectionReason.userInteraction,
        ),
        const ClearComposingRegionRequest(),
      ]);
    } catch (_) {}
  }

  /// Body claimed typing: forget the object mark and caret, then focus SE.
  ///
  /// Phone: Super Editor's iOS tap handler returns after our BiDi delegate
  /// [TapHandlingInstruction.halt] without requesting focus, so an open
  /// object would otherwise keep the IME and swallow this caret.
  void _takeDocumentWriting() {
    if (BlockTextFocusRegistry.isInMenuSession) return;
    BlockTextFocusRegistry.releaseLiveMark();
    _caretSession.adoptDocument();
    runWhenKeyboardIdle(() {
      if (!mounted) return;
      final primary = FocusManager.instance.primaryFocus;
      if (primary != null && primary != _focusNode) {
        primary.unfocus();
      }
      if (!_focusNode.hasPrimaryFocus) {
        _focusNode.requestFocus();
      }
    });
  }

  Future<void> _onSecondaryTap(TapDownDetails details) async {
    _claimFile();
    // Embed fields show their own menus and mark the gate first — same pointer
    // only. A new right-click is a new pointer and must retarget.
    if (DocumentSecondaryTap.embedHandled) return;
    if (!mounted) return;
    BlockTextFocusRegistry.beginNewPointerAim();

    // Super Editor is hosted as a sliver — never cast documentLayoutKey's
    // render object to RenderBox. Use DocumentLayout's coordinate helper.
    DocumentNode? node = _nodeAtGlobalOffset(details.globalPosition);
    node ??= () {
      final sel = _composer.selection;
      if (sel == null) return null;
      return _doc.getNodeById(sel.extent.nodeId);
    }();

    final strings = widget.state.strings;

    if (node is ObjectEmbedNode) {
      // Chrome / block caret — whole-object menu (not a text line mark).
      // Text fields mark [DocumentSecondaryTap] first and handle their own menu.
      final gateway = _embedCaretRegistry[node.id];
      gateway?.prepareObjectMenuMark();
      await _showObjectEmbedMenu(node, details.globalPosition);
      return;
    }

    _takeDocumentWriting();
    if (!mounted) return;
    _aimCaretAtPointer(details.globalPosition);
    _expandCollapsedToCaretLine();

    if (node is ListItemNode) {
      final listNode = node;
      await DocumentContextMenu.showListMenu(
        context: context,
        globalPosition: details.globalPosition,
        strings: strings,
        isOrdered: listNode.type == ListItemType.ordered,
        onAction: (action) async {
          if (action == 'list:style:bullet' ||
              action == 'list:style:numbered') {
            final wantOrdered = action == 'list:style:numbered';
            // Switch every consecutive list item in this fence.
            _setListFenceType(
              listNode.id,
              wantOrdered ? ListItemType.ordered : ListItemType.unordered,
            );
            return;
          }
          await _handleTextMenuAction(action);
        },
      );
      return;
    }

    await DocumentContextMenu.showTextMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: strings,
      includeMakeList: true,
      onAction: _handleTextMenuAction,
    );
  }

  void _onPhoneMore() {
    _phoneCaretMenuWanted = false;
    _iosControls.hideToolbar();
    final sel = _composer.selection;
    if (sel == null) return;
    runWhenKeyboardIdle(() {
      if (!mounted) return;
      _expandCollapsedToCaretLine();
      final node = _doc.getNodeById(sel.extent.nodeId);
      if (node is ListItemNode) {
        unawaited(
          DocumentContextMenu.showListMenu(
            context: context,
            globalPosition: Offset.zero,
            strings: widget.state.strings,
            isOrdered: node.type == ListItemType.ordered,
            onAction: (action) async {
              if (action == 'list:style:bullet' ||
                  action == 'list:style:numbered') {
                _setListFenceType(
                  node.id,
                  action == 'list:style:numbered'
                      ? ListItemType.ordered
                      : ListItemType.unordered,
                );
                return;
              }
              await _handleTextMenuAction(action);
            },
          ),
        );
        return;
      }
      unawaited(
        DocumentContextMenu.showTextMenu(
          context: context,
          globalPosition: Offset.zero,
          strings: widget.state.strings,
          includeMakeList: true,
          onAction: _handleTextMenuAction,
        ),
      );
    });
  }

  Future<void> _showObjectEmbedMenu(
    ObjectEmbedNode node,
    Offset globalPosition,
  ) async {
    final embed = _lookup(node.objectId);
    if (embed == null || !mounted) return;
    final strings = widget.state.strings;
    final type = embed.type == 'graph' ? 'table' : embed.type;

    switch (type) {
      case 'info':
        await DocumentContextMenu.showInfoChromeMenu(
          context: context,
          globalPosition: globalPosition,
          strings: strings,
          onAction: (action) async {
            if (action == 'object:move_mode') {
              _toggleMoveModeForNode(node.id);
              return;
            }
            if (action == 'object:design') {
              await _openObjectDesign(embed, kind: 'info');
              return;
            }
            if (action == 'info:add_tag') {
              await showAssignObjectTagsDialog(
                context: context,
                state: widget.state,
                embed: embed,
              );
              await _loadEmbedsQuietly();
              return;
            }
            if (action == 'info:add_connection') {
              final pick = await showAddConnectionDialog(
                context: context,
                state: widget.state,
                source: embed,
              );
              if (pick == null) return;
              await widget.state.addRelatedObjectLink(
                embed,
                targetObjectId: pick.objectId,
              );
              await _loadEmbedsQuietly();
              return;
            }
            await runBlockTextAction(action);
          },
        );
      case 'task_list':
        final taskId = _firstTaskId(embed);
        await DocumentContextMenu.showTaskListMenu(
          context: context,
          globalPosition: globalPosition,
          strings: strings,
          includeAssignView: taskId != null,
          onAction: (action) async {
            if (action == 'object:move_mode') {
              _toggleMoveModeForNode(node.id);
              return;
            }
            if (action == 'tasks:assign_view' && taskId != null) {
              await showAssignTaskViewDialog(
                context: context,
                state: widget.state,
                taskIds: [taskId],
              );
              return;
            }
            if (action == 'tasks:reorder_mode') {
              final gateway = _embedCaretRegistry[node.id];
              gateway?.enterFromAbove();
              gateway?.beginTaskReorderMode();
              return;
            }
            await runBlockTextAction(action);
          },
        );
      case 'table':
        final chartOn = TableObjectPayload.chartEnabled(embed.payload);
        if (chartOn) {
          await DocumentContextMenu.showChartMenu(
            context: context,
            globalPosition: globalPosition,
            strings: strings,
            onAction: (action) async {
              if (action == 'object:move_mode') {
                _toggleMoveModeForNode(node.id);
                return;
              }
              if (action == 'object:design') {
                await _openObjectDesign(embed, kind: 'table', isChart: true);
                return;
              }
              if (action == 'table:reorder_columns') {
                final gateway = _embedCaretRegistry[node.id];
                gateway?.enterFromAbove();
                gateway?.beginTableReorderColumns();
                return;
              }
              await _applyChartMenuToEmbed(embed, action);
            },
          );
        } else {
          await DocumentContextMenu.showTableCellMenu(
            context: context,
            globalPosition: globalPosition,
            strings: strings,
            includeConnectInfo: false,
            includeMoveObject: true,
            onAction: (action) async {
              if (action == 'object:move_mode') {
                _toggleMoveModeForNode(node.id);
                return;
              }
              if (action == 'object:design') {
                await _openObjectDesign(embed, kind: 'table');
                return;
              }
              if (action == 'table:add_column') {
                // Prefer the live grid (after current/last cell); payload
                // fallback only if the embed host is not registered yet.
                final gateway = _embedCaretRegistry[node.id];
                if (gateway != null) {
                  gateway.addColumnAfterCurrent();
                } else {
                  await _addColumnToTableEmbedAfterLast(embed);
                }
                return;
              }
              if (action == 'table:add_row') {
                final gateway = _embedCaretRegistry[node.id];
                if (gateway != null) {
                  gateway.addRowAfterCurrent();
                } else {
                  await _addRowToTableEmbedAfterLast(embed);
                }
                return;
              }
              if (action == 'table:reorder_rows') {
                final gateway = _embedCaretRegistry[node.id];
                gateway?.enterFromAbove();
                gateway?.beginTableReorderRows();
                return;
              }
              if (action == 'table:reorder_columns') {
                final gateway = _embedCaretRegistry[node.id];
                gateway?.enterFromAbove();
                gateway?.beginTableReorderColumns();
                return;
              }
              await runBlockTextAction(action);
            },
          );
        }
      case 'image':
        await DocumentContextMenu.showImageMenu(
          context: context,
          globalPosition: globalPosition,
          strings: strings,
          scale: ImageDisplaySize.scaleOf(embed.payload),
          canMergeNext: _canMergeImageWithNext(embed.id),
          onAction: (action) async {
            if (action == 'object:move_mode') {
              _toggleMoveModeForNode(node.id);
              return;
            }
            if (action == 'object:design') {
              await _openObjectDesign(embed, kind: 'image');
              return;
            }
            if (action == 'image:merge_next') {
              await _mergeImageWithNext(embed.id);
              return;
            }
            final next = ImageDisplaySize.apply(action, embed.payload);
            if (next == null) return;
            await _onPayloadChanged(embed.id, next);
            _replaceEmbedPayload(embed.id, next);
            if (mounted) setState(() {});
          },
        );
        return;
      default:
        return;
    }
  }

  int? _firstTaskId(ObjectEmbed embed) {
    final tasks = TaskZones.fromTasks(embed.tasks ?? const <Task>[]).all;
    return tasks.isEmpty ? null : tasks.first.id;
  }

  /// Fallback when the table embed is not mounted — insert after the last row.
  Future<void> _addRowToTableEmbedAfterLast(ObjectEmbed embed) async {
    final payload = TableObjectPayload.normalize(embed.payload);
    if (TableObjectPayload.chartEnabled(payload)) return;
    final rows = TableObjectPayload.rowsOf(payload);
    final colCount = rows.isEmpty
        ? 2
        : rows.map((r) => r.length).fold<int>(0, (a, b) => a > b ? a : b);
    final width = colCount <= 0 ? 2 : colCount;
    final nextRows = [
      ...rows,
      [
        for (var i = 0; i < width; i++) {'text': ''},
      ],
    ];
    await widget.state.updateObjectPayload(
      embed.id,
      TableObjectPayload.normalize({...payload, 'rows': nextRows}),
    );
    await _loadEmbedsQuietly();
  }

  /// Fallback when the table embed is not mounted — insert after the last column.
  Future<void> _addColumnToTableEmbedAfterLast(ObjectEmbed embed) async {
    final payload = TableObjectPayload.normalize(embed.payload);
    final rows = TableObjectPayload.rowsOf(payload);
    final chartOn = TableObjectPayload.chartEnabled(payload);
    final limit = chartOn ? AppColorPalettes.seriesLimit : 64;
    final colCount = rows.isEmpty ? 0 : rows.first.length;
    if (colCount >= limit) return;

    final nextRows = rows.isEmpty
        ? [
            [
              {'text': ''},
              {'text': ''},
            ],
          ]
        : [
            for (final row in rows)
              [
                ...row,
                {'text': ''},
              ],
          ];
    final next = Map<String, dynamic>.from(payload)..['rows'] = nextRows;
    if (chartOn) {
      final chart = Map<String, dynamic>.from(
        TableObjectPayload.chartOf(payload) ?? {'enabled': true},
      );
      final cols = nextRows.first.length;
      final colors = List<String>.from(
        (chart['colors'] as List?)?.map((e) => '$e') ?? const [],
      );
      final hexes = AppColorPalettes.defaultChart.hexes;
      while (colors.length < cols) {
        colors.add(hexes[colors.length % hexes.length]);
      }
      chart['colors'] = colors;
      chart['enabled'] = true;
      next['chart'] = chart;
    }
    await widget.state.updateObjectPayload(
      embed.id,
      TableObjectPayload.normalize(next),
    );
    await _loadEmbedsQuietly();
  }

  Future<void> _openObjectDesign(
    ObjectEmbed embed, {
    required String kind,
    bool isChart = false,
  }) async {
    Map<String, dynamic> livePayload() {
      final live = _lookup(embed.id) ?? embed;
      return kind == 'table'
          ? TableObjectPayload.normalize(live.payload)
          : Map<String, dynamic>.from(live.payload ?? const {});
    }

    final payload = livePayload();
    final chart = TableObjectPayload.chartOf(payload);
    final colors = List<String>.from(
      (chart?['colors'] as List?)?.map((e) => '$e') ?? const [],
    );
    final initialLook = switch (kind) {
      'info' => ObjectLook.infoOf(payload),
      'table' => ObjectLook.tableOf(payload),
      _ => ObjectLook.imageOf(payload),
    };
    await showObjectDesignDialog(
      context: context,
      strings: widget.state.strings,
      kind: kind,
      look: initialLook,
      isChart: isChart,
      chartType: '${chart?['chartType'] ?? 'bar'}',
      paletteId: AppColorPalettes.matchingId(colors),
      greyscale: ObjectLook.imageGreyscaleOf(payload),
      onLook: (look) {
        _writeObjectLook(embed.id, kind, look);
      },
      onChartType: isChart
          ? (type) {
              final live = _lookup(embed.id) ?? embed;
              _applyChartMenuToEmbed(live, 'chart:type:$type');
            }
          : null,
      onPalette: isChart
          ? (id) {
              final live = _lookup(embed.id) ?? embed;
              _applyChartMenuToEmbed(live, 'chart:palette:$id');
            }
          : null,
      onGreyscale: kind == 'image'
          ? (value) {
              final base = livePayload();
              _onPayloadChanged(
                embed.id,
                ObjectLook.withLook(
                  base,
                  ObjectLook.imageOf(base),
                  greyscale: value,
                ),
              );
            }
          : null,
    );
  }

  Future<void> _writeObjectLook(int objectId, String kind, String look) async {
    if (!ObjectLook.looksFor(kind).contains(look)) return;
    final live = _lookup(objectId);
    final raw = live?.payload ?? const <String, dynamic>{};
    final base = kind == 'table'
        ? TableObjectPayload.normalize(raw)
        : Map<String, dynamic>.from(raw);
    final next = ObjectLook.withLook(
      base,
      look,
      greyscale: kind == 'image' ? ObjectLook.imageGreyscaleOf(base) : null,
    );
    await _onPayloadChanged(
      objectId,
      kind == 'table' ? TableObjectPayload.normalize(next) : next,
    );
    if (mounted) setState(() {});
  }

  Future<void> _applyChartMenuToEmbed(ObjectEmbed embed, String action) async {
    final payload = Map<String, dynamic>.from(
      TableObjectPayload.normalize(embed.payload),
    );
    final chart = Map<String, dynamic>.from(
      TableObjectPayload.chartOf(payload) ?? {'enabled': true},
    );
    chart['enabled'] = true;
    if (action.startsWith('chart:type:')) {
      chart['chartType'] = action.substring('chart:type:'.length);
    } else if (action.startsWith('chart:palette:')) {
      final paletteId = action.substring('chart:palette:'.length);
      final rows = TableObjectPayload.rowsOf(payload);
      final cols = rows.isEmpty ? 0 : rows.first.length;
      final palette = AppColorPalettes.byId(paletteId);
      if (palette != null) {
        chart['colors'] = palette.colorsForCount(cols);
      }
    } else {
      return;
    }
    payload['chart'] = chart;
    await widget.state.updateObjectPayload(embed.id, payload);
    await _loadEmbedsQuietly();
  }

  Future<void> _handleTextMenuAction(String action) async {
    final expandsLine =
        action != 'text:paste' && !action.startsWith('text:emoji:');
    if (expandsLine) _expandCollapsedToCaretLine();

    switch (action) {
      case 'text:bold':
        _docOps.toggleAttributionsOnSelection({boldAttribution});
      case 'text:italic':
        _docOps.toggleAttributionsOnSelection({italicsAttribution});
      case 'text:underline':
        _docOps.toggleAttributionsOnSelection({underlineAttribution});
      case 'text:strikethrough':
        _docOps.toggleAttributionsOnSelection({strikethroughAttribution});
      case 'text:make_link':
        _makeLinkOnSelection();
      case 'text:size_up':
        _applyFontSizeDelta(1.5);
      case 'text:size_down':
        _applyFontSizeDelta(-1.5);
      case 'text:color:clear':
        _clearColorAttribution();
      case 'text:cut':
        if (_composer.selection != null && !_composer.selection!.isCollapsed) {
          final text = _plainTextInDocumentSelection(_composer.selection!);
          if (text.isNotEmpty) await setClipboardText(text);
          _docOps.deleteSelection(TextAffinity.downstream);
        }
      case 'text:copy':
        if (_composer.selection != null && !_composer.selection!.isCollapsed) {
          final text = _plainTextInDocumentSelection(_composer.selection!);
          if (text.isNotEmpty) await setClipboardText(text);
        }
      case 'text:paste':
        if (_composer.selection != null) await _pasteInDocument();
      case 'list:make':
        _convertSelectionToList();
      default:
        if (action.startsWith('text:emoji:')) {
          final emoji = action.substring('text:emoji:'.length);
          if (emoji.isNotEmpty) {
            _editor.execute([InsertPlainTextAtCaretRequest(emoji)]);
          }
        } else if (action.startsWith('text:color:') &&
            action != 'text:color:pick' &&
            action != 'text:color:clear') {
          final hex = action.substring('text:color:'.length);
          _applyColorAttribution(AppColors.colorFromHex(hex));
        }
    }
  }

  /// Marked text stays marked. A collapsed caret becomes the line it sits on.
  void _expandCollapsedToCaretLine() {
    final next = caretLineSelection(_doc, _composer.selection);
    final current = _composer.selection;
    if (next == null || current == null) return;
    if (next == current) return;
    _editor.execute([
      ChangeSelectionRequest(
        next,
        SelectionChangeType.expandSelection,
        SelectionReason.userInteraction,
      ),
    ]);
  }

  /// ⌘O when the Super Editor caret sits on a task list or table block.
  bool _toggleEmbedReorderFromShortcut() {
    final selection = _composer.selection;
    if (selection == null || !selection.isCollapsed) return false;
    final node = _doc.getNodeById(selection.extent.nodeId);
    if (node is! ObjectEmbedNode) return false;
    final gateway = _embedCaretRegistry[node.id];
    if (gateway == null) return false;
    if (node.objectType == 'task_list') {
      gateway.beginTaskReorderMode();
      return true;
    }
    if (node.objectType == 'table' || node.objectType == 'graph') {
      final embed = _lookup(node.objectId);
      final chart =
          embed != null && TableObjectPayload.chartEnabled(embed.payload);
      if (chart) {
        gateway.beginTableReorderColumns();
      } else {
        gateway.beginTableReorderRows();
      }
      return true;
    }
    return false;
  }

  void _toggleMoveModeFromShortcut() {
    if (_moveModeNodeId != null) {
      _endMoveMode();
      return;
    }
    String? nodeId = _caretSession.activeEmbedNodeId;
    if (nodeId == null) {
      final sel = _composer.selection;
      if (sel != null) {
        final node = _doc.getNodeById(sel.extent.nodeId);
        if (node is ObjectEmbedNode) nodeId = node.id;
      }
    }
    if (nodeId == null) return;
    _toggleMoveModeForNode(nodeId);
  }

  void _toggleMoveModeForNode(String nodeId) {
    if (_moveModeNodeId == nodeId) {
      _endMoveMode();
      return;
    }
    _onMoveModeChanged(nodeId);
  }

  void _makeLinkOnSelection() {
    final sel = _composer.selection;
    if (sel == null || sel.isCollapsed) return;
    final nodes = _doc.getNodesInside(sel.base, sel.extent);
    for (final node in nodes) {
      if (node is! TextNode) continue;
      final plain = node.text.toPlainText();
      if (plain.isEmpty) continue;
      int start;
      int end;
      if (sel.base.nodeId == node.id && sel.extent.nodeId == node.id) {
        final a = (sel.base.nodePosition as TextNodePosition).offset;
        final b = (sel.extent.nodePosition as TextNodePosition).offset;
        start = a < b ? a : b;
        end = a < b ? b : a;
      } else if (sel.base.nodeId == node.id) {
        final offset = (sel.base.nodePosition as TextNodePosition).offset;
        start = offset;
        end = plain.length;
      } else if (sel.extent.nodeId == node.id) {
        start = 0;
        end = (sel.extent.nodePosition as TextNodePosition).offset;
      } else {
        start = 0;
        end = plain.length;
      }
      final snapped = normalizeUtf16Range(plain, start, end);
      start = snapped.$1;
      end = snapped.$2;
      if (end <= start) continue;
      final slice = safeSubstring(plain, start, end);
      final hit = firstUrlIn(slice);
      if (hit == null) continue;
      final uri = Uri.tryParse(hit.url);
      if (uri == null) continue;
      _editor.execute([
        AddTextAttributionsRequest(
          documentRange: DocumentSelection(
            base: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: start + hit.start),
            ),
            extent: DocumentPosition(
              nodeId: node.id,
              nodePosition: TextNodePosition(offset: start + hit.end),
            ),
          ),
          attributions: {LinkAttribution.fromUri(uri)},
        ),
      ]);
      return;
    }
  }

  void _applyFontSizeDelta(double delta) {
    var sel = _composer.selection;
    if (sel == null) return;
    if (sel.isCollapsed) {
      final node = _doc.getNodeById(sel.extent.nodeId);
      if (node is! TextNode) return;
      final length = node.text.length;
      if (length <= 0) return;
      sel = DocumentSelection(
        base: DocumentPosition(
          nodeId: node.id,
          nodePosition: const TextNodePosition(offset: 0),
        ),
        extent: DocumentPosition(
          nodeId: node.id,
          nodePosition: TextNodePosition(offset: length),
        ),
      );
    }
    final base = AppTypography.documentParagraphStyle.fontSize ?? 12.5;
    // Bump relative to the size already on the text — not always base±delta.
    final current = _fontSizeAt(sel.extent) ?? base;
    final next = (current + delta).clamp(10.0, 28.0);
    _editor.execute([
      AddTextAttributionsRequest(
        documentRange: sel,
        attributions: {FontSizeAttribution(next)},
      ),
    ]);
  }

  /// Current [FontSizeAttribution] at [position], if any.
  double? _fontSizeAt(DocumentPosition position) {
    final node = _doc.getNodeById(position.nodeId);
    if (node is! TextNode) return null;
    final pos = position.nodePosition;
    if (pos is! TextNodePosition) return null;
    final text = node.text;
    if (text.isEmpty) return null;
    final offset = pos.offset.clamp(0, text.length - 1);
    for (final attr in text.getAllAttributionsAt(offset)) {
      if (attr is FontSizeAttribution) return attr.fontSize;
    }
    return null;
  }

  void _applyColorAttribution(Color color) {
    final sel = _composer.selection;
    if (sel == null || sel.isCollapsed) return;
    _editor.execute([
      AddTextAttributionsRequest(
        documentRange: sel,
        attributions: {ColorAttribution(color)},
      ),
    ]);
  }

  void _clearColorAttribution() {
    final sel = _composer.selection;
    if (sel == null || sel.isCollapsed) return;
    _editor.execute([
      AddTextAttributionsRequest(
        documentRange: sel,
        attributions: {ColorAttribution(AppColors.text)},
      ),
    ]);
  }

  void _setListFenceType(String anyItemId, ListItemType type) {
    final start = _doc.getNodeIndexById(anyItemId);
    if (start < 0) return;
    // Expand to the contiguous list fence containing [anyItemId].
    var lo = start;
    while (lo > 0 && _doc.getNodeAt(lo - 1) is ListItemNode) {
      lo--;
    }
    var hi = start;
    while (hi + 1 < _doc.nodeCount && _doc.getNodeAt(hi + 1) is ListItemNode) {
      hi++;
    }
    final requests = <EditRequest>[];
    for (var i = lo; i <= hi; i++) {
      final n = _doc.getNodeAt(i);
      if (n is ListItemNode) {
        requests.add(ChangeListItemTypeRequest(nodeId: n.id, newType: type));
      }
    }
    if (requests.isNotEmpty) _editor.execute(requests);
  }

  List<ComponentBuilder> _componentBuilders(TextDirection ambient) => [
    ObjectEmbedComponentBuilder(
      state: widget.state,
      lookup: _lookup,
      onRefresh: _loadEmbedsQuietly,
      onPayloadChanged: _onPayloadChanged,
      onDelete: _deleteObject,
      onClaimFile: _claimFile,
      onInnerFocusChanged: _onEmbedInnerFocusChanged,
      moveModeNodeId: _moveModeNodeId,
      onMoveToIndex: _moveEmbedToIndex,
      canMergeImageWithNext: _canMergeImageWithNext,
      onMergeImageWithNext: _mergeImageWithNext,
    ),
    const LegacyTableFenceComponentBuilder(),
    ...ambientAwareTextBuilders(ambient),
    const HorizontalRuleComponentBuilder(),
    // Intentionally omit TaskComponentBuilder + ImageComponentBuilder.
  ];

  @override
  Widget build(BuildContext context) {
    // Super Editor always builds a SliverHybridStack. When it finds *any*
    // ancestor Scrollable (the topic canvas is a SingleChildScrollView), it
    // emits that sliver raw — so it must sit in *our* CustomScrollView as a
    // sliver, never under Column/Expanded.
    final ambient = Directionality.of(context);
    _visualCaretPlugin.ambient = ambient;
    return EmbedCaretScope(
      registry: _embedCaretRegistry,
      onExitObject: _exitEmbedObject,
      child: KeepEditorFocus(
        child: SuperEditorIosControlsScope(
          controller: _iosControls,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (event) {
              if ((event.buttons & kSecondaryMouseButton) != 0) {
                DocumentSecondaryTap.notePointer(event.pointer);
              }
              _onBidiMarkPointerDown(event);
            },
            onPointerMove: _onBidiMarkPointerMove,
            onPointerUp: (_) => _clearBidiMarkPointer(),
            onPointerCancel: (_) => _clearBidiMarkPointer(),
            child: GestureDetector(
              onSecondaryTapDown: _onSecondaryTap,
              behavior: HitTestBehavior.translucent,
              child: CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SuperEditor(
                    key: ValueKey<int>(_superEditorEpoch),
                    editor: _editor,
                    focusNode: _focusNode,
                    // One IME identity per file. Panes share the app's single IME
                    // connection, so without a role a second open file registers as
                    // the same input: super_editor throws "duplicate input IDs" and
                    // the two panes fight over the connection.
                    inputRole: 'file-${widget.file.id}',
                    documentLayoutKey: _docLayoutKey,
                    stylesheet: _stylesheet,
                    selectionStyle: _selectionStyles,
                    componentBuilders: _componentBuilders(ambient),
                    keyboardActions: [
                      if (_moveModeNodeId != null) _handleMoveModeKey,
                      ...kFileEditorImeKeyboardActions,
                    ],
                    contentTapDelegateFactories: [
                      cmdClickLinkTapHandlerFactory,
                      bidiCaretTapHandler(
                        onBodyTextTap: _onPhoneBodyTextTap,
                        onBodyDoubleTap: _onPhoneBodyDoubleTap,
                      ),
                    ],
                    documentOverlayBuilders: documentOverlayBuilders(
                      withCaret: _showCaret,
                    ),
                    plugins: {
                      _visibleSelectionPlugin,
                      _visualCaretPlugin,
                      _embedCaretPlugin,
                    },
                    // Tab/Enter embeds + visual ←/→ when the paragraph is RTL.
                    selectorHandlers: withVisualHorizontalSelectors(
                      base: _embedCaretPlugin.selectorHandlers,
                      ambient: ambient,
                    ),
                    shrinkWrap: true,
                    imePolicies: const SuperEditorImePolicies(
                      openImeOnNonPrimaryFocusGain: false,
                      closeKeyboardOnLosePrimaryFocus: true,
                      openKeyboardOnGainPrimaryFocus: true,
                      openKeyboardOnSelectionChange: true,
                      closeKeyboardOnSelectionLost: true,
                    ),
                    imeConfiguration: kFileEditorImeConfiguration,
                    selectionPolicies: const SuperEditorSelectionPolicies(
                      clearSelectionWhenEditorLosesFocus: false,
                      clearSelectionWhenImeConnectionCloses: false,
                    ),
                  ),
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () =>
                          runWhenKeyboardIdle(_placeCaretAtDocumentEnd),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
