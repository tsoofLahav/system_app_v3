import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/app_state.dart';
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
import '../data/app_file.dart';
import '../model/document_text_codec.dart';
import '../model/marker_super_editor_bridge.dart';
import '../model/object_embed_node.dart';
import '../rich_text/block_text_actions.dart';
import '../rich_text/document_context_menu.dart';
import '../rich_text/rtl/rtl.dart';
import './document_caret_session.dart';
import './document_editor_controller.dart';
import './document_secondary_tap.dart';
import './editor_key_handoff.dart';
import './embed_caret_bridge.dart';
import './embed_move_bubble.dart';
import './object_embed_component.dart';
import './selection_background_phase.dart';

/// File editor surface backed by Super Editor + v4 marker-text persistence.
class SuperDocumentEditor extends StatefulWidget {
  const SuperDocumentEditor({
    super.key,
    required this.file,
    required this.state,
    this.embeds = const [],
    this.minViewportHeight,
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;
  final double? minViewportHeight;

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
  String? _lastSavedJson;
  var _applyingRemote = false;

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

  /// Bumped when [_reloadFromStored] swaps [Editor]. Forces a full SuperEditor
  /// remount so DocumentImeInputClient is disposed — SE's didUpdateWidget
  /// recreates the client without disposing the old one, which then serializes
  /// the dead document against the shared composer selection (Escape crash).
  var _superEditorEpoch = 0;

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
      widget.state.selectedDetail?.files
          .where((f) => f.id == widget.file.id)
          .firstOrNull ??
      widget.file;

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
    _doc.addListener(_onDocumentChange);
    _composer.selectionNotifier.addListener(
      _caretSession.suppressDocumentSelectionWhileEmbedOwns,
    );
    _lastSavedJson = _currentFile.documentJson;
    _trackedObjectIds = _objectIdsInDocument();
    widget.state.addListener(_onAppStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DocumentEditorRegistry.register(
        DocumentEditorController(
          fileId: widget.file.id,
          insertAtBlock: _insertAtBlock,
          focusBlock: (_) {},
          flushPendingChanges: _flushPendingChanges,
          focusedTaskId: _focusedTaskId,
        ),
      );
      unawaited(_loadEmbedsQuietly());
      unawaited(_migrateLegacyTablesIfNeeded());
    });
  }

  @override
  void dispose() {
    _removeMoveBubble();
    _saveTimer?.cancel();
    unawaited(_flushPendingChanges());
    DocumentEditorRegistry.unregister(widget.file.id);
    widget.state.removeListener(_onAppStateChanged);
    _doc.removeListener(_onDocumentChange);
    _composer.selectionNotifier.removeListener(
      _caretSession.suppressDocumentSelectionWhileEmbedOwns,
    );
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) _claimFile();
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
    _tryFocusPendingObject();
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
    if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
      runAfterKeystroke(() {
        if (!mounted) return;
        setState(() {});
      });
      return;
    }
    setState(() {});
  }

  Future<void> _loadEmbedsQuietly() async {
    await widget.state.loadEmbedsForFile(widget.file.id, notify: false);
    if (!mounted) return;
    setState(() {
      _embedsSnapshot = widget.state.embedsByFileId[widget.file.id];
    });
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
    await widget.state.updateFile(
      _currentFile,
      {'document_json': json},
      notify: false,
    );
    _lastSavedJson = json;
    _dirty = false;
  }

  ObjectEmbed? _lookup(int objectId) =>
      _embeds.where((e) => e.id == objectId).firstOrNull;

  int? _focusedTaskId() {
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

  Future<void> _insertAtBlock(String action) async {
    await _flushPendingChanges();
    DocumentEditorRegistry.claim(widget.file.id);
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

    if (action == 'paragraph') {
      final id = Editor.createNodeId();
      _editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: seInsertIndex,
          newNode: ParagraphNode(id: id, text: AttributedText()),
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
      return;
    }

    if (action == 'list' || action == 'bullet_list') {
      final id = Editor.createNodeId();
      _editor.execute([
        InsertNodeAtIndexRequest(
          nodeIndex: seInsertIndex,
          newNode: ListItemNode.unordered(
            id: id,
            text: AttributedText(),
          ),
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

  Future<void> _insertObject(String type, int blockIndex) async {
    var apiType = type;
    Map<String, dynamic>? payload;
    if (type == 'graph') {
      // Graph is a table with chart quality (pointer still [GRAPH id]).
      apiType = 'table';
      payload = TableObjectPayload.emptyChart(
        hebrewLabels: widget.state.isRtl,
      );
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
    final updated =
        await widget.state.reloadFile(widget.file.id, notify: false);
    final nodeId = ObjectEmbedNode.idFor(embed.id);
    _embedsSnapshot = widget.state.embedsByFileId[widget.file.id];
    _reloadFromStored(updated.documentJson);
    // After remount, put the caret *inside* the object (Tab-equivalent).
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
    bool tryEnter(EmbedCaretGateway gateway) {
      if (gateway.lineCount <= 0) return false;
      _caretSession.adoptEmbed(nodeId);
      gateway.enterFromAbove();
      return true;
    }

    final gateway = _embedCaretRegistry[nodeId];
    if (gateway != null && tryEnter(gateway)) return;
    // Task-list surface may register one frame later than the embed host.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final late = _embedCaretRegistry[nodeId];
      if (late != null && tryEnter(late)) return;
      _caretSession.placeOnObjectLine(nodeId);
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
    _caretSession.bind(
      editor: _editor,
      document: _doc,
      composer: _composer,
    );
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
    await widget.state.deleteObjectEmbed(objectId);
    final nodeId = ObjectEmbedNode.idFor(objectId);
    if (_doc.getNodeById(nodeId) != null) {
      _editor.execute([DeleteNodeRequest(nodeId: nodeId)]);
    }
    _trackedObjectIds = _objectIdsInDocument();
    _dirty = true;
    await _flushPendingChanges();
  }

  Future<void> _onPayloadChanged(
    int objectId,
    Map<String, dynamic> payload,
  ) async {
    await widget.state.updateObjectPayload(objectId, payload);
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
    _moveBubbleEntry?.markNeedsBuild();
    setState(() {});
    _dirty = true;
    _scheduleSave();
  }

  void _endMoveMode() {
    if (_moveModeNodeId == null) return;
    setState(() => _moveModeNodeId = null);
    _removeMoveBubble();
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
      _claimFile();
      _caretSession.adoptEmbed(nodeId);
    } else {
      _caretSession.embedBlurred();
    }
  }

  void _exitEmbedObject(String nodeId) {
    _caretSession.exitToObjectLine(nodeId);
  }

  /// Full stylesheet (not layered on defaults) — defaults use maxWidth 640 and
  /// 24px paragraph gaps, which look wrong in a file pane.
  Stylesheet get _stylesheet {
    final para = AppTypography.documentParagraphStyle;
    return Stylesheet(
      documentPadding: EdgeInsets.zero,
      inlineTextStyler: defaultInlineTextStyler,
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
          (doc, node) => {
            Styles.padding: const CascadingPadding.only(top: 0),
          },
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
            Styles.padding: const CascadingPadding.only(top: AppSpacing.sm),
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

  SelectionStyles get _selectionStyles => SelectionStyles(
        selectionColor: _selectionFill,
      );

  /// Node under a global pointer — safe when Super Editor is a sliver.
  DocumentNode? _nodeAtGlobalOffset(Offset global) {
    final layout = _docLayoutKey.currentState as DocumentLayout?;
    if (layout == null) return null;
    try {
      final local = layout.getDocumentOffsetFromAncestorOffset(global);
      final pos = layout.getDocumentPositionNearestToOffset(local) ??
          layout.getDocumentPositionAtOffset(local);
      if (pos == null) return null;
      return _doc.getNodeById(pos.nodeId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _onSecondaryTap(TapDownDetails details) async {
    _claimFile();
    // Embed fields show their own menus and mark the gate first.
    if (DocumentSecondaryTap.embedHandled) return;
    if (!mounted) return;

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

    _focusNode.requestFocus();
    if (!mounted) return;

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
      onAction: _handleTextMenuAction,
    );
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
        await DocumentContextMenu.showInfoMenu(
          context: context,
          globalPosition: globalPosition,
          strings: strings,
          onAction: (action) async {
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
            if (action == 'tasks:assign_view' && taskId != null) {
              await showAssignTaskViewDialog(
                context: context,
                state: widget.state,
                taskId: taskId,
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
            onAction: (action) async {
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
        // No object-specific actions yet — keep caret on the block.
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
      TableObjectPayload.normalize({
        ...payload,
        'rows': nextRows,
      }),
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
            for (final row in rows) [...row, {'text': ''}],
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

  Future<void> _applyChartMenuToEmbed(
    ObjectEmbed embed,
    String action,
  ) async {
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
    switch (action) {
      case 'text:bold':
        _docOps.toggleAttributionsOnSelection({boldAttribution});
      case 'text:italic':
        _docOps.toggleAttributionsOnSelection({italicsAttribution});
      case 'text:underline':
        _docOps.toggleAttributionsOnSelection({underlineAttribution});
      case 'text:size_up':
        _applyFontSizeDelta(1.5);
      case 'text:size_down':
        _applyFontSizeDelta(-1.5);
      case 'text:color:clear':
        _clearColorAttribution();
      case 'text:cut':
        if (_composer.selection != null &&
            !_composer.selection!.isCollapsed) {
          _docOps.cut();
        }
      case 'text:copy':
        if (_composer.selection != null &&
            !_composer.selection!.isCollapsed) {
          _docOps.copy();
        }
      case 'text:paste':
        if (_composer.selection != null) _docOps.paste();
      default:
        if (action.startsWith('text:color:') &&
            action != 'text:color:pick' &&
            action != 'text:color:clear') {
          final hex = action.substring('text:color:'.length);
          _applyColorAttribution(AppColors.colorFromHex(hex));
        }
    }
  }

  void _applyFontSizeDelta(double delta) {
    final sel = _composer.selection;
    if (sel == null || sel.isCollapsed) return;
    final base =
        AppTypography.documentParagraphStyle.fontSize ?? 12.5;
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
    while (hi + 1 < _doc.nodeCount &&
        _doc.getNodeAt(hi + 1) is ListItemNode) {
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
          onMoveModeChanged: _onMoveModeChanged,
          onMoveToIndex: _moveEmbedToIndex,
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
      child: GestureDetector(
        onSecondaryTapDown: _onSecondaryTap,
        behavior: HitTestBehavior.translucent,
        child: CustomScrollView(
          slivers: [
            SuperEditor(
              key: ValueKey<int>(_superEditorEpoch),
              editor: _editor,
              focusNode: _focusNode,
              documentLayoutKey: _docLayoutKey,
              stylesheet: _stylesheet,
              selectionStyle: _selectionStyles,
              componentBuilders: _componentBuilders(ambient),
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
              selectionPolicies: const SuperEditorSelectionPolicies(
                clearSelectionWhenEditorLosesFocus: false,
                clearSelectionWhenImeConnectionCloses: false,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
