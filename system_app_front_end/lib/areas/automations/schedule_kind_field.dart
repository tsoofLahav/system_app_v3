import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n/app_strings.dart';
import '../ui/app_segmented_toggle.dart';
import '../ui/dialog_field_style.dart';
import './schedule_format.dart';

/// Daily / weekly / monthly / every N months — the same chips on the builder
/// and the section-window clock.
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
        ),
      );
    }
  }

  void _setKind(String kind) {
    var next = widget.schedule.copyWith(kind: kind);
    if (kind == AutomationSchedule.everyNMonths) {
      next = next.copyWith(
        monthInterval: widget.schedule.monthInterval < 2
            ? 2
            : widget.schedule.monthInterval,
      );
    } else if (kind == AutomationSchedule.monthly) {
      next = next.copyWith(monthInterval: 1);
    }
    widget.onChanged(next);
  }

  void _setMonths(String raw) {
    final n = int.tryParse(raw.trim());
    if (n == null || n < 2 || n > 12) return;
    widget.onChanged(
      widget.schedule.copyWith(
        kind: AutomationSchedule.everyNMonths,
        monthInterval: n,
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
              value: AutomationSchedule.monthly,
              label: s['onceAMonth'],
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
