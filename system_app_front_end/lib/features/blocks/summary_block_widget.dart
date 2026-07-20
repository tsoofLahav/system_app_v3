import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../core/models/block.dart';
import 'block_text_focus.dart';
import 'formatted_text_field.dart';
import 'rich_text_block_sync.dart';
import 'span_text_editing_controller.dart';
import 'text_formatting.dart';

class SummaryBlockWidget extends StatefulWidget {
  const SummaryBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.hint = 'Summary...',
    this.topicAccent,
    this.fileType = 'doc',
    this.isMainTopic = false,
    this.aiState,
    this.aiFileId,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String hint;
  final Color? topicAccent;
  final String fileType;
  final bool isMainTopic;
  final AppState? aiState;
  final int? aiFileId;

  @override
  State<SummaryBlockWidget> createState() => _SummaryBlockWidgetState();
}

class _SummaryBlockWidgetState extends State<SummaryBlockWidget> {
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
  }

  @override
  void didUpdateWidget(SummaryBlockWidget oldWidget) {
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
  }

  @override
  void dispose() {
    _controller.removeListener(_reportAiFocus);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
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
  Widget build(BuildContext context) {
    final accent = widget.topicAccent ?? AppColors.text;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: AppColors.summaryPaneDecoration(
        accent,
        widget.fileType,
        isMainTopic: widget.isMainTopic,
      ),
      child: FormattedTextField(
        controller: _controller,
        focusNode: _focusNode,
        style: AppTypography.noteBodyStyle,
        blockContent: widget.block.content,
        hintText: widget.hint,
        maxLines: null,
        emojiSearchHint: widget.aiState?.strings['searchEmoji'] ?? 'Search emoji',
        emojiPickerTitle: widget.aiState?.strings['insertEmoji'] ?? 'Insert emoji…',
        onChanged: (_) {
          _reportAiFocus();
          _emit();
        },
      ),
    );
  }
}
