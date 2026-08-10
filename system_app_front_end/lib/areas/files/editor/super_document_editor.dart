import 'dart:async';

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/app_state.dart';
import '../../objects/data/object_embed.dart';
import '../../objects/data/task.dart';
import '../../objects/tasks/task_zones.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../data/app_file.dart';
import '../model/document_text_codec.dart';
import '../model/marker_super_editor_bridge.dart';
import '../model/object_embed_node.dart';
import '../rich_text/document_context_menu.dart';
import './document_editor_controller.dart';
import './embeds/table_embed.dart';
import './object_embed_component.dart';

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
  String? _moveModeNodeId;
  List<ObjectEmbed>? _embedsSnapshot;

  /// Tight constant gap between blocks (Enter creates a new paragraph).
  static const _blockGap = AppSpacing.blockGap;

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
    _docOps = CommonEditorOperations(
      editor: _editor,
      document: _doc,
      composer: _composer,
      documentLayoutResolver: () =>
          _docLayoutKey.currentState as DocumentLayout,
    );
    _doc.addListener(_onDocumentChange);
    _lastSavedJson = _currentFile.documentJson;
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
    _saveTimer?.cancel();
    unawaited(_flushPendingChanges());
    DocumentEditorRegistry.unregister(widget.file.id);
    widget.state.removeListener(_onAppStateChanged);
    _doc.removeListener(_onDocumentChange);
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
    _dirty = true;
    _scheduleSave();
  }

  void _onAppStateChanged() {
    final embeds = widget.state.embedsByFileId[widget.file.id];
    if (embeds != null && !identical(embeds, _embedsSnapshot) && mounted) {
      setState(() => _embedsSnapshot = embeds);
    }
    _tryFocusPendingObject();
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
    _editor.execute([
      ChangeSelectionRequest(
        DocumentSelection.collapsed(
          position: DocumentPosition(
            nodeId: nodeId,
            nodePosition: const UpstreamDownstreamNodePosition.upstream(),
          ),
        ),
        SelectionChangeType.placeCaret,
        SelectionReason.userInteraction,
      ),
    ]);
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
    await widget.state.updateFile(_currentFile, {'document_json': json});
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
    Map<String, dynamic>? payload;
    if (type == 'graph') {
      payload = {
        'labels': ['A', 'B'],
        'values': ['1', '2'],
        'chartType': 'bar',
        'colors': ['#37899E', '#58C4D8'],
        'color': '#37899E',
      };
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
      type: type,
      title: type == 'info' ? '' : null,
      body: type == 'info' ? '' : null,
      payload: payload,
      blockIndex: blockIndex,
    );

    final updated = await widget.state.reloadFile(widget.file.id);
    _reloadFromStored(updated.documentJson);
    final nodeId = ObjectEmbedNode.idFor(embed.id);
    if (_doc.getNodeById(nodeId) != null) {
      _editor.execute([
        ChangeSelectionRequest(
          DocumentSelection.collapsed(
            position: DocumentPosition(
              nodeId: nodeId,
              nodePosition: const UpstreamDownstreamNodePosition.upstream(),
            ),
          ),
          SelectionChangeType.placeCaret,
          SelectionReason.userInteraction,
        ),
      ]);
    }
    _focusNode.requestFocus();
  }

  void _reloadFromStored(String? json) {
    _applyingRemote = true;
    _doc.removeListener(_onDocumentChange);
    final next = markerTextToMutableDocument(json);
    // Replace nodes in place via editor reset pattern: rebuild editor.
    _editor = createDefaultDocumentEditor(
      document: next,
      composer: _composer,
      isHistoryEnabled: true,
    );
    _doc = next;
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
    _applyingRemote = false;
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
    await widget.state.deleteObjectEmbed(objectId);
    final nodeId = ObjectEmbedNode.idFor(objectId);
    if (_doc.getNodeById(nodeId) != null) {
      _editor.execute([DeleteNodeRequest(nodeId: nodeId)]);
    }
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
  }

  void _moveEmbedToIndex(String nodeId, int targetIndex) {
    final current = _doc.getNodeIndexById(nodeId);
    if (current < 0) return;
    var dest = targetIndex.clamp(0, _doc.nodeCount);
    if (dest == current || dest == current + 1) {
      setState(() => _moveModeNodeId = null);
      return;
    }
    _editor.execute([
      MoveNodeRequest(nodeId: nodeId, newIndex: dest > current ? dest - 1 : dest),
    ]);
    setState(() => _moveModeNodeId = null);
    _dirty = true;
    _scheduleSave();
  }

  void _claimFile() => DocumentEditorRegistry.claim(widget.file.id);

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
        selectionColor: AppColors.primary.withValues(alpha: 0.38),
      );

  Future<void> _onSecondaryTap(TapDownDetails details) async {
    _claimFile();
    _focusNode.requestFocus();
    if (!mounted) return;

    final sel = _composer.selection;
    final node = sel == null ? null : _doc.getNodeById(sel.extent.nodeId);
    final strings = widget.state.strings;

    if (node is ListItemNode) {
      await DocumentContextMenu.showListMenu(
        context: context,
        globalPosition: details.globalPosition,
        strings: strings,
        isOrdered: node.type == ListItemType.ordered,
        onAction: (action) async {
          if (action == 'list:style:bullet' ||
              action == 'list:style:numbered') {
            final wantOrdered = action == 'list:style:numbered';
            // Switch every consecutive list item in this fence.
            _setListFenceType(node.id, wantOrdered
                ? ListItemType.ordered
                : ListItemType.unordered);
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
    final next = (base + delta).clamp(10.0, 28.0);
    _editor.execute([
      AddTextAttributionsRequest(
        documentRange: sel,
        attributions: {FontSizeAttribution(next)},
      ),
    ]);
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

  List<ComponentBuilder> get _componentBuilders => [
        ObjectEmbedComponentBuilder(
          state: widget.state,
          lookup: _lookup,
          onRefresh: _loadEmbedsQuietly,
          onPayloadChanged: _onPayloadChanged,
          onDelete: _deleteObject,
          onClaimFile: _claimFile,
          moveModeNodeId: _moveModeNodeId,
          onMoveModeChanged: _onMoveModeChanged,
          onMoveToIndex: _moveEmbedToIndex,
        ),
        const LegacyTableFenceComponentBuilder(),
        const BlockquoteComponentBuilder(),
        const ParagraphComponentBuilder(),
        const ListItemComponentBuilder(),
        const HorizontalRuleComponentBuilder(),
        // Intentionally omit TaskComponentBuilder + ImageComponentBuilder.
      ];

  @override
  Widget build(BuildContext context) {
    // Super Editor always builds a SliverHybridStack. When it finds *any*
    // ancestor Scrollable (the topic canvas is a SingleChildScrollView), it
    // emits that sliver raw — so it must sit in *our* CustomScrollView as a
    // sliver, never under Column/Expanded.
    return GestureDetector(
      onSecondaryTapDown: _onSecondaryTap,
      behavior: HitTestBehavior.translucent,
      child: CustomScrollView(
        slivers: [
          if (_moveModeNodeId != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text('Move', style: AppTypography.metaStyle),
                    const SizedBox(width: 8),
                    IconButton(
                      tooltip: 'Move up',
                      icon: const Icon(Icons.arrow_upward, size: 18),
                      onPressed: () {
                        final i = _doc.getNodeIndexById(_moveModeNodeId!);
                        if (i > 0) _moveEmbedToIndex(_moveModeNodeId!, i - 1);
                      },
                    ),
                    IconButton(
                      tooltip: 'Move down',
                      icon: const Icon(Icons.arrow_downward, size: 18),
                      onPressed: () {
                        final i = _doc.getNodeIndexById(_moveModeNodeId!);
                        if (i >= 0 && i + 1 < _doc.nodeCount) {
                          _moveEmbedToIndex(_moveModeNodeId!, i + 2);
                        }
                      },
                    ),
                    TextButton(
                      onPressed: () => setState(() => _moveModeNodeId = null),
                      child: const Text('Done'),
                    ),
                  ],
                ),
              ),
            ),
          SuperEditor(
            editor: _editor,
            focusNode: _focusNode,
            documentLayoutKey: _docLayoutKey,
            stylesheet: _stylesheet,
            selectionStyle: _selectionStyles,
            componentBuilders: _componentBuilders,
            shrinkWrap: true,
            selectionPolicies: const SuperEditorSelectionPolicies(
              clearSelectionWhenEditorLosesFocus: false,
              clearSelectionWhenImeConnectionCloses: false,
            ),
          ),
        ],
      ),
    );
  }
}
