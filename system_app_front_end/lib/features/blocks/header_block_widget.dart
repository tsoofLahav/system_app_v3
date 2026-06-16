import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../design_system/app_typography.dart';
import '../../core/models/block.dart';

class HeaderBlockWidget extends StatefulWidget {
  const HeaderBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.hint = 'Header',
    this.aiState,
    this.aiFileId,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String hint;
  final AppState? aiState;
  final int? aiFileId;

  @override
  State<HeaderBlockWidget> createState() => _HeaderBlockWidgetState();
}

class _HeaderBlockWidgetState extends State<HeaderBlockWidget> {
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
    final level = widget.block.content['level'] as int? ?? 2;
    final style = switch (level) {
      1 => AppTypography.blockHeaderStyle.copyWith(fontSize: 15),
      2 => AppTypography.blockHeaderStyle,
      _ => AppTypography.blockHeaderStyle.copyWith(fontSize: 12),
    };

    return TextField(
      controller: _controller,
      style: style,
      decoration: AppTypography.noteInputDecoration(hint: widget.hint),
      onChanged: (value) => widget.onChanged({
        ...widget.block.content,
        'text': value,
      }),
      onTap: _reportAiFocus,
    );
  }
}
