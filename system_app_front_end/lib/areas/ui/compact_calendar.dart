import 'package:flutter/material.dart';

import './app_colors.dart';
import './app_icons.dart';
import './app_typography.dart';
import './dialog_field_style.dart';
import './dialog_metrics.dart';

/// A small month grid meant to sit beside a compact clock, not in its own dialog.
class AppCompactCalendar extends StatefulWidget {
  const AppCompactCalendar({
    super.key,
    required this.title,
    required this.weekdayLabels,
    required this.formatMonth,
    required this.isMarked,
    required this.onDaySelected,
    this.caption,
    this.firstWeekday = DateTime.sunday,
  });

  final String title;

  /// Seven labels, first column first. [firstWeekday] is that column's
  /// [DateTime.weekday] (Sunday = 7 in this app — weeks start on Sunday).
  final List<String> weekdayLabels;
  final int firstWeekday;
  final String Function(DateTime month) formatMonth;
  final bool Function(DateTime date) isMarked;
  final ValueChanged<DateTime> onDaySelected;
  final String? caption;

  @override
  State<AppCompactCalendar> createState() => _AppCompactCalendarState();
}

class _AppCompactCalendarState extends State<AppCompactCalendar> {
  late DateTime _visible;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visible = DateTime(now.year, now.month);
  }

  int _column(int dartWeekday) => (dartWeekday - widget.firstWeekday) % 7;

  void _shiftMonth(int delta) {
    setState(() => _visible = DateTime(_visible.year, _visible.month + delta));
  }

  void _select(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    widget.onDaySelected(day);
    if (day.month != _visible.month || day.year != _visible.year) {
      setState(() => _visible = DateTime(day.year, day.month));
    }
  }

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final firstOfMonth = DateTime(_visible.year, _visible.month, 1);
    final gridStart = firstOfMonth.subtract(
      Duration(days: _column(firstOfMonth.weekday)),
    );

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
                  AppIcons.calendar,
                  size: 14,
                  color: AppColors.primary.withValues(alpha: 0.82),
                ),
              ],
            ),
            const SizedBox(height: 6),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: AppColors.noteBottom.withValues(alpha: 0.72),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                child: Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => _shiftMonth(-1),
                      icon: AppIcon(
                        rtl ? AppIcons.chevronRight : AppIcons.chevronLeft,
                        size: 14,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.formatMonth(_visible),
                        textAlign: TextAlign.center,
                        style: AppTypography.metaStyle.copyWith(
                          fontWeight: AppTypography.titleWeight,
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      onPressed: () => _shiftMonth(1),
                      icon: AppIcon(
                        rtl ? AppIcons.chevronLeft : AppIcons.chevronRight,
                        size: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    children: [
                      for (final label in widget.weekdayLabels)
                        Expanded(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: AppTypography.metaStyle.copyWith(
                              fontSize: 10,
                              fontWeight: AppTypography.titleWeight,
                              color: AppColors.text.withValues(alpha: 0.72),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  for (var week = 0; week < 6; week++)
                    Row(
                      children: [
                        for (var col = 0; col < 7; col++)
                          Expanded(
                            child: _DayCell(
                              date: gridStart.add(Duration(days: week * 7 + col)),
                              visibleMonth: _visible.month,
                              marked: widget.isMarked(
                                gridStart.add(Duration(days: week * 7 + col)),
                              ),
                              onTap: _select,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (widget.caption != null && widget.caption!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                widget.caption!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.metaStyle.copyWith(fontSize: 11),
              ),
            ],
          ],
        ),
      ),
    ),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.date,
    required this.visibleMonth,
    required this.marked,
    required this.onTap,
  });

  final DateTime date;
  final int visibleMonth;
  final bool marked;
  final ValueChanged<DateTime> onTap;

  @override
  Widget build(BuildContext context) {
    final inMonth = date.month == visibleMonth;
    final size = AppDialogMetrics.compactCalendarDay;
    final textColor = marked
        ? AppColors.canvasNeutralTop
        : AppColors.text.withValues(alpha: inMonth ? 0.88 : 0.38);

    return SizedBox(
      height: size + 4,
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => onTap(date),
            overlayColor: WidgetStatePropertyAll(
              AppColors.primary.withValues(alpha: 0.12),
            ),
            child: Ink(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: marked ? AppColors.primary : Colors.transparent,
              ),
              child: Center(
                child: Text(
                  '${date.day}',
                  style: AppTypography.metaStyle.copyWith(
                    fontSize: 10,
                    height: 1,
                    color: textColor,
                    fontWeight: marked
                        ? AppTypography.titleWeight
                        : AppTypography.weight,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
