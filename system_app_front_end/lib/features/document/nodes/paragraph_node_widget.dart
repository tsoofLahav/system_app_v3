import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../../design_system/app_typography.dart';
import '../document_model.dart';
import '../rich_text/block_text_focus.dart';
import '../rich_text/block_text_actions.dart';
import '../rich_text/document_context_menu.dart';
import '../rich_text/formatted_text_field.dart';
import '../rich_text/rich_text_block_sync.dart';
import '../rich_text/span_text_editing_controller.dart';

class ParagraphNodeWidget extends StatefulWidget {
  const ParagraphNodeWidget({
    super.key,
    required this.node,
    required this.state,
    required this.onChanged,
    this.onBackspaceAtStart,
  });

  final ParagraphNode node;
  final AppState state;
  final ValueChanged<ParagraphNode> onChanged;
  final VoidCallback? onBackspaceAtStart;

  @override
  State<ParagraphNodeWidget> createState() => _ParagraphNodeWidgetState();
}

class _ParagraphNodeWidgetState extends State<ParagraphNodeWidget> {
  late final SpanTextEditingController _controller;
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = SpanTextEditingController(
      text: widget.node.text,
      spans: widget.node.spans.map((s) => s.toJson()).toList(),
    );
    _focus.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(ParagraphNodeWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    syncRichControllerFromBlockIfIdle(
      controller: _controller,
      focusNode: _focus,
      blockContent: {
        'text': widget.node.text,
        'spans': widget.node.spans.map((s) => s.toJson()).toList(),
      },
    );
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focus.hasFocus) _commit();
  }

  Map<String, dynamic> _spanToMap(TextSpanMark mark) => mark.toJson();

  List<TextSpanMark> _spansFromController() {
    return [
      for (final span in _controller.spans)
        TextSpanMark.fromJson(Map<String, dynamic>.from(span)),
    ];
  }

  void _commit() {
    widget.onChanged(
      widget.node.copyWith(
        text: _controller.text,
        spans: _spansFromController(),
      ),
    );
  }

  Future<void> _onMenuAction(String action) async {
    await runBlockTextAction(action);
    _commit();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return FormattedTextField(
      controller: _controller,
      focusNode: _focus,
      style: AppTypography.noteBodyStyle,
      hintText: '',
      maxLines: null,
      blockId: null,
      onChanged: (_) => _commit(),
      onBackspaceAtStart: widget.onBackspaceAtStart == null
          ? null
          : () async => widget.onBackspaceAtStart!(),
      onSecondaryTapDown: (details) {
        DocumentContextMenu.showTextMenu(
          context: context,
          globalPosition: details.globalPosition,
          strings: widget.state.strings,
          onAction: _onMenuAction,
        );
      },
    );
  }
}
