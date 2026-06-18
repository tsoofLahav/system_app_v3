import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../core/models/block.dart';

class SummaryBlockWidget extends StatefulWidget {
  const SummaryBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.hint = 'Summary...',
    this.aiState,
    this.aiFileId,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String hint;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.noteBottom.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.noteBorder.withValues(alpha: 0.5)),
      ),
      child: TextField(
        controller: _controller,
        maxLines: null,
        style: AppTypography.noteBodyStyle,
        decoration: AppTypography.noteInputDecoration(hint: widget.hint),
        onChanged: (value) => widget.onChanged({'text': value}),
        onTap: _reportAiFocus,
      ),
    );
  }
}
