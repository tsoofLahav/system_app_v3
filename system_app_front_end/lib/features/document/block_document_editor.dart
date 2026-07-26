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

  AppStrings get _strings => widget.state.strings;

  AppFile get _currentFile =>
      widget.state.selectedDetail?.files.where((f) => f.id == widget.file.id).firstOrNull ??
      widget.file;

  @override
  void initState() {
    super.initState();
    _doc = DocumentCodec.parse(_currentFile.documentJson);
    if (_doc.blocks.isEmpty) {
      _doc = _doc.copyWith(blocks: [ParagraphNode(id: DocumentCodec.newId('b'), text: '')]);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      DocumentEditorRegistry.register(
        DocumentEditorController(
          fileId: widget.file.id,
          insertAtBlock: _insertAtBlock,
          focusBlock: (index) => setState(() => _focusedBlockIndex = index),
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
      _doc = DocumentCodec.parse(_currentFile.documentJson);
      _dirty = false;
      _clearControllers();
    } else if (!_dirty && oldWidget.file.documentJson != widget.file.documentJson) {
      final incoming = _currentFile.documentJson;
      if (incoming != _lastSavedJson) {
        _doc = DocumentCodec.parse(_currentFile.documentJson);
        _clearControllers();
      }
    }
  }

  void _clearControllers() {
    BlockTextFocusRegistry.abandonStashedFocus();
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
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
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _clearControllers();
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

  void _applyDoc(RichDocument doc, {bool save = true, bool recordHistory = true}) {
    if (recordHistory) _recordHistory();
    setState(() => _doc = doc);
    if (save) _scheduleSave();
  }

  void _undo() {
    final previous = _history.undo(_doc);
    if (previous == null) return;
    _applyingHistory = true;
    setState(() => _doc = previous);
    _clearControllers();
    _applyingHistory = false;
    _scheduleSave();
  }

  void _redo() {
    final next = _history.redo(_doc);
    if (next == null) return;
    _applyingHistory = true;
    setState(() => _doc = next);
    _clearControllers();
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
        _applyDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            ParagraphNode(id: DocumentCodec.newId('b'), text: ''),
          ),
          recordHistory: false,
        );
      case 'list':
      case 'bullet_list':
        _applyDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            ListNode(
              id: DocumentCodec.newId('b'),
              items: [ListItem(id: DocumentCodec.newId('li'), text: '')],
            ),
          ),
          recordHistory: false,
        );
      case 'ordered_list':
        _applyDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            ListNode(
              id: DocumentCodec.newId('b'),
              listStyle: 'numbered',
              items: [ListItem(id: DocumentCodec.newId('li'), text: '')],
            ),
          ),
          recordHistory: false,
        );
      case 'table':
        _applyDoc(
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
          recordHistory: false,
        );
    }
  }

  void _updateParagraph(ParagraphNode block, int index, SpanTextEditingController controller) {
    _focusedBlockIndex = index;
    _applyDoc(
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
    );
  }

  void _splitParagraph(ParagraphNode block, int index, SpanTextEditingController controller) {
    _recordHistory(force: true);
    final sel = controller.selection;
    final splitAt = sel.isValid ? sel.start.clamp(0, controller.text.length) : controller.text.length;
    final beforeText = controller.text.substring(0, splitAt);
    final afterText = controller.text.substring(splitAt);
    final beforeSpans = _spansBefore(controller.spans, splitAt);
    final afterSpans = _spansAfter(controller.spans, splitAt);

    final newId = DocumentCodec.newId('b');
    var blocks = [..._doc.blocks];
    blocks[index] = block.copyWith(text: beforeText, spans: beforeSpans);
    blocks.insert(
      index + 1,
      ParagraphNode(id: newId, text: afterText, spans: afterSpans),
    );
    _controllers.remove(block.id)?.dispose();
    _applyDoc(_doc.copyWith(blocks: blocks), recordHistory: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusFor(newId).requestFocus();
    });
  }

  List<TextSpanMark> _spansBefore(List<Map<String, dynamic>> spans, int splitAt) {
    return [
      for (final s in spans)
        if ((s['start'] as int? ?? 0) < splitAt)
          TextSpanMark.fromJson({
            ...s,
            'end': ((s['end'] as int? ?? 0).clamp(0, splitAt)),
          }),
    ];
  }

  List<TextSpanMark> _spansAfter(List<Map<String, dynamic>> spans, int splitAt) {
    return [
      for (final s in spans)
        if ((s['end'] as int? ?? 0) > splitAt)
          TextSpanMark.fromJson({
            ...s,
            'start': ((s['start'] as int? ?? 0) - splitAt).clamp(0, 999999),
            'end': ((s['end'] as int? ?? 0) - splitAt).clamp(0, 999999),
          }),
    ];
  }

  Future<void> _mergeOrDeleteParagraph(ParagraphNode block, int index) async {
    if (index == 0) return;
    _recordHistory(force: true);
    final prev = _doc.blocks[index - 1];
    if (prev is! ParagraphNode) return;

    final controller = _controllerFor(block.id, block.text, block.spans);
    final mergeAt = prev.text.length;
    final mergedText = prev.text + controller.text;
    final mergedSpanMarks = <TextSpanMark>[
      ...prev.spans,
      for (final s in controller.spans)
        TextSpanMark.fromJson({
          ...Map<String, dynamic>.from(s),
          'start': (s['start'] as int) + mergeAt,
          'end': (s['end'] as int) + mergeAt,
        }),
    ];

    final blocks = [..._doc.blocks];
    blocks[index - 1] = prev.copyWith(text: mergedText, spans: mergedSpanMarks);
    blocks.removeAt(index);
    _controllers.remove(block.id)?.dispose();
    _controllers.remove(prev.id)?.dispose();
    _applyDoc(_doc.copyWith(blocks: blocks), recordHistory: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusFor(prev.id).requestFocus();
      final c = _controllerFor(prev.id, mergedText, mergedSpanMarks);
      c.selection = TextSelection.collapsed(offset: mergeAt);
    });
  }

  void _exitListToParagraph(ListNode block, int index) {
    _recordHistory(force: true);
    final items = block.items;
    final text = items.map((i) => i.text).join('\n');
    final spans = <TextSpanMark>[];
    var offset = 0;
    for (var i = 0; i < items.length; i++) {
      if (i > 0) offset++;
      for (final s in items[i].spans) {
        spans.add(s.copyWith(start: s.start + offset, end: s.end + offset));
      }
      offset += items[i].text.length;
    }
    var blocks = [..._doc.blocks];
    blocks[index] = ParagraphNode(id: block.id, text: text, spans: spans);
    blocks.insert(
      index + 1,
      ParagraphNode(id: DocumentCodec.newId('b'), text: ''),
    );
    _applyDoc(_doc.copyWith(blocks: blocks), recordHistory: false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusFor(blocks[index + 1].id).requestFocus();
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
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _buildBlock(_doc.blocks[index], index),
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
        controller: controller,
        focusNode: _focusFor(block.id),
        style: AppTypography.noteBodyStyle,
        maxLines: null,
        minLines: 1,
        onChanged: (_) => _updateParagraph(block, index, controller),
        onEnter: () => _splitParagraph(block, index, controller),
        onBackspaceAtStart: () => _mergeOrDeleteParagraph(block, index),
        onSecondaryTapDown: _showTextMenu,
      );
    }
    if (block is HeadingNode) {
      final controller = _controllerFor(block.id, block.text, block.spans);
      return FormattedTextField(
        controller: controller,
        focusNode: _focusFor(block.id),
        style: AppTypography.noteTitleStyle.copyWith(
          fontSize: 24 - (block.level * 2),
        ),
        maxLines: null,
        onChanged: (text) {
          _focusedBlockIndex = index;
          _applyDoc(
            DocumentCodec.replaceBlock(
              _doc,
              block.id,
              block.copyWith(
                text: text,
                spans: [
                  for (final s in controller.spans)
                    TextSpanMark.fromJson(Map<String, dynamic>.from(s)),
                ],
              ),
            ),
          );
        },
        onSecondaryTapDown: _showTextMenu,
      );
    }
    if (block is ListNode) {
      return RichListEditor(
        node: block,
        strings: _strings,
        onFocus: () => _focusedBlockIndex = index,
        onChanged: (updated) {
          _focusedBlockIndex = index;
          _applyDoc(DocumentCodec.replaceBlock(_doc, block.id, updated));
        },
        onExitList: () => _exitListToParagraph(block, index),
      );
    }
    if (block is TableNode) {
      return RichTableEditor(
        node: block,
        strings: _strings,
        onFocus: () => _focusedBlockIndex = index,
        onChanged: (updated) {
          _focusedBlockIndex = index;
          _applyDoc(DocumentCodec.replaceBlock(_doc, block.id, updated));
        },
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
