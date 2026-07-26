import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/object_embed.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import 'document_codec.dart';
import 'document_editor_controller.dart';
import 'inline_document_model.dart';
import 'objects/inline_embed_widgets.dart';
import 'objects/inline_task_list.dart';
import 'rich_text/block_text_actions.dart';
import 'rich_text/document_context_menu.dart';
import 'rich_text/document_selection_menu.dart';
import 'rich_text/formatted_text_field.dart';
import 'rich_text/region_overlay.dart';
import 'rich_text/rich_text_block_sync.dart';
import 'rich_text/span_text_editing_controller.dart';

class InlineDocumentEditor extends StatefulWidget {
  const InlineDocumentEditor({
    super.key,
    required this.file,
    required this.state,
    required this.embeds,
  });

  final AppFile file;
  final AppState state;
  final List<ObjectEmbed> embeds;

  @override
  State<InlineDocumentEditor> createState() => _InlineDocumentEditorState();
}

class _InlineDocumentEditorState extends State<InlineDocumentEditor> {
  late InlineDocument _doc;
  final _textControllers = <String, SpanTextEditingController>{};
  final _focusNodes = <String, FocusNode>{};
  var _dirty = false;
  var _saveScheduled = false;
  String? _movingEmbedId;
  int? _moveDropOffset;

  @override
  void initState() {
    super.initState();
    _doc = DocumentCodec.parse(widget.file.body);
    _syncControllers();
    _registerEditor();
  }

  @override
  void didUpdateWidget(InlineDocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id ||
        (!_dirty && oldWidget.file.body != widget.file.body)) {
      _doc = DocumentCodec.parse(widget.file.body);
      _syncControllers();
      _dirty = false;
    }
  }

  @override
  void dispose() {
    DocumentEditorRegistry.unregister(widget.file.id);
    widget.state.setEditingFileId(null);
    for (final c in _textControllers.values) {
      c.dispose();
    }
    for (final f in _focusNodes.values) {
      f.dispose();
    }
    super.dispose();
  }

  void _registerEditor() {
    DocumentEditorRegistry.register(
      DocumentEditorController(
        fileId: widget.file.id,
        insertAtCaret: _handleInsertAction,
        focusCaret: _focusPrimaryField,
      ),
    );
    widget.state.setEditingFileId(widget.file.id);
  }

  void _focusPrimaryField() {
    for (final node in _focusNodes.values) {
      node.requestFocus();
      return;
    }
  }

  String _segmentKey(InlineTextSegment segment) => '${segment.start}:${segment.end}';

  void _syncControllers() {
    final segments = splitInlineSegments(_doc);
    final liveKeys = <String>{};
    for (final segment in segments) {
      if (segment is! InlineTextSegment) continue;
      final key = _segmentKey(segment);
      liveKeys.add(key);
      final text = segment.textSlice(_doc);
      final spans = segment.spans.map((s) => s.toJson()).toList();
      final existing = _textControllers[key];
      if (existing == null) {
        _textControllers[key] = SpanTextEditingController(text: text, spans: spans);
        _focusNodes[key] = FocusNode();
      } else {
        syncRichControllerFromBlockIfIdle(
          controller: existing,
          focusNode: _focusNodes[key]!,
          blockContent: {'text': text, 'spans': spans},
        );
      }
    }
    for (final key in _textControllers.keys.toList()) {
      if (!liveKeys.contains(key)) {
        _textControllers.remove(key)?.dispose();
        _focusNodes.remove(key)?.dispose();
      }
    }
  }

  ObjectEmbed? _embedForObjectId(int? objectId) {
    if (objectId == null) return null;
    for (final embed in widget.embeds) {
      if (embed.id == objectId) return embed;
    }
    return null;
  }

  AppFile get _currentFile {
    return widget.state.selectedDetail?.files
            .where((f) => f.id == widget.file.id)
            .firstOrNull ??
        widget.file;
  }

  void _reloadFromServerBody() {
    setState(() {
      _doc = DocumentCodec.parse(_currentFile.body);
      _dirty = false;
    });
    _syncControllers();
  }

  void _commitFromControllers() {
    final segments = splitInlineSegments(_doc);
    final buffer = StringBuffer();
    final spans = <TextSpanMark>[];
    final embeds = [..._doc.embeds]..sort((a, b) => a.offset.compareTo(b.offset));
    var cursor = 0;
    var embedIdx = 0;

    for (final segment in segments) {
      if (segment is InlineTextSegment) {
        final key = _segmentKey(segment);
        final controller = _textControllers[key];
        final slice = controller?.text ?? segment.textSlice(_doc);
        final segmentSpans = controller == null
            ? segment.spans
            : [
                for (final s in controller.spans)
                  TextSpanMark.fromJson(Map<String, dynamic>.from(s)),
              ];
        for (final span in segmentSpans) {
          spans.add(span.shift(cursor));
        }
        buffer.write(slice);
        cursor += slice.length;
      } else if (segment is InlineEmbedSegment) {
        if (embedIdx < embeds.length) {
          embeds[embedIdx] = embeds[embedIdx].copyWith(offset: cursor);
          embedIdx++;
        }
        buffer.write(InlineDocument.embedChar);
        cursor += 1;
      }
    }

    setState(() {
      _doc = _doc.copyWith(
        text: buffer.toString(),
        spans: spans,
        embeds: embeds,
      );
      _dirty = true;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    if (_saveScheduled) return;
    _saveScheduled = true;
    Future<void>.delayed(const Duration(milliseconds: 400), () async {
      _saveScheduled = false;
      await _saveBody();
    });
  }

  Future<void> _saveBody() async {
    if (!_dirty) return;
    await widget.state.updateFile(
      _currentFile,
      {'body': DocumentCodec.serialize(_doc)},
    );
    _dirty = false;
  }

  _FocusedSegment? _focusedSegment() {
    for (final entry in _focusNodes.entries) {
      if (!entry.value.hasFocus) continue;
      final parts = entry.key.split(':');
      final start = int.tryParse(parts.first) ?? 0;
      final controller = _textControllers[entry.key];
      if (controller == null) continue;
      return _FocusedSegment(
        start: start,
        controller: controller,
      );
    }
    return null;
  }

  int get _caretOffset {
    final focused = _focusedSegment();
    if (focused == null) return _doc.text.length;
    return focused.start +
        focused.controller.selection.baseOffset
            .clamp(0, focused.controller.text.length);
  }

  Future<void> _handleInsertAction(String action) async {
    _commitFromControllers();
    final offset = _caretOffset;
    switch (action) {
      case 'paragraph':
        setState(() {
          _doc = DocumentCodec.replaceTextRange(
            _doc,
            offset,
            offset,
            '\n',
          );
          _dirty = true;
        });
      case 'list':
        setState(() {
          _doc = DocumentCodec.insertRegion(
            _doc,
            DocumentRegion(
              id: DocumentCodec.newId('r'),
              kind: 'list',
              start: offset,
              end: offset,
              listStyle: 'bullet',
            ),
            offset: offset,
          );
          _dirty = true;
        });
      case 'table':
        setState(() {
          _doc = DocumentCodec.insertRegion(
            _doc,
            DocumentRegion(
              id: DocumentCodec.newId('r'),
              kind: 'table',
              start: offset,
              end: offset,
            ),
            offset: offset,
          );
          _dirty = true;
        });
      case 'image':
        setState(() {
          _doc = DocumentCodec.insertEmbed(
            _doc,
            DocumentEmbed(
              id: DocumentCodec.newId('e'),
              kind: 'image',
              offset: offset,
              url: '',
            ),
            offset: offset,
          );
          _dirty = true;
        });
      case 'graph':
        setState(() {
          _doc = DocumentCodec.insertEmbed(
            _doc,
            DocumentEmbed(
              id: DocumentCodec.newId('e'),
              kind: 'graph',
              offset: offset,
              labels: const ['A'],
              values: const [1],
            ),
            offset: offset,
          );
          _dirty = true;
        });
      case 'task_list':
      case 'info':
        await widget.state.createObjectInDocument(
          _currentFile,
          type: action == 'task_list' ? 'task_list' : 'info',
          offset: offset,
        );
        await widget.state.loadEmbedsForFile(widget.file.id);
        _reloadFromServerBody();
        return;
    }
    _syncControllers();
    _scheduleSave();
  }

  Future<void> _refreshEmbeds() async {
    await widget.state.loadEmbedsForFile(widget.file.id);
    if (mounted) setState(() {});
  }

  void _startMoveEmbed(String embedId) {
    final embed = _doc.embeds.firstWhere((e) => e.id == embedId);
    setState(() {
      _movingEmbedId = embedId;
      _moveDropOffset = embed.offset;
    });
  }

  void _cancelMoveEmbed() {
    setState(() {
      _movingEmbedId = null;
      _moveDropOffset = null;
    });
  }

  void _confirmMoveEmbed() {
    if (_movingEmbedId == null || _moveDropOffset == null) return;
    setState(() {
      _doc = DocumentCodec.moveEmbed(_doc, _movingEmbedId!, _moveDropOffset!);
      _movingEmbedId = null;
      _moveDropOffset = null;
      _dirty = true;
    });
    _syncControllers();
    _scheduleSave();
  }

  Future<void> _onTextMenuAction(String action) async {
    await runBlockTextAction(action);
    _commitFromControllers();
    setState(() {});
  }

  Future<void> _onSelectionMenuAction(String action) async {
    _commitFromControllers();
    final focused = _focusedSegment();
    if (focused == null) return;
    final selection = focused.controller.selection;
    if (!selection.isValid || selection.start == selection.end) return;
    final globalStart = focused.start + selection.start;
    final globalEnd = focused.start + selection.end;

    if (action == 'convert:task_list') {
      await widget.state.convertSelectionToTaskList(
        _currentFile,
        document: _doc,
        start: globalStart,
        end: globalEnd,
        onDocumentChanged: (doc) {
          setState(() {
            _doc = doc;
            _dirty = true;
          });
          _syncControllers();
          _scheduleSave();
        },
      );
      await _refreshEmbeds();
    } else if (action == 'convert:info') {
      await widget.state.convertSelectionToInfo(
        _currentFile,
        document: _doc,
        start: globalStart,
        end: globalEnd,
        onDocumentChanged: (doc) {
          setState(() {
            _doc = doc;
            _dirty = true;
          });
          _syncControllers();
          _scheduleSave();
        },
      );
      await _refreshEmbeds();
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = splitInlineSegments(_doc);
    return Shortcuts(
      shortcuts: {
        if (_movingEmbedId != null)
          const SingleActivator(LogicalKeyboardKey.escape): const ActivateIntent(),
      },
      child: Actions(
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _cancelMoveEmbed();
              return null;
            },
          ),
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_movingEmbedId != null)
              _MoveModeBar(
                onCancel: _cancelMoveEmbed,
                onConfirm: _confirmMoveEmbed,
                dropOffset: _moveDropOffset ?? 0,
                maxOffset: _doc.text.length,
                onOffsetChanged: (v) => setState(() => _moveDropOffset = v),
              ),
            RegionOverlayHost(
              document: _doc,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final segment in segments) ...[
                    if (segment is InlineTextSegment)
                      _buildTextSegment(segment)
                    else if (segment is InlineEmbedSegment)
                      _buildEmbedSegment(segment),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextSegment(InlineTextSegment segment) {
    final key = _segmentKey(segment);
    final controller = _textControllers[key]!;
    final focusNode = _focusNodes[key]!;
    final overlappingRegions = _doc.regions
        .where((r) => r.start < segment.end && r.end > segment.start)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final region in overlappingRegions)
          RegionStyleHint(region: region, text: segment.textSlice(_doc)),
        FormattedTextField(
          controller: controller,
          focusNode: focusNode,
          style: AppTypography.noteBodyStyle,
          maxLines: null,
          onChanged: (_) => _commitFromControllers(),
          onSecondaryTapDown: (details) async {
            final selection = controller.selection;
            final entries = DocumentSelectionMenu.buildEntries(
              strings: widget.state.strings,
              document: _doc,
              selectionStart: segment.start + selection.start,
              selectionEnd: segment.start + selection.end,
            );
            if (entries.isEmpty) {
              await DocumentContextMenu.showTextMenu(
                context: context,
                globalPosition: details.globalPosition,
                strings: widget.state.strings,
                onAction: _onTextMenuAction,
              );
              return;
            }
            await DocumentSelectionMenu.show(
              context: context,
              globalPosition: details.globalPosition,
              strings: widget.state.strings,
              extraEntries: entries,
              onTextAction: _onTextMenuAction,
              onSelectionAction: _onSelectionMenuAction,
            );
          },
        ),
      ],
    );
  }

  Widget _buildEmbedSegment(InlineEmbedSegment segment) {
    final embed = segment.embed;
    final moving = _movingEmbedId == embed.id;
    Widget child;
    switch (embed.kind) {
      case 'object':
        final objectEmbed = _embedForObjectId(embed.objectId);
        if (embed.objectType == 'task_list' && objectEmbed != null) {
          child = InlineTaskListWidget(
            embed: objectEmbed,
            file: _currentFile,
            state: widget.state,
            onRefresh: _refreshEmbeds,
          );
        } else if (embed.objectType == 'info' && objectEmbed != null) {
          child = InlineInfoWidget(
            embed: objectEmbed,
            state: widget.state,
            onRefresh: _refreshEmbeds,
          );
        } else {
          child = Text(
            '[${embed.objectType} #${embed.objectId}]',
            style: AppTypography.metaStyle,
          );
        }
      case 'image':
        child = InlineImageWidget(
          embed: embed,
          onUrlChanged: (url) {
            setState(() {
              _doc = _doc.copyWith(
                embeds: [
                  for (final e in _doc.embeds)
                    e.id == embed.id ? e.copyWith(url: url) : e,
                ],
              );
              _dirty = true;
            });
            _scheduleSave();
          },
        );
      case 'graph':
        child = InlineGraphWidget(embed: embed);
      default:
        child = const SizedBox.shrink();
    }

    return GestureDetector(
      onDoubleTap: () => _startMoveEmbed(embed.id),
      child: Container(
        decoration: moving
            ? BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              )
            : null,
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: child,
      ),
    );
  }
}

class _FocusedSegment {
  const _FocusedSegment({required this.start, required this.controller});

  final int start;
  final SpanTextEditingController controller;
}

class _MoveModeBar extends StatelessWidget {
  const _MoveModeBar({
    required this.onCancel,
    required this.onConfirm,
    required this.dropOffset,
    required this.maxOffset,
    required this.onOffsetChanged,
  });

  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final int dropOffset;
  final int maxOffset;
  final ValueChanged<int> onOffsetChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: [
            const Expanded(
              child: Text('Move embed — set position in text, then Place'),
            ),
            SizedBox(
              width: 160,
              child: Slider(
                value: dropOffset.clamp(0, maxOffset).toDouble(),
                min: 0,
                max: maxOffset.toDouble(),
                onChanged: (v) => onOffsetChanged(v.round()),
              ),
            ),
            TextButton(onPressed: onCancel, child: const Text('Cancel')),
            FilledButton(onPressed: onConfirm, child: const Text('Place')),
          ],
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
