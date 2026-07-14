import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../design_system/app_typography.dart';
import '../../core/models/block.dart';
import 'block_text_focus.dart';
import 'formatted_text_field.dart';
import 'rich_text_block_sync.dart';
import 'span_text_editing_controller.dart';
import 'text_formatting.dart';

class HeaderBlockWidget extends StatefulWidget {
  const HeaderBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.hint = 'Header',
    this.aiState,
    this.aiFileId,
    this.hasContentAbove = false,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String hint;
  final AppState? aiState;
  final int? aiFileId;
  final bool hasContentAbove;

  @override
  State<HeaderBlockWidget> createState() => _HeaderBlockWidgetState();
}

class _HeaderBlockWidgetState extends State<HeaderBlockWidget> {
  late final SpanTextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final rich = richContentFromBlock(widget.block.content);
    _controller = SpanTextEditingController(text: rich.text, spans: rich.spans);
    _controller.addListener(_reportAiFocus);
  }

  @override
  void didUpdateWidget(HeaderBlockWidget oldWidget) {
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
    BlockTextFocusRegistry.unregister(_controller);
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
    final level = widget.block.content['level'] as int? ?? 2;
    final style = switch (level) {
      1 => AppTypography.blockHeaderStyle.copyWith(fontSize: 15),
      2 => AppTypography.blockHeaderStyle,
      _ => AppTypography.blockHeaderStyle.copyWith(fontSize: 12),
    };

    return Padding(
      padding: EdgeInsets.only(top: widget.hasContentAbove ? 16 : 0),
      child: FormattedTextField(
        controller: _controller,
        focusNode: _focusNode,
        style: style,
        blockContent: widget.block.content,
        hintText: widget.hint,
        onChanged: (_) {
          _reportAiFocus();
          _emit();
        },
      ),
    );
  }
}
