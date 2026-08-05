import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';

import '../../core/l10n/app_strings.dart';
import './adaptive_dialog.dart';
import './app_colors.dart';
import './app_typography.dart';
import './dialog_metrics.dart';
import './dialog_field_style.dart';

/// Full-spectrum colour picker used by topic theme, text colour, graphs, etc.
///
/// Returns `#RRGGBB`, or null if cancelled. Preset swatches are shortcuts;
/// the HSV area is the wide spectrum.
Future<String?> showAppColorDialog({
  required BuildContext context,
  required AppStrings strings,
  required String selectedHex,
  List<String> presetHexes = const [],
}) {
  return showAppDialog<String>(
    context: context,
    builder: (ctx) => _AppColorDialog(
      strings: strings,
      initialHex: selectedHex,
      presetHexes: presetHexes,
    ),
  );
}

class _AppColorDialog extends StatefulWidget {
  const _AppColorDialog({
    required this.strings,
    required this.initialHex,
    required this.presetHexes,
  });

  final AppStrings strings;
  final String initialHex;
  final List<String> presetHexes;

  @override
  State<_AppColorDialog> createState() => _AppColorDialogState();
}

class _AppColorDialogState extends State<_AppColorDialog> {
  late Color _color;
  late final TextEditingController _hexController;

  @override
  void initState() {
    super.initState();
    _color = AppColors.colorFromHex(widget.initialHex);
    _hexController = TextEditingController(text: AppColors.colorToHex(_color));
  }

  @override
  void dispose() {
    _hexController.dispose();
    super.dispose();
  }

  void _setColor(Color color, {bool syncHexField = true}) {
    setState(() => _color = color);
    if (syncHexField) {
      final hex = AppColors.colorToHex(color);
      if (_hexController.text.toUpperCase() != hex) {
        _hexController.value = TextEditingValue(
          text: hex,
          selection: TextSelection.collapsed(offset: hex.length),
        );
      }
    }
  }

  void _onHexSubmitted(String raw) {
    final parsed = AppColors.tryParseHex(raw);
    if (parsed != null) _setColor(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return AppAdaptiveDialogShell(
      title: Text(s['chooseColor']),
      width: AppDialogMetrics.wideWidth,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(s['cancel']),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, AppColors.colorToHex(_color)),
          child: Text(s['choose']),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.presetHexes.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in widget.presetHexes)
                  _PresetSwatch(
                    color: AppColors.colorFromHex(hex),
                    selected: AppColors.colorToHex(_color) ==
                        AppColors.normalizeHex(hex),
                    onTap: () => _setColor(AppColors.colorFromHex(hex)),
                  ),
              ],
            ),
            const SizedBox(height: DialogFieldStyle.fieldGap),
          ],
          // Portrait stack + LTR: the package's landscape Row overflows in a
          // narrow dialog, and RTL mirrors the HSV area incorrectly.
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth.clamp(200.0, 320.0);
              return Directionality(
                textDirection: TextDirection.ltr,
                child: ColorPicker(
                  pickerColor: _color,
                  onColorChanged: _setColor,
                  enableAlpha: false,
                  displayThumbColor: true,
                  hexInputBar: false,
                  labelTypes: const [],
                  portraitOnly: true,
                  colorPickerWidth: width,
                  pickerAreaHeightPercent: 0.72,
                  paletteType: PaletteType.hsvWithHue,
                  pickerAreaBorderRadius: BorderRadius.circular(8),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _color,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: AppColors.noteBorder.withValues(alpha: 0.7),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _hexController,
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.text,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Hex',
                    labelStyle: AppTypography.metaStyle,
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  onChanged: _onHexSubmitted,
                  onSubmitted: _onHexSubmitted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? AppColors.text.withValues(alpha: 0.55)
                : AppColors.noteTop.withValues(alpha: 0.85),
            width: selected ? 1.4 : 0.8,
          ),
        ),
      ),
    );
  }
}
