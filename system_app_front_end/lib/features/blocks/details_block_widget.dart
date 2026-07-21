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

class DetailsBlockWidget extends StatefulWidget {
  const DetailsBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.aiState,
    this.aiFileId,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final AppState? aiState;
  final int? aiFileId;

  @override
  State<DetailsBlockWidget> createState() => _DetailsBlockWidgetState();
}

class _DetailsBlockWidgetState extends State<DetailsBlockWidget> {
  late final TextEditingController _titleController;
  late final SpanTextEditingController _bodyController;
  final _titleFocus = FocusNode();
  final _bodyFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    final content = widget.block.content;
    _titleController = TextEditingController(
      text: content['title']?.toString() ?? '',
    );
    final rich = richContentFromBlock(content);
    _bodyController = SpanTextEditingController(
      text: rich.text,
      spans: rich.spans,
    );
    _bodyController.addListener(_reportAiFocus);
  }

  @override
  void didUpdateWidget(DetailsBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final content = widget.block.content;
    final nextTitle = content['title']?.toString() ?? '';
    if (!_titleFocus.hasFocus && _titleController.text != nextTitle) {
      _titleController.text = nextTitle;
    }
    if (_bodyFocus.hasFocus ||
        BlockTextFocusRegistry.isInMenuSession ||
        BlockTextFocusRegistry.activeController == _bodyController) {
      return;
    }
    syncRichControllerFromBlockIfIdle(
      focusNode: _bodyFocus,
      blockContent: content,
      controller: _bodyController,
    );
  }

  @override
  void dispose() {
    _bodyController.removeListener(_reportAiFocus);
    _titleController.dispose();
    _bodyController.dispose();
    _titleFocus.dispose();
    _bodyFocus.dispose();
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
        fullText: _bodyController.text,
        selection: _bodyController.selection,
      ),
    );
  }

  void _emit() {
    widget.onChanged({
      ...widget.block.content,
      'title': _titleController.text,
      ..._bodyController.contentPatch(_bodyController.text),
    });
  }

  String get insertText {
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    if (title.isEmpty) return body;
    if (body.isEmpty) return title;
    return '$title\n$body';
  }

  @override
  Widget build(BuildContext context) {
    final strings = widget.aiState?.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _titleController,
          focusNode: _titleFocus,
          style: AppTypography.listItemStyle.copyWith(
            fontWeight: FontWeight.w600,
          ),
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: strings?['detailsTitleHint'] ?? 'Details title',
            hintStyle: AppTypography.listItemStyle.copyWith(
              color: AppTypography.listItemStyle.color?.withValues(alpha: 0.35),
              fontWeight: FontWeight.w600,
            ),
            contentPadding: const EdgeInsets.only(bottom: 4),
          ),
          onChanged: (_) => _emit(),
        ),
        FormattedTextField(
          controller: _bodyController,
          focusNode: _bodyFocus,
          style: AppTypography.noteBodyStyle,
          blockContent: widget.block.content,
          hintText: strings?['detailsBodyHint'] ?? 'Details text…',
          maxLines: null,
          emojiSearchHint: strings?['searchEmoji'] ?? 'Search emoji',
          emojiPickerTitle: strings?['insertEmoji'] ?? 'Insert emoji…',
          onChanged: (_) {
            _reportAiFocus();
            _emit();
          },
        ),
      ],
    );
  }
}
