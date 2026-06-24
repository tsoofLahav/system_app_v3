import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/models/block.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import 'graph_content.dart';

class GraphBlockWidget extends StatelessWidget {
  const GraphBlockWidget({
    super.key,
    required this.block,
    required this.onChanged,
    this.emptyLabel = '',
  });

  final Block block;
  final ValueChanged<Map<String, dynamic>> onChanged;
  final String emptyLabel;

  void _emit({
    List<String>? labels,
    List<double>? values,
    String? title,
    String? chartType,
    int? paletteIndex,
  }) {
    final nextLabels = labels ?? graphLabels(block.content);
    final nextValues = values ?? graphValues(block.content, nextLabels.length);
    onChanged({
      ...block.content,
      if (title != null) 'title': title,
      if (chartType != null) 'chart_type': chartType,
      if (paletteIndex != null) 'palette_index': paletteIndex,
      'labels': nextLabels,
      'values': nextValues,
      'colors': null,
    });
  }

  @override
  Widget build(BuildContext context) {
    final chartType = block.content['chart_type'] as String? ?? 'bar';
    final title = block.content['title']?.toString() ?? '';
    final labels = graphLabels(block.content);
    final values = graphValues(block.content, labels.length);
    final colors = graphColumnColors(block.content, labels.length);
    final maxValue = values.fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.noteBorder),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(title, style: AppTypography.blockHeaderStyle),
            ),
          SizedBox(
            height: 180,
            child: maxValue <= 0 && chartType != 'pie'
                ? Center(
                    child: Text(
                      emptyLabel.isEmpty ? ' ' : emptyLabel,
                      style: AppTypography.metaStyle,
                    ),
                  )
                : switch (chartType) {
                    'line' => _lineChart(labels, values, colors),
                    'pie' => _pieChart(labels, values, colors),
                    _ => _barChart(labels, values, colors),
                  },
          ),
          const SizedBox(height: 10),
          _GraphDataGrid(
            labels: labels,
            values: values,
            onLabelChanged: (index, text) {
              final next = [...labels];
              next[index] = text;
              _emit(labels: next, values: values);
            },
            onValueCommitted: (index, text) {
              final next = [...values];
              next[index] = double.tryParse(text.trim()) ?? 0;
              _emit(labels: labels, values: next);
            },
          ),
        ],
      ),
    );
  }

  FlTitlesData _bottomTitles(List<String> labels) {
    return FlTitlesData(
      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
      bottomTitles: AxisTitles(
        sideTitles: SideTitles(
          showTitles: true,
          reservedSize: 22,
          getTitlesWidget: (v, _) {
            final i = v.toInt();
            if (i < 0 || i >= labels.length) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                labels[i],
                style: AppTypography.metaStyle.copyWith(fontSize: 10),
              ),
            );
          },
        ),
      ),
    );
  }

  BarTouchTooltipData _barTooltip(List<String> labels) {
    return BarTouchTooltipData(
      tooltipRoundedRadius: 6,
      tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      tooltipMargin: 6,
      getTooltipColor: (_) => AppColors.noteTop,
      getTooltipItem: (group, groupIndex, rod, rodIndex) {
        final i = group.x.toInt();
        final label = i >= 0 && i < labels.length ? labels[i] : '';
        return BarTooltipItem(
          '$label\n${rod.toY.toStringAsFixed(rod.toY.truncateToDouble() == rod.toY ? 0 : 1)}',
          AppTypography.metaStyle.copyWith(
            color: AppColors.text,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        );
      },
    );
  }

  Widget _barChart(List<String> labels, List<double> values, List<Color> colors) {
    final maxY = values.fold<double>(1, (a, b) => a > b ? a : b) * 1.15;
    return BarChart(
      BarChartData(
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.noteBorder.withValues(alpha: 0.45),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _bottomTitles(labels),
        barTouchData: BarTouchData(touchTooltipData: _barTooltip(labels)),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: colors[i % colors.length],
                  width: 18,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _lineChart(List<String> labels, List<double> values, List<Color> colors) {
    final maxY = values.fold<double>(1, (a, b) => a > b ? a : b) * 1.15;
    final lineColor = colors.isNotEmpty ? colors.first : AppColors.aiCyan;
    return LineChart(
      LineChartData(
        maxY: maxY,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: maxY / 4,
          getDrawingHorizontalLine: (_) => FlLine(
            color: AppColors.noteBorder.withValues(alpha: 0.45),
            strokeWidth: 0.5,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: _bottomTitles(labels),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            tooltipRoundedRadius: 6,
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            getTooltipColor: (_) => AppColors.noteTop,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                LineTooltipItem(
                  labels[spot.x.toInt()],
                  AppTypography.metaStyle.copyWith(
                    color: AppColors.text,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                  children: [
                    TextSpan(
                      text: '\n${spot.y.toStringAsFixed(spot.y.truncateToDouble() == spot.y ? 0 : 1)}',
                      style: AppTypography.metaStyle.copyWith(
                        color: AppColors.textHint,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            color: lineColor.withValues(alpha: 0.85),
            barWidth: 2,
            dotData: FlDotData(
              getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
                radius: 3.5,
                color: colors[spot.x.toInt() % colors.length],
                strokeWidth: 0,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: lineColor.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pieChart(List<String> labels, List<double> values, List<Color> colors) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      return Center(child: Text(emptyLabel, style: AppTypography.metaStyle));
    }
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 24,
        sections: [
          for (var i = 0; i < values.length; i++)
            PieChartSectionData(
              value: values[i],
              title: labels[i],
              color: colors[i % colors.length],
              radius: 52,
              titleStyle: AppTypography.metaStyle.copyWith(
                fontSize: 9,
                color: AppColors.text,
                fontWeight: FontWeight.w500,
              ),
            ),
        ],
      ),
    );
  }
}

class _GraphDataGrid extends StatefulWidget {
  const _GraphDataGrid({
    required this.labels,
    required this.values,
    required this.onLabelChanged,
    required this.onValueCommitted,
  });

  final List<String> labels;
  final List<double> values;
  final void Function(int index, String text) onLabelChanged;
  final void Function(int index, String text) onValueCommitted;

  @override
  State<_GraphDataGrid> createState() => _GraphDataGridState();
}

class _GraphDataGridState extends State<_GraphDataGrid> {
  final _labelFocus = <FocusNode>[];
  final _valueFocus = <FocusNode>[];

  @override
  void initState() {
    super.initState();
    _syncFocusNodes(widget.labels.length);
  }

  @override
  void didUpdateWidget(_GraphDataGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusNodes(widget.labels.length);
  }

  @override
  void dispose() {
    for (final node in _labelFocus) {
      node.dispose();
    }
    for (final node in _valueFocus) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes(int count) {
    while (_labelFocus.length < count) {
      _labelFocus.add(FocusNode());
    }
    while (_valueFocus.length < count) {
      _valueFocus.add(FocusNode());
    }
    while (_labelFocus.length > count) {
      _labelFocus.removeLast().dispose();
    }
    while (_valueFocus.length > count) {
      _valueFocus.removeLast().dispose();
    }
  }

  FocusNode? _nextFocus(int labelIndex, {required bool isLabelRow}) {
    if (isLabelRow) {
      if (labelIndex + 1 < widget.labels.length) {
        return _labelFocus[labelIndex + 1];
      }
      return _valueFocus.isNotEmpty ? _valueFocus.first : null;
    }
    if (labelIndex + 1 < widget.values.length) {
      return _valueFocus[labelIndex + 1];
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.noteBorder.withValues(alpha: 0.7)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.labels.length; i++)
                  Expanded(
                    child: _GraphCell(
                      key: ValueKey('graph-label-${widget.labels.length}-$i'),
                      text: widget.labels[i],
                      focusNode: _labelFocus[i],
                      nextFocus: _nextFocus(i, isLabelRow: true),
                      align: TextAlign.center,
                      style: AppTypography.metaStyle.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                      hint: '—',
                      onChanged: (v) => widget.onLabelChanged(i, v),
                    ),
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.noteBorder.withValues(alpha: 0.7)),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < widget.values.length; i++)
                  Expanded(
                    child: _GraphCell(
                      key: ValueKey('graph-value-${widget.values.length}-$i'),
                      text: _formatValue(widget.values[i]),
                      focusNode: _valueFocus[i],
                      nextFocus: _nextFocus(i, isLabelRow: false),
                      style: AppTypography.noteBodyStyle,
                      align: TextAlign.center,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                      hint: '0',
                      commitOnChange: false,
                      onCommitted: (v) => widget.onValueCommitted(i, v),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatValue(double value) {
    if (value == 0) return '';
    if (value.truncateToDouble() == value) return value.toInt().toString();
    return value.toString();
  }
}

class _GraphCell extends StatefulWidget {
  const _GraphCell({
    super.key,
    required this.text,
    required this.focusNode,
    required this.style,
    this.align = TextAlign.start,
    this.hint = '',
    this.keyboardType,
    this.nextFocus,
    this.onChanged,
    this.onCommitted,
    this.commitOnChange = true,
  });

  final String text;
  final FocusNode focusNode;
  final FocusNode? nextFocus;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onCommitted;
  final bool commitOnChange;
  final TextStyle style;
  final TextAlign align;
  final String hint;
  final TextInputType? keyboardType;

  @override
  State<_GraphCell> createState() => _GraphCellState();
}

class _GraphCellState extends State<_GraphCell> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.text);
  }

  @override
  void didUpdateWidget(_GraphCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.text != _controller.text && !widget.focusNode.hasFocus) {
      _controller.text = widget.text;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _commit({bool moveNext = false}) {
    final text = _controller.text;
    if (widget.commitOnChange) {
      widget.onChanged?.call(text);
    } else {
      widget.onCommitted?.call(text);
    }
    if (moveNext) {
      final next = widget.nextFocus;
      if (next != null) {
        next.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 48),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: AppColors.noteBorder.withValues(alpha: 0.5)),
        ),
      ),
      child: TextField(
        controller: _controller,
        focusNode: widget.focusNode,
        style: widget.style,
        textAlign: widget.align,
        keyboardType: widget.keyboardType,
        textInputAction: widget.nextFocus != null
            ? TextInputAction.next
            : TextInputAction.done,
        decoration: AppTypography.noteInputDecoration(
          hint: widget.hint,
          fontSize: widget.style.fontSize ?? 12,
        ),
        onChanged: widget.commitOnChange ? widget.onChanged : null,
        onSubmitted: (_) => _commit(moveNext: true),
        onEditingComplete: () => _commit(moveNext: false),
      ),
    );
  }
}
