import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../design_system/app_typography.dart';
import '../../core/models/block.dart';

class ChecklistBlockWidget extends StatefulWidget {
  const ChecklistBlockWidget({
    super.key,
    required this.block,
    required this.onItemChanged,
    required this.onAddItem,
    this.aiState,
    this.aiFileId,
  });

  final Block block;
  final void Function(int index, String text, bool done) onItemChanged;
  final ValueChanged<int> onAddItem;
  final AppState? aiState;
  final int? aiFileId;

  @override
  State<ChecklistBlockWidget> createState() => _ChecklistBlockWidgetState();
}

class _ChecklistBlockWidgetState extends State<ChecklistBlockWidget> {
  final _focusNodes = <FocusNode>[];
  int? _pendingFocusIndex;

  @override
  void didUpdateWidget(ChecklistBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _requestPendingFocus();
  }

  @override
  void dispose() {
    for (final node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = List<Map<String, dynamic>>.from(
      widget.block.content['items'] as List<dynamic>? ?? [],
    );
    if (items.isEmpty) {
      items.add({'text': '', 'done': false});
    }
    _syncFocusNodes(items.length);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < items.length; i++)
          _ChecklistRow(
            key: ValueKey('${widget.block.id}-$i'),
            focusNode: _focusNodes[i],
            text: items[i]['text'] as String? ?? '',
            done: items[i]['done'] as bool? ?? false,
            onChanged: (text, done) => widget.onItemChanged(i, text, done),
            onSubmitted: () {
              _pendingFocusIndex = i + 1;
              widget.onAddItem(i + 1);
            },
            aiState: widget.aiState,
            aiFileId: widget.aiFileId,
            aiBlockId: widget.block.id,
          ),
      ],
    );
  }

  void _syncFocusNodes(int count) {
    while (_focusNodes.length < count) {
      _focusNodes.add(FocusNode());
    }
    while (_focusNodes.length > count) {
      _focusNodes.removeLast().dispose();
    }
  }

  void _requestPendingFocus() {
    final index = _pendingFocusIndex;
    if (index == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= _focusNodes.length) return;
      _focusNodes[index].requestFocus();
    });
    _pendingFocusIndex = null;
  }
}

class _ChecklistRow extends StatefulWidget {
  const _ChecklistRow({
    super.key,
    required this.focusNode,
    required this.text,
    required this.done,
    required this.onChanged,
    required this.onSubmitted,
    this.aiState,
    this.aiFileId,
    this.aiBlockId,
  });

  final String text;
  final bool done;
  final FocusNode focusNode;
  final void Function(String text, bool done) onChanged;
  final VoidCallback onSubmitted;
  final AppState? aiState;
  final int? aiFileId;
  final int? aiBlockId;

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
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
        blockId: widget.aiBlockId,
        fullText: _controller.text,
        selection: _controller.selection,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Checkbox(
          value: widget.done,
          onChanged: (v) => widget.onChanged(_controller.text, v ?? false),
        ),
        Expanded(
          child: TextField(
            controller: _controller,
            focusNode: widget.focusNode,
            maxLines: 1,
            textInputAction: TextInputAction.next,
            style: AppTypography.noteBodyStyle,
            decoration: AppTypography.noteInputDecoration(),
            onChanged: (v) => widget.onChanged(v, widget.done),
            onSubmitted: (_) {
              widget.onSubmitted();
            },
            onTap: _reportAiFocus,
          ),
        ),
      ],
    );
  }
}
