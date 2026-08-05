import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../../config/api_config.dart';
import '../../../../core/app_state.dart';
import '../../../objects/data/object_embed.dart';
import '../../../objects/links/add_connection_dialog.dart';
import '../../../objects/tags/assign_object_tags_dialog.dart';
import '../../../ux/topic/topic_appearance.dart';
import '../document_text_flow.dart';
import '../../rich_text/block_text_actions.dart';
import '../../rich_text/document_context_menu.dart';
import '../../rich_text/formatted_text_field.dart';
import '../../rich_text/span_text_editing_controller.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/app_typography.dart';

/// Info object — gentle frame, title + body as two document-flow lines.
///
/// Arrows / Enter / Backspace move between title and body the way they move
/// between lines of a paragraph; empty final body line + Enter exits below.
class InfoEmbed extends StatefulWidget {
  const InfoEmbed({
    super.key,
    required this.embed,
    required this.blockId,
    required this.state,
    required this.onRefresh,
    this.onFocus,
    this.onExitBelow,
  });

  final ObjectEmbed embed;
  final String blockId;
  final AppState state;
  final VoidCallback onRefresh;
  final VoidCallback? onFocus;
  final VoidCallback? onExitBelow;

  @override
  State<InfoEmbed> createState() => _InfoEmbedState();
}

class _InfoEmbedState extends State<InfoEmbed> {
  late SpanTextEditingController _titleController;
  late SpanTextEditingController _bodyController;
  late final FocusNode _titleFocus;
  late final FocusNode _bodyFocus;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _titleFocus = FocusNode();
    _bodyFocus = FocusNode();
    final info = widget.embed.information ?? const {};
    _titleController = SpanTextEditingController(
      text: info['title'] as String? ?? '',
    );
    final meta = info['metadata'];
    final spans = meta is Map ? meta['spans'] : null;
    _bodyController = SpanTextEditingController(
      text: info['body'] as String? ?? '',
      spans: spans is List
          ? [for (final s in spans) if (s is Map) Map<String, dynamic>.from(s)]
          : const [],
    );
  }

  @override
  void didUpdateWidget(InfoEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.embed.id != widget.embed.id) {
      final info = widget.embed.information ?? const {};
      _titleController.text = info['title'] as String? ?? '';
      _bodyController.text = info['body'] as String? ?? '';
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Best-effort flush — ignore if the object was already deleted.
    unawaited(_save(flush: true).catchError((_) {}));
    _titleFocus.dispose();
    _bodyFocus.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    widget.onFocus?.call();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_save());
    });
  }

  Future<void> _save({bool flush = false}) async {
    _saveTimer?.cancel();
    try {
      await widget.state.updateInfoObject(
        widget.embed,
        title: _titleController.text,
        body: _bodyController.text,
        spans: _bodyController.spans,
      );
    } catch (_) {
      // Object may have been removed while a debounce was pending.
    }
    if (flush) return;
  }

  void _focusBody({int offset = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bodyFocus.requestFocus();
      final len = _bodyController.text.length;
      _bodyController.selection =
          TextSelection.collapsed(offset: offset.clamp(0, len));
    });
  }

  void _focusTitle({int? offset}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _titleFocus.requestFocus();
      final len = _titleController.text.length;
      _titleController.selection = TextSelection.collapsed(
        offset: (offset ?? len).clamp(0, len),
      );
    });
  }

  /// Enter in the title drops into the body — next line.
  void _onTitleEnter() {
    widget.onFocus?.call();
    unawaited(_save());
    _focusBody();
  }

  /// Backspace at the start of the body climbs into the title — previous line.
  Future<void> _onBodyBackspaceAtStart() async {
    widget.onFocus?.call();
    _focusTitle();
  }

  /// Enter adds a line; Enter on an empty final line exits to text below.
  void _onBodyEnter() {
    widget.onFocus?.call();
    final text = _bodyController.text;
    final sel = _bodyController.selection;
    final offset =
        sel.isValid ? sel.baseOffset.clamp(0, text.length) : text.length;

    final lastBreak = text.lastIndexOf('\n');
    final lastLineStart = lastBreak + 1;
    final lastLine = text.substring(lastLineStart);
    final onLastLine = offset >= lastLineStart;

    if (onLastLine && lastLine.trim().isEmpty && text.contains('\n')) {
      final trimmed =
          text.substring(0, lastLineStart).replaceFirst(RegExp(r'\n$'), '');
      _bodyController.value = TextEditingValue(
        text: trimmed,
        selection: TextSelection.collapsed(offset: trimmed.length),
      );
      unawaited(_save());
      _titleFocus.unfocus();
      _bodyFocus.unfocus();
      widget.onExitBelow?.call();
      return;
    }

    if (text.trim().isEmpty) {
      _titleFocus.unfocus();
      _bodyFocus.unfocus();
      widget.onExitBelow?.call();
      return;
    }

    final next = text.replaceRange(offset, offset, '\n');
    _bodyController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset + 1),
    );
    _scheduleSave();
  }

  Future<void> _showTextMenu(TapDownDetails details) async {
    await DocumentContextMenu.showInfoMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.state.strings,
      onAction: (action) async {
        if (action == 'info:add_tag') {
          await _assignTags();
          return;
        }
        if (action == 'info:add_connection') {
          await _addConnection();
          return;
        }
        await runBlockTextAction(action);
      },
    );
  }

  Future<void> _addConnection() async {
    final pick = await showAddConnectionDialog(
      context: context,
      state: widget.state,
      source: widget.embed,
    );
    if (pick == null) return;
    await widget.state.addRelatedObjectLink(
      widget.embed,
      targetObjectId: pick.objectId,
    );
    widget.onRefresh();
  }

  Future<void> _assignTags() async {
    await showAssignObjectTagsDialog(
      context: context,
      state: widget.state,
      embed: widget.embed,
    );
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final tags = widget.embed.tags;
    return DecoratedBox(
      decoration: AppColors.detailsBlockDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormattedTextField(
              controller: _titleController,
              focusNode: _titleFocus,
              segmentId: infoTitleSegmentId(widget.blockId),
              style: AppTypography.noteTitleStyle,
              hintText: s['detailsTitleHint'],
              maxLines: 1,
              minLines: 1,
              onChanged: (_) => _scheduleSave(),
              onEnter: _onTitleEnter,
              onSecondaryTapDown: _showTextMenu,
            ),
            const SizedBox(height: 4),
            FormattedTextField(
              controller: _bodyController,
              focusNode: _bodyFocus,
              segmentId: infoBodySegmentId(widget.blockId),
              style: AppTypography.noteBodyStyle,
              maxLines: null,
              minLines: 1,
              onChanged: (_) => _scheduleSave(),
              onEnter: _onBodyEnter,
              onBackspaceAtStart: _onBodyBackspaceAtStart,
              onSecondaryTapDown: _showTextMenu,
            ),
            if (tags.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final tag in tags)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: TopicAppearance.colorFromHex(
                          tag.color ?? TopicAppearance.defaultColor,
                        ).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${tag.icon?.isNotEmpty == true ? '${tag.icon} ' : ''}${tag.name}',
                        style: AppTypography.metaStyle.copyWith(fontSize: 11),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class ImageEmbed extends StatefulWidget {
  const ImageEmbed({
    super.key,
    required this.embed,
    required this.state,
    required this.onPayloadChanged,
  });

  final ObjectEmbed embed;
  final AppState state;
  final ValueChanged<Map<String, dynamic>> onPayloadChanged;

  @override
  State<ImageEmbed> createState() => _ImageEmbedState();
}

class _ImageEmbedState extends State<ImageEmbed> {
  late TextEditingController _captionController;
  var _uploading = false;

  Map<String, dynamic> get _payload => widget.embed.payload ?? const {};

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(
      text: _payload['caption'] as String? ?? '',
    );
  }

  @override
  void didUpdateWidget(ImageEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.embed.payload?['caption'] as String? ?? '';
    if (next != _captionController.text) {
      _captionController.text = next;
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    final file = result?.files.firstOrNull;
    if (file?.bytes == null) return;
    setState(() => _uploading = true);
    try {
      final uploaded = await widget.state.uploadImageBytes(
        file!.name,
        file.bytes!,
      );
      final url = uploaded['url'] as String? ?? '';
      widget.onPayloadChanged({
        ..._payload,
        'url': url,
        'caption': _captionController.text,
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = _payload['url'] as String? ?? '';
    final resolved = url.isEmpty
        ? null
        : (url.startsWith('http') ? url : '${ApiConfig.baseUrl}$url');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (resolved != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.network(
              resolved,
              fit: BoxFit.contain,
              errorBuilder: (_, error, stackTrace) => Text(
                'Image unavailable',
                style: AppTypography.metaStyle,
              ),
            ),
          )
        else
          OutlinedButton.icon(
            onPressed: _uploading ? null : _pick,
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(_uploading ? 'Uploading…' : 'Add image'),
          ),
        const SizedBox(height: 4),
        TextField(
          controller: _captionController,
          style: AppTypography.metaStyle,
          decoration: const InputDecoration(
            hintText: 'Caption',
            isDense: true,
            border: InputBorder.none,
          ),
          onSubmitted: (value) => widget.onPayloadChanged({
            ..._payload,
            'caption': value,
          }),
          onEditingComplete: () => widget.onPayloadChanged({
            ..._payload,
            'caption': _captionController.text,
          }),
        ),
      ],
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
