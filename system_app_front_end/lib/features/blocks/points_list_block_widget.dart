import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/models/block.dart';
import '../../design_system/app_colors.dart';
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
    final currentIndexes = _currentIndexes(block.content['items']);
    final listStyle = block.content['list_style'] as String? ?? 'bullet';
    final numbered = listStyle == 'numbered';

    return ConnectedLinesEditor(
      lines: items,
      style: AppTypography.listItemStyle,
      accessoryWidth: currentIndexes.isEmpty ? 0 : 20,
      lineAccessoryBuilder: currentIndexes.isEmpty
          ? null
          : (context, index) {
              if (!currentIndexes.contains(index)) {
                return const SizedBox.shrink();
              }
              return Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.78),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              );
            },
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
    return [
      for (final item in value)
        if (item is Map)
          item['text']?.toString() ?? ''
        else
          item?.toString() ?? '',
    ];
  }

  static Set<int> _currentIndexes(Object? value) {
    if (value is! List || value.isEmpty) return {};
    final indexes = <int>{};
    for (var i = 0; i < value.length; i++) {
      final item = value[i];
      if (item is Map && item['is_current_part'] == true) {
        indexes.add(i);
      }
    }
    return indexes;
  }

  static List<Map<String, dynamic>> _toContentItems(List<String> items) => [
    for (final item in items) {'text': item},
  ];
}
