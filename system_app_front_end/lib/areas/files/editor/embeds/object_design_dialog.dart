import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/l10n/app_strings.dart';
import '../../../ui/adaptive_dialog.dart';
import '../../../ui/app_color_palettes.dart';
import '../../../ui/app_colors.dart';
import '../../../ui/bilingual_layout.dart';
import '../../../ui/dialog_field_style.dart';
import '../../../ui/dialog_metrics.dart';
import '../../../ui/object_look_preview.dart';
import './object_look.dart';
import './table_chart.dart';

/// Design of an in-file object: look samples, and for graphs the chart type
/// and colour set. Taps apply immediately; Done / Escape closes.
Future<void> showObjectDesignDialog({
  required BuildContext context,
  required AppStrings strings,
  required String kind,
  required String look,
  required ValueChanged<String> onLook,
  bool isChart = false,
  String chartType = 'bar',
  ValueChanged<String>? onChartType,
  String? paletteId,
  ValueChanged<String>? onPalette,
  bool greyscale = false,
  ValueChanged<bool>? onGreyscale,
}) {
  return showAppDialog<void>(
    context: context,
    builder: (ctx) => _ObjectDesignDialog(
      strings: strings,
      kind: kind,
      look: look,
      onLook: onLook,
      isChart: isChart,
      chartType: chartType,
      onChartType: onChartType,
      paletteId: paletteId,
      onPalette: onPalette,
      greyscale: greyscale,
      onGreyscale: onGreyscale,
    ),
  );
}

class _ObjectDesignDialog extends StatefulWidget {
  const _ObjectDesignDialog({
    required this.strings,
    required this.kind,
    required this.look,
    required this.onLook,
    required this.isChart,
    required this.chartType,
    required this.onChartType,
    required this.paletteId,
    required this.onPalette,
    required this.greyscale,
    required this.onGreyscale,
  });

  final AppStrings strings;
  final String kind;
  final String look;
  final ValueChanged<String> onLook;
  final bool isChart;
  final String chartType;
  final ValueChanged<String>? onChartType;
  final String? paletteId;
  final ValueChanged<String>? onPalette;
  final bool greyscale;
  final ValueChanged<bool>? onGreyscale;

  @override
  State<_ObjectDesignDialog> createState() => _ObjectDesignDialogState();
}

class _ObjectDesignDialogState extends State<_ObjectDesignDialog> {
  late String _look;
  late String _chartType;
  late String? _paletteId;
  late bool _greyscale;

  static const _chartTypes = ['bar', 'line', 'pie'];
  static const _sampleValues = [3.0, 5.0, 2.0, 4.0];

  @override
  void initState() {
    super.initState();
    _look = ObjectLook.canonical(widget.kind, widget.look);
    _chartType = widget.chartType;
    _paletteId = widget.paletteId ?? AppColorPalettes.defaultChart.id;
    _greyscale = widget.greyscale;
  }

  List<Color> get _sampleColors {
    final palette =
        AppColorPalettes.byId(_paletteId ?? '') ??
        AppColorPalettes.defaultChart;
    return [
      for (final hex in palette.colorsForCount(_sampleValues.length))
        AppColors.colorFromHex(hex),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.pop(context),
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            Navigator.pop(context),
      },
      child: Focus(
        autofocus: true,
        child: AppAdaptiveDialogShell(
          title: Text(s['design']),
          width: AppDialogMetrics.wideWidth,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(s['arrangeDone']),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AppDialogField(
                label: s['look'],
                child: _SampleWrap(
                  children: [
                    for (final look in ObjectLook.looksFor(widget.kind))
                      _SampleTile(
                        selected: _look == look,
                        label: s[ObjectLook.labelKey(widget.kind, look)],
                        onTap: () {
                          setState(() => _look = look);
                          widget.onLook(look);
                        },
                        child: ObjectLookPreview(
                          lookId: look,
                          kind: widget.kind,
                          selected: _look == look,
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.kind == 'image' && widget.onGreyscale != null) ...[
                const SizedBox(height: DialogFieldStyle.fieldGap),
                AppDialogField(
                  label: s['lookGreyscale'],
                  child: _SampleWrap(
                    children: [
                      _SampleTile(
                        selected: !_greyscale,
                        label: s['lookNone'],
                        onTap: () {
                          setState(() => _greyscale = false);
                          widget.onGreyscale!(false);
                        },
                        child: ObjectLookPreview(
                          lookId: _look,
                          kind: 'image',
                          selected: !_greyscale,
                        ),
                      ),
                      _SampleTile(
                        selected: _greyscale,
                        label: s['lookGreyscale'],
                        onTap: () {
                          setState(() => _greyscale = true);
                          widget.onGreyscale!(true);
                        },
                        child: ColorFiltered(
                          colorFilter: ObjectLook.greyscaleFilter,
                          child: ObjectLookPreview(
                            lookId: _look,
                            kind: 'image',
                            selected: _greyscale,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (widget.isChart) ...[
                const SizedBox(height: DialogFieldStyle.fieldGap),
                AppDialogField(
                  label: s['graphType'],
                  child: _SampleWrap(
                    children: [
                      for (final type in _chartTypes)
                        _SampleTile(
                          selected: _chartType == type,
                          label: s[_chartLabel(type)],
                          onTap: () {
                            setState(() => _chartType = type);
                            widget.onChartType?.call(type);
                          },
                          child: SizedBox(
                            width: 64,
                            height: 36,
                            child: IgnorePointer(
                              child: TableChartView(
                                type: type,
                                values: _sampleValues,
                                labels: const ['', '', '', ''],
                                colors: _sampleColors,
                                textDirection: Directionality.of(context),
                                height: 36,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: DialogFieldStyle.fieldGap),
                AppDialogField(
                  label: s['graphChangeColors'],
                  child: Column(
                    children: [
                      for (final palette in AppColorPalettes.chart) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: _PaletteRow(
                            selected: _paletteId == palette.id,
                            label: s[palette.nameKey],
                            hexes: palette.hexes,
                            onTap: () {
                              setState(() => _paletteId = palette.id);
                              widget.onPalette?.call(palette.id);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _chartLabel(String type) => switch (type) {
    'line' => 'graphLine',
    'pie' => 'graphPie',
    _ => 'graphBar',
  };
}

class _SampleWrap extends StatelessWidget {
  const _SampleWrap({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 6, runSpacing: 6, children: children);
  }
}

class _SampleTile extends StatelessWidget {
  const _SampleTile({
    required this.selected,
    required this.label,
    required this.onTap,
    required this.child,
  });

  final bool selected;
  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                child,
                const SizedBox(height: 3),
                SizedBox(
                  width: 64,
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DialogFieldStyle.labelStyle.copyWith(
                      color: selected
                          ? AppColors.primaryBright.withValues(alpha: 0.96)
                          : AppColors.text.withValues(alpha: 0.68),
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteRow extends StatelessWidget {
  const _PaletteRow({
    required this.selected,
    required this.label,
    required this.hexes,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final List<String> hexes;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: StartTrailingRow(
            gap: 8,
            crossAxisAlignment: CrossAxisAlignment.center,
            content: Text(
              label,
              style: DialogFieldStyle.labelStyle.copyWith(
                color: selected
                    ? AppColors.primaryBright.withValues(alpha: 0.96)
                    : AppColors.text.withValues(alpha: 0.78),
              ),
            ),
            trailing: SizedBox(
              width: 118,
              child: PalettePreview(hexes: hexes, selected: selected),
            ),
          ),
        ),
      ),
    );
  }
}
