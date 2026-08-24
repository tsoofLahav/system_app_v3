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
import '../editor_key_handoff.dart';
import '../embed_caret_bridge.dart';
import '../../rich_text/block_text_actions.dart';
import '../../rich_text/block_text_focus.dart';
import '../../rich_text/document_context_menu.dart';
import '../../rich_text/formatted_text_field.dart';
import '../../rich_text/span_text_editing_controller.dart';
import '../../rich_text/text_formatting.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/app_typography.dart';

/// Compose API `title` + `body` into one editable string (first line = title).
String composeInfoText(String title, String body) {
  if (title.isEmpty && body.isEmpty) return '';
  if (body.isEmpty) return title;
  return '$title\n$body';
}

(String title, String body) splitInfoText(String text) {
  final nl = text.indexOf('\n');
  if (nl < 0) return (text, '');
  return (text.substring(0, nl), text.substring(nl + 1));
}

/// Body-relative spans → offsets in the combined title\\nbody string.
List<Map<String, dynamic>> infoSpansToCombined(
  List<Map<String, dynamic>> bodySpans,
  String combined,
) {
  final nl = combined.indexOf('\n');
  if (nl < 0) return const [];
  final offset = nl + 1;
  return [
    for (final s in bodySpans)
      {
        ...s,
        'start': (s['start'] as int) + offset,
        'end': (s['end'] as int) + offset,
      },
  ];
}

/// Combined-string spans → body-relative spans for the API.
List<Map<String, dynamic>> infoSpansToBody(
  List<Map<String, dynamic>> combinedSpans,
  String combined,
) {
  final nl = combined.indexOf('\n');
  if (nl < 0) return const [];
  final offset = nl + 1;
  final bodyLen = combined.length - offset;
  final out = <Map<String, dynamic>>[];
  for (final s in combinedSpans) {
    var start = s['start'] as int;
    var end = s['end'] as int;
    if (end <= offset) continue;
    if (start < offset) start = offset;
    start -= offset;
    end -= offset;
    if (start >= bodyLen) continue;
    if (end > bodyLen) end = bodyLen;
    if (start >= end) continue;
    out.add({...s, 'start': start, 'end': end});
  }
  return out;
}

/// Renders the first line as title weight/size; rest as body + user spans.
class _InfoTextController extends SpanTextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final titleStyle = AppTypography.noteTitleStyle;
    final bodyStyle = AppTypography.noteBodyStyle;
    final t = text;
    final nl = t.indexOf('\n');
    if (nl < 0) {
      return TextSpanBuilder.build(
        text: t,
        baseStyle: titleStyle,
        spans: spans,
      );
    }

    final titlePart = t.substring(0, nl);
    final bodyPart = t.substring(nl + 1);
    final titleSpans = <Map<String, dynamic>>[];
    final bodySpans = <Map<String, dynamic>>[];
    for (final s in spans) {
      final start = s['start'] as int;
      final end = s['end'] as int;
      if (end > 0 && start < nl) {
        titleSpans.add({
          ...s,
          'start': start.clamp(0, nl),
          'end': end.clamp(0, nl),
        });
      }
      if (end > nl + 1) {
        final bs = (start - (nl + 1)).clamp(0, bodyPart.length);
        final be = (end - (nl + 1)).clamp(0, bodyPart.length);
        if (bs < be) {
          bodySpans.add({...s, 'start': bs, 'end': be});
        }
      }
    }

    return TextSpan(
      children: [
        TextSpanBuilder.build(
          text: titlePart,
          baseStyle: titleStyle,
          spans: titleSpans,
        ),
        TextSpan(text: '\n', style: bodyStyle),
        TextSpanBuilder.build(
          text: bodyPart,
          baseStyle: bodyStyle,
          spans: bodySpans,
        ),
      ],
    );
  }
}

/// Info object — one text field; first line is the title (diagrams / API).
class InfoEmbed extends StatefulWidget {
  const InfoEmbed({
    super.key,
    required this.embed,
    required this.blockId,
    required this.state,
    required this.onRefresh,
    this.onFocus,
    this.onExitBelow,
    this.onDeleteObject,
    this.documentBaseOffset = 0,
  });

  final ObjectEmbed embed;
  final String blockId;
  final AppState state;
  final VoidCallback onRefresh;
  final VoidCallback? onFocus;
  final VoidCallback? onExitBelow;

  /// Backspace on a fully empty info object — remove it from the file.
  final VoidCallback? onDeleteObject;

  /// Start of this pointer slice in the marker-text buffer.
  final int documentBaseOffset;

  @override
  InfoEmbedState createState() => InfoEmbedState();
}

class InfoEmbedState extends State<InfoEmbed>
    with EmbedLineGatewayMixin
    implements EmbedCaretGateway {
  /// Info field that currently owns the caret — for the add-connection shortcut.
  static InfoEmbedState? keyboardFocus;

  late _InfoTextController _controller;
  late final FocusNode _focus;
  Timer? _saveTimer;
  EmbedCaretRegistry? _registry;

  @override
  String get nodeId => widget.blockId;

  @override
  int get lineCount => 1;

  @override
  void focusLine(int index, {required bool fromAbove}) {
    focusFieldLine(_focus, _controller, fromAbove: fromAbove);
  }

  @override
  void prepareObjectMenuMark() {
    BlockTextFocusRegistry.register(
      controller: _controller,
      changed: _scheduleSave,
      focusNode: _focus,
      fontSize: AppTypography.noteBodyStyle.fontSize ?? 12.5,
    );
    BlockTextFocusRegistry.capturePendingWholeFieldMark(
      controller: _controller,
      onChanged: _scheduleSave,
      segmentId: infoTextSegmentId(widget.blockId),
    );
  }

  void _seedFromEmbed() {
    final info = widget.embed.information ?? const {};
    final title = info['title'] as String? ?? '';
    final body = info['body'] as String? ?? '';
    final combined = composeInfoText(title, body);
    final meta = info['metadata'];
    final rawSpans = meta is Map ? meta['spans'] : null;
    final bodySpans = rawSpans is List
        ? [
            for (final s in rawSpans)
              if (s is Map) Map<String, dynamic>.from(s),
          ]
        : <Map<String, dynamic>>[];
    _controller.setRichState(
      text: combined,
      spans: infoSpansToCombined(bodySpans, combined),
    );
  }

  (String, String, List<Map<String, dynamic>>) _splitForApi() {
    final combined = _controller.text;
    final parts = splitInfoText(combined);
    return (
      parts.$1,
      parts.$2,
      infoSpansToBody(_controller.spans, combined),
    );
  }

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(_onKeyboardFocus);
    _controller = _InfoTextController();
    _seedFromEmbed();
  }

  void _onKeyboardFocus() {
    if (_focus.hasFocus) {
      keyboardFocus = this;
      return;
    }
    if (identical(keyboardFocus, this)) keyboardFocus = null;
  }

  Future<void> addConnectionFromShortcut() => _addConnection();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = EmbedCaretScope.maybeOf(context)?.registry;
    if (!identical(next, _registry)) {
      _registry?.unregister(nodeId);
      _registry = next;
      _registry?.register(this);
    }
  }

  /// Push live controllers into AppState cache before a structural remount.
  Future<void> flushToCache() async {
    pushControllersToCache();
    await _save(flush: true);
  }

  @override
  void didUpdateWidget(InfoEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Controllers are the live source of truth. Only re-seed when the object
    // identity changes — never overwrite typed text with a stale empty cache
    // after Move Mode (GlobalKey keeps this State across rebuilds).
    if (oldWidget.embed.id == widget.embed.id) return;
    _seedFromEmbed();
  }

  @override
  void dispose() {
    if (identical(keyboardFocus, this)) keyboardFocus = null;
    _focus.removeListener(_onKeyboardFocus);
    _registry?.unregister(nodeId);
    _registry = null;
    _saveTimer?.cancel();
    // Best-effort flush — ignore if the object was already deleted.
    unawaited(_save(flush: true).catchError((_) {}));
    _focus.dispose();
    _controller.dispose();
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
    final (title, body, spans) = _splitForApi();
    try {
      await widget.state.updateInfoObject(
        widget.embed,
        title: title,
        body: body,
        spans: spans,
      );
    } catch (_) {
      // Object may have been removed while a debounce was pending.
    }
    if (flush) return;
  }

  /// Sync cache only — use before structural rebuild; API can catch up async.
  void pushControllersToCache() {
    final (title, body, spans) = _splitForApi();
    widget.state.patchInfoObjectCache(
      widget.embed,
      title: title,
      body: body,
      spans: spans,
    );
  }

  bool get _isEmptyObject => _controller.text.trim().isEmpty;

  Future<void> _onBackspaceAtStart() async {
    widget.onFocus?.call();
    if (_isEmptyObject) {
      runAfterKeystroke(() => widget.onDeleteObject?.call());
    }
  }

  /// Enter inserts a newline (first line stays the title). Leave with Escape.
  void _onEnter() {
    widget.onFocus?.call();
    final text = _controller.text;
    final sel = _controller.selection;
    final offset =
        sel.isValid ? sel.baseOffset.clamp(0, text.length) : text.length;

    final next = text.replaceRange(offset, offset, '\n');
    _controller.value = TextEditingValue(
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
    final tags = widget.embed.tags;
    return DecoratedBox(
      decoration: AppColors.detailsBlockDecoration(),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormattedTextField(
              controller: _controller,
              focusNode: _focus,
              segmentId: infoTextSegmentId(widget.blockId),
              documentBaseOffset: widget.documentBaseOffset,
              style: AppTypography.noteBodyStyle,
              maxLines: null,
              minLines: 1,
              onChanged: (_) => _scheduleSave(),
              onEnter: _onEnter,
              onBackspaceAtStart: _onBackspaceAtStart,
              onSecondaryTapDown: _showTextMenu,
              onArrowExitAbove: () => navigateEmbedLine(
                lineIndex: 0,
                lineCount: lineCount,
                focusLine: focusLine,
                goingDown: false,
              ),
              onArrowExitBelow: () => navigateEmbedLine(
                lineIndex: 0,
                lineCount: lineCount,
                focusLine: focusLine,
                goingDown: true,
              ),
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
