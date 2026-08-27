import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../ui/app_colors.dart';
import './format_range.dart';
import './text_formatting.dart';

/// Text controller that renders inline spans while editing.
///
/// See [RICH_TEXT.md] for invariants.
class SpanTextEditingController extends TextEditingController {
  SpanTextEditingController({
    super.text,
    List<Map<String, dynamic>> spans = const [],
  }) : _spans = spans.map(Map<String, dynamic>.from).toList() {
    _previousText = text;
    addListener(_onControllerTextChanged);
  }

  List<Map<String, dynamic>> _spans;
  List<({int start, int end})> _descriptionPaintRanges = const [];
  var _paintNotifyQueued = false;
  var _disposed = false;
  late String _previousText;
  bool _suppressSpanUpdates = false;

  List<Map<String, dynamic>> get spans => _spans;

  /// Persisted spans with description-link colour applied for painting only.
  List<Map<String, dynamic>> get displaySpans => paintSpansWithLinkColor(
    _spans,
    _descriptionPaintRanges,
    text.length,
    AppColors.colorToHex(AppColors.descriptionLink),
  );

  void setDescriptionPaintRanges(List<({int start, int end})> ranges) {
    if (_disposed) return;
    if (_samePaintRanges(_descriptionPaintRanges, ranges)) return;
    _descriptionPaintRanges = List<({int start, int end})>.from(ranges);
    switch (SchedulerBinding.instance.schedulerPhase) {
      case SchedulerPhase.idle:
      case SchedulerPhase.postFrameCallbacks:
        notifyListeners();
      case SchedulerPhase.transientCallbacks:
      case SchedulerPhase.midFrameMicrotasks:
      case SchedulerPhase.persistentCallbacks:
        if (_paintNotifyQueued) return;
        _paintNotifyQueued = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _paintNotifyQueued = false;
          if (_disposed) return;
          notifyListeners();
        });
    }
  }

  set spans(List<Map<String, dynamic>> value) {
    _spans = value.map(Map<String, dynamic>.from).toList();
    notifyListeners();
  }

  /// Replace document state without treating it as a user edit.
  void setRichState({
    required String text,
    required List<Map<String, dynamic>> spans,
    bool preserveSelection = false,
  }) {
    _suppressSpanUpdates = true;
    _spans = spans.map(Map<String, dynamic>.from).toList();
    if (this.text != text) {
      value = value.copyWith(
        text: text,
        selection: preserveSelection
            ? TextSelection(
                baseOffset: selection.baseOffset.clamp(0, text.length),
                extentOffset: selection.extentOffset.clamp(0, text.length),
              )
            : TextSelection.collapsed(offset: text.length),
        composing: TextRange.empty,
      );
    }
    _previousText = this.text;
    _suppressSpanUpdates = false;
    notifyListeners();
  }

  void _onControllerTextChanged() {
    if (text == _previousText) return;
    handleTextChange();
  }

  Map<String, dynamic> contentPatch(String currentText) {
    return spanContentPatch(const {}, currentText, _spans);
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    return TextSpanBuilder.build(
      text: text,
      baseStyle: style ?? const TextStyle(),
      spans: displaySpans,
    );
  }

  void ensureSpansMatchText() {
    handleTextChange();
  }

  void handleTextChange() {
    if (_suppressSpanUpdates) return;

    final newText = text;
    final oldText = _previousText;
    if (newText == oldText) return;

    _spans = remapSpansForTextEdit(_spans, oldText, newText);
    _descriptionPaintRanges = [
      for (final range in _descriptionPaintRanges)
        ?remapOffsetRange(
          start: range.start,
          end: range.end,
          oldText: oldText,
          newText: newText,
        ),
    ];

    _previousText = newText;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    removeListener(_onControllerTextChanged);
    super.dispose();
  }

  void applyFormatAction(
    String action, {
    required FormatRange range,
    required double baseFontSize,
  }) {
    if (!range.isValid) return;

    _spans = applyFormatActionToRange(
      _spans,
      start: range.start,
      end: range.end,
      textLength: text.length,
      action: action,
      baseFontSize: baseFontSize,
      sourceText: text,
    );
    _previousText = text;
    try {
      notifyListeners();
    } catch (_) {}
  }
}

bool _samePaintRanges(
  List<({int start, int end})> a,
  List<({int start, int end})> b,
) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i].start != b[i].start || a[i].end != b[i].end) return false;
  }
  return true;
}
