import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/app_file.dart';
import '../../design_system/app_typography.dart';
import 'document_codec.dart';
import 'document_edit_history.dart';
import 'document_editor_controller.dart';
import 'document_model.dart';
import 'rich_text/block_text_actions.dart';
import 'rich_text/block_text_focus.dart';
import 'rich_text/document_context_menu.dart';
import 'rich_text/formatted_text_field.dart';
import 'rich_text/list_editor.dart';
import 'rich_text/rich_table_editor.dart';
import 'rich_text/span_text_editing_controller.dart';

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
  final List<dynamic> embeds;

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

  static final _paragraphStyle = AppTypography.noteBodyStyle.copyWith(height: 1.35);

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DocumentEditorRegistry.register(
        DocumentEditorController(
          fileId: widget.file.id,
          insertAtBlock: _insertAtBlock,
          focusBlock: (index) => _focusedBlockIndex = index,
          flushPendingChanges: _flushPendingChanges,
        ),
      );
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
    unawaited(_flushPendingChanges());
    DocumentEditorRegistry.unregister(widget.file.id);
    _saveTimer?.cancel();
    _disposeAllFocusNodes();
    _disposeControllers();
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
    });
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

  FocusNode _focusFor(String blockId) =>
      _focusNodes.putIfAbsent(blockId, FocusNode.new);

  Future<void> _showTextMenu(TapDownDetails details) async {
    await DocumentContextMenu.showTextMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: _strings,
      onAction: runBlockTextAction,
    );
  }

  Future<void> _insertAtBlock(String action) async {
    await _flushPendingChanges();
    _recordHistory(force: true);
    final index = (_focusedBlockIndex + 1).clamp(0, _doc.blocks.length);
    switch (action) {
      case 'paragraph':
        _mutateDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            ParagraphNode(id: DocumentCodec.newId('b'), text: ''),
          ),
          rebuild: true,
          recordHistory: false,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final block = _doc.blocks[index];
          _focusFor(block.id).requestFocus();
        });
      case 'list':
      case 'bullet_list':
        _mutateDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            ListNode(
              id: DocumentCodec.newId('b'),
              items: [ListItem(id: DocumentCodec.newId('li'), text: '')],
            ),
          ),
          rebuild: true,
          recordHistory: false,
        );
      case 'ordered_list':
        _mutateDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            ListNode(
              id: DocumentCodec.newId('b'),
              listStyle: 'numbered',
              items: [ListItem(id: DocumentCodec.newId('li'), text: '')],
            ),
          ),
          rebuild: true,
          recordHistory: false,
        );
      case 'table':
        _mutateDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            TableNode(
              id: DocumentCodec.newId('b'),
              rows: [
                [const DocumentTableCell(text: ''), const DocumentTableCell(text: '')],
              ],
            ),
          ),
          rebuild: true,
          recordHistory: false,
        );
    }
  }

  void _updateParagraph(ParagraphNode block, SpanTextEditingController controller) {
    _focusedBlockIndex = _doc.blocks.indexWhere((b) => b.id == block.id);
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

  void _exitListBelow(ListNode block, int index, int emptyItemIndex) {
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

  void _exitTableBelow(TableNode block, int index, int emptyRowIndex) {
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

  @override
  Widget build(BuildContext context) {
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
      return Text(
        '[embedded object ${block.objectId}]',
        style: AppTypography.metaStyle.copyWith(
          color: Theme.of(context).colorScheme.outline,
        ),
      );
    }
    if (block is ParagraphNode) {
      final controller = _controllerFor(block.id, block.text, block.spans);
      return FormattedTextField(
        key: ValueKey('p-${block.id}'),
        controller: controller,
        focusNode: _focusFor(block.id),
        style: _paragraphStyle,
        maxLines: null,
        minLines: 1,
        onChanged: (_) => _updateParagraph(block, controller),
        onBackspaceAtStart: () => _mergeOrDeleteParagraph(block, index),
        onSecondaryTapDown: _showTextMenu,
      );
    }
    if (block is HeadingNode) {
      final controller = _controllerFor(block.id, block.text, block.spans);
      return FormattedTextField(
        key: ValueKey('h-${block.id}'),
        controller: controller,
        focusNode: _focusFor(block.id),
        style: AppTypography.noteTitleStyle.copyWith(
          fontSize: 24 - (block.level * 2),
          height: 1.3,
        ),
        maxLines: null,
        onChanged: (_) {
          _focusedBlockIndex = index;
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
        onFocus: () => _focusedBlockIndex = index,
        onChanged: (updated) {
          _focusedBlockIndex = index;
          _mutateDoc(
            DocumentCodec.replaceBlock(_doc, block.id, updated),
            rebuild: false,
          );
        },
        onExitList: (emptyItemIndex) => _exitListBelow(block, index, emptyItemIndex),
      );
    }
    if (block is TableNode) {
      return RichTableEditor(
        key: ValueKey('t-${block.id}'),
        node: block,
        strings: _strings,
        onFocus: () => _focusedBlockIndex = index,
        onChanged: (updated) {
          _focusedBlockIndex = index;
          _mutateDoc(
            DocumentCodec.replaceBlock(_doc, block.id, updated),
            rebuild: false,
          );
        },
        onExitTable: (emptyRowIndex) => _exitTableBelow(block, index, emptyRowIndex),
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
