import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../core/models/block.dart';
import 'formatted_text_field.dart';

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
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.block.text);
    _controller.addListener(_reportAiFocus);
  }

  @override
  void dispose() {
    _controller.removeListener(_reportAiFocus);
    _controller.dispose();
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
      'text': _controller.text,
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
        style: AppTypography.noteBodyStyle,
        content: widget.block.content,
        hintText: widget.hint,
        maxLines: null,
        onChanged: (_) {
          _reportAiFocus();
          _emit();
        },
        onContentChanged: widget.onChanged,
      ),
    );
  }
}
