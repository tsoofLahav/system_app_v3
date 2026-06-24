import 'package:flutter/material.dart';

import 'format_range.dart';
import 'text_formatting.dart';

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
  late String _previousText;
  bool _suppressSpanUpdates = false;

  List<Map<String, dynamic>> get spans => _spans;

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
      spans: _spans,
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

    _previousText = newText;
  }

  @override
  void dispose() {
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
    );
    _previousText = text;
    notifyListeners();
  }
}
