import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
///
/// Keyboard: Tab walks presets → spectrum → hex → buttons. Arrows move inside
/// the focused pane. Enter chooses.
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
  final _presetsFocus = FocusNode(debugLabel: 'color-presets');
  final _spectrumFocus = FocusNode(debugLabel: 'color-spectrum');
  final _hexFocus = FocusNode(debugLabel: 'color-hex');
  final _presetsKey = GlobalKey();
  var _presetIndex = -1;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _color = AppColors.colorFromHex(widget.initialHex);
    _hexController = TextEditingController(text: AppColors.colorToHex(_color));
    _presetIndex = _indexOfHex(AppColors.colorToHex(_color));
    _presetsFocus.addListener(_onFocusChanged);
    _spectrumFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _presetsFocus.removeListener(_onFocusChanged);
    _spectrumFocus.removeListener(_onFocusChanged);
    _presetsFocus.dispose();
    _spectrumFocus.dispose();
    _hexFocus.dispose();
    _hexController.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  int _indexOfHex(String hex) {
    for (var i = 0; i < widget.presetHexes.length; i++) {
      if (AppColors.normalizeHex(widget.presetHexes[i]) == hex) return i;
    }
    return -1;
  }

  void _setColor(Color color, {bool syncHexField = true}) {
    setState(() {
      _color = color;
      _presetIndex = _indexOfHex(AppColors.colorToHex(color));
    });
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

  void _confirm() {
    if (_closing) return;
    _closing = true;
    _onHexSubmitted(_hexController.text);
    Navigator.pop(context, AppColors.colorToHex(_color));
  }

  void _applyPresetAt(int index) {
    if (index < 0 || index >= widget.presetHexes.length) return;
    _presetIndex = index;
    _setColor(AppColors.colorFromHex(widget.presetHexes[index]));
  }

  int _presetColumns() {
    final box = _presetsKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return 8;
    const swatch = 26.0;
    const spacing = 8.0;
    return math.max(
      1,
      ((box.size.width + spacing) / (swatch + spacing)).floor(),
    );
  }

  KeyEventResult _onPresetsKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final n = widget.presetHexes.length;
    if (n == 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final columns = _presetColumns();

    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowLeft) {
      final visualLeft = key == LogicalKeyboardKey.arrowLeft;
      final dx = visualLeft ? -1 : 1;
      if (_presetIndex < 0) {
        _applyPresetAt(dx > 0 ? 0 : n - 1);
      } else {
        _applyPresetAt((_presetIndex + dx + n) % n);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      final index = _presetIndex < 0 ? 0 : _presetIndex;
      final next = index + columns;
      if (next >= n) {
        _spectrumFocus.requestFocus();
      } else {
        _applyPresetAt(next);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      if (_presetIndex < 0) {
        _applyPresetAt(0);
      } else if (_presetIndex >= columns) {
        _applyPresetAt(_presetIndex - columns);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _applyPresetAt(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _applyPresetAt(n - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _onSpectrumKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    final shift = HardwareKeyboard.instance.isShiftPressed;
    const hueStep = 4.0;
    const satStep = 0.04;
    const valStep = 0.04;

    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowRight) {
      final sign = key == LogicalKeyboardKey.arrowRight ? 1.0 : -1.0;
      if (shift) {
        _nudgeHsv(ds: sign * satStep);
      } else {
        _nudgeHsv(dh: sign * hueStep);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _nudgeHsv(dv: valStep);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _nudgeHsv(dv: -valStep);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _nudgeHsv({double dh = 0, double ds = 0, double dv = 0}) {
    final hsv = HSVColor.fromColor(_color);
    var hue = (hsv.hue + dh) % 360;
    if (hue < 0) hue += 360;
    _setColor(
      hsv
          .withHue(hue)
          .withSaturation((hsv.saturation + ds).clamp(0.0, 1.0))
          .withValue((hsv.value + dv).clamp(0.0, 1.0))
          .toColor(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.strings;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _confirm,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _confirm,
      },
      child: AppAdaptiveDialogShell(
        title: Text(s['chooseColor']),
        width: AppDialogMetrics.wideWidth,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s['cancel']),
          ),
          TextButton(onPressed: _confirm, child: Text(s['choose'])),
        ],
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.presetHexes.isNotEmpty) ...[
              Focus(
                focusNode: _presetsFocus,
                autofocus: true,
                onKeyEvent: _onPresetsKey,
                child: ExcludeFocus(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    padding: const EdgeInsets.all(4),
                    decoration: DialogFieldStyle.paneFocusDecoration(
                      focused: _presetsFocus.hasFocus,
                    ),
                    child: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Wrap(
                      key: _presetsKey,
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < widget.presetHexes.length; i++)
                          _PresetSwatch(
                            color: AppColors.colorFromHex(
                              widget.presetHexes[i],
                            ),
                            selected:
                                AppColors.colorToHex(_color) ==
                                AppColors.normalizeHex(widget.presetHexes[i]),
                            keyboardFocused:
                                _presetsFocus.hasFocus && i == _presetIndex,
                            onTap: () {
                              _presetsFocus.requestFocus();
                              _applyPresetAt(i);
                            },
                          ),
                      ],
                    ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DialogFieldStyle.fieldGap),
            ],
            // Portrait stack + LTR: the package's landscape Row overflows in a
            // narrow dialog, and RTL mirrors the HSV area incorrectly.
            Focus(
              focusNode: _spectrumFocus,
              autofocus: widget.presetHexes.isEmpty,
              onKeyEvent: _onSpectrumKey,
              child: Listener(
                onPointerDown: (_) => _spectrumFocus.requestFocus(),
                child: ExcludeFocus(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    padding: const EdgeInsets.all(4),
                    decoration: DialogFieldStyle.paneFocusDecoration(
                      focused: _spectrumFocus.hasFocus,
                    ),
                    child: LayoutBuilder(
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
                  ),
                ),
              ),
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
                    focusNode: _hexFocus,
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
                    onSubmitted: (_) => _confirm(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DialogKeyboardHint(s['colorPickerKeyboardHint']),
          ],
        ),
      ),
    );
  }
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.keyboardFocused,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final bool keyboardFocused;
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
            color: keyboardFocused
                ? AppColors.primary.withValues(alpha: 0.7)
                : selected
                ? AppColors.text.withValues(alpha: 0.55)
                : AppColors.noteTop.withValues(alpha: 0.85),
            width: keyboardFocused || selected ? 1.4 : 0.8,
          ),
        ),
      ),
    );
  }
}
