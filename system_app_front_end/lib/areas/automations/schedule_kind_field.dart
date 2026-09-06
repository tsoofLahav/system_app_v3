import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../ui/app_icons.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import './schedule_format.dart';

/// Day / week / month — the same chips on the builder and the section-window
/// clock. Week and month calendars toggle days. Month can unlock an every-N
/// interval (locked at 1 by default).
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
  late bool _adaptive;

  AppStrings get s => widget.strings;

  @override
  void initState() {
    super.initState();
    _adaptive = widget.schedule.isEveryNMonths;
    _months = TextEditingController(text: '${_shownInterval()}');
    _monthsFocus.addListener(_commitMonthsIfUnfocused);
  }

  @override
  void didUpdateWidget(covariant AutomationScheduleKindField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.schedule.uiKind != widget.schedule.uiKind) {
      _adaptive = widget.schedule.isEveryNMonths;
    } else if (widget.schedule.isEveryNMonths && !_adaptive) {
      _adaptive = true;
    }
    if (_monthsFocus.hasFocus) return;
    final shown = '${_shownInterval()}';
    if (_months.text != shown) _months.text = shown;
  }

  @override
  void dispose() {
    _monthsFocus.removeListener(_commitMonthsIfUnfocused);
    _monthsFocus.dispose();
    _months.dispose();
    super.dispose();
  }

  int _shownInterval() =>
      _adaptive ? widget.schedule.shownMonthInterval : 1;

  void _commitMonthsIfUnfocused() {
    if (_monthsFocus.hasFocus || !_adaptive) return;
    final n = (int.tryParse(_months.text.trim()) ?? 1).clamp(1, 12);
    if (_months.text != '$n') _months.text = '$n';
    _applyInterval(n);
  }

  void _setKind(String kind) {
    widget.onChanged(_scheduleForKind(kind));
    if (kind != AutomationSchedule.monthly) {
      setState(() => _adaptive = false);
    }
  }

  AutomationSchedule _scheduleForKind(String kind) {
    final current = widget.schedule;
    return switch (kind) {
      AutomationSchedule.weekly => current.copyWith(
          kind: AutomationSchedule.weekly,
          weekdays: current.kind == AutomationSchedule.weekly
              ? current.selectedWeekdays
              : [
                  AutomationSchedule.weekdayFromDart(DateTime.now().weekday),
                ],
          allowMultiple: true,
          monthInterval: 1,
          clearCycleFrom: true,
        ),
      AutomationSchedule.monthly => current.copyWith(
          kind: AutomationSchedule.monthly,
          monthSlots: (current.kind == AutomationSchedule.monthly ||
                  current.isEveryNMonths)
              ? current.monthSlots
              : [
                  ScheduleMonthSlot(
                    placement: AutomationSchedule.placementFromDate(
                      DateTime.now(),
                    ),
                    weekday: AutomationSchedule.weekdayFromDart(
                      DateTime.now().weekday,
                    ),
                  ),
                ],
          allowMultiple: true,
          monthInterval: 1,
          clearCycleFrom: true,
        ),
      _ => current.copyWith(
          kind: AutomationSchedule.daily,
          allowMultiple: false,
          monthInterval: 1,
          clearCycleFrom: true,
        ),
    };
  }

  void _setAdaptive(bool adaptive) {
    setState(() => _adaptive = adaptive);
    if (!adaptive) {
      _months.text = '1';
      widget.onChanged(
        widget.schedule.copyWith(
          kind: AutomationSchedule.monthly,
          monthInterval: 1,
          allowMultiple: true,
          clearCycleFrom: true,
        ),
      );
      return;
    }
    _months.text = '${widget.schedule.shownMonthInterval}';
  }

  void _setMonths(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null || n < 1 || n > 12) return;
    _applyInterval(n);
  }

  void _applyInterval(int n) {
    final now = DateTime.now();
    widget.onChanged(
      widget.schedule.copyWith(
        kind: n > 1
            ? AutomationSchedule.everyNMonths
            : AutomationSchedule.monthly,
        monthInterval: n,
        allowMultiple: true,
        cycleFrom: n > 1
            ? (widget.schedule.cycleFrom ?? DateTime(now.year, now.month))
            : null,
        clearCycleFrom: n <= 1,
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
              label: s['scheduleDay'],
            ),
            AppSegmentedOption(
              value: AutomationSchedule.weekly,
              label: s['scheduleWeek'],
            ),
            AppSegmentedOption(
              value: AutomationSchedule.monthly,
              label: s['scheduleMonth'],
            ),
          ],
          selected: widget.schedule.uiKind,
          onSelected: widget.enabled ? _setKind : null,
        ),
        if (widget.schedule.uiKind == AutomationSchedule.monthly) ...[
          const SizedBox(height: DialogFieldStyle.fieldGap),
          AppDialogField(
            label: s['onceInMonthsCount'],
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _months,
                    focusNode: _monthsFocus,
                    enabled: widget.enabled && _adaptive,
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(2),
                    ],
                    decoration: DialogFieldStyle.decoration(),
                    onChanged: widget.enabled && _adaptive ? _setMonths : null,
                  ),
                ),
                IconButton(
                  tooltip: _adaptive
                      ? s['lockMonthInterval']
                      : s['unlockMonthInterval'],
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.enabled
                      ? () => _setAdaptive(!_adaptive)
                      : null,
                  icon: AppIcon(
                    _adaptive ? AppIcons.lockOpen : AppIcons.lock,
                    size: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
