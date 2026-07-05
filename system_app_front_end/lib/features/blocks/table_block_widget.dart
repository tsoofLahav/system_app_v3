import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/block.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import 'block_text_focus.dart';
import 'formatted_text_field.dart';

typedef TableCellSecondaryTapCallback =
    void Function(Offset globalPosition, int rowIndex, int columnIndex);

class TableBlockWidget extends StatefulWidget {
  const TableBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.onCellSecondaryTapDown,
  });

  static const double minColumnWidth = 104;
  static const double maxColumnWidth = 280;

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final TableCellSecondaryTapCallback? onCellSecondaryTapDown;

  @override
  State<TableBlockWidget> createState() => _TableBlockWidgetState();
}

class _TableBlockWidgetState extends State<TableBlockWidget> {
  final _horizontalScrollController = ScrollController();

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final rows = _normalizedRows(block.content['rows']);
    final columnCount = rows
        .map((r) => r.length)
        .fold<int>(2, (a, b) => a > b ? a : b);
    final paddedRows = [
      for (final row in rows)
        [...row, for (var i = row.length; i < columnCount; i++) ''],
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final columnWidths = _resolveColumnWidths(
          paddedRows,
          columnCount,
          availableWidth,
        );
        final tableWidth = columnWidths.fold(0.0, (sum, width) => sum + width);
        final needsHorizontalScroll = tableWidth > availableWidth + 0.5;

        final table = Table(
          border: TableBorder.all(color: AppColors.noteBorder),
          columnWidths: {
            for (var i = 0; i < columnCount; i++)
              i: FixedColumnWidth(columnWidths[i]),
          },
          defaultVerticalAlignment: TableCellVerticalAlignment.top,
          children: [
            for (var rowIndex = 0; rowIndex < paddedRows.length; rowIndex++)
              TableRow(
                children: [
                  for (
                    var columnIndex = 0;
                    columnIndex < columnCount;
                    columnIndex++
                  )
                    _TableCell(
                      key: ValueKey('${block.id}-$rowIndex-$columnIndex'),
                      blockId: block.id,
                      text: paddedRows[rowIndex][columnIndex],
                      onChanged: (value) {
                        final next = _copyRows(paddedRows);
                        next[rowIndex][columnIndex] = value;
                        widget.onChanged({...block.content, 'rows': next});
                      },
                      onSecondaryTapDown: widget.onCellSecondaryTapDown == null
                          ? null
                          : (position) => widget.onCellSecondaryTapDown!(
                              position,
                              rowIndex,
                              columnIndex,
                            ),
                    ),
                ],
              ),
          ],
        );

        final framedTable = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: table,
        );

        if (needsHorizontalScroll) {
          return Scrollbar(
            controller: _horizontalScrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _horizontalScrollController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: framedTable,
              ),
            ),
          );
        }

        return SizedBox(
          width: availableWidth,
          child: framedTable,
        );
      },
    );
  }

  static List<double> _resolveColumnWidths(
    List<List<String>> rows,
    int columnCount,
    double availableWidth,
  ) {
    final preferred = List<double>.generate(
      columnCount,
      (columnIndex) => _columnPreferredWidth(rows, columnIndex),
    );
    final preferredTotal = preferred.fold(0.0, (sum, width) => sum + width);

    if (preferredTotal <= availableWidth) {
      final scale = availableWidth / preferredTotal;
      return [for (final width in preferred) width * scale];
    }

    return preferred;
  }

  static double _columnPreferredWidth(List<List<String>> rows, int columnIndex) {
    var longestChars = 0;
    for (final row in rows) {
      if (columnIndex >= row.length) continue;
      longestChars = math.max(longestChars, row[columnIndex].trim().length);
    }

    if (longestChars == 0) {
      return TableBlockWidget.minColumnWidth;
    }

    // Rough width estimate for wrapped note text; capped so very long cells scroll
    // instead of forcing other columns below the minimum.
    const charWidth = 6.5;
    const horizontalPadding = 16.0;
    final contentWidth = longestChars * charWidth + horizontalPadding;
    return contentWidth.clamp(
      TableBlockWidget.minColumnWidth,
      TableBlockWidget.maxColumnWidth,
    );
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

class _TableCell extends StatefulWidget {
  const _TableCell({
    super.key,
    required this.blockId,
    required this.text,
    required this.onChanged,
    this.onSecondaryTapDown,
  });

  final int blockId;
  final String text;
  final ValueChanged<String> onChanged;
  final void Function(Offset globalPosition)? onSecondaryTapDown;

  @override
  State<_TableCell> createState() => _TableCellState();
}

class _TableCellState extends State<_TableCell> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
    _controller.addListener(_registerFocus);
  }

  @override
  void didUpdateWidget(_TableCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text && _controller.text != widget.text) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_registerFocus);
    _controller.dispose();
    super.dispose();
  }

  void _registerFocus() {
    BlockTextFocusRegistry.register(
      controller: _controller,
      changed: () => widget.onChanged(_controller.text),
      blockId: widget.blockId,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: FormattedTextField(
        controller: _controller,
        blockId: widget.blockId,
        style: AppTypography.noteBodyStyle,
        maxLines: null,
        minLines: 1,
        onChanged: widget.onChanged,
        onSecondaryTapDown: widget.onSecondaryTapDown == null
            ? null
            : (details) => widget.onSecondaryTapDown!(details.globalPosition),
      ),
    );
  }
}
