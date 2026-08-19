import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import './app_colors.dart';
import './app_icons.dart';
import './app_typography.dart';
import './dialog_field_style.dart';
import './dialog_metrics.dart';

/// 24-hour dial in a secondary dialog. Prefer [AppCompactTimePicker] when the
/// clock has to sit next to a calendar in the same panel.
Future<TimeOfDay?> showAppTimePicker({
  required BuildContext context,
  required TimeOfDay initialTime,
  String? helpText,
}) {
  return showTimePicker(
    context: context,
    initialTime: initialTime,
    initialEntryMode: TimePickerEntryMode.dial,
    helpText: helpText,
    builder: (context, child) {
      final theme = Theme.of(context);
      return MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: AppColors.primary,
              onPrimary: AppColors.canvasNeutralTop,
              primaryContainer: AppColors.primaryBright,
              onPrimaryContainer: AppColors.text,
            ),
            timePickerTheme: TimePickerThemeData(
              dialHandColor: AppColors.primary,
              hourMinuteColor: AppColors.primaryBright.withValues(alpha: 0.22),
              hourMinuteTextColor: AppColors.text,
              dayPeriodColor: AppColors.primaryBright,
            ),
          ),
          child: child!,
        ),
      );
    },
  );
}

TimeOfDay timeOfDayFromHmm(String raw) {
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
  if (match == null) return const TimeOfDay(hour: 8, minute: 0);
  return TimeOfDay(
    hour: int.parse(match.group(1)!).clamp(0, 23),
    minute: int.parse(match.group(2)!).clamp(0, 59),
  );
}

String hmmFromTimeOfDay(TimeOfDay time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

enum _DialMode { hour, minute }

/// Numbered 24-hour dial with a typed HH:MM field under it — same card size
/// as [AppCompactCalendar], no extra dialog.
class AppCompactTimePicker extends StatefulWidget {
  const AppCompactTimePicker({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;

  @override
  State<AppCompactTimePicker> createState() => _AppCompactTimePickerState();
}

class _AppCompactTimePickerState extends State<AppCompactTimePicker> {
  late final TextEditingController _hour;
  late final TextEditingController _minute;
  late final FocusNode _hourFocus;
  late final FocusNode _minuteFocus;
  var _mode = _DialMode.hour;

  @override
  void initState() {
    super.initState();
    _hour = TextEditingController(text: _two(widget.value.hour));
    _minute = TextEditingController(text: _two(widget.value.minute));
    _hourFocus = FocusNode()
      ..addListener(() {
        if (_hourFocus.hasFocus) setState(() => _mode = _DialMode.hour);
      });
    _minuteFocus = FocusNode()
      ..addListener(() {
        if (_minuteFocus.hasFocus) setState(() => _mode = _DialMode.minute);
      });
  }

  @override
  void didUpdateWidget(AppCompactTimePicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) return;
    if (!_hourFocus.hasFocus) _hour.text = _two(widget.value.hour);
    if (!_minuteFocus.hasFocus) _minute.text = _two(widget.value.minute);
  }

  @override
  void dispose() {
    _hour.dispose();
    _minute.dispose();
    _hourFocus.dispose();
    _minuteFocus.dispose();
    super.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  void _emit(TimeOfDay time) {
    if (time == widget.value) return;
    widget.onChanged(time);
  }

  void _fromFields() {
    final hour = int.tryParse(_hour.text);
    final minute = int.tryParse(_minute.text);
    if (hour == null || minute == null) return;
    if (hour > 23 || minute > 59) return;
    _emit(TimeOfDay(hour: hour, minute: minute));
  }

  void _commitField(TextEditingController controller, int max) {
    final parsed = int.tryParse(controller.text);
    if (parsed == null) {
      controller.text = _two(max == 23 ? widget.value.hour : widget.value.minute);
      return;
    }
    controller.text = _two(parsed.clamp(0, max));
    _fromFields();
  }

  void _fromDial(TimeOfDay time) {
    _hour.text = _two(time.hour);
    _minute.text = _two(time.minute);
    _emit(time);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: AppDialogMetrics.compactPickerCardHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: AppColors.canvasNeutralTop.withValues(alpha: 0.86),
          border: Border.all(
            color: AppColors.noteBorder.withValues(alpha: 0.68),
            width: 0.85,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: DialogFieldStyle.labelStyle.copyWith(
                        fontWeight: AppTypography.titleWeight,
                        color: AppColors.text.withValues(alpha: 0.88),
                      ),
                    ),
                  ),
                  AppIcon(
                    AppIcons.automations,
                    size: 14,
                    color: AppColors.primary.withValues(alpha: 0.82),
                  ),
                ],
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: _HourMinuteDial(
                    time: widget.value,
                    mode: _mode,
                    onChanged: _fromDial,
                    onHourSelected: () =>
                        setState(() => _mode = _DialMode.minute),
                  ),
                ),
              ),
              Directionality(
                // Clock notation stays LTR in Hebrew — hour then minute, not swapped.
                textDirection: TextDirection.ltr,
                child: Row(
                  children: [
                    Expanded(
                      child: _TimePartField(
                        controller: _hour,
                        focusNode: _hourFocus,
                        hint: 'HH',
                        onChanged: _fromFields,
                        onSubmitted: () => _commitField(_hour, 23),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        ':',
                        style: AppTypography.metaStyle.copyWith(
                          fontWeight: AppTypography.titleWeight,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _TimePartField(
                        controller: _minute,
                        focusNode: _minuteFocus,
                        hint: 'MM',
                        onChanged: _fromFields,
                        onSubmitted: () => _commitField(_minute, 59),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimePartField extends StatelessWidget {
  const _TimePartField({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    this.hint,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String? hint;
  final VoidCallback onChanged;
  final VoidCallback onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: TextInputType.number,
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      style: AppTypography.metaStyle.copyWith(
        fontWeight: AppTypography.titleWeight,
      ),
      inputFormatters: [
        FilteringTextInputFormatter.digitsOnly,
        LengthLimitingTextInputFormatter(2),
      ],
      decoration: DialogFieldStyle.decoration(hintText: hint),
      onChanged: (_) => onChanged(),
      onEditingComplete: onSubmitted,
      onTapOutside: (_) => onSubmitted(),
    );
  }
}

class _HourMinuteDial extends StatelessWidget {
  const _HourMinuteDial({
    required this.time,
    required this.mode,
    required this.onChanged,
    required this.onHourSelected,
  });

  final TimeOfDay time;
  final _DialMode mode;
  final ValueChanged<TimeOfDay> onChanged;
  final VoidCallback onHourSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        return Center(
          child: SizedBox.square(
            dimension: size,
            child: _DialSurface(
              time: time,
              mode: mode,
              onChanged: onChanged,
              onHourSelected: onHourSelected,
            ),
          ),
        );
      },
    );
  }
}

class _DialSurface extends StatelessWidget {
  const _DialSurface({
    required this.time,
    required this.mode,
    required this.onChanged,
    required this.onHourSelected,
  });

  final TimeOfDay time;
  final _DialMode mode;
  final ValueChanged<TimeOfDay> onChanged;
  final VoidCallback onHourSelected;

  void _apply(BuildContext context, Offset local, {required bool end}) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final next = _timeOnDial(local, box.size, time: time, mode: mode);
    if (next != time) onChanged(next);
    if (end && mode == _DialMode.hour) onHourSelected();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanUpdate: (details) =>
          _apply(context, details.localPosition, end: false),
      onPanEnd: (_) {
        if (mode == _DialMode.hour) onHourSelected();
      },
      onTapUp: (details) => _apply(context, details.localPosition, end: true),
      child: CustomPaint(
        painter: _DialPainter(time: time, mode: mode),
        child: const SizedBox.expand(),
      ),
    );
  }
}

/// Maps a point on the 24-hour double-ring (or minute ring) to a time.
TimeOfDay _timeOnDial(
  Offset local,
  Size size, {
  required TimeOfDay time,
  required _DialMode mode,
}) {
  if (size.shortestSide <= 0) return time;
  final center = size.center(Offset.zero);
  final offset = local - center;
  final angle = math.atan2(-offset.dy, offset.dx);
  var turn = (math.pi / 2 - angle) / (2 * math.pi);
  turn %= 1;
  if (turn < 0) turn += 1;

  if (mode == _DialMode.minute) {
    final minute = (turn * 60).round() % 60;
    return TimeOfDay(hour: time.hour, minute: minute);
  }

  final slot = (turn * 12).round() % 12;
  final radius = size.shortestSide / 2;
  final inner = radius * 0.52;
  final outer = radius * 0.82;
  final distance = offset.distance;
  final mid = (inner + outer) / 2;
  final hour = distance < mid ? slot : slot + 12;
  return TimeOfDay(hour: hour, minute: time.minute);
}

class _DialPainter extends CustomPainter {
  const _DialPainter({required this.time, required this.mode});

  final TimeOfDay time;
  final _DialMode mode;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = AppColors.noteBottom.withValues(alpha: 0.9),
    );

    final innerR = radius * 0.52;
    final outerR = radius * 0.82;
    final selected = mode == _DialMode.hour ? time.hour : time.minute;
    final handleR = mode == _DialMode.minute
        ? outerR
        : (time.hour < 12 ? innerR : outerR);

    final theta = mode == _DialMode.hour
        ? _thetaForSlot(time.hour % 12, 12)
        : _thetaForSlot(time.minute, 60);
    final handle = _point(center, theta, handleR);

    final hand = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(center, handle, hand);
    canvas.drawCircle(center, 3.5, hand);
    canvas.drawCircle(handle, 11, hand);

    if (mode == _DialMode.hour) {
      _paintHours(canvas, center, innerR, selected, inner: true);
      _paintHours(canvas, center, outerR, selected, inner: false);
    } else {
      _paintMinutes(canvas, center, outerR, selected);
    }
  }

  void _paintHours(
    Canvas canvas,
    Offset center,
    double ring,
    int selected, {
    required bool inner,
  }) {
    for (var slot = 0; slot < 12; slot++) {
      final hour = inner ? slot : slot + 12;
      final theta = _thetaForSlot(slot, 12);
      _label(
        canvas,
        _point(center, theta, ring),
        _two(hour),
        selected: hour == selected,
      );
    }
  }

  void _paintMinutes(Canvas canvas, Offset center, double ring, int selected) {
    for (var slot = 0; slot < 12; slot++) {
      final minute = slot * 5;
      final theta = _thetaForSlot(minute, 60);
      _label(
        canvas,
        _point(center, theta, ring),
        _two(minute),
        selected: minute == selected,
      );
    }
  }

  void _label(
    Canvas canvas,
    Offset center,
    String text, {
    required bool selected,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: AppTypography.metaStyle.copyWith(
          fontSize: 10,
          height: 1,
          fontWeight: selected
              ? AppTypography.titleWeight
              : AppTypography.weight,
          color: selected
              ? AppColors.canvasNeutralTop
              : AppColors.text.withValues(alpha: 0.82),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      center - Offset(painter.width / 2, painter.height / 2),
    );
    painter.dispose();
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  static double _thetaForSlot(int slot, int count) =>
      math.pi / 2 - (slot / count) * 2 * math.pi;

  static Offset _point(Offset center, double theta, double radius) =>
      center + Offset(math.cos(theta) * radius, -math.sin(theta) * radius);

  @override
  bool shouldRepaint(covariant _DialPainter oldDelegate) =>
      oldDelegate.time != time || oldDelegate.mode != mode;
}
