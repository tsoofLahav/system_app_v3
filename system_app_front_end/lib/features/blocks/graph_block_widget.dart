import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/models/block.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';

class GraphBlockWidget extends StatelessWidget {
  const GraphBlockWidget({
    super.key,
    required this.block,
    required this.emptyLabel,
  });

  final Block block;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final chartType = block.content['chart_type'] as String? ?? 'bar';
    final title = block.content['title']?.toString() ?? '';
    final labels = [
      for (final l in (block.content['labels'] as List?) ?? const [])
        l.toString(),
    ];
    final values = [
      for (final v in (block.content['values'] as List?) ?? const [])
        (v as num?)?.toDouble() ?? 0,
    ];

    if (labels.isEmpty || values.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: AppColors.noteBorder),
          borderRadius: BorderRadius.circular(8),
          color: AppColors.noteBottom.withValues(alpha: 0.45),
        ),
        child: Text(emptyLabel, style: AppTypography.metaStyle),
      );
    }

    final count = labels.length < values.length ? labels.length : values.length;
    final safeLabels = labels.sublist(0, count);
    final safeValues = values.sublist(0, count);

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
            child: switch (chartType) {
              'line' => _lineChart(safeLabels, safeValues),
              'pie' => _pieChart(safeLabels, safeValues),
              _ => _barChart(safeLabels, safeValues),
            },
          ),
        ],
      ),
    );
  }

  Widget _barChart(List<String> labels, List<double> values) {
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Text(
                  labels[i],
                  style: AppTypography.metaStyle.copyWith(fontSize: 10),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  color: AppColors.text.withValues(alpha: 0.55),
                  width: 14,
                  borderRadius: BorderRadius.circular(2),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _lineChart(List<String> labels, List<double> values) {
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (v, _) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Text(
                  labels[i],
                  style: AppTypography.metaStyle.copyWith(fontSize: 10),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i]),
            ],
            isCurved: true,
            color: AppColors.text.withValues(alpha: 0.65),
            barWidth: 2,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }

  Widget _pieChart(List<String> labels, List<double> values) {
    final total = values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) {
      return Center(child: Text(emptyLabel, style: AppTypography.metaStyle));
    }
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < values.length; i++) {
      final share = values[i] / total * 100;
      sections.add(
        PieChartSectionData(
          value: share,
          title: labels[i],
          color: AppColors.text.withValues(alpha: 0.25 + (i % 4) * 0.15),
          radius: 52,
          titleStyle: AppTypography.metaStyle.copyWith(fontSize: 9),
        ),
      );
    }
    return PieChart(PieChartData(sections: sections, sectionsSpace: 1));
  }
}
