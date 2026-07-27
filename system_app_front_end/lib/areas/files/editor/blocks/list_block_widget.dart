import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_typography.dart';
import '../../model/document_codec.dart';
import '../../model/document_model.dart';

class ListBlockWidget extends StatefulWidget {
  const ListBlockWidget({
    super.key,
    required this.node,
    required this.onChanged,
    this.onConvertToTaskList,
  });

  final ListNode node;
  final ValueChanged<ListNode> onChanged;
  final VoidCallback? onConvertToTaskList;

  @override
  State<ListBlockWidget> createState() => _ListBlockWidgetState();
}

class _ListBlockWidgetState extends State<ListBlockWidget> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _serializeItems());
  }

  @override
  void didUpdateWidget(ListBlockWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.id != widget.node.id) {
      _controller.text = _serializeItems();
    }
  }

  String _serializeItems() {
    final numbered = widget.node.listStyle == 'numbered';
    final lines = <String>[];
    for (var i = 0; i < widget.node.items.length; i++) {
      final item = widget.node.items[i];
      final indent = '  ' * item.indent;
      final prefix = numbered ? '${i + 1}. ' : '- ';
      lines.add('$indent$prefix${item.text}');
    }
    return lines.join('\n');
  }

  void _applyLines(String raw) {
    final numbered = widget.node.listStyle == 'numbered';
    final items = <ListItem>[];
    for (final line in raw.split('\n')) {
      if (line.trim().isEmpty && items.isEmpty) continue;
      final leading = line.length - line.trimLeft().length;
      final indent = leading ~/ 2;
      var text = line.trimLeft();
      if (numbered) {
        text = text.replaceFirst(RegExp(r'^\d+[\.\)]\s*'), '');
      } else {
        text = text.replaceFirst(RegExp(r'^[•\-\*]\s*'), '');
      }
      items.add(
        ListItem(
          id: DocumentCodec.newId('li'),
          text: text,
          indent: indent,
        ),
      );
    }
    if (items.isEmpty) {
      items.add(ListItem(id: DocumentCodec.newId('li'), text: ''));
    }
    widget.onChanged(widget.node.copyWith(items: items));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) async {
        if (widget.onConvertToTaskList == null) return;
        final result = await showMenu<String>(
          context: context,
          position: RelativeRect.fromLTRB(
            details.globalPosition.dx,
            details.globalPosition.dy,
            details.globalPosition.dx,
            details.globalPosition.dy,
          ),
          items: const [
            PopupMenuItem(value: 'task_list', child: Text('Convert to Task list')),
          ],
        );
        if (result == 'task_list') widget.onConvertToTaskList!();
      },
      child: TextField(
        controller: _controller,
        style: AppTypography.listItemStyle,
        maxLines: null,
        decoration: InputDecoration(
          hintText: widget.node.listStyle == 'numbered' ? '1. Item' : '- Item',
          border: InputBorder.none,
          isDense: true,
        ),
        onChanged: _applyLines,
      ),
    );
  }
}
