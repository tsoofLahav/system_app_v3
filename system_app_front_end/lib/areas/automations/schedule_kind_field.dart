import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import './schedule_format.dart';

/// Daily / weekly / a few times a week / monthly / a few times a month /
/// every N months — the same chips on the builder and the section-window clock.
class AutomationScheduleKindField extends StatefulWidget {
  const AutomationScheduleKindField({
    super.key,
    required this.schedule,
    required this.strings,
    required this.onChanged,
    this.enabled = true,
  });

  final AutomationSchedule schedule;
  final AppStrings strings;
  final ValueChanged<AutomationSchedule> onChanged;
  final bool enabled;

  @override
  State<AutomationScheduleKindField> createState() =>
      _AutomationScheduleKindFieldState();
}

class _AutomationScheduleKindFieldState
    extends State<AutomationScheduleKindField> {
  late final TextEditingController _months;
  final _monthsFocus = FocusNode();

  AppStrings get s => widget.strings;

  @override
  void initState() {
    super.initState();
    _months = TextEditingController(text: '${widget.schedule.uiMonthInterval}');
    _monthsFocus.addListener(_commitMonthsIfUnfocused);
  }

  @override
  void didUpdateWidget(covariant AutomationScheduleKindField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_monthsFocus.hasFocus) return;
    final shown = '${widget.schedule.uiMonthInterval}';
    if (_months.text != shown) _months.text = shown;
  }

  @override
  void dispose() {
    _monthsFocus.removeListener(_commitMonthsIfUnfocused);
    _monthsFocus.dispose();
    _months.dispose();
    super.dispose();
  }

  void _commitMonthsIfUnfocused() {
    if (_monthsFocus.hasFocus) return;
    final n = (int.tryParse(_months.text.trim()) ?? 2).clamp(2, 12);
    if (_months.text != '$n') _months.text = '$n';
    if (n != widget.schedule.uiMonthInterval) {
      widget.onChanged(
        widget.schedule.copyWith(
          kind: AutomationSchedule.everyNMonths,
          monthInterval: n,
          allowMultiple: false,
          cycleFrom: widget.schedule.effectiveCycleFrom,
        ),
      );
    }
  }

  void _setKind(String kind) {
    widget.onChanged(_scheduleForKind(kind));
  }

  AutomationSchedule _scheduleForKind(String kind) {
    final current = widget.schedule;
    final now = DateTime.now();
    return switch (kind) {
      AutomationSchedule.fewTimesWeek => current.copyWith(
          kind: AutomationSchedule.weekly,
          weekdays: current.kind == AutomationSchedule.weekly
              ? current.selectedWeekdays
              : const [],
          allowMultiple: true,
          monthInterval: 1,
          clearCycleFrom: true,
        ),
      AutomationSchedule.weekly => current.copyWith(
          kind: AutomationSchedule.weekly,
          weekdays: [current.weekday],
          allowMultiple: false,
          monthInterval: 1,
          clearCycleFrom: true,
        ),
      AutomationSchedule.fewTimesMonth => current.copyWith(
          kind: AutomationSchedule.monthly,
          monthSlots: (current.kind == AutomationSchedule.monthly ||
                  current.isEveryNMonths)
              ? current.monthSlots
              : const [],
          allowMultiple: true,
          monthInterval: 1,
          clearCycleFrom: true,
        ),
      AutomationSchedule.monthly => current.copyWith(
          kind: AutomationSchedule.monthly,
          monthSlots: [current.monthSlots.first],
          allowMultiple: false,
          monthInterval: 1,
          clearCycleFrom: true,
        ),
      AutomationSchedule.everyNMonths => current.copyWith(
          kind: AutomationSchedule.everyNMonths,
          monthSlots: [current.monthSlots.first],
          allowMultiple: false,
          monthInterval: current.monthInterval < 2 ? 2 : current.monthInterval,
          cycleFrom: current.cycleFrom ?? DateTime(now.year, now.month),
        ),
      _ => current.copyWith(
          kind: AutomationSchedule.daily,
          allowMultiple: false,
          monthInterval: 1,
          clearCycleFrom: true,
        ),
    };
  }

  void _setMonths(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null || n < 2 || n > 12) return;
    widget.onChanged(
      widget.schedule.copyWith(
        kind: AutomationSchedule.everyNMonths,
        monthInterval: n,
        allowMultiple: false,
        cycleFrom: widget.schedule.effectiveCycleFrom,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogChoiceField<String>(
          label: s['schedule'],
          enabled: widget.enabled,
          options: [
            AppSegmentedOption(
              value: AutomationSchedule.daily,
              label: s['onceADay'],
            ),
            AppSegmentedOption(
              value: AutomationSchedule.weekly,
              label: s['onceAWeek'],
            ),
            AppSegmentedOption(
              value: AutomationSchedule.fewTimesWeek,
              label: s['fewTimesAWeek'],
            ),
            AppSegmentedOption(
              value: AutomationSchedule.monthly,
              label: s['onceAMonth'],
            ),
            AppSegmentedOption(
              value: AutomationSchedule.fewTimesMonth,
              label: s['fewTimesAMonth'],
            ),
            AppSegmentedOption(
              value: AutomationSchedule.everyNMonths,
              label: s['onceInMonths'],
            ),
          ],
          selected: widget.schedule.uiKind,
          onSelected: widget.enabled ? _setKind : null,
        ),
        if (widget.schedule.uiKind == AutomationSchedule.everyNMonths) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['onceInMonthsCount'],
            child: TextField(
              controller: _months,
              focusNode: _monthsFocus,
              enabled: widget.enabled,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              decoration: DialogFieldStyle.decoration(),
              onChanged: widget.enabled ? _setMonths : null,
            ),
          ),
        ],
      ],
    );
  }
}
