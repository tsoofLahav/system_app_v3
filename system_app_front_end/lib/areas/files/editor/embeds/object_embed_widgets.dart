import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../config/api_config.dart';
import '../../../../core/app_state.dart';
import '../../../objects/data/image_payload.dart';
import '../../../objects/data/object_embed.dart';
import '../../../objects/links/add_connection_dialog.dart';
import '../../../ux/topic/topic_appearance.dart';
import '../document_secondary_tap.dart';
import '../document_text_flow.dart';
import '../edit_conflict.dart';
import '../editor_key_handoff.dart';
import '../embed_caret_bridge.dart';
import '../../rich_text/block_text_actions.dart';
import '../../rich_text/block_text_focus.dart';
import '../../rich_text/connect_info.dart';
import '../../rich_text/document_context_menu.dart';
import '../../rich_text/formatted_text_field.dart';
import '../../rich_text/span_text_editing_controller.dart';
import '../../rich_text/text_formatting.dart';
import '../../../ui/app_typography.dart';
import './image_display_size.dart';
import './object_design_dialog.dart';
import './object_look.dart';

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

String infoEditSnapshot({
  required String title,
  required String body,
  required List<dynamic> spans,
}) => jsonEncode({'title': title, 'body': body, 'spans': spans});

String infoSnapshotFromEmbed(ObjectEmbed embed) {
  final info = embed.information ?? const {};
  final meta = info['metadata'];
  final rawSpans = meta is Map ? meta['spans'] : null;
  final spans = rawSpans is List ? rawSpans : const [];
  return infoEditSnapshot(
    title: info['title'] as String? ?? '',
    body: info['body'] as String? ?? '',
    spans: spans,
  );
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
        spans: displaySpans,
      );
    }

    final titlePart = t.substring(0, nl);
    final bodyPart = t.substring(nl + 1);
    final titleSpans = <Map<String, dynamic>>[];
    final bodySpans = <Map<String, dynamic>>[];
    for (final s in displaySpans) {
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
  var _dirty = false;
  var _conflictOpen = false;
  late String _baselineKey;

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
      fontSize: AppTypography.noteTitleStyle.fontSize ?? 14,
    );
    BlockTextFocusRegistry.capturePendingMark();
  }

  void _seedFromEmbed(ObjectEmbed embed, {bool preserveSelection = false}) {
    final info = embed.information ?? const {};
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
      preserveSelection: preserveSelection,
    );
  }

  (String, String, List<Map<String, dynamic>>) _splitForApi() {
    final combined = _controller.text;
    final parts = splitInfoText(combined);
    return (parts.$1, parts.$2, infoSpansToBody(_controller.spans, combined));
  }

  @override
  void initState() {
    super.initState();
    _focus = FocusNode();
    _focus.addListener(_onKeyboardFocus);
    _controller = _InfoTextController();
    _seedFromEmbed(widget.embed);
    _baselineKey = infoSnapshotFromEmbed(widget.embed);
    widget.state.addListener(_onAppState);
  }

  void _onKeyboardFocus() {
    if (_focus.hasFocus) {
      keyboardFocus = this;
      return;
    }
    if (identical(keyboardFocus, this)) keyboardFocus = null;
    final cached = _cachedEmbed;
    if (cached != null) _considerInbound(cached);
  }

  Future<void> addConnectionFromShortcut() => _addConnection();

  Future<void> connectInfoFromShortcut() => connectInfoFromMark(
    context: context,
    state: widget.state,
    host: widget.embed,
    segmentId: infoTextSegmentId(widget.blockId),
  );

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
    if (oldWidget.embed.id != widget.embed.id) {
      _setDirty(false);
      _seedFromEmbed(widget.embed);
      _baselineKey = infoSnapshotFromEmbed(widget.embed);
      return;
    }
    _considerInbound(widget.embed);
  }

  @override
  void dispose() {
    widget.state.removeListener(_onAppState);
    if (identical(keyboardFocus, this)) keyboardFocus = null;
    _focus.removeListener(_onKeyboardFocus);
    _registry?.unregister(nodeId);
    _registry = null;
    _saveTimer?.cancel();
    if (_shouldFlushOnDispose()) {
      unawaited(_save(flush: true).catchError((_) {}));
    }
    UnsavedEmbedEdits.mark(widget.embed.id, false);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  ObjectEmbed? get _cachedEmbed {
    final list = widget.state.embedsByFileId[widget.embed.fileId];
    if (list == null) return null;
    for (final embed in list) {
      if (embed.id == widget.embed.id) return embed;
    }
    return null;
  }

  void _onAppState() {
    if (!mounted) return;
    final cached = _cachedEmbed;
    if (cached == null) return;
    _considerInbound(cached);
  }

  void _setDirty(bool value) {
    if (_dirty == value) return;
    _dirty = value;
    UnsavedEmbedEdits.mark(
      widget.embed.id,
      value,
      baselineKey: value ? _baselineKey : null,
    );
  }

  String get _localKey {
    final (title, body, spans) = _splitForApi();
    return infoEditSnapshot(title: title, body: body, spans: spans);
  }

  bool _shouldFlushOnDispose() {
    if (!_dirty) return false;
    final cached = _cachedEmbed;
    if (cached == null) return true;
    final cacheKey = infoSnapshotFromEmbed(cached);
    if (cacheKey == _localKey) return false;
    if (cacheKey != _baselineKey) return false;
    return true;
  }

  void _considerInbound(ObjectEmbed inbound) {
    if (UnsavedEmbedEdits.takeLocalOverInbound && _dirty) {
      UnsavedEmbedEdits.takeLocalOverInbound = false;
      unawaited(_save());
      return;
    }
    final inboundKey = infoSnapshotFromEmbed(inbound);
    final decision = decideRemoteEdit(
      localDirty: _dirty,
      inboundEqualsLocal: inboundKey == _localKey,
      inboundEqualsBaseline: inboundKey == _baselineKey,
    );
    switch (decision) {
      case RemoteEditDecision.ignore:
        return;
      case RemoteEditDecision.takeRemote:
        // Do not jump the caret while this field owns typing. Apply on blur
        // (see _onKeyboardFocus) unless the user chose Take theirs.
        if (_focus.hasFocus) return;
        _applyRemote(inbound);
        return;
      case RemoteEditDecision.ask:
        if (UnsavedEmbedEdits.fileConflictPending) return;
        _askConflict(inbound);
        return;
    }
  }

  void _applyRemote(ObjectEmbed inbound) {
    _saveTimer?.cancel();
    _setDirty(false);
    void paint() {
      if (!mounted) return;
      if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
        runAfterKeystroke(paint);
        return;
      }
      _seedFromEmbed(inbound, preserveSelection: _focus.hasFocus);
      _baselineKey = infoSnapshotFromEmbed(inbound);
      setState(() {});
    }

    paint();
  }

  void _askConflict(ObjectEmbed inbound) {
    if (_conflictOpen) return;
    void run() async {
      if (!mounted || _conflictOpen) return;
      _conflictOpen = true;
      final choice = await showEditConflictDialog(
        context: context,
        strings: widget.state.strings,
      );
      _conflictOpen = false;
      if (!mounted) return;
      if (choice == EditConflictChoice.keepYours) {
        unawaited(_save());
        return;
      }
      _applyRemote(inbound);
    }

    if (HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
      runAfterKeystroke(run);
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => run());
  }

  void _scheduleSave() {
    widget.onFocus?.call();
    _setDirty(true);
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
      _baselineKey = infoEditSnapshot(title: title, body: body, spans: spans);
      _setDirty(false);
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

  Future<void> _showTextMenu(TapDownDetails details) async {
    final ranges = descriptionRangesForSegment(
      state: widget.state,
      fileId: widget.embed.fileId,
      segmentId: infoTextSegmentId(widget.blockId),
    );
    await DocumentContextMenu.showInfoFieldMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.state.strings,
      includeDisconnectInfo: descriptionRangeCoveringMark(ranges) != null,
      onAction: (action) async {
        if (action == 'text:connect_info') {
          await connectInfoFromMark(
            context: context,
            state: widget.state,
            host: widget.embed,
            segmentId: infoTextSegmentId(widget.blockId),
          );
          if (mounted) setState(() {});
          return;
        }
        if (action == 'text:disconnect_info') {
          await disconnectInfoAtMark(state: widget.state, ranges: ranges);
          if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final tags = widget.embed.tags;
    final look = ObjectLook.infoOf(widget.embed.payload);
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormattedTextField(
          controller: _controller,
          focusNode: _focus,
          segmentId: infoTextSegmentId(widget.blockId),
          documentBaseOffset: widget.documentBaseOffset,
          style: AppTypography.noteTitleStyle,
          maxLines: null,
          minLines: 1,
          onChanged: (_) => _scheduleSave(),
          onBackspaceAtStart: _onBackspaceAtStart,
          onSecondaryTapDown: _showTextMenu,
          descriptionRanges: descriptionRangesForSegment(
            state: widget.state,
            fileId: widget.embed.fileId,
            segmentId: infoTextSegmentId(widget.blockId),
          ),
          onDescriptionActivate: (range) =>
              openDescriptionTarget(state: widget.state, link: range.link),
          onDescriptionAnchorsChanged: (ranges) {
            unawaited(
              persistRemappedDescriptionAnchors(widget.state, ranges),
            );
          },
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
    );
    return wrapInfoLook(look: look, child: body);
  }
}

class ImageEmbed extends StatefulWidget {
  const ImageEmbed({
    super.key,
    required this.embed,
    required this.state,
    required this.onPayloadChanged,
    this.canMergeNext = false,
    this.onMergeNext,
  });

  final ObjectEmbed embed;
  final AppState state;
  final ValueChanged<Map<String, dynamic>> onPayloadChanged;
  final bool canMergeNext;
  final Future<void> Function()? onMergeNext;

  @override
  State<ImageEmbed> createState() => _ImageEmbedState();
}

class _ImageEmbedState extends State<ImageEmbed> {
  late List<TextEditingController> _captionControllers;
  late List<FocusNode> _captionFocus;
  Timer? _captionSaveTimer;
  var _uploading = false;
  late double _scale;

  Map<String, dynamic> get _payload {
    final list = widget.state.embedsByFileId[widget.embed.fileId];
    if (list != null) {
      for (final embed in list) {
        if (embed.id == widget.embed.id) {
          return embed.payload ?? const {};
        }
      }
    }
    return widget.embed.payload ?? const {};
  }

  List<Map<String, String>> get _panes => ImageObjectPayload.panesOf(_payload);

  @override
  void initState() {
    super.initState();
    _scale = ImageDisplaySize.scaleOf(widget.embed.payload);
    _captionControllers = [
      for (final pane in _panes) TextEditingController(text: pane['caption']),
    ];
    _captionFocus = [for (final _ in _panes) FocusNode()];
  }

  @override
  void didUpdateWidget(ImageEmbed oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextScale = ImageDisplaySize.scaleOf(_payload);
    if (nextScale != _scale) _scale = nextScale;
    _syncCaptionControllers();
  }

  void _syncCaptionControllers() {
    final panes = _panes;
    while (_captionControllers.length > panes.length) {
      _captionControllers.removeLast().dispose();
      _captionFocus.removeLast().dispose();
    }
    while (_captionControllers.length < panes.length) {
      final i = _captionControllers.length;
      _captionControllers.add(
        TextEditingController(text: panes[i]['caption'] ?? ''),
      );
      _captionFocus.add(FocusNode());
    }
    for (var i = 0; i < panes.length; i++) {
      final next = panes[i]['caption'] ?? '';
      if (_captionFocus[i].hasFocus) continue;
      if (next != _captionControllers[i].text) {
        _captionControllers[i].text = next;
      }
    }
  }

  @override
  void dispose() {
    _captionSaveTimer?.cancel();
    for (final c in _captionControllers) {
      c.dispose();
    }
    for (final n in _captionFocus) {
      n.dispose();
    }
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
        'width': _scale,
        'caption': _captionControllers.firstOrNull?.text ?? '',
      });
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _scheduleCaptionSave() {
    _captionSaveTimer?.cancel();
    _captionSaveTimer = Timer(
      const Duration(milliseconds: 400),
      _commitCaptions,
    );
  }

  void _commitCaptions() {
    final panes = [
      for (var i = 0; i < _panes.length; i++)
        {
          'url': _panes[i]['url'] ?? '',
          'caption': i < _captionControllers.length
              ? _captionControllers[i].text
              : (_panes[i]['caption'] ?? ''),
        },
    ];
    widget.onPayloadChanged(
      ImageObjectPayload.mirrored(
        panes,
        existing: {..._payload, 'width': _scale},
      ),
    );
  }

  Future<void> _onSecondaryTap(TapDownDetails details) async {
    DocumentSecondaryTap.markEmbedHandled();
    if (!mounted) return;
    await DocumentContextMenu.showImageMenu(
      context: context,
      globalPosition: details.globalPosition,
      strings: widget.state.strings,
      scale: _scale,
      canMergeNext: widget.canMergeNext,
      onAction: (action) async {
        if (action == 'image:merge_next') {
          await widget.onMergeNext?.call();
          return;
        }
        if (action == 'object:design') {
          await _openDesign();
          return;
        }
        final next = ImageDisplaySize.apply(action, {
          ..._payload,
          'width': _scale,
        });
        if (next == null) return;
        final scale = ImageDisplaySize.scaleOf(next);
        setState(() => _scale = scale);
        widget.onPayloadChanged(next);
      },
    );
  }

  Future<void> _openDesign() async {
    await showObjectDesignDialog(
      context: context,
      strings: widget.state.strings,
      kind: 'image',
      look: ObjectLook.imageOf(_payload),
      greyscale: ObjectLook.imageGreyscaleOf(_payload),
      onLook: (look) {
        widget.onPayloadChanged(
          ObjectLook.withLook(
            _payload,
            look,
            greyscale: ObjectLook.imageGreyscaleOf(_payload),
          ),
        );
        if (mounted) setState(() {});
      },
      onGreyscale: (value) {
        widget.onPayloadChanged(
          ObjectLook.withLook(
            _payload,
            ObjectLook.imageOf(_payload),
            greyscale: value,
          ),
        );
        if (mounted) setState(() {});
      },
    );
  }

  Widget _picture(String url) {
    final resolved = url.startsWith('http') ? url : '${ApiConfig.baseUrl}$url';
    Widget picture = Image.network(
      resolved,
      fit: BoxFit.contain,
      errorBuilder: (_, error, stackTrace) =>
          Text('Image unavailable', style: AppTypography.metaStyle),
    );
    return wrapImageLook(
      look: ObjectLook.imageOf(_payload),
      greyscale: ObjectLook.imageGreyscaleOf(_payload),
      child: picture,
    );
  }

  Widget _captionField(int index) {
    return FormattedTextField(
      controller: _captionControllers[index],
      focusNode: _captionFocus[index],
      style: AppTypography.metaStyle,
      maxLines: null,
      minLines: 1,
      stripNewlines: true,
      onChanged: (_) => _scheduleCaptionSave(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final panes = _panes;
    final hasPicture = panes.any((p) => (p['url'] ?? '').isNotEmpty);

    return GestureDetector(
      onSecondaryTapDown: _onSecondaryTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasPicture)
            LayoutBuilder(
              builder: (context, constraints) {
                final rowWidth = constraints.maxWidth * _scale;
                if (panes.length == 1) {
                  final url = panes.first['url'] ?? '';
                  return Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: SizedBox(
                      width: rowWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (url.isNotEmpty) _picture(url),
                          const SizedBox(height: 4),
                          _captionField(0),
                        ],
                      ),
                    ),
                  );
                }
                return Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: SizedBox(
                    width: rowWidth,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var i = 0; i < panes.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if ((panes[i]['url'] ?? '').isNotEmpty)
                                  _picture(panes[i]['url'] ?? ''),
                                const SizedBox(height: 4),
                                _captionField(i),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            )
          else ...[
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pick,
              icon: const Icon(Icons.image_outlined, size: 18),
              label: Text(_uploading ? 'Uploading…' : 'Add image'),
            ),
            const SizedBox(height: 4),
            _captionField(0),
          ],
        ],
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
