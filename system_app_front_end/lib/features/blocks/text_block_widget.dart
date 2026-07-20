import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../core/models/block.dart';
import '../../design_system/app_typography.dart';
import 'block_text_focus.dart';
import 'formatted_text_field.dart';
import 'rich_text_block_sync.dart';
import 'span_text_editing_controller.dart';
import 'text_formatting.dart';

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
  late final SpanTextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final rich = richContentFromBlock(widget.block.content);
    _controller = SpanTextEditingController(
      text: rich.text,
      spans: rich.spans,
    );
    _controller.addListener(_reportAiFocus);
    _requestAutofocus();
  }

  @override
  void didUpdateWidget(TextBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusNode.hasFocus ||
        BlockTextFocusRegistry.isInMenuSession ||
        BlockTextFocusRegistry.activeController == _controller) {
      return;
    }
    syncRichControllerFromBlockIfIdle(
      focusNode: _focusNode,
      blockContent: widget.block.content,
      controller: _controller,
    );
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

  void _emit() {
    widget.onChanged({
      ...widget.block.content,
      ..._controller.contentPatch(_controller.text),
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_reportAiFocus);
    BlockTextFocusRegistry.unregister(_controller);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FormattedTextField(
      controller: _controller,
      focusNode: _focusNode,
      blockId: widget.block.id,
      style: AppTypography.noteBodyStyle,
      blockContent: widget.block.content,
      hintText: widget.hint,
      maxLines: null,
      emojiSearchHint: widget.aiState?.strings['searchEmoji'] ?? 'Search emoji',
      emojiPickerTitle: widget.aiState?.strings['insertEmoji'] ?? 'Insert emoji…',
      aiState: widget.aiState,
      aiSuggestEmojiLabel:
          widget.aiState?.strings['aiSuggestEmoji'] ?? 'Suggest emoji',
      onChanged: (_) {
        _reportAiFocus();
        _emit();
      },
    );
  }
}
