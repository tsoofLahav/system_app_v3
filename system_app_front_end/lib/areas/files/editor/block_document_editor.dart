import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/app_state.dart';
import '../../../core/l10n/app_strings.dart';
import '../data/app_file.dart';
import '../../objects/data/object_embed.dart';
import '../../objects/data/task.dart';
import '../../objects/links/add_connection_dialog.dart';
import '../../objects/links/info_description_bubble.dart';
import '../../objects/tasks/task_zones.dart';
import './embeds/graph_embed.dart';
import './embeds/inline_task_list.dart';
import './embeds/object_embed_widgets.dart';
import '../../ui/app_typography.dart';
import '../model/document_codec.dart';
import './document_edit_history.dart';
import './document_editor_controller.dart';
import './document_structure_prune.dart';
import './document_text_flow.dart';
import './embed_block_host.dart';
import '../model/document_model.dart';
import '../rich_text/block_text_actions.dart';
import '../rich_text/block_text_focus.dart';
import '../rich_text/document_context_menu.dart';
import '../rich_text/formatted_text_field.dart';
import '../rich_text/list_editor.dart';
import '../rich_text/rich_table_editor.dart';
import '../rich_text/span_text_editing_controller.dart';

/// Continuous rich-text document: paragraphs hold multiline text (`\n` = line break).
/// Enter inserts a newline in-place; use the insert bar for a new block after lists/tables.
class BlockDocumentEditor extends StatefulWidget {
  const BlockDocumentEditor({
    super.key,
    required this.file,
    required this.state,
    this.embeds = const [],
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;

  @override
  State<BlockDocumentEditor> createState() => _BlockDocumentEditorState();
}

class _BlockDocumentEditorState extends State<BlockDocumentEditor> {
  late RichDocument _doc;
  var _dirty = false;
  var _focusedBlockIndex = 0;
  var _applyingHistory = false;
  Timer? _saveTimer;
  DateTime? _lastHistoryRecord;
  String? _lastSavedJson;
  final _history = DocumentEditHistory();
  final _focusNodes = <String, FocusNode>{};
  final _controllers = <String, SpanTextEditingController>{};
  final _flow = DocumentTextFlow();
  Offset? _dragOrigin;
  String? _dragOriginSegment;
  bool _draggingAcrossParts = false;
  List<ObjectEmbed>? _embedsSnapshot;
  var _embedRebuildScheduled = false;
  OverlayEntry? _descriptionBubble;
  List<Map<String, dynamic>>? _descriptionLinksSnapshot;

  // Read per build, never cached: the styles carry the font of the current
  // language, and a field caching one would keep Inter under Hebrew text.
  TextStyle get _paragraphStyle => AppTypography.documentParagraphStyle;

  AppStrings get _strings => widget.state.strings;

  AppFile get _currentFile =>
      widget.state.selectedDetail?.files.where((f) => f.id == widget.file.id).firstOrNull ??
      widget.file;

  @override
  void initState() {
    super.initState();
    _doc = DocumentCodec.coalesceAdjacentParagraphs(
      DocumentCodec.parse(_currentFile.documentJson),
    );
    if (_doc.blocks.isEmpty) {
      _doc = _doc.copyWith(blocks: [ParagraphNode(id: DocumentCodec.newId('b'), text: '')]);
    }
    _embedsSnapshot = widget.state.embedsByFileId[widget.file.id] ?? widget.embeds;
    _flow.onPruneStructures = _pruneStructures;
    _flow.addListener(_rememberCaretBlock);
    widget.state.addListener(_onAppStateChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DocumentEditorRegistry.register(
        DocumentEditorController(
          fileId: widget.file.id,
          insertAtBlock: _insertAtBlock,
          focusBlock: (index) => _focusedBlockIndex = index,
          flushPendingChanges: _flushPendingChanges,
          focusedTaskId: _focusedTaskId,
        ),
      );
      unawaited(_loadEmbedsQuietly());
      _tryFocusPendingObject();
    });
  }

  /// Keep the last caret block even after focus moves to the insert bar.
  void _rememberCaretBlock() {
    final segmentId = _flow.focusedSegmentId;
    if (segmentId == null) return;
    final hash = segmentId.indexOf('#');
    final blockId = hash < 0 ? segmentId : segmentId.substring(0, hash);
    final i = _doc.blocks.indexWhere((b) => b.id == blockId);
    if (i >= 0) _focusedBlockIndex = i;
  }

  /// Task title under the caret, if the focused segment is a task row.
  int? _focusedTaskId() {
    final segmentId = _flow.focusedSegmentId;
    if (segmentId == null) return null;
    final marker = segmentId.lastIndexOf('#t');
    if (marker < 0) return null;
    final blockId = segmentId.substring(0, marker);
    final index = int.tryParse(segmentId.substring(marker + 2));
    if (index == null) return null;
    EmbedNode? block;
    for (final b in _doc.blocks) {
      if (b is EmbedNode && b.id == blockId) {
        block = b;
        break;
      }
    }
    if (block == null) return null;
    final embed = _embedFor(block.objectId);
    if (embed == null || embed.type != 'task_list') return null;
    final tasks = TaskZones.fromTasks(embed.tasks ?? const <Task>[]).all;
    if (index < 0 || index >= tasks.length) return null;
    return tasks[index].id;
  }

  Future<void> _loadEmbedsQuietly() async {
    await widget.state.loadEmbedsForFile(widget.file.id, notify: false);
    if (!mounted) return;
    _scheduleEmbedRebuildIfNeeded();
  }

  /// Rebuild for embed data only — never synchronously from a keystroke's
  /// notifyListeners, or HardwareKeyboard desyncs (see DEVELOPMENT.md).
  void _onAppStateChanged() {
    _scheduleEmbedRebuildIfNeeded();
    _tryFocusPendingObject();
    final links =
        widget.state.descriptionLinksByFileId[widget.file.id] ?? const [];
    if (!identical(links, _descriptionLinksSnapshot) && mounted) {
      setState(() => _descriptionLinksSnapshot = links);
    }
  }

  void _tryFocusPendingObject() {
    final pending = widget.state.pendingFocusObjectId;
    if (pending == null) return;
    final embeds =
        widget.state.embedsByFileId[widget.file.id] ?? widget.embeds;
    final hit = embeds.where((e) => e.id == pending).firstOrNull;
    if (hit == null) return;
    widget.state.takePendingFocusObjectId();
    final block = _doc.blocks.whereType<EmbedNode>().where((b) => b.objectId == pending).firstOrNull;
    if (block == null) return;
    final i = _doc.blocks.indexWhere((b) => b.id == block.id);
    if (i >= 0) _claimThisFile(i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _flow.placeCaret(
        DocumentTextPosition(infoTitleSegmentId(block.id), 0),
      );
    });
  }

  void _scheduleEmbedRebuildIfNeeded() {
    final next = widget.state.embedsByFileId[widget.file.id] ?? widget.embeds;
    if (identical(next, _embedsSnapshot)) return;
    if (_embedRebuildScheduled) return;
    _embedRebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _embedRebuildScheduled = false;
      if (!mounted) return;
      // Holding a key while TextFields are swapped desyncs HardwareKeyboard.
      if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
        _scheduleEmbedRebuildIfNeeded();
        return;
      }
      final latest =
          widget.state.embedsByFileId[widget.file.id] ?? widget.embeds;
      if (identical(latest, _embedsSnapshot)) return;
      setState(() => _embedsSnapshot = latest);
    });
  }

  @override
  void didUpdateWidget(BlockDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id) {
      _flushPendingChanges();
      _doc = DocumentCodec.coalesceAdjacentParagraphs(
        DocumentCodec.parse(_currentFile.documentJson),
      );
      _dirty = false;
      _rebuildEditingState();
    } else if (!_dirty && oldWidget.file.documentJson != widget.file.documentJson) {
      final incoming = _currentFile.documentJson;
      if (incoming != _lastSavedJson) {
        _doc = DocumentCodec.coalesceAdjacentParagraphs(
          DocumentCodec.parse(_currentFile.documentJson),
        );
        _rebuildEditingState();
      }
    }
  }

  void _rebuildEditingState() {
    BlockTextFocusRegistry.abandonStashedFocus();
    _disposeControllers();
    _disposeAllFocusNodes();
    if (mounted) setState(() {});
  }

  void _disposeControllers() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
  }

  void _disposeAllFocusNodes() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _focusNodes.clear();
  }

  void _pruneOrphans() {
    final liveIds = _doc.blocks.map((b) => b.id).toSet();
    for (final id in _controllers.keys.toList()) {
      if (!liveIds.contains(id)) {
        _controllers.remove(id)?.dispose();
      }
    }
    for (final id in _focusNodes.keys.toList()) {
      if (!liveIds.contains(id)) {
        _focusNodes.remove(id)?.dispose();
      }
    }
  }

  @override
  void deactivate() {
    unawaited(_flushPendingChanges());
    super.deactivate();
  }

  @override
  void dispose() {
    _descriptionBubble?.remove();
    _descriptionBubble = null;
    widget.state.removeListener(_onAppStateChanged);
    _flow.removeListener(_rememberCaretBlock);
    unawaited(_flushPendingChanges());
    DocumentEditorRegistry.unregister(widget.file.id);
    _saveTimer?.cancel();
    _disposeAllFocusNodes();
    _disposeControllers();
    _flow.dispose();
    super.dispose();
  }

  Future<void> _flushPendingChanges() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    final json = DocumentCodec.serialize(_doc);
    _lastSavedJson = json;
    await widget.state.updateFile(_currentFile, {
      'document_json': json,
    }, notify: false);
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) unawaited(_flushPendingChanges());
    });
  }

  void _recordHistory({bool force = false}) {
    if (_applyingHistory) return;
    final now = DateTime.now();
    if (!force &&
        _lastHistoryRecord != null &&
        now.difference(_lastHistoryRecord!) < const Duration(milliseconds: 400)) {
      return;
    }
    _history.record(_doc);
    _lastHistoryRecord = now;
  }

  void _mutateDoc(
    RichDocument doc, {
    bool rebuild = false,
    bool save = true,
    bool recordHistory = true,
  }) {
    if (recordHistory) _recordHistory();
    _doc = doc;
    _pruneOrphans();
    if (save) _scheduleSave();
    if (rebuild && mounted) setState(() {});
  }

  void _undo() {
    final previous = _history.undo(_doc);
    if (previous == null) return;
    _applyingHistory = true;
    _doc = DocumentCodec.coalesceAdjacentParagraphs(previous);
    _rebuildEditingState();
    _applyingHistory = false;
    _scheduleSave();
  }

  void _redo() {
    final next = _history.redo(_doc);
    if (next == null) return;
    _applyingHistory = true;
    _doc = DocumentCodec.coalesceAdjacentParagraphs(next);
    _rebuildEditingState();
    _applyingHistory = false;
    _scheduleSave();
  }

  SpanTextEditingController _controllerFor(String blockId, String text, List<TextSpanMark> spans) {
    final existing = _controllers[blockId];
    if (existing != null) return existing;
    return _controllers[blockId] = SpanTextEditingController(
      text: text,
      spans: spans.map((s) => s.toJson()).toList(),
    );
  }

  FocusNode _focusFor(String blockId) => _focusNodes.putIfAbsent(blockId, () {
        final node = FocusNode();
        node.addListener(() {
          if (!node.hasFocus || !mounted) return;
          final i = _doc.blocks.indexWhere((b) => b.id == blockId);
          if (i >= 0) _claimThisFile(i);
        });
        return node;
      });

  Future<void> _showTextMenu(TapDownDetails details) async {
    await DocumentContextMenu.showTextMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: _strings,
      includeConnectInfo: true,
      onAction: _handleDocumentMenuAction,
    );
  }

  Future<void> _handleDocumentMenuAction(String action) async {
    if (action == 'text:connect_info') {
      await _connectInfoFromMark();
      return;
    }
    await runBlockTextAction(action);
  }

  Future<void> _connectInfoFromMark() async {
    final mark = BlockTextFocusRegistry.resolveMark();
    if (!mark.isValid || mark.spansParts) return;
    final span = mark.first;
    if (span == null || span.segmentId == null) return;
    final pick = await showPickInfoObjectDialog(
      context: context,
      state: widget.state,
    );
    if (pick == null) return;
    final blockId = span.segmentId!.contains('#')
        ? span.segmentId!.substring(0, span.segmentId!.indexOf('#'))
        : span.segmentId!;
    final snippet = span.text.trim();
    await widget.state.createDescriptionLink(
      infoObjectId: pick.objectId,
      anchor: {
        'file_id': widget.file.id,
        'block_id': blockId,
        'segment_id': span.segmentId,
        'start': span.safeStart,
        'end': span.safeEnd,
      },
      label: snippet.isEmpty ? null : snippet,
    );
    if (mounted) setState(() {});
  }

  List<DescriptionTextRange> _descriptionRangesFor(String segmentId) {
    final links = widget.state.descriptionLinksForSegment(
      fileId: widget.file.id,
      segmentId: segmentId,
    );
    return [
      for (final link in links)
        if (link['anchor'] is Map)
          DescriptionTextRange(
            start: (link['anchor'] as Map)['start'] as int? ?? 0,
            end: (link['anchor'] as Map)['end'] as int? ?? 0,
            link: link,
          ),
    ];
  }

  void _onDescriptionHover(DescriptionTextRange? range, Offset globalAnchor) {
    _descriptionBubble?.remove();
    _descriptionBubble = null;
    if (range == null) return;
    final peer = range.link['peer'];
    final title = peer is Map
        ? (peer['title'] as String? ?? '').trim().isNotEmpty
            ? (peer['title'] as String).trim()
            : (range.link['label'] as String? ?? 'Info')
        : (range.link['label'] as String? ?? 'Info');
    final body = peer is Map
        ? (peer['body'] as String? ?? '').trim()
        : '';
    final overlay = Overlay.of(context);
    _descriptionBubble = OverlayEntry(
      builder: (context) => Positioned(
        left: globalAnchor.dx + 12,
        top: globalAnchor.dy + 18,
        child: IgnorePointer(
          child: InfoDescriptionBubble(
            title: title,
            body: body.length > 220 ? '${body.substring(0, 220)}…' : body,
          ),
        ),
      ),
    );
    overlay.insert(_descriptionBubble!);
  }

  Future<void> _onDescriptionDoubleTap(DescriptionTextRange range) async {
    final sourceId = range.link['source_id'] as int?;
    if (sourceId == null) return;
    await widget.state.openObjectInFile(objectId: sourceId);
  }

  Future<void> _insertAtBlock(String action) async {
    await _flushPendingChanges();
    _recordHistory(force: true);
    final index = _blockIndexForInsert();

    // Objects are created on the server, which also inserts the embed block.
    if (action == 'task_list' ||
        action == 'info' ||
        action == 'image' ||
        action == 'graph') {
      await _insertObject(action, index);
      return;
    }

    final node = switch (action) {
      'paragraph' => ParagraphNode(id: DocumentCodec.newId('b'), text: ''),
      // One way to insert a list. Points vs numbers is switched afterwards on
      // the block itself, from its right-click menu.
      'list' || 'bullet_list' => ListNode(
          id: DocumentCodec.newId('b'),
          items: [ListItem(id: DocumentCodec.newId('li'), text: '')],
        ),
      'table' => TableNode(
          id: DocumentCodec.newId('b'),
          rows: [
            [const DocumentTableCell(text: ''), const DocumentTableCell(text: '')],
          ],
        ),
      _ => null,
    };
    if (node == null) return;

    _mutateDoc(
      DocumentCodec.insertBlock(_doc, index, node),
      rebuild: true,
      recordHistory: false,
    );
    // Whatever was inserted, the caret goes into it — a new list or table is
    // ready to type in, exactly like a new paragraph.
    _focusFirstPartOf(node.id);
  }

  /// Insert after the block that currently holds the caret — not a stale
  /// index from another pane or an earlier click.
  int _blockIndexForInsert() {
    final segmentId = _flow.focusedSegmentId;
    if (segmentId != null) {
      final hash = segmentId.indexOf('#');
      final blockId = hash < 0 ? segmentId : segmentId.substring(0, hash);
      final i = _doc.blocks.indexWhere((b) => b.id == blockId);
      if (i >= 0) return (i + 1).clamp(0, _doc.blocks.length);
    }
    return (_focusedBlockIndex + 1).clamp(0, _doc.blocks.length);
  }

  void _claimThisFile([int? blockIndex]) {
    DocumentEditorRegistry.claim(widget.file.id);
    if (blockIndex != null) _focusedBlockIndex = blockIndex;
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
    }

    final embed = await widget.state.createObjectInDocument(
      _currentFile,
      type: type,
      title: type == 'info' ? '' : null,
      body: type == 'info' ? '' : null,
      payload: payload,
      blockIndex: blockIndex,
    );

    // Server wrote the embed into document_json; adopt that tree.
    final updated = await widget.state.reloadFile(widget.file.id);
    _doc = DocumentCodec.coalesceAdjacentParagraphs(
      DocumentCodec.parse(updated.documentJson),
    );
    _lastSavedJson = updated.documentJson;
    _dirty = false;
    if (mounted) setState(() {});

    final embedIndex = DocumentCodec.embedBlockIndex(_doc, embed.id);
    if (embedIndex != null) {
      _focusedBlockIndex = embedIndex;
      _focusFirstPartOf(_doc.blocks[embedIndex].id);
    }
  }

  /// Puts the caret in the first part of a block: the paragraph itself, the
  /// first bullet, the top-left cell, the first task, or an atomic embed.
  void _focusFirstPartOf(String blockId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final index = _doc.blocks.indexWhere((b) => b.id == blockId);
      if (index < 0) return;
      final block = _doc.blocks[index];
      final segmentId = switch (block) {
        ListNode() when block.items.isNotEmpty => listItemSegmentId(blockId, 0),
        TableNode() when block.rows.isNotEmpty && block.rows.first.isNotEmpty =>
          tableCellSegmentId(blockId, 0, 0),
        EmbedNode() => _embedSegmentIds(block).firstOrNull,
        ParagraphNode() || HeadingNode() => paragraphSegmentId(blockId),
        _ => null,
      };
      if (segmentId == null) return;
      _flow.placeCaret(DocumentTextPosition(segmentId, 0));
    });
  }

  void _updateParagraph(ParagraphNode block, SpanTextEditingController controller) {
    _claimThisFile(_doc.blocks.indexWhere((b) => b.id == block.id));
    _mutateDoc(
      DocumentCodec.replaceBlock(
        _doc,
        block.id,
        block.copyWith(
          text: controller.text,
          spans: [
            for (final s in controller.spans)
              TextSpanMark.fromJson(Map<String, dynamic>.from(s)),
          ],
        ),
      ),
      rebuild: false,
    );
  }

  Future<void> _mergeOrDeleteParagraph(ParagraphNode block, int index) async {
    if (index == 0) return;
    _recordHistory(force: true);
    final prev = _doc.blocks[index - 1];
    if (prev is! ParagraphNode) return;

    final controller = _controllerFor(block.id, block.text, block.spans);
    if (controller.text.isNotEmpty) return;

    final joinAt = prev.text.isEmpty ? 0 : prev.text.length + 1;
    final mergedText = prev.text.isEmpty ? '' : '${prev.text}\n';
    final mergedSpanMarks = [...prev.spans];

    final blocks = [..._doc.blocks];
    blocks[index - 1] = prev.copyWith(text: mergedText, spans: mergedSpanMarks);
    blocks.removeAt(index);
    _controllers.remove(block.id)?.dispose();
    _focusNodes.remove(block.id)?.dispose();
    _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true, recordHistory: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _focusFor(prev.id);
      if (node.context != null) node.requestFocus();
      final c = _controllerFor(prev.id, mergedText, mergedSpanMarks);
      c.selection = TextSelection.collapsed(offset: joinAt.clamp(0, mergedText.length));
    });
  }

  void _exitListBelow(String blockId, int emptyItemIndex) {
    // Resolve the block from `_doc`: list edits are applied without a rebuild,
    // so any node captured during build is already out of date.
    final index = _doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _doc.blocks[index];
    if (block is! ListNode) return;

    _recordHistory(force: true);
    var items = [...block.items];
    if (emptyItemIndex >= 0 && emptyItemIndex < items.length) {
      items.removeAt(emptyItemIndex);
    }

    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [..._doc.blocks];

    if (items.isEmpty) {
      blocks[index] = ParagraphNode(id: newParagraphId, text: '');
    } else {
      blocks[index] = block.copyWith(items: items);
      blocks.insert(
        index + 1,
        ParagraphNode(id: newParagraphId, text: ''),
      );
    }

    _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true, recordHistory: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _focusFor(newParagraphId);
      if (node.context != null) node.requestFocus();
    });
  }

  void _exitTableBelow(String blockId, int emptyRowIndex) {
    final index = _doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _doc.blocks[index];
    if (block is! TableNode) return;

    _recordHistory(force: true);
    var rows = [
      for (final row in block.rows)
        [for (final cell in row) cell],
    ];
    if (emptyRowIndex >= 0 && emptyRowIndex < rows.length) {
      rows.removeAt(emptyRowIndex);
    }

    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [..._doc.blocks];
    final hasContent = rows.any(
      (row) => row.any((cell) => cell.text.trim().isNotEmpty),
    );

    if (!hasContent || rows.isEmpty) {
      blocks[index] = ParagraphNode(id: newParagraphId, text: '');
    } else {
      blocks[index] = block.copyWith(rows: rows);
      blocks.insert(
        index + 1,
        ParagraphNode(id: newParagraphId, text: ''),
      );
    }

    _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true, recordHistory: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final node = _focusFor(newParagraphId);
      if (node.context != null) node.requestFocus();
    });
  }

  /// Continues writing below an embedded object without destroying it —
  /// same empty-final-exit idea as lists and tables.
  void _exitEmbedBelow(String blockId) {
    final index = _doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _doc.blocks[index];
    if (block is! EmbedNode) return;

    _recordHistory(force: true);
    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [..._doc.blocks];
    blocks.insert(
      index + 1,
      ParagraphNode(id: newParagraphId, text: ''),
    );
    _focusedBlockIndex = index + 1;
    _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true, recordHistory: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _flow.placeCaret(
        DocumentTextPosition(paragraphSegmentId(newParagraphId), 0),
      );
    });
  }

  /// Empty task + Enter — drop that task and continue as a paragraph below,
  /// mirroring list exit. [emptyTaskId] is the row that was empty (not a
  /// positional index — Active/Done order can disagree with raw list order).
  Future<void> _exitTaskListBelow(String blockId, int? emptyTaskId) async {
    final index = _doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _doc.blocks[index];
    if (block is! EmbedNode) return;
    final embed = _embedFor(block.objectId);
    if (embed == null || embed.type != 'task_list') return;

    _recordHistory(force: true);

    if (emptyTaskId != null) {
      Task? toDelete;
      for (final t in embed.tasks ?? const <Task>[]) {
        if (t.id == emptyTaskId) {
          toDelete = t;
          break;
        }
      }
      if (toDelete != null) {
        await widget.state.deleteTask(toDelete, notify: false);
      }
    }

    final remaining = [
      for (final t in embed.tasks ?? const <Task>[])
        if (t.id != emptyTaskId) t,
    ];

    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [..._doc.blocks];

    if (remaining.isEmpty) {
      blocks[index] = ParagraphNode(id: newParagraphId, text: '');
      _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true, recordHistory: false);
      await _flushPendingChanges();
      await widget.state.deleteObjectEmbed(block.objectId);
      await _reloadEmbedsQuiet();
    } else {
      blocks.insert(
        index + 1,
        ParagraphNode(id: newParagraphId, text: ''),
      );
      _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true, recordHistory: false);
      await _reloadEmbedsQuiet();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Same landing as graph / list exit — claim the new paragraph field.
      final node = _focusFor(newParagraphId);
      if (node.context != null) node.requestFocus();
      _flow.placeCaret(
        DocumentTextPosition(paragraphSegmentId(newParagraphId), 0),
      );
    });
  }

  /// Empty graph column + Enter — drop that column and continue below,
  /// mirroring table exit.
  Future<void> _exitGraphBelow(String blockId, int emptyCol) async {
    final index = _doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _doc.blocks[index];
    if (block is! EmbedNode) return;
    final embed = _embedFor(block.objectId);
    if (embed == null || embed.type != 'graph') return;

    final payload = Map<String, dynamic>.from(embed.payload ?? const {});
    final labels = [
      for (final e in payload['labels'] as List? ?? const []) '$e',
    ];
    final values = [
      for (final v in payload['values'] as List? ?? const []) '$v',
    ];
    while (values.length < labels.length) {
      values.add('');
    }

    if (emptyCol >= 0 && emptyCol < labels.length) {
      labels.removeAt(emptyCol);
      values.removeAt(emptyCol);
    }

    _recordHistory(force: true);
    final newParagraphId = DocumentCodec.newId('b');
    final blocks = [..._doc.blocks];
    final hasContent = labels.any((l) => l.trim().isNotEmpty) ||
        values.any((v) => v.trim().isNotEmpty);

    if (!hasContent || labels.isEmpty) {
      blocks[index] = ParagraphNode(id: newParagraphId, text: '');
      _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true, recordHistory: false);
      await _flushPendingChanges();
      await widget.state.deleteObjectEmbed(block.objectId);
      await _reloadEmbedsQuiet();
    } else {
      _patchEmbedPayloadLocally(
        embed.id,
        {...payload, 'labels': labels, 'values': values},
      );
      unawaited(
        widget.state.updateObjectPayload(
          embed.id,
          {...payload, 'labels': labels, 'values': values},
          notify: false,
        ),
      );
      blocks.insert(
        index + 1,
        ParagraphNode(id: newParagraphId, text: ''),
      );
      _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true, recordHistory: false);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Same landing as list / table exit — focus the new paragraph field.
      final node = _focusFor(newParagraphId);
      if (node.context != null) node.requestFocus();
      _flow.placeCaret(
        DocumentTextPosition(paragraphSegmentId(newParagraphId), 0),
      );
    });
  }

  /// Keep segment order in lockstep with the graph grid — patch the local
  /// embed snapshot immediately; API write is fire-and-forget.
  ///
  /// [rebuild] only when column count changes so typing does not rebuild the
  /// whole file on every keystroke.
  void _patchEmbedPayloadLocally(
    int objectId,
    Map<String, dynamic> payload, {
    bool? structureChanged,
  }) {
    final live = _embedsSnapshot ??
        widget.state.embedsByFileId[widget.file.id] ??
        widget.embeds;
    final index = live.indexWhere((e) => e.id == objectId);
    if (index < 0) return;
    final current = live[index];
    final oldCols = (current.payload?['labels'] as List?)?.length ?? 0;
    final newCols = (payload['labels'] as List?)?.length ?? 0;
    final next = [
      for (var i = 0; i < live.length; i++)
        if (i == index)
          ObjectEmbed(
            id: current.id,
            fileId: current.fileId,
            type: current.type,
            taskListId: current.taskListId,
            informationId: current.informationId,
            anchor: current.anchor,
            sortKey: current.sortKey,
            tasks: current.tasks,
            information: current.information,
            links: current.links,
            payload: payload,
          )
        else
          live[i],
    ];
    widget.state.embedsByFileId[widget.file.id] = next;
    final mustRebuild = structureChanged ?? oldCols != newCols;
    if (mustRebuild) {
      setState(() => _embedsSnapshot = next);
    } else {
      _embedsSnapshot = next;
    }
  }

  Future<void> _reloadEmbedsQuiet() async {
    await widget.state.loadEmbedsForFile(widget.file.id, notify: false);
    if (!mounted) return;
    setState(() {
      _embedsSnapshot = widget.state.embedsByFileId[widget.file.id];
    });
  }

  /// Drops the bullets, rows, embeds, and blocks a delete emptied completely.
  ///
  /// Runs after the frame because it restructures the document while the text
  /// fields that triggered the delete are still settling.
  void _pruneStructures(Set<String> fullyEmptied, {required bool spansParts}) {
    if (fullyEmptied.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      final objectPartsTouched = await _pruneTaskAndGraphParts(fullyEmptied);

      final removedObjectIds = <int>[
        for (final block in _doc.blocks)
          if (block is EmbedNode &&
              fullyEmptied.contains(embedSegmentId(block.id)))
            block.objectId,
      ];

      final caretSegment = _flow.focusedSegmentId;
      final pruned = pruneFullyMarkedStructures(
        blocks: _doc.blocks,
        fullyEmptied: fullyEmptied,
        spansParts: spansParts,
      );
      if (!pruned.changed &&
          removedObjectIds.isEmpty &&
          !objectPartsTouched) {
        return;
      }

      _flow.clearSelection();
      if (pruned.changed) {
        _mutateDoc(_doc.copyWith(blocks: pruned.blocks), rebuild: true);
        await _flushPendingChanges();
      }

      // Cascade-delete backing rows so agent text and views stay clean.
      for (final objectId in removedObjectIds) {
        await widget.state.deleteObjectEmbed(objectId);
      }
      if (removedObjectIds.isNotEmpty) {
        final updated = await widget.state.reloadFile(widget.file.id);
        if (!mounted) return;
        _doc = DocumentCodec.coalesceAdjacentParagraphs(
          DocumentCodec.parse(updated.documentJson),
        );
        _lastSavedJson = updated.documentJson;
        _dirty = false;
        setState(() {});
      }

      final caretSurvived =
          caretSegment != null && _segmentOrder().contains(caretSegment);
      if (!caretSurvived) {
        final landing =
            pruned.firstRemovedIndex.clamp(0, _doc.blocks.length - 1);
        _focusFirstPartOf(_doc.blocks[landing].id);
      }
    });
  }

  /// Task-list / graph parts live outside `document_json` — prune them via API
  /// / payload when their segments were marked end to end.
  Future<bool> _pruneTaskAndGraphParts(Set<String> fullyEmptied) async {
    final taskByBlock = <String, List<int>>{};
    final graphColsByBlock = <String, Set<int>>{};

    for (final id in fullyEmptied) {
      final task = parseTaskItemSegmentId(id);
      if (task != null) {
        taskByBlock.putIfAbsent(task.$1, () => []).add(task.$2);
        continue;
      }
      final graph = parseGraphCellSegmentId(id);
      if (graph != null) {
        graphColsByBlock.putIfAbsent(graph.$1, () => {}).add(graph.$3);
      }
    }
    if (taskByBlock.isEmpty && graphColsByBlock.isEmpty) return false;

    for (final entry in taskByBlock.entries) {
      final blockIndex = _doc.blocks.indexWhere((b) => b.id == entry.key);
      if (blockIndex < 0) continue;
      final block = _doc.blocks[blockIndex];
      if (block is! EmbedNode) continue;
      final embed = _embedFor(block.objectId);
      if (embed?.type != 'task_list') continue;
      final tasks = [...(embed!.tasks ?? const <Task>[])]
        ..sort((a, b) => a.listOrderIndex.compareTo(b.listOrderIndex));
      final indexes = entry.value.toSet().toList()..sort((a, b) => b.compareTo(a));
      for (final i in indexes) {
        if (i < 0 || i >= tasks.length) continue;
        await widget.state.deleteTask(tasks[i], notify: false);
        tasks.removeAt(i);
      }
      if (tasks.isEmpty) {
        final blocks = [..._doc.blocks]..removeAt(blockIndex);
        _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true);
        await _flushPendingChanges();
        await widget.state.deleteObjectEmbed(block.objectId);
      }
    }

    for (final entry in graphColsByBlock.entries) {
      final blockIndex = _doc.blocks.indexWhere((b) => b.id == entry.key);
      if (blockIndex < 0) continue;
      final block = _doc.blocks[blockIndex];
      if (block is! EmbedNode) continue;
      final embed = _embedFor(block.objectId);
      if (embed?.type != 'graph') continue;

      // A column goes only when both of its cells were marked in full.
      final toDrop = <int>[];
      for (final col in entry.value) {
        final labelId = graphCellSegmentId(block.id, 0, col);
        final valueId = graphCellSegmentId(block.id, 1, col);
        if (fullyEmptied.contains(labelId) && fullyEmptied.contains(valueId)) {
          toDrop.add(col);
        }
      }
      if (toDrop.isEmpty) continue;

      final payload = Map<String, dynamic>.from(embed!.payload ?? const {});
      final labels = [
        for (final e in payload['labels'] as List? ?? const []) '$e',
      ];
      final values = [
        for (final v in payload['values'] as List? ?? const []) '$v',
      ];
      while (values.length < labels.length) {
        values.add('');
      }
      toDrop.sort((a, b) => b.compareTo(a));
      for (final col in toDrop) {
        if (col < 0 || col >= labels.length) continue;
        labels.removeAt(col);
        values.removeAt(col);
      }

      if (labels.isEmpty) {
        final blocks = [..._doc.blocks]..removeAt(blockIndex);
        _mutateDoc(_doc.copyWith(blocks: blocks), rebuild: true);
        await _flushPendingChanges();
        await widget.state.deleteObjectEmbed(block.objectId);
      } else {
        _patchEmbedPayloadLocally(
          embed.id,
          {...payload, 'labels': labels, 'values': values},
        );
        await widget.state.updateObjectPayload(
          embed.id,
          {...payload, 'labels': labels, 'values': values},
          notify: false,
        );
      }
    }

    if (taskByBlock.isNotEmpty || graphColsByBlock.isNotEmpty) {
      await _reloadEmbedsQuiet();
    }
    return true;
  }

  /// Switches an existing list between points and numbers. A list has one
  /// style, so this replaces it rather than creating a different kind of list.
  void _setListStyle(String blockId, String style) {
    final index = _doc.blocks.indexWhere((b) => b.id == blockId);
    if (index < 0) return;
    final block = _doc.blocks[index];
    if (block is! ListNode || block.listStyle == style) return;
    _mutateDoc(
      DocumentCodec.replaceBlock(_doc, blockId, block.copyWith(listStyle: style)),
      rebuild: true,
    );
  }

  /// Segment ids in reading order: a paragraph or heading is one segment, a
  /// list contributes one per bullet, a table one per cell, a task list one
  /// per task, a graph one per cell, and other embeds are one atomic unit.
  List<String> _segmentOrder() {
    final ids = <String>[];
    for (final block in _doc.blocks) {
      if (block is ListNode) {
        for (var i = 0; i < block.items.length; i++) {
          ids.add(listItemSegmentId(block.id, i));
        }
      } else if (block is TableNode) {
        for (var r = 0; r < block.rows.length; r++) {
          for (var c = 0; c < block.rows[r].length; c++) {
            ids.add(tableCellSegmentId(block.id, r, c));
          }
        }
      } else if (block is EmbedNode) {
        ids.addAll(_embedSegmentIds(block));
      } else if (block is ParagraphNode || block is HeadingNode) {
        ids.add(paragraphSegmentId(block.id));
      }
    }
    return ids;
  }

  List<String> _embedSegmentIds(EmbedNode block) {
    final embed = _embedFor(block.objectId);
    if (embed?.type == 'task_list') {
      final count = (embed!.tasks?.length ?? 0).clamp(1, 10000);
      return [
        taskListTitleSegmentId(block.id),
        for (var i = 0; i < count; i++) taskItemSegmentId(block.id, i),
      ];
    }
    if (embed?.type == 'graph') {
      final labels = embed!.payload?['labels'] as List? ?? const ['', ''];
      final cols = labels.isEmpty ? 2 : labels.length;
      return [
        for (var r = 0; r < 2; r++)
          for (var c = 0; c < cols; c++) graphCellSegmentId(block.id, r, c),
      ];
    }
    if (embed?.type == 'info') {
      return [
        infoTitleSegmentId(block.id),
        infoBodySegmentId(block.id),
      ];
    }
    return [embedSegmentId(block.id)];
  }

  /// Up/down links for table and graph cells: within the grid the caret moves
  /// by column, and from the edge rows it leaves into the adjacent block.
  (Map<String, String>, Map<String, String>) _verticalLinks(List<String> order) {
    final above = <String, String>{};
    final below = <String, String>{};

    for (var b = 0; b < _doc.blocks.length; b++) {
      final block = _doc.blocks[b];
      if (block is TableNode && block.rows.isNotEmpty) {
        _linkGridVertically(
          order: order,
          above: above,
          below: below,
          rowCount: block.rows.length,
          columnCount: block.rows.first.length,
          cellId: (r, c) => tableCellSegmentId(block.id, r, c),
        );
      } else if (block is EmbedNode) {
        final embed = _embedFor(block.objectId);
        if (embed?.type == 'graph') {
          final labels = embed!.payload?['labels'] as List? ?? const ['', ''];
          final cols = labels.isEmpty ? 2 : labels.length;
          _linkGridVertically(
            order: order,
            above: above,
            below: below,
            rowCount: 2,
            columnCount: cols,
            cellId: (r, c) => graphCellSegmentId(block.id, r, c),
          );
        }
      }
    }
    return (above, below);
  }

  void _linkGridVertically({
    required List<String> order,
    required Map<String, String> above,
    required Map<String, String> below,
    required int rowCount,
    required int columnCount,
    required String Function(int row, int col) cellId,
  }) {
    if (rowCount <= 0 || columnCount <= 0) return;
    final firstCell = cellId(0, 0);
    final firstIndex = order.indexOf(firstCell);
    final lastCell = cellId(rowCount - 1, columnCount - 1);
    final lastIndex = order.indexOf(lastCell);

    final beforeGrid = firstIndex > 0 ? order[firstIndex - 1] : null;
    final afterGrid =
        lastIndex >= 0 && lastIndex < order.length - 1 ? order[lastIndex + 1] : null;

    for (var r = 0; r < rowCount; r++) {
      for (var c = 0; c < columnCount; c++) {
        final id = cellId(r, c);
        if (r > 0) {
          above[id] = cellId(r - 1, c);
        } else if (beforeGrid != null) {
          above[id] = beforeGrid;
        }
        if (r < rowCount - 1) {
          below[id] = cellId(r + 1, c);
        } else if (afterGrid != null) {
          below[id] = afterGrid;
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _segmentOrder();
    _flow.setOrder(order);
    final (above, below) = _verticalLinks(order);
    _flow.setVerticalLinks(above: above, below: below);
    return DocumentTextFlowScope(
      flow: _flow,
      child: Listener(
        onPointerDown: _onEditorPointerDown,
        onPointerMove: _onEditorPointerMove,
        onPointerUp: (_) => _endDragSelection(),
        onPointerCancel: (_) => _endDragSelection(),
        child: _buildEditor(context),
      ),
    );
  }

  void _onEditorPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    final at = _flow.positionAtGlobal(event.position);
    _dragOrigin = event.position;
    _dragOriginSegment = at?.segmentId;
    _draggingAcrossParts = false;
    if (at != null) {
      final segmentId = at.segmentId;
      final hash = segmentId.indexOf('#');
      final blockId = hash < 0 ? segmentId : segmentId.substring(0, hash);
      final i = _doc.blocks.indexWhere((b) => b.id == blockId);
      _claimThisFile(i >= 0 ? i : null);
    } else {
      _claimThisFile();
    }
  }

  /// Extends the document selection while the pointer is dragged.
  ///
  /// A drag that stays inside one part is left to that text field's own
  /// selection; this only takes over once the pointer reaches another part.
  void _onEditorPointerMove(PointerMoveEvent event) {
    final origin = _dragOrigin;
    if (origin == null || event.buttons != kPrimaryButton) return;

    final current = _flow.positionAtGlobal(event.position);
    if (current == null) return;

    if (!_draggingAcrossParts) {
      if (current.segmentId == _dragOriginSegment) return;
      final start = _flow.positionAtGlobal(origin);
      if (start == null) return;
      _draggingAcrossParts = true;
      _flow.collapseTo(start);
    }
    _flow.extendTo(current);
  }

  void _endDragSelection() {
    _dragOrigin = null;
    _dragOriginSegment = null;
    _draggingAcrossParts = false;
  }

  Widget _buildEditor(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift, LogicalKeyboardKey.keyZ):
            const _RedoIntent(),
      },
      child: Actions(
        actions: {
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) {
            _undo();
            return null;
          }),
          _RedoIntent: CallbackAction<_RedoIntent>(onInvoke: (_) {
            _redo();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < _doc.blocks.length; index++)
                KeyedSubtree(
                  key: ValueKey(_doc.blocks[index].id),
                  child: Padding(
                    padding: EdgeInsets.only(
                      bottom: _doc.blocks[index] is ParagraphNode ? 2 : 8,
                    ),
                    child: _buildBlock(_doc.blocks[index], index),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(DocumentNode block, int index) {
    if (block is EmbedNode) {
      return _buildEmbed(block, index);
    }
    final content = _buildEditableBlock(block, index);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != block.id,
      onAcceptWithDetails: (details) => _moveEmbedTo(details.data, index),
      builder: (context, candidate, rejected) {
        return DecoratedBox(
          decoration: BoxDecoration(
            border: candidate.isNotEmpty
                ? Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  )
                : null,
          ),
          child: content,
        );
      },
    );
  }

  Widget _buildEmbed(EmbedNode block, int index) {
    final embed = _embedFor(block.objectId);
    final child = embed == null
        ? Text(
            '[object ${block.objectId}]',
            style: AppTypography.metaStyle.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          )
        : _embedWidget(embed, block.id);

    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != block.id,
      onAcceptWithDetails: (details) => _moveEmbedTo(details.data, index),
      builder: (context, candidate, rejected) {
        return DecoratedBox(
          decoration: BoxDecoration(
            border: candidate.isNotEmpty
                ? Border(
                    top: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 2,
                    ),
                  )
                : null,
          ),
          child: EmbedBlockHost(
            blockId: block.id,
            registerAsUnit: embed == null ||
                (embed.type != 'task_list' &&
                    embed.type != 'graph' &&
                    embed.type != 'info'),
            onInteract: () => _claimThisFile(index),
            child: child,
          ),
        );
      },
    );
  }

  ObjectEmbed? _embedFor(int objectId) {
    final live = _embedsSnapshot ??
        widget.state.embedsByFileId[widget.file.id] ??
        widget.embeds;
    for (final embed in live) {
      if (embed.id == objectId) return embed;
    }
    return null;
  }

  Widget _embedWidget(ObjectEmbed embed, String blockId) {
    Future<void> refresh() => _reloadEmbedsQuiet();
    void exitBelow() => _exitEmbedBelow(blockId);

    return switch (embed.type) {
      'task_list' => InlineTaskListWidget(
          embed: embed,
          blockId: blockId,
          state: widget.state,
          onRefresh: refresh,
          onFocus: () {
            final i = _doc.blocks.indexWhere((b) => b.id == blockId);
            if (i >= 0) _claimThisFile(i);
          },
          onExitBelow: (emptyTaskId) =>
              unawaited(_exitTaskListBelow(blockId, emptyTaskId)),
        ),
      'info' => InfoEmbed(
          embed: embed,
          blockId: blockId,
          state: widget.state,
          onRefresh: () => unawaited(refresh()),
          onFocus: () {
            final i = _doc.blocks.indexWhere((b) => b.id == blockId);
            if (i >= 0) _claimThisFile(i);
          },
          onExitBelow: exitBelow,
        ),
      'image' => ImageEmbed(
          embed: embed,
          state: widget.state,
          onPayloadChanged: (payload) {
            unawaited(widget.state.updateObjectPayload(embed.id, payload));
          },
        ),
      'graph' => GraphEmbed(
          key: ValueKey('graph-${embed.id}'),
          embed: embed,
          blockId: blockId,
          strings: _strings,
          onPayloadChanged: (payload) {
            _patchEmbedPayloadLocally(embed.id, payload);
            unawaited(
              widget.state.updateObjectPayload(embed.id, payload, notify: false),
            );
          },
          onFocus: () {
            final i = _doc.blocks.indexWhere((b) => b.id == blockId);
            if (i >= 0) _claimThisFile(i);
          },
          onExitBelow: (emptyCol) =>
              unawaited(_exitGraphBelow(blockId, emptyCol)),
        ),
      _ => Text('[${embed.type}]', style: AppTypography.metaStyle),
    };
  }

  void _moveEmbedTo(String blockId, int targetIndex) {
    final current = _doc.blocks.indexWhere((b) => b.id == blockId);
    if (current < 0 || current == targetIndex) return;
    _mutateDoc(
      DocumentCodec.moveEmbedBlock(_doc, blockId, targetIndex),
      rebuild: true,
    );
  }

  Widget _buildEditableBlock(DocumentNode block, int index) {
    if (block is ParagraphNode) {
      final segmentId = paragraphSegmentId(block.id);
      final controller = _controllerFor(block.id, block.text, block.spans);
      return FormattedTextField(
        key: ValueKey('p-${block.id}'),
        controller: controller,
        focusNode: _focusFor(block.id),
        segmentId: segmentId,
        style: _paragraphStyle,
        maxLines: null,
        minLines: 1,
        descriptionRanges: _descriptionRangesFor(segmentId),
        onDescriptionHover: (range) {
          final box = context.findRenderObject() as RenderBox?;
          final anchor = box?.localToGlobal(Offset.zero) ?? Offset.zero;
          _onDescriptionHover(range, anchor);
        },
        onDescriptionDoubleTap: (range) =>
            unawaited(_onDescriptionDoubleTap(range)),
        onChanged: (_) {
          _claimThisFile(index);
          _updateParagraph(block, controller);
        },
        onBackspaceAtStart: () => _mergeOrDeleteParagraph(block, index),
        onSecondaryTapDown: _showTextMenu,
      );
    }
    if (block is HeadingNode) {
      final segmentId = paragraphSegmentId(block.id);
      final controller = _controllerFor(block.id, block.text, block.spans);
      return FormattedTextField(
        key: ValueKey('h-${block.id}'),
        controller: controller,
        focusNode: _focusFor(block.id),
        segmentId: segmentId,
        style: AppTypography.documentHeadingStyle(block.level),
        maxLines: null,
        descriptionRanges: _descriptionRangesFor(segmentId),
        onDescriptionHover: (range) {
          final box = context.findRenderObject() as RenderBox?;
          final anchor = box?.localToGlobal(Offset.zero) ?? Offset.zero;
          _onDescriptionHover(range, anchor);
        },
        onDescriptionDoubleTap: (range) =>
            unawaited(_onDescriptionDoubleTap(range)),
        onChanged: (_) {
          _claimThisFile(index);
          _mutateDoc(
            DocumentCodec.replaceBlock(
              _doc,
              block.id,
              block.copyWith(
                text: controller.text,
                spans: [
                  for (final s in controller.spans)
                    TextSpanMark.fromJson(Map<String, dynamic>.from(s)),
                ],
              ),
            ),
            rebuild: false,
          );
        },
        onSecondaryTapDown: _showTextMenu,
      );
    }
    if (block is ListNode) {
      return RichListEditor(
        key: ValueKey('l-${block.id}'),
        node: block,
        strings: _strings,
        onFocus: () => _claimThisFile(index),
        onChanged: (updated) {
          _claimThisFile(index);
          _mutateDoc(
            DocumentCodec.replaceBlock(_doc, block.id, updated),
            rebuild: false,
          );
        },
        onExitList: (emptyItemIndex) => _exitListBelow(block.id, emptyItemIndex),
        onStyleChanged: (style) => _setListStyle(block.id, style),
      );
    }
    if (block is TableNode) {
      return RichTableEditor(
        key: ValueKey('t-${block.id}'),
        node: block,
        strings: _strings,
        onFocus: () => _claimThisFile(index),
        onChanged: (updated) {
          _claimThisFile(index);
          _mutateDoc(
            DocumentCodec.replaceBlock(_doc, block.id, updated),
            rebuild: false,
          );
        },
        onExitTable: (emptyRowIndex) => _exitTableBelow(block.id, emptyRowIndex),
      );
    }
    return const SizedBox.shrink();
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

class _RedoIntent extends Intent {
  const _RedoIntent();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
