import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/block.dart';
import '../../design_system/app_typography.dart';
import 'connected_lines_editor.dart';
import 'list_text_parse.dart';

class PointsListBlockWidget extends StatelessWidget {
  const PointsListBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = _itemsFrom(block.content['items']);
    final listStyle = block.content['list_style'] as String? ?? 'bullet';
    final numbered = listStyle == 'numbered';

    return ConnectedLinesEditor(
      lines: items,
      style: AppTypography.listItemStyle,
      gutterLabelBuilder: (index) => numbered ? '${index + 1}.' : '•',
      onCopyAll: () {
        Clipboard.setData(ClipboardData(text: serializeListLines(items)));
      },
      onLinesChanged: (lines) {
        onChanged({
          ...block.content,
          'items': _toContentItems(lines),
          'list_style': listStyle,
        });
      },
    );
  }

  static List<String> _itemsFrom(Object? value) {
    if (value is! List || value.isEmpty) return [''];
    final lines = [
      for (final item in value)
        if (item is Map)
          item['text']?.toString() ?? ''
        else
          item?.toString() ?? '',
    ];
    final nonEmpty = [for (final line in lines) if (line.trim().isNotEmpty) line];
    return nonEmpty.isEmpty ? [''] : nonEmpty;
  }

  static List<Map<String, dynamic>> _toContentItems(List<String> items) => [
    for (final item in items) {'text': item},
  ];
}
