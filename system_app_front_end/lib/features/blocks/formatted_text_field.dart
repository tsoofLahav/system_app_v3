import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'block_text_focus.dart';
import 'text_formatting.dart';

/// Text field that registers for block context-menu clipboard/format actions.
class FormattedTextField extends StatefulWidget {
  const FormattedTextField({
    super.key,
    required this.controller,
    required this.style,
    this.content,
    this.hintText,
    this.maxLines,
    this.minLines = 1,
    this.onChanged,
    this.onSubmitted,
    this.onBackspaceAtStart,
    this.onSelectAll,
    this.onPaste,
    this.textInputAction,
    this.focusNode,
    this.onContentChanged,
    this.onEnter,
    this.stripNewlines = false,
  });

  final TextEditingController controller;
  final TextStyle style;
  final Map<String, dynamic>? content;
  final String? hintText;
  final int? maxLines;
  final int minLines;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onBackspaceAtStart;
  final VoidCallback? onSelectAll;
  final Future<void> Function(String text)? onPaste;
  final TextInputAction? textInputAction;
  final FocusNode? focusNode;
  final ValueChanged<Map<String, dynamic>>? onContentChanged;
  final VoidCallback? onEnter;
  final bool stripNewlines;

  @override
  State<FormattedTextField> createState() => _FormattedTextFieldState();
}

class _FormattedTextFieldState extends State<FormattedTextField> {
  late FocusNode _focusNode;
  bool _ownsFocus = false;
  bool _listeningKeys = false;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode != null) {
      _focusNode = widget.focusNode!;
    } else {
      _focusNode = FocusNode();
      _ownsFocus = true;
    }
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _stopListeningKeys();
    _focusNode.removeListener(_onFocusChanged);
    BlockTextFocusRegistry.unregister(widget.controller);
    if (_ownsFocus) _focusNode.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (_focusNode.hasFocus) {
      _startListeningKeys();
      BlockTextFocusRegistry.register(
        controller: widget.controller,
        changed: () => widget.onChanged?.call(widget.controller.text),
        contentChanged: widget.onContentChanged,
        content: {
          ...?widget.content,
          'text': widget.controller.text,
        },
      );
    } else {
      _stopListeningKeys();
      BlockTextFocusRegistry.unregister(widget.controller);
    }
  }

  void _startListeningKeys() {
    if (_listeningKeys) return;
    HardwareKeyboard.instance.addHandler(_handleKey);
    _listeningKeys = true;
  }

  void _stopListeningKeys() {
    if (!_listeningKeys) return;
    HardwareKeyboard.instance.removeHandler(_handleKey);
    _listeningKeys = false;
  }

  bool _handleKey(KeyEvent event) {
    if (!_focusNode.hasFocus) return false;
    if (event is! KeyDownEvent) return false;

    final isMeta = HardwareKeyboard.instance.isMetaPressed;
    if (isMeta && event.logicalKey == LogicalKeyboardKey.keyA) {
      widget.onSelectAll?.call();
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter &&
        !HardwareKeyboard.instance.isShiftPressed &&
        widget.onEnter != null) {
      widget.onEnter!();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.backspace &&
        widget.controller.text.isEmpty &&
        widget.controller.selection.baseOffset == 0 &&
        widget.onBackspaceAtStart != null) {
      widget.onBackspaceAtStart!();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final style = applyBlockTextStyle(widget.style, widget.content);
    final formatters = <TextInputFormatter>[
      if (widget.onEnter != null) _SubmitOnEnterFormatter(widget.onEnter!),
      if (widget.stripNewlines) _StripNewlinesFormatter(),
    ];

    return TextField(
      controller: widget.controller,
      focusNode: _focusNode,
      style: style,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      decoration: InputDecoration(
        isDense: true,
        border: InputBorder.none,
        hintText: widget.hintText,
        hintStyle: style.copyWith(color: style.color?.withValues(alpha: 0.35)),
        contentPadding: EdgeInsets.zero,
      ),
      textInputAction:
          widget.onEnter != null ? TextInputAction.none : widget.textInputAction,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      onTap: () => _onFocusChanged(),
      inputFormatters: formatters.isEmpty ? null : formatters,
      contextMenuBuilder: (context, editableTextState) {
        return AdaptiveTextSelectionToolbar.editableText(
          editableTextState: editableTextState,
        );
      },
    );
  }
}

/// Enter creates a new list/task row instead of a soft line break.
class _SubmitOnEnterFormatter extends TextInputFormatter {
  _SubmitOnEnterFormatter(this.onSubmit);

  final VoidCallback onSubmit;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains('\n')) return newValue;
    WidgetsBinding.instance.addPostFrameCallback((_) => onSubmit());
    return oldValue;
  }
}

class _StripNewlinesFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!newValue.text.contains('\n')) return newValue;
    final cleaned = newValue.text.replaceAll('\n', ' ');
    return newValue.copyWith(
      text: cleaned,
      selection: TextSelection.collapsed(offset: cleaned.length),
      composing: TextRange.empty,
    );
  }
}
