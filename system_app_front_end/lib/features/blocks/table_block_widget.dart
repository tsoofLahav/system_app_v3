import 'package:flutter/material.dart';

import '../../core/models/block.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import 'block_text_focus.dart';
import 'formatted_text_field.dart';

class TableBlockWidget extends StatelessWidget {
  const TableBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;

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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.noteBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            for (var rowIndex = 0; rowIndex < paddedRows.length; rowIndex++)
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
              ),
          ],
        ),
      ),
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
  const _TableCell({super.key, required this.text, required this.onChanged});

  final String text;
  final ValueChanged<String> onChanged;

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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.noteBorder),
          bottom: BorderSide(color: AppColors.noteBorder),
        ),
      ),
      child: Align(
        alignment: Alignment.topLeft,
        child: FormattedTextField(
          controller: _controller,
          style: AppTypography.noteBodyStyle,
          maxLines: null,
          minLines: 1,
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}
