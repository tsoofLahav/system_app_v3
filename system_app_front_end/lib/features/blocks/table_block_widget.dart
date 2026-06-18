import 'package:flutter/material.dart';

import '../../core/models/block.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';

class TableBlockWidget extends StatelessWidget {
  const TableBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    required this.addRowLabel,
    required this.addColumnLabel,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String addRowLabel;
  final String addColumnLabel;

  @override
  Widget build(BuildContext context) {
    final rows = _normalizedRows(block.content['rows']);
    final columnCount = rows
        .map((r) => r.length)
        .fold<int>(2, (a, b) => a > b ? a : b);
    final paddedRows = [
      for (final row in rows)
        [...row, for (var i = row.length; i < columnCount; i++) ''],
    ];

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: (details) => _showTableMenu(
        context,
        details.globalPosition,
        paddedRows,
        columnCount,
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.noteBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              for (var rowIndex = 0; rowIndex < paddedRows.length; rowIndex++)
                Row(
                  children: [
                    for (
                      var columnIndex = 0;
                      columnIndex < columnCount;
                      columnIndex++
                    )
                      _TableCell(
                        key: ValueKey('${block.id}-$rowIndex-$columnIndex'),
                        text: paddedRows[rowIndex][columnIndex],
                        onChanged: (value) {
                          final next = _copyRows(paddedRows);
                          next[rowIndex][columnIndex] = value;
                          onChanged({...block.content, 'rows': next});
                        },
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTableMenu(
    BuildContext context,
    Offset position,
    List<List<String>> rows,
    int columnCount,
  ) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(position);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        overlay.size.width - localPosition.dx,
        overlay.size.height - localPosition.dy,
      ),
      items: [
        PopupMenuItem(value: 'row', child: Text(addRowLabel)),
        PopupMenuItem(value: 'column', child: Text(addColumnLabel)),
      ],
    );
    if (selected == 'row') {
      final next = _copyRows(rows)
        ..add([for (var i = 0; i < columnCount; i++) '']);
      onChanged({...block.content, 'rows': next});
    } else if (selected == 'column') {
      final next = [
        for (final row in rows) [...row, ''],
      ];
      onChanged({...block.content, 'rows': next});
    }
  }

  static List<List<String>> _normalizedRows(Object? value) {
    if (value is! List || value.isEmpty) {
      return [
        ['', ''],
        ['', ''],
      ];
    }
    return [
      for (final row in value)
        if (row is List)
          [for (final cell in row) cell?.toString() ?? '']
        else if (row is Map)
          [for (final cell in row.values) cell?.toString() ?? '']
        else
          [row.toString()],
    ];
  }

  static List<List<String>> _copyRows(List<List<String>> rows) => [
    for (final row in rows) [...row],
  ];
}

class _TableCell extends StatelessWidget {
  const _TableCell({super.key, required this.text, required this.onChanged});

  final String text;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      constraints: const BoxConstraints(minHeight: 38),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.noteBorder),
          bottom: BorderSide(color: AppColors.noteBorder),
        ),
      ),
      child: TextFormField(
        initialValue: text,
        maxLines: null,
        style: AppTypography.noteBodyStyle,
        decoration: AppTypography.noteInputDecoration(),
        onChanged: onChanged,
      ),
    );
  }
}
