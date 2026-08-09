import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../model/document_buffer.dart';
import '../model/document_codec.dart';
import '../model/document_text_codec.dart';
import './document_edit_history.dart';
import './document_editor_controller.dart';
import './document_session.dart';
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
    this.minViewportHeight,
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;

  /// When set, the editor fills at least this height so empty space under the
  /// text receives taps (place caret at end of last line).
  final double? minViewportHeight;

  @override
  State<BlockDocumentEditor> createState() => _BlockDocumentEditorState();
}

class _BlockDocumentEditorState extends State<BlockDocumentEditor> {
  static const _session = DocumentSession();

  /// Marker-text source of truth (v4 body). [_doc] is a derived view for widgets.
  late DocumentBuffer _buffer;
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
  /// Defers [_rebuildEditingState] until no keys are held (Backspace desync).
  var _deferredRebuildScheduled = false;
  VoidCallback? _pendingAfterRebuild;
  OverlayEntry? _descriptionBubble;
  List<Map<String, dynamic>>? _descriptionLinksSnapshot;
  /// Block id of the embed currently in Move Mode (text becomes drop targets).
  String? _moveModeEmbedId;
  _EmbedDropPreview? _dropPreview;
  /// Preserve [InfoEmbedState] across Move Mode rebuilds / block reordering.
  final _infoEmbedKeys = <int, GlobalKey<InfoEmbedState>>{};

  // Read per build, never cached: the styles carry the font of the current
  // language, and a field caching one would keep Inter under Hebrew text.
  TextStyle get _paragraphStyle => AppTypography.documentParagraphStyle;

  AppStrings get _strings => widget.state.strings;

  AppFile get _currentFile =>
      widget.state.selectedDetail?.files.where((f) => f.id == widget.file.id).firstOrNull ??
      widget.file;

  void _syncDocFromBuffer() {
    _doc = _stampEmbedTypes(_buffer.toRichDocument());
  }

  @override
  void initState() {
    super.initState();
    _embedsSnapshot = widget.state.embedsByFileId[widget.file.id] ?? widget.embeds;
    _buffer = DocumentBuffer.fromStored(_currentFile.documentJson);
    _syncDocFromBuffer();
    if (_doc.blocks.isEmpty) {
      _buffer = DocumentBuffer.empty();
      _syncDocFromBuffer();
    }
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
      _embedsSnapshot =
          widget.state.embedsByFileId[widget.file.id] ?? widget.embeds;
      _buffer = DocumentBuffer.fromStored(_currentFile.documentJson);
      _syncDocFromBuffer();
      _dirty = false;
      _rebuildEditingState();
    } else if (!_dirty && oldWidget.file.documentJson != widget.file.documentJson) {
      final incoming = _currentFile.documentJson;
      if (incoming != _lastSavedJson) {
        _embedsSnapshot =
            widget.state.embedsByFileId[widget.file.id] ?? widget.embeds;
        _buffer = DocumentBuffer.fromStored(_currentFile.documentJson);
        _syncDocFromBuffer();
        _rebuildEditingState();
      }
    }
  }

  void _rebuildEditingState() {
    BlockTextFocusRegistry.abandonStashedFocus();
    _flow.clearBindings();
    _disposeControllers();
    _disposeAllFocusNodes();
    if (mounted) setState(() {});
  }

  /// Disposing / swapping TextFields while a key is still down desyncs
  /// Flutter's [HardwareKeyboard] (`KeyDownEvent … already pressed`).
  void _rebuildEditingStateWhenSafe({VoidCallback? after}) {
    if (!mounted) return;
    if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
      _pendingAfterRebuild = after ?? _pendingAfterRebuild;
      if (_deferredRebuildScheduled) return;
      _deferredRebuildScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _deferredRebuildScheduled = false;
        if (!mounted) return;
        final next = _pendingAfterRebuild;
        _pendingAfterRebuild = null;
        _rebuildEditingStateWhenSafe(after: next);
      });
      return;
    }
    _rebuildEditingState();
    // Controllers are disposed above; flow bindings still point at them until
    // the next build remounts fields. Place caret only after that frame.
    if (after == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      after();
    });
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

  Map<int, String> get _objectTypesById => {
        for (final e in _embedsSnapshot ??
            widget.state.embedsByFileId[widget.file.id] ??
            widget.embeds)
          e.id: e.type,
      };

  String _serializeDoc() => _buffer.stored;

  RichDocument _stampEmbedTypes(RichDocument doc) {
    final types = _objectTypesById;
    return doc.copyWith(
      blocks: [
        for (final block in doc.blocks)
          if (block is EmbedNode)
            block.copyWith(objectType: types[block.objectId] ?? block.objectType)
          else
            block,
      ],
    );
  }

  Future<void> _flushPendingChanges() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    final json = _serializeDoc();
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
    _history.record(_buffer.text);
    _lastHistoryRecord = now;
  }

  void _mutateDoc(
    RichDocument doc, {
    bool rebuild = false,
    bool save = true,
    bool recordHistory = true,
  }) {
    if (recordHistory) _recordHistory();
    _buffer.loadFromRichDocument(doc, objectTypes: _objectTypesById);
    _syncDocFromBuffer();
    _pruneOrphans();
    if (save) _scheduleSave();
    if (rebuild && mounted) setState(() {});
  }

  void _undo() {
    final previous = _history.undo(_buffer.text);
    if (previous == null) return;
    _applyingHistory = true;
    _buffer = DocumentBuffer(previous);
    _syncDocFromBuffer();
    _rebuildEditingState();
    _applyingHistory = false;
    _scheduleSave();
  }

  void _redo() {
    final next = _history.redo(_buffer.text);
    if (next == null) return;
    _applyingHistory = true;
    _buffer = DocumentBuffer(next);
    _syncDocFromBuffer();
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
    // Split mid-paragraph / mid-heading at the caret when needed, then insert
    // between the halves (or after the block when the caret is at its end).
    final index = await _prepareInsertSite();

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

  /// Prepares the document for an insert at the caret and returns the block
  /// index where the new block should go.
  ///
  /// Mid-paragraph / mid-heading splits into before | (insert) | after.
  /// Caret at the start inserts before that block; at the end, after it.
  Future<int> _prepareInsertSite() async {
    _flushParagraphControllersIntoDoc();
    final result = _session.prepareInsertSite(
      doc: _doc,
      focusedSegmentId: _flow.focusedSegmentId,
      fallbackBlockIndex: _focusedBlockIndex,
      liveTextOf: (id) => _controllers[id]?.text,
      liveSpansOf: (id) {
        final c = _controllers[id];
        if (c == null) return null;
        return [
          for (final s in c.spans)
            TextSpanMark.fromJson(Map<String, dynamic>.from(s)),
        ];
      },
      caretOffsetOf: _caretOffsetInSegment,
    );
    if (result.changed) {
      _commitSessionResult(result, recordHistory: false, resetControllers: true);
      await _flushPendingChanges();
    }
    return result.insertGapIndex ??
        (_focusedBlockIndex + 1).clamp(0, _doc.blocks.length);
  }

  int _caretOffsetInSegment(String segmentId) {
    final sel = _flow.selection;
    if (sel != null && sel.focus.segmentId == segmentId) {
      return sel.focus.offset;
    }
    final c = _flow.controllerFor(segmentId) ?? _controllers[segmentId];
    if (c != null && c.selection.isValid) {
      return c.selection.extentOffset;
    }
    return c?.text.length ?? 0;
  }

  /// Push paragraph/heading controller text into the marker buffer before ops.
  void _flushParagraphControllersIntoDoc() {
    var changed = false;
    for (final block in _doc.blocks) {
      final c = _controllers[block.id];
      if (c == null) continue;
      final DocumentNode? node = switch (block) {
        ParagraphNode(:final text) when c.text != text =>
          block.copyWith(text: c.text),
        HeadingNode(:final text) when c.text != text =>
          block.copyWith(text: c.text),
        _ => null,
      };
      if (node == null) continue;
      _buffer.replacePartSlice(block.id, _sliceForNode(node));
      changed = true;
    }
    if (changed) _syncDocFromBuffer();
  }

  /// Single commit path after [DocumentSession] structural edits.
  void _commitSessionResult(
    DocumentSessionResult result, {
    bool recordHistory = true,
    bool resetControllers = true,
    bool clearMoveMode = false,
  }) {
    if (!result.changed) return;
    if (recordHistory) _recordHistory(force: true);
    _flushLiveInfoEmbedCaches();
    // Session still returns a RichDocument view — fold into marker buffer (SoT).
    _buffer.loadFromRichDocument(result.doc, objectTypes: _objectTypesById);
    _syncDocFromBuffer();
    _embedsSnapshot =
        widget.state.embedsByFileId[widget.file.id] ?? _embedsSnapshot;
    if (!resetControllers) _pruneOrphans();
    _scheduleSave();
    if (clearMoveMode) {
      _moveModeEmbedId = null;
      _dropPreview = null;
    }
    final segmentId = result.focusSegmentId;
    final landingId = result.landingBlockId;
    final focusOffset = result.focusOffset;
    void placeFocus() {
      if (!mounted) return;
      if (segmentId != null) {
        _flow.placeCaret(DocumentTextPosition(segmentId, focusOffset));
        return;
      }
      if (landingId != null) _focusFirstPartOf(landingId);
    }

    if (resetControllers) {
      _rebuildEditingStateWhenSafe(after: placeFocus);
    } else if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) => placeFocus());
    }
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

    // Server wrote the pointer into document_json; adopt buffer text.
    final updated = await widget.state.reloadFile(widget.file.id);
    _buffer = DocumentBuffer.fromStored(updated.documentJson);
    _syncDocFromBuffer();
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

  /// Serialize one view node to its marker-text slice.
  String _sliceForNode(DocumentNode node) {
    return DocumentTextCodec.stripHeader(
      DocumentTextCodec.serialize(
        RichDocument(version: RichDocument.documentVersion, blocks: [node]),
        objectTypes: _objectTypesById,
      ),
    );
  }

  /// Write-through: replace the part slice in the buffer (SoT).
  void _writeNodeToBuffer(DocumentNode node, {bool recordHistory = true}) {
    if (recordHistory) _recordHistory();
    final slice = _sliceForNode(node);
    if (_buffer.partByKey(node.id) != null) {
      _buffer.replacePartSlice(node.id, slice);
    } else {
      _buffer.loadFromRichDocument(
        DocumentCodec.replaceBlock(_doc, node.id, node),
        objectTypes: _objectTypesById,
      );
    }
    _syncDocFromBuffer();
    _scheduleSave();
  }

  void _updateParagraph(ParagraphNode block, SpanTextEditingController controller) {
    _claimThisFile(_doc.blocks.indexWhere((b) => b.id == block.id));
    _writeNodeToBuffer(
      block.copyWith(text: controller.text),
    );
  }

  Future<void> _mergeOrDeleteParagraph(ParagraphNode block, int index) async {
    final controller = _controllerFor(block.id, block.text, block.spans);
    if (controller.text.trim().isNotEmpty) return;
    if (_doc.blocks.length <= 1) return;

    _recordHistory(force: true);
    final blocks = [..._doc.blocks]..removeAt(index);

    // Prefer landing at the end of the text above; else start of what follows.
    String? focusBlockId;
    var focusOffset = 0;
    if (index > 0) {
      final prev = _doc.blocks[index - 1];
      if (prev is ParagraphNode) {
        focusBlockId = prev.id;
        focusOffset = prev.text.length;
      } else if (prev is HeadingNode) {
        focusBlockId = prev.id;
        focusOffset = prev.text.length;
      } else if (index < blocks.length) {
        final next = blocks[index];
        if (next is ParagraphNode || next is HeadingNode) {
          focusBlockId = next.id;
          focusOffset = 0;
        }
      }
    } else if (blocks.isNotEmpty) {
      final next = blocks.first;
      if (next is ParagraphNode || next is HeadingNode) {
        focusBlockId = next.id;
        focusOffset = 0;
      }
    }

    final coalesced = DocumentCodec.coalesceAdjacentParagraphs(
      _doc.copyWith(blocks: blocks),
    );
    _buffer.loadFromRichDocument(coalesced, objectTypes: _objectTypesById);
    _syncDocFromBuffer();
    _scheduleSave();

    final landingId = focusBlockId != null &&
            coalesced.blocks.any((b) => b.id == focusBlockId)
        ? focusBlockId
        : (coalesced.blocks.isNotEmpty ? coalesced.blocks.first.id : null);
    final offset = landingId == focusBlockId ? focusOffset : 0;

    _rebuildEditingStateWhenSafe(
      after: () {
        if (!mounted || landingId == null) return;
        _flow.placeCaret(
          DocumentTextPosition(paragraphSegmentId(landingId), offset),
        );
      },
    );
  }

  /// Removes a list/table block entirely (Backspace on the last empty unit).
  void _removeStructureBlock(String blockId) {
    _flushParagraphControllersIntoDoc();
    _commitSessionResult(_session.removeStructureBlock(_doc, blockId));
  }

  /// Backspace on an empty object — remove embed from doc, then cascade API.
  Future<void> _deleteEmbedBlock(String blockId) async {
    _flushParagraphControllersIntoDoc();
    final result = _session.deleteEmbedBlock(_doc, blockId);
    if (!result.changed) return;
    _commitSessionResult(result);
    await _flushPendingChanges();
    final objectId = result.removedObjectId;
    if (objectId != null) {
      await widget.state.deleteObjectEmbed(objectId);
      await _reloadEmbedsQuiet();
    }
  }

  void _exitListBelow(String blockId, int emptyItemIndex) {
    _commitSessionResult(
      _session.exitListBelow(_doc, blockId, emptyItemIndex),
    );
  }

  void _exitTableBelow(String blockId, int emptyRowIndex) {
    _commitSessionResult(
      _session.exitTableBelow(_doc, blockId, emptyRowIndex),
    );
  }

  /// Continues writing below an embedded object without destroying it.
  void _exitEmbedBelow(String blockId) {
    _commitSessionResult(_session.exitEmbedBelow(_doc, blockId));
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

    if (remaining.isEmpty) {
      final result = _session.replaceEmbedWithParagraph(_doc, blockId);
      _commitSessionResult(result, recordHistory: false);
      await _flushPendingChanges();
      if (result.removedObjectId != null) {
        await widget.state.deleteObjectEmbed(result.removedObjectId!);
      }
      await _reloadEmbedsQuiet();
      return;
    }

    _commitSessionResult(
      _session.exitEmbedBelow(_doc, blockId),
      recordHistory: false,
    );
    await _reloadEmbedsQuiet();
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

    final hasContent = labels.any((l) => l.trim().isNotEmpty) ||
        values.any((v) => v.trim().isNotEmpty);

    if (!hasContent || labels.isEmpty) {
      final result = _session.replaceEmbedWithParagraph(_doc, blockId);
      _commitSessionResult(result);
      await _flushPendingChanges();
      if (result.removedObjectId != null) {
        await widget.state.deleteObjectEmbed(result.removedObjectId!);
      }
      await _reloadEmbedsQuiet();
      return;
    }

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
    _commitSessionResult(_session.exitEmbedBelow(_doc, blockId));
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
              (fullyEmptied.contains(embedSegmentId(block.id)) ||
                  (fullyEmptied.contains(infoTitleSegmentId(block.id)) &&
                      fullyEmptied.contains(infoBodySegmentId(block.id)))))
            block.objectId,
      ];

      final caretSegment = _flow.focusedSegmentId;
      final sessionResult = _session.applyPrune(
        doc: _doc,
        fullyEmptied: fullyEmptied,
        spansParts: spansParts,
      );
      if (!sessionResult.changed &&
          removedObjectIds.isEmpty &&
          !objectPartsTouched) {
        return;
      }

      _flow.clearSelection();
      if (sessionResult.changed) {
        _commitSessionResult(sessionResult);
        await _flushPendingChanges();
      }

      // Cascade-delete backing rows so agent text and views stay clean.
      // Do not reload document_json from the server — local buffer is source
      // of truth after flush (reload used to overwrite with a stale body).
      for (final objectId in removedObjectIds) {
        await widget.state.deleteObjectEmbed(objectId);
      }
      if (removedObjectIds.isNotEmpty) {
        await _reloadEmbedsQuiet();
      }

      final caretSurvived =
          caretSegment != null && _segmentOrder().contains(caretSegment);
      if (!caretSurvived && sessionResult.landingBlockId != null) {
        _focusFirstPartOf(sessionResult.landingBlockId!);
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
    final editor = _buildEditor(context);
    final minHeight = widget.minViewportHeight;
    // Fill the pane height so taps under short/empty files hit this editor
    // (the scroll child is otherwise only as tall as the text). During Move
    // Mode the fill is also a drop target for "after the last line".
    final body = minHeight == null
        ? editor
        : Stack(
            children: [
              SizedBox(
                height: minHeight,
                width: double.infinity,
                child: _moveModeEmbedId == null
                    ? const ColoredBox(color: Color(0x00000000))
                    : _embedDropGap(
                        gapIndex: _doc.blocks.length,
                        expand: true,
                      ),
              ),
              editor,
            ],
          );

    return DocumentTextFlowScope(
      flow: _flow,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onEditorPointerDown,
        onPointerMove: _onEditorPointerMove,
        onPointerUp: (_) => _endDragSelection(),
        onPointerCancel: (_) => _endDragSelection(),
        child: body,
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
      // Only place the caret when the tap missed every field box (empty space
      // under the file). Taps inside a field — including RTL empty padding
      // beside glyphs — are owned by FormattedTextField.onTap in the same
      // event turn. Placing here too fights the TextField (correct → wrong →
      // correct) and paints a caret jump.
      if (!_flow.segmentContainsGlobal(event.position)) {
        _flow.placeCaret(at);
      }
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
                      // Embeds sit in the text like paragraphs — not list/table
                      // chrome with a taller gap.
                      bottom: _doc.blocks[index] is ParagraphNode ||
                              _doc.blocks[index] is EmbedNode
                          ? 2
                          : 8,
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

  /// Empty space under the file — drop = after the last block.
  Widget _embedDropGap({required int gapIndex, bool expand = false}) {
    final movingId = _moveModeEmbedId;
    return DragTarget<String>(
      hitTestBehavior: HitTestBehavior.opaque,
      onWillAcceptWithDetails: (details) {
        if (movingId == null || details.data != movingId) return false;
        final current = _doc.blocks.indexWhere((b) => b.id == details.data);
        if (current < 0) return false;
        return gapIndex != current && gapIndex != current + 1;
      },
      onAcceptWithDetails: (details) {
        _clearDropPreview();
        _moveEmbedToGap(details.data, gapIndex);
      },
      builder: (context, candidate, rejected) {
        final hot = candidate.isNotEmpty;
        return ColoredBox(
          color: hot
              ? AppColors.primary.withValues(alpha: 0.06)
              : const Color(0x00000000),
          child: expand
              ? Align(
                  alignment: Alignment.topCenter,
                  child: hot
                      ? Container(
                          height: 3,
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.75),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        )
                      : null,
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }

  Widget _buildBlock(DocumentNode block, int index) {
    final content = block is EmbedNode
        ? _buildEmbed(block, index)
        : _buildEditableBlock(block, index);
    if (_moveModeEmbedId == null || block.id == _moveModeEmbedId) {
      return content;
    }
    // Whole block is a drop zone — pointer Y picks before / between lines / after.
    return Builder(
      builder: (targetContext) {
        return DragTarget<String>(
          hitTestBehavior: HitTestBehavior.opaque,
          onWillAcceptWithDetails: (details) =>
              details.data == _moveModeEmbedId,
          onMove: (details) => _updateDropPreview(
            block,
            index,
            details.offset,
            targetBox: targetContext.findRenderObject() as RenderBox?,
          ),
          onLeave: (_) {
            if (_dropPreview?.blockIndex == index) _clearDropPreview();
          },
          onAcceptWithDetails: (details) {
            final preview = _dropPreview;
            _clearDropPreview();
            if (preview == null || preview.blockIndex != index) {
              _moveEmbedToGap(details.data, index);
              return;
            }
            _acceptEmbedDrop(details.data, preview);
          },
          builder: (context, candidate, rejected) {
            final preview =
                candidate.isNotEmpty && _dropPreview?.blockIndex == index
                    ? _dropPreview
                    : null;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                IgnorePointer(child: content),
                if (preview != null)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: () {
                      final box = context.findRenderObject();
                      if (box is! RenderBox || !box.hasSize) {
                        return preview.localY - 1.5;
                      }
                      return box
                              .globalToLocal(Offset(0, preview.globalY))
                              .dy -
                          1.5;
                    }(),
                    child: IgnorePointer(
                      child: Container(
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
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

    return EmbedBlockHost(
      blockId: block.id,
      documentBaseOffset: _partBaseOffset(block.id),
      registerAsUnit: embed == null ||
          (embed.type != 'task_list' &&
              embed.type != 'graph' &&
              embed.type != 'info'),
      onInteract: () => _claimThisFile(index),
      onMoveModeChanged: (active) {
        if (!mounted) return;
        setState(() {
          _moveModeEmbedId = active ? block.id : null;
          if (!active) _dropPreview = null;
        });
      },
      child: child,
    );
  }

  void _clearDropPreview() {
    if (_dropPreview == null) return;
    setState(() => _dropPreview = null);
  }

  void _updateDropPreview(
    DocumentNode block,
    int index,
    Offset global, {
    RenderBox? targetBox,
  }) {
    final next = _resolveDropPreview(
      block,
      index,
      global,
      targetBox: targetBox,
    );
    final prev = _dropPreview;
    if (prev != null &&
        next != null &&
        prev.blockIndex == next.blockIndex &&
        prev.gapIndex == next.gapIndex &&
        prev.splitOffset == next.splitOffset &&
        (prev.globalY - next.globalY).abs() < 0.5) {
      return;
    }
    setState(() => _dropPreview = next);
  }

  /// Maps a pointer over [block] to a between-line (or before/after) drop.
  _EmbedDropPreview? _resolveDropPreview(
    DocumentNode block,
    int index,
    Offset global, {
    RenderBox? targetBox,
  }) {
    if (block is ParagraphNode || block is HeadingNode) {
      final resolved = _resolveTextLineDrop(block.id, index, global);
      if (resolved != null) return resolved;
    }

    // Lists / tables / embeds / fallback: before vs after by vertical half.
    final box = (targetBox != null && targetBox.hasSize)
        ? targetBox
        : null;
    if (box != null) {
      final local = box.globalToLocal(global);
      final before = local.dy < box.size.height / 2;
      final y = before ? 0.0 : box.size.height;
      return _EmbedDropPreview(
        blockIndex: index,
        gapIndex: before ? index : index + 1,
        localY: y,
        globalY: box.localToGlobal(Offset(0, y)).dy,
      );
    }
    return _EmbedDropPreview(
      blockIndex: index,
      gapIndex: index,
      localY: 0,
      globalY: global.dy,
    );
  }

  _EmbedDropPreview? _resolveTextLineDrop(
    String blockId,
    int blockIndex,
    Offset global,
  ) {
    final focusCtx = _focusNodes[blockId]?.context;
    final root = focusCtx?.findRenderObject();
    if (root == null || !root.attached) return null;

    RenderEditable? editable;
    void walk(RenderObject object) {
      if (editable != null) return;
      if (object is RenderEditable) {
        editable = object;
        return;
      }
      object.visitChildren(walk);
    }

    walk(root);
    final edit = editable;
    if (edit == null || !edit.hasSize) {
      if (root is! RenderBox || !root.hasSize) return null;
      final box = root;
      final local = box.globalToLocal(global);
      final before = local.dy < box.size.height / 2;
      final y = before ? 0.0 : box.size.height;
      return _EmbedDropPreview(
        blockIndex: blockIndex,
        gapIndex: before ? blockIndex : blockIndex + 1,
        localY: y,
        globalY: box.localToGlobal(Offset(0, y)).dy,
      );
    }

    final textLength = _flow.lengthOf(blockId) ??
        _controllers[blockId]?.text.length ??
        0;
    if (textLength <= 0) {
      final box = edit;
      final local = box.globalToLocal(global);
      final before = local.dy < box.size.height / 2;
      final y = before ? 0.0 : box.size.height;
      return _EmbedDropPreview(
        blockIndex: blockIndex,
        gapIndex: before ? blockIndex : blockIndex + 1,
        localY: y,
        globalY: box.localToGlobal(Offset(0, y)).dy,
      );
    }
    final raw = edit.getPositionForPoint(global).offset.clamp(0, textLength);
    final line = edit.getLineAtOffset(TextPosition(offset: raw));
    if (!line.isValid || line.start < 0 || line.end < 0) {
      final box = edit;
      final local = box.globalToLocal(global);
      final before = local.dy < box.size.height / 2;
      final y = before ? 0.0 : box.size.height;
      return _EmbedDropPreview(
        blockIndex: blockIndex,
        gapIndex: before ? blockIndex : blockIndex + 1,
        localY: y,
        globalY: box.localToGlobal(Offset(0, y)).dy,
      );
    }
    final extent = line.end > line.start
        ? line.end
        : (line.start + 1).clamp(0, textLength);
    final selection = TextSelection(
      baseOffset: line.start.clamp(0, textLength),
      extentOffset: extent.clamp(0, textLength),
    );
    if (!selection.isValid) {
      final box = edit;
      final local = box.globalToLocal(global);
      final before = local.dy < box.size.height / 2;
      final y = before ? 0.0 : box.size.height;
      return _EmbedDropPreview(
        blockIndex: blockIndex,
        gapIndex: before ? blockIndex : blockIndex + 1,
        localY: y,
        globalY: box.localToGlobal(Offset(0, y)).dy,
      );
    }
    final boxes = edit.getBoxesForSelection(selection);
    final local = edit.globalToLocal(global);
    var lineTop = local.dy;
    var lineBottom = local.dy;
    if (boxes.isNotEmpty) {
      lineTop = boxes.map((b) => b.top).reduce((a, b) => a < b ? a : b);
      lineBottom = boxes.map((b) => b.bottom).reduce((a, b) => a > b ? a : b);
    }
    final mid = (lineTop + lineBottom) / 2;
    // Snap to the visual line boundary — that's "between lines".
    final cut = local.dy < mid ? line.start : line.end;
    final indicatorLocalY = local.dy < mid ? lineTop : lineBottom;
    final globalY = edit.localToGlobal(Offset(0, indicatorLocalY)).dy;

    if (cut <= 0) {
      return _EmbedDropPreview(
        blockIndex: blockIndex,
        gapIndex: blockIndex,
        localY: indicatorLocalY,
        globalY: globalY,
      );
    }
    if (cut >= textLength) {
      return _EmbedDropPreview(
        blockIndex: blockIndex,
        gapIndex: blockIndex + 1,
        localY: indicatorLocalY,
        globalY: globalY,
      );
    }
    return _EmbedDropPreview(
      blockIndex: blockIndex,
      gapIndex: blockIndex + 1,
      splitOffset: cut,
      localY: indicatorLocalY,
      globalY: globalY,
    );
  }

  void _acceptEmbedDrop(String embedBlockId, _EmbedDropPreview preview) {
    if (preview.splitOffset != null) {
      _moveEmbedSplittingText(
        embedBlockId,
        preview.blockIndex,
        preview.splitOffset!,
      );
      return;
    }
    _moveEmbedToGap(embedBlockId, preview.gapIndex);
  }

  ObjectEmbed? _embedFor(int objectId) {
    // Prefer AppState (patched sync by info editors) over a stale snapshot.
    final live = widget.state.embedsByFileId[widget.file.id] ??
        _embedsSnapshot ??
        widget.embeds;
    for (final embed in live) {
      if (embed.id == objectId) return embed;
    }
    return null;
  }

  Widget _embedWidget(ObjectEmbed embed, String blockId) {
    Future<void> refresh() => _reloadEmbedsQuiet();
    void exitBelow() => _exitEmbedBelow(blockId);
    void deleteObject() => unawaited(_deleteEmbedBlock(blockId));
    final base = _partBaseOffset(blockId);

    return switch (embed.type) {
      'task_list' => InlineTaskListWidget(
          embed: embed,
          blockId: blockId,
          state: widget.state,
          documentBaseOffset: base,
          onRefresh: refresh,
          onFocus: () {
            final i = _doc.blocks.indexWhere((b) => b.id == blockId);
            if (i >= 0) _claimThisFile(i);
          },
          onExitBelow: (emptyTaskId) =>
              unawaited(_exitTaskListBelow(blockId, emptyTaskId)),
          onDeleteObject: deleteObject,
        ),
      'info' => InfoEmbed(
          key: _infoEmbedKeys.putIfAbsent(
            embed.id,
            () => GlobalKey<InfoEmbedState>(debugLabel: 'info-${embed.id}'),
          ),
          embed: embed,
          blockId: blockId,
          state: widget.state,
          documentBaseOffset: base,
          onRefresh: () => unawaited(refresh()),
          onFocus: () {
            final i = _doc.blocks.indexWhere((b) => b.id == blockId);
            if (i >= 0) _claimThisFile(i);
          },
          onExitBelow: exitBelow,
          onDeleteObject: deleteObject,
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
          documentBaseOffset: base,
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
          onDeleteObject: deleteObject,
        ),
      _ => Text('[${embed.type}]', style: AppTypography.metaStyle),
    };
  }

  /// Warm AppState from live info controllers before any remount.
  void _flushLiveInfoEmbedCaches() {
    for (final key in _infoEmbedKeys.values) {
      key.currentState?.pushControllersToCache();
    }
    _embedsSnapshot =
        widget.state.embedsByFileId[widget.file.id] ?? _embedsSnapshot;
  }

  void _moveEmbedToGap(String blockId, int gapIndex) {
    _flushParagraphControllersIntoDoc();
    _flushLiveInfoEmbedCaches();
    final objectId = _objectIdForEmbedBlock(blockId);
    if (objectId == null) return;
    _recordHistory(force: true);
    if (!_buffer.movePointer(objectId, gapIndex)) {
      setState(() {
        _moveModeEmbedId = null;
        _dropPreview = null;
      });
      return;
    }
    _syncDocFromBuffer();
    _moveModeEmbedId = null;
    _dropPreview = null;
    _scheduleSave();
    _rebuildEditingStateWhenSafe(
      after: () {
        if (!mounted) return;
        _focusFirstPartOf('embed:$objectId');
      },
    );
  }

  /// Splits a paragraph/heading at [cut] and places the embed between the halves.
  void _moveEmbedSplittingText(
    String embedBlockId,
    int targetIndex,
    int cut,
  ) {
    _flushParagraphControllersIntoDoc();
    _flushLiveInfoEmbedCaches();
    if (targetIndex < 0 || targetIndex >= _doc.blocks.length) return;
    final block = _doc.blocks[targetIndex];
    final objectId = _objectIdForEmbedBlock(embedBlockId);
    if (objectId == null) return;
    EmbedNode? embed;
    for (final b in _doc.blocks) {
      if (b is EmbedNode && b.objectId == objectId) {
        embed = b;
        break;
      }
    }
    final controller = _controllers[block.id];
    if (controller != null &&
        (block is ParagraphNode || block is HeadingNode)) {
      _buffer.replacePartSlice(block.id, controller.text);
      _syncDocFromBuffer();
    }
    _recordHistory(force: true);
    final ok = _buffer.splitPartAndInsertPointer(
      partKey: block.id,
      cut: cut,
      objectId: objectId,
      objectType: embed?.objectType ?? _objectTypesById[objectId],
    );
    if (!ok) {
      _moveEmbedToGap(embedBlockId, targetIndex);
      return;
    }
    _syncDocFromBuffer();
    _moveModeEmbedId = null;
    _dropPreview = null;
    _scheduleSave();
    _rebuildEditingStateWhenSafe(
      after: () {
        if (!mounted) return;
        _focusFirstPartOf('embed:$objectId');
      },
    );
  }

  int? _objectIdForEmbedBlock(String blockId) {
    for (final b in _doc.blocks) {
      if (b is EmbedNode && b.id == blockId) return b.objectId;
    }
    if (blockId.startsWith('embed:')) {
      return int.tryParse(blockId.substring(6));
    }
    return null;
  }

  int _partBaseOffset(String partKey) =>
      _buffer.partByKey(partKey)?.start ?? 0;

  Widget _buildEditableBlock(DocumentNode block, int index) {
    if (block is ParagraphNode) {
      final segmentId = paragraphSegmentId(block.id);
      final controller = _controllerFor(block.id, block.text, block.spans);
      return FormattedTextField(
        key: ValueKey('p-${block.id}'),
        controller: controller,
        focusNode: _focusFor(block.id),
        segmentId: segmentId,
        documentBaseOffset: _partBaseOffset(block.id),
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
        documentBaseOffset: _partBaseOffset(block.id),
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
          _writeNodeToBuffer(block.copyWith(text: controller.text));
        },
        onSecondaryTapDown: _showTextMenu,
      );
    }
    if (block is ListNode) {
      return RichListEditor(
        key: ValueKey('l-${block.id}'),
        node: block,
        strings: _strings,
        documentBaseOffset: _partBaseOffset(block.id),
        onFocus: () => _claimThisFile(index),
        onChanged: (updated) {
          _claimThisFile(index);
          _writeNodeToBuffer(updated);
        },
        onExitList: (emptyItemIndex) => _exitListBelow(block.id, emptyItemIndex),
        onDeleteList: () => _removeStructureBlock(block.id),
        onStyleChanged: (style) => _setListStyle(block.id, style),
      );
    }
    if (block is TableNode) {
      return RichTableEditor(
        key: ValueKey('t-${block.id}'),
        node: block,
        strings: _strings,
        documentBaseOffset: _partBaseOffset(block.id),
        onFocus: () => _claimThisFile(index),
        onChanged: (updated) {
          _claimThisFile(index);
          _writeNodeToBuffer(updated);
        },
        onExitTable: (emptyRowIndex) => _exitTableBelow(block.id, emptyRowIndex),
        onDeleteTable: () => _removeStructureBlock(block.id),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Where an embed will land while hovering during Move Mode.
class _EmbedDropPreview {
  const _EmbedDropPreview({
    required this.blockIndex,
    required this.gapIndex,
    required this.localY,
    required this.globalY,
    this.splitOffset,
  });

  final int blockIndex;
  /// Gap index for [DocumentBuffer.movePointer] when not splitting.
  final int gapIndex;
  final double localY;
  final double globalY;
  /// When set, split the paragraph/heading at this offset and insert between.
  final int? splitOffset;
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
