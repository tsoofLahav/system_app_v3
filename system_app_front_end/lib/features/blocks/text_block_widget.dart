import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../core/models/block.dart';
import '../../design_system/app_typography.dart';

class TextBlockWidget extends StatefulWidget {
  const TextBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.hint = 'Write here...',
    this.aiState,
    this.aiFileId,
    this.autofocus = false,
    this.onAutofocused,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String hint;
  final AppState? aiState;
  final int? aiFileId;
  final bool autofocus;
  final VoidCallback? onAutofocused;

  @override
  State<TextBlockWidget> createState() => _TextBlockWidgetState();
}

class _TextBlockWidgetState extends State<TextBlockWidget> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
    _controller.addListener(_reportAiFocus);
    _requestAutofocus();
  }

  @override
  void didUpdateWidget(TextBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.id != widget.block.id &&
        _controller.text != widget.block.text) {
      _controller.text = widget.block.text;
    }
    _requestAutofocus();
  }

  void _requestAutofocus() {
    if (!widget.autofocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
      _reportAiFocus();
      widget.onAutofocused?.call();
    });
  }

  void _reportAiFocus() {
    final state = widget.aiState;
    final fileId = widget.aiFileId;
    if (state == null || fileId == null) return;
    state.setAiFocus(
      AiFocus(
        fileId: fileId,
        blockId: widget.block.id,
        fullText: _controller.text,
        selection: _controller.selection,
      ),
    );
  }

  @override
  void dispose() {
    _controller.removeListener(_reportAiFocus);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      maxLines: null,
      style: AppTypography.noteBodyStyle,
      decoration: AppTypography.noteInputDecoration(hint: widget.hint),
      onChanged: (value) => widget.onChanged({'text': value}),
      onTap: _reportAiFocus,
    );
  }
}
