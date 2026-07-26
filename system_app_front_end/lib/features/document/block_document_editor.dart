import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/object_embed.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import 'blocks/list_block_widget.dart';
import 'blocks/table_block_widget.dart';
import 'document_codec.dart';
import 'document_editor_controller.dart';
import 'document_model.dart';
import 'document_undo_stack.dart';
import 'embeds/inline_task_list.dart';
import 'embeds/object_embed_widgets.dart';
import 'rich_text/formatted_text_field.dart';
import 'rich_text/span_text_editing_controller.dart';

class BlockDocumentEditor extends StatefulWidget {
  const BlockDocumentEditor({
    super.key,
    required this.file,
    required this.state,
    required this.embeds,
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
  String? _selectedEmbedBlockId;
  Timer? _saveTimer;
  final _undoStack = DocumentUndoStack();
  final _focusNodes = <String, FocusNode>{};
  final _controllers = <String, SpanTextEditingController>{};

  AppFile get _currentFile =>
      widget.state.selectedDetail?.files.where((f) => f.id == widget.file.id).firstOrNull ??
      widget.file;

  ObjectEmbed? _embedFor(int objectId) {
    for (final e in widget.embeds) {
      if (e.id == objectId) return e;
    }
    return null;
  }

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
      _selectedEmbedBlockId = null;
    } else if (!_dirty && oldWidget.file.documentJson != widget.file.documentJson) {
      _doc = DocumentCodec.parse(_currentFile.documentJson);
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
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _flushPendingChanges() async {
    _saveTimer?.cancel();
    if (!_dirty) return;
    _dirty = false;
    await widget.state.updateFile(_currentFile, {
      'document_json': DocumentCodec.serialize(_doc),
    });
  }

  void _scheduleSave() {
    _dirty = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 150), () {
      if (mounted) unawaited(_flushPendingChanges());
    });
  }

  void _applyDoc(RichDocument doc, {bool save = true}) {
    setState(() => _doc = doc);
    if (save) _scheduleSave();
  }

  void _pushUndo() => _undoStack.push(_doc);

  void _undo() {
    final previous = _undoStack.pop();
    if (previous != null) _applyDoc(previous);
  }

  SpanTextEditingController _controllerFor(ParagraphNode node) {
    return _controllers.putIfAbsent(
      node.id,
      () => SpanTextEditingController(
        text: node.text,
        spans: node.spans.map((s) => s.toJson()).toList(),
      ),
    );
  }

  FocusNode _focusFor(String blockId) =>
      _focusNodes.putIfAbsent(blockId, FocusNode.new);

  Future<void> _insertAtBlock(String action) async {
    await _flushPendingChanges();
    final index = (_focusedBlockIndex + 1).clamp(0, _doc.blocks.length);
    switch (action) {
      case 'paragraph':
        _applyDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            ParagraphNode(id: DocumentCodec.newId('b'), text: ''),
          ),
        );
      case 'heading':
        _applyDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            HeadingNode(id: DocumentCodec.newId('b'), level: 2, text: ''),
          ),
        );
      case 'list':
        _applyDoc(
          DocumentCodec.insertBlock(
            _doc,
            index,
            ListNode(
              id: DocumentCodec.newId('b'),
              items: [ListItem(id: DocumentCodec.newId('li'), text: '')],
            ),
          ),
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
        );
      case 'task_list':
      case 'info':
        final embed = await widget.state.createObjectInDocument(
          _currentFile,
          type: action,
          blockIndex: index,
        );
        final updated = await widget.state.reloadFile(_currentFile.id);
        _doc = DocumentCodec.parse(updated.documentJson);
        setState(() {});
        if (embed.taskListId != null && action == 'task_list') {
          await widget.state.createTaskInList(embed.taskListId!, title: 'New task');
        }
      case 'image':
      case 'graph':
        await widget.state.createObjectInDocument(
          _currentFile,
          type: action,
          blockIndex: index,
          payload: action == 'graph'
              ? {
                  'labels': ['A', 'B'],
                  'values': [1, 2],
                }
              : {'url': ''},
        );
        final updated = await widget.state.reloadFile(_currentFile.id);
        _doc = DocumentCodec.parse(updated.documentJson);
        setState(() {});
    }
  }

  Future<void> _moveEmbedBlock(String blockId, int newIndex) async {
    _pushUndo();
    _applyDoc(DocumentCodec.moveEmbedBlock(_doc, blockId, newIndex));
  }

  Future<void> _convertSelectionToInfo(
    ParagraphNode block,
    SpanTextEditingController controller,
    TextSelection selection,
  ) async {
    if (!selection.isValid || selection.isCollapsed) return;
    final slice = controller.text.substring(selection.start, selection.end);
    final sliceSpans = _spansForRange(controller.spans, selection.start, selection.end);
    _pushUndo();
    final newText = controller.text.replaceRange(selection.start, selection.end, '');
    final updatedBlock = block.copyWith(text: newText);
    _applyDoc(DocumentCodec.replaceBlock(_doc, block.id, updatedBlock), save: true);
    await _flushPendingChanges();
    final blockIndex = _doc.blocks.indexWhere((b) => b.id == block.id);
    await widget.state.createObjectInDocument(
      _currentFile,
      type: 'info',
      title: slice.split('\n').first.trim().isEmpty ? 'Info' : slice.split('\n').first.trim(),
      body: slice,
      metadata: {'spans': sliceSpans},
      blockIndex: blockIndex + 1,
    );
    final updated = await widget.state.reloadFile(_currentFile.id);
    _doc = DocumentCodec.parse(updated.documentJson);
    setState(() {});
  }

  List<Map<String, dynamic>> _spansForRange(
    List<Map<String, dynamic>> spans,
    int start,
    int end,
  ) {
    return [
      for (final span in spans)
        if ((span['end'] as int? ?? 0) > start && (span['start'] as int? ?? 0) < end)
          {
            ...span,
            'start': ((span['start'] as int? ?? 0) - start).clamp(0, end - start),
            'end': ((span['end'] as int? ?? 0) - start).clamp(0, end - start),
          },
    ];
  }

  Future<void> _convertListToTaskList(ListNode block) async {
    _pushUndo();
    final blockIndex = _doc.blocks.indexWhere((b) => b.id == block.id);
    _applyDoc(DocumentCodec.removeBlock(_doc, block.id));
    await _flushPendingChanges();
    final embed = await widget.state.createObjectInDocument(
      _currentFile,
      type: 'task_list',
      blockIndex: blockIndex,
    );
    if (embed.taskListId != null) {
      for (final item in block.items) {
        if (item.text.trim().isNotEmpty) {
          await widget.state.createTaskInList(embed.taskListId!, title: item.text.trim());
        }
      }
    }
    final updated = await widget.state.reloadFile(_currentFile.id);
    _doc = DocumentCodec.parse(updated.documentJson);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ):
            const _UndoIntent(),
      },
      child: Actions(
        actions: {
          _UndoIntent: CallbackAction<_UndoIntent>(onInvoke: (_) {
            _undo();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _doc.blocks.length,
            itemBuilder: (context, index) {
              final block = _doc.blocks[index];
              return _BlockShell(
                index: index,
                selected: block.id == _selectedEmbedBlockId,
                onSelectEmbed: block is EmbedNode
                    ? () => setState(() => _selectedEmbedBlockId = block.id)
                    : null,
                onMoveUp: block is EmbedNode && index > 0
                    ? () => _moveEmbedBlock(block.id, index - 1)
                    : null,
                onMoveDown: block is EmbedNode && index < _doc.blocks.length - 1
                    ? () => _moveEmbedBlock(block.id, index + 1)
                    : null,
                child: _buildBlock(block, index),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBlock(DocumentNode block, int index) {
    if (block is ParagraphNode) {
      final controller = _controllerFor(block);
      return FormattedTextField(
        controller: controller,
        focusNode: _focusFor(block.id),
        style: AppTypography.noteBodyStyle,
        maxLines: null,
        onChanged: (text) {
          _focusedBlockIndex = index;
          _applyDoc(
            DocumentCodec.replaceBlock(_doc, block.id, block.copyWith(text: text, spans: [
              for (final s in controller.spans)
                TextSpanMark.fromJson(Map<String, dynamic>.from(s)),
            ])),
          );
        },
        onSecondaryTapDown: (details) async {
          final selection = controller.selection;
          if (!selection.isValid || selection.isCollapsed) return;
          final result = await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx,
              details.globalPosition.dy,
            ),
            items: const [
              PopupMenuItem(value: 'info', child: Text('Convert to Info section')),
            ],
          );
          if (result == 'info') {
            await _convertSelectionToInfo(block, controller, selection);
          }
        },
      );
    }
    if (block is HeadingNode) {
      final controller = _controllerFor(
        ParagraphNode(id: block.id, text: block.text, spans: block.spans),
      );
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
              block.copyWith(text: text),
            ),
          );
        },
      );
    }
    if (block is ListNode) {
      return ListBlockWidget(
        node: block,
        onChanged: (updated) {
          _focusedBlockIndex = index;
          _applyDoc(DocumentCodec.replaceBlock(_doc, block.id, updated));
        },
        onConvertToTaskList: () => _convertListToTaskList(block),
      );
    }
    if (block is TableNode) {
      return DocumentTableBlockWidget(
        node: block,
        onChanged: (updated) {
          _focusedBlockIndex = index;
          _applyDoc(DocumentCodec.replaceBlock(_doc, block.id, updated));
        },
      );
    }
    if (block is EmbedNode) {
      final embed = _embedFor(block.objectId);
      if (embed == null) {
        return Text('[missing object ${block.objectId}]', style: AppTypography.metaStyle);
      }
      return switch (embed.type) {
        'task_list' => InlineTaskListWidget(
          embed: embed,
          file: _currentFile,
          state: widget.state,
          onRefresh: () async {
            await widget.state.loadEmbedsForFile(_currentFile.id);
            setState(() {});
          },
        ),
        'info' => InfoEmbed(
          embed: embed,
          state: widget.state,
          onRefresh: () async {
            await widget.state.loadEmbedsForFile(_currentFile.id);
            setState(() {});
          },
        ),
        'image' => ImageEmbed(
          embed: embed,
          onPayloadChanged: (payload) async {
            await widget.state.updateObjectPayload(embed.id, payload);
            await widget.state.loadEmbedsForFile(_currentFile.id);
            setState(() {});
          },
        ),
        'graph' => GraphEmbed(embed: embed),
        _ => Text('[${embed.type}]', style: AppTypography.metaStyle),
      };
    }
    return const SizedBox.shrink();
  }
}

class _BlockShell extends StatelessWidget {
  const _BlockShell({
    required this.index,
    required this.child,
    this.selected = false,
    this.onSelectEmbed,
    this.onMoveUp,
    this.onMoveDown,
  });

  final int index;
  final Widget child;
  final bool selected;
  final VoidCallback? onSelectEmbed;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: onSelectEmbed,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selected && onSelectEmbed != null)
            Column(
              children: [
                IconButton(
                  icon: const AppIcon(AppIcons.drag, size: 18),
                  tooltip: 'Move up',
                  onPressed: onMoveUp,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward, size: 18),
                  tooltip: 'Move down',
                  onPressed: onMoveDown,
                ),
              ],
            ),
          Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: child)),
        ],
      ),
    );
  }
}

class _UndoIntent extends Intent {
  const _UndoIntent();
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
