import '../../core/l10n/app_strings.dart';

/// One monthly fire: the first / second / third / last weekday of the month.
class ScheduleMonthSlot {
  const ScheduleMonthSlot({required this.placement, required this.weekday});

  final String placement;
  final String weekday;

  @override
  bool operator ==(Object other) =>
      other is ScheduleMonthSlot &&
      other.placement == placement &&
      other.weekday == weekday;

  @override
  int get hashCode => Object.hash(placement, weekday);
}

/// The schedule string the backend's `next_run_after()` reads.
///
/// Daily / weekly / monthly / every N months, never a cron line. The create
/// form used to send `0 8 * * *` at a parser that only knows `daily 08:00`,
/// which is why a scheduled automation could never have fired on time.
class AutomationSchedule {
  AutomationSchedule({
    required this.kind,
    this.time = '08:00',
    String weekday = 'mon',
    String placement = 'first',
    List<String>? weekdays,
    List<ScheduleMonthSlot>? monthSlots,
    this.monthInterval = 1,
    this.cycleFrom,
    this.allowMultiple = false,
  })  : selectedWeekdays = _uniqueWeekdays(weekdays ?? [weekday]),
        monthSlots = monthSlots ??
            [
              ScheduleMonthSlot(
                placement: placement,
                weekday: (weekdays ?? [weekday]).first,
              ),
            ];

  /// Twin of `DEFAULT_AUTOMATION_TIMEZONE` in
  /// `areas/automations/services/automation_schedule.py`.
  static const defaultTimezone = 'Asia/Jerusalem';

  static const daily = 'daily';
  static const weekly = 'weekly';
  static const monthly = 'monthly';
  static const everyNMonths = 'every_n_months';
  static const fewTimesWeek = 'few_times_week';
  static const fewTimesMonth = 'few_times_month';

  static const kinds = [daily, weekly, monthly, everyNMonths];
  static const weekdays = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  static const placements = ['first', 'second', 'third', 'last'];

  static const weekdayKeys = {
    'mon': 'monday',
    'tue': 'tuesday',
    'wed': 'wednesday',
    'thu': 'thursday',
    'fri': 'friday',
    'sat': 'saturday',
    'sun': 'sunday',
  };

  final String kind;
  final String time;
  final List<String> selectedWeekdays;
  final List<ScheduleMonthSlot> monthSlots;

  /// 1 = every month. 2–12 = once every N months (`monthly N …` in the DSL).
  final int monthInterval;

  /// Month the every-N-months cycle is counted from (`from YYYY-MM`).
  final DateTime? cycleFrom;

  /// Calendar taps toggle days instead of replacing the only one.
  final bool allowMultiple;

  String get weekday {
    if (isEveryNMonths || kind == monthly) {
      return monthSlots.isEmpty ? 'mon' : monthSlots.first.weekday;
    }
    return selectedWeekdays.isEmpty ? 'mon' : selectedWeekdays.first;
  }

  String get placement =>
      monthSlots.isEmpty ? 'first' : monthSlots.first.placement;

  bool get isEveryNMonths =>
      kind == everyNMonths || (kind == monthly && monthInterval > 1);

  bool get selectsMultipleDays =>
      allowMultiple || selectedWeekdays.length > 1 || monthSlots.length > 1;

  /// Kind the schedule chips show — every-N-months and "a few times" are
  /// their own chips.
  String get uiKind {
    if (isEveryNMonths) return everyNMonths;
    if (kind == weekly && (allowMultiple || selectedWeekdays.length > 1)) {
      return fewTimesWeek;
    }
    if (kind == monthly && (allowMultiple || monthSlots.length > 1)) {
      return fewTimesMonth;
    }
    return kind;
  }

  int get uiMonthInterval => monthInterval < 2 ? 2 : monthInterval.clamp(2, 12);

  DateTime get effectiveCycleFrom {
    final origin = cycleFrom;
    if (origin != null) return DateTime(origin.year, origin.month);
    final now = DateTime.now();
    return DateTime(now.year, now.month);
  }

  String toDsl() {
    final clock = _normaliseTime(time);
    return switch (uiKind) {
      weekly || fewTimesWeek =>
        'weekly ${(selectedWeekdays.isEmpty ? const ['mon'] : selectedWeekdays).join(',')} $clock',
      monthly || fewTimesMonth => 'monthly ${_monthSlotsDsl()} $clock',
      everyNMonths =>
        'monthly $uiMonthInterval ${_monthSlotsDsl()} $clock'
            ' from ${_yearMonth(effectiveCycleFrom)}',
      _ => 'daily $clock',
    };
  }

  String _monthSlotsDsl() {
    if (monthSlots.isEmpty) return 'first mon';
    if (monthSlots.length == 1) {
      final slot = monthSlots.first;
      return '${slot.placement} ${slot.weekday}';
    }
    return monthSlots
        .map((slot) => '${slot.placement}.${slot.weekday}')
        .join(',');
  }

  String whenCaption(AppStrings strings) {
    if (kind == weekly) {
      if (selectedWeekdays.isEmpty) return '';
      final keys = [
        for (final day in selectedWeekdays) weekdayKeys[day] ?? 'monday',
      ];
      if (keys.length == 1) return strings.weeklyScheduleCaption(keys.first);
      return strings.weeklyMultiCaption(keys);
    }
    if (isEveryNMonths) {
      if (monthSlots.isEmpty) return '';
      if (monthSlots.length == 1) {
        final slot = monthSlots.first;
        return strings.everyNMonthsCaption(
          uiMonthInterval,
          slot.placement,
          weekdayKeys[slot.weekday]!,
        );
      }
      return strings.everyNMonthsMultiCaption(
        uiMonthInterval,
        [
          for (final slot in monthSlots)
            (placementKey: slot.placement, dayKey: weekdayKeys[slot.weekday]!),
        ],
      );
    }
    if (kind == monthly) {
      if (monthSlots.isEmpty) return '';
      if (monthSlots.length == 1) {
        final slot = monthSlots.first;
        return strings.monthlyScheduleCaption(
          slot.placement,
          weekdayKeys[slot.weekday]!,
        );
      }
      return strings.monthlyMultiCaption([
        for (final slot in monthSlots)
          (placementKey: slot.placement, dayKey: weekdayKeys[slot.weekday]!),
      ]);
    }
    return '';
  }

  AutomationSchedule copyWith({
    String? kind,
    String? time,
    String? weekday,
    String? placement,
    List<String>? weekdays,
    List<ScheduleMonthSlot>? monthSlots,
    int? monthInterval,
    DateTime? cycleFrom,
    bool clearCycleFrom = false,
    bool? allowMultiple,
  }) {
    final nextWeekdays = weekdays ??
        (weekday != null
            ? [weekday, ...selectedWeekdays.skip(1)]
            : selectedWeekdays);
    var nextSlots = monthSlots ?? this.monthSlots;
    if (monthSlots == null && (placement != null || weekday != null)) {
      final first = this.monthSlots.first;
      nextSlots = [
        ScheduleMonthSlot(
          placement: placement ?? first.placement,
          weekday: weekday ?? first.weekday,
        ),
        ...this.monthSlots.skip(1),
      ];
    }
    return AutomationSchedule(
      kind: kind ?? this.kind,
      time: time ?? this.time,
      weekdays: nextWeekdays,
      monthSlots: nextSlots,
      monthInterval: monthInterval ?? this.monthInterval,
      cycleFrom: clearCycleFrom ? null : (cycleFrom ?? this.cycleFrom),
      allowMultiple: allowMultiple ?? this.allowMultiple,
    );
  }

  /// Unreadable strings become a daily 08:00 rather than a crash — the form
  /// has to open even for a row someone typed by hand.
  static AutomationSchedule parse(String? raw) {
    final parts = (raw ?? '').trim().toLowerCase().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) {
      return AutomationSchedule(kind: daily);
    }
    final kind = parts.first;
    if (kind == weekly) {
      var rest = parts.sublist(1);
      rest = _stripOrigin(rest).parts;
      if (rest.isEmpty) return AutomationSchedule(kind: weekly);
      if (rest.length == 1 && _isTime(rest.first)) {
        return AutomationSchedule(kind: weekly, time: _normaliseTime(rest.first));
      }
      return AutomationSchedule(
        kind: weekly,
        weekdays: _parseWeekdays(rest.first),
        time: _normaliseTime(rest.length > 1 ? rest[1] : '08:00'),
        allowMultiple: rest.first.contains(','),
      );
    }
    if (kind == monthly || kind == 'quarterly') {
      var rest = parts.sublist(1);
      var interval = kind == 'quarterly' ? 3 : 1;
      if (rest.isNotEmpty && int.tryParse(rest.first) != null) {
        interval = int.parse(rest.first).clamp(1, 12);
        rest = rest.sublist(1);
      }
      final stripped = _stripOrigin(rest);
      rest = stripped.parts;
      var time = '08:00';
      if (rest.isNotEmpty && _isTime(rest.last)) {
        time = _normaliseTime(rest.last);
        rest = rest.sublist(0, rest.length - 1);
      }
      return AutomationSchedule(
        kind: interval > 1 ? everyNMonths : monthly,
        monthInterval: interval,
        monthSlots: _parseMonthSlots(rest),
        time: time,
        cycleFrom: stripped.origin,
        allowMultiple: rest.isNotEmpty &&
            (rest.first.contains(',') || rest.first.contains('.')),
      );
    }
    if (kind == daily) {
      return AutomationSchedule(
        kind: daily,
        time: _normaliseTime(parts.length > 1 ? parts[1] : '08:00'),
      );
    }
    return AutomationSchedule(kind: daily);
  }

  static String weekdayFromDart(int dartWeekday) {
    final index = (dartWeekday - 1).clamp(0, 6);
    return weekdays[index];
  }

  int get dartWeekday {
    final index = weekdays.indexOf(weekday);
    return (index < 0 ? 0 : index) + 1;
  }

  /// First / second / third / last occurrence of this date's weekday in its month.
  static String placementFromDate(DateTime date) {
    final days = _weekdayDaysInMonth(date.year, date.month, date.weekday);
    final index = days.indexOf(date.day);
    if (index < 0) return 'first';
    if (index == days.length - 1) return 'last';
    return placements[index.clamp(0, placements.length - 2)];
  }

  /// Weekly takes the weekday; monthly / every N months also infer placement.
  /// "A few times" chips toggle; once-a-week / once-a-month replace.
  AutomationSchedule applyingDate(DateTime date) {
    final day = weekdayFromDart(date.weekday);
    if (kind == weekly) {
      if (allowMultiple || selectedWeekdays.length > 1) {
        return copyWith(weekdays: _toggleWeekday(day));
      }
      return copyWith(weekdays: [day]);
    }
    if (kind == monthly || kind == everyNMonths) {
      final slot = ScheduleMonthSlot(
        placement: placementFromDate(date),
        weekday: day,
      );
      final nextSlots = (allowMultiple || monthSlots.length > 1)
          ? _toggleMonthSlot(slot)
          : [slot];
      return copyWith(
        monthSlots: nextSlots,
        cycleFrom: isEveryNMonths ? DateTime(date.year, date.month) : cycleFrom,
      );
    }
    return this;
  }

  List<String> _toggleWeekday(String day) {
    if (selectedWeekdays.contains(day)) {
      if (selectedWeekdays.length == 1) return selectedWeekdays;
      return [
        for (final existing in selectedWeekdays)
          if (existing != day) existing,
      ];
    }
    return _uniqueWeekdays([...selectedWeekdays, day]);
  }

  List<ScheduleMonthSlot> _toggleMonthSlot(ScheduleMonthSlot slot) {
    if (monthSlots.contains(slot)) {
      if (monthSlots.length == 1) return monthSlots;
      return [for (final existing in monthSlots) if (existing != slot) existing];
    }
    return [...monthSlots, slot];
  }

  /// Which days this schedule would fire. Every N months only marks months
  /// on the stored cycle (`from YYYY-MM`), not every month.
  bool marksDate(DateTime date) {
    if (kind == weekly) {
      return selectedWeekdays.contains(weekdayFromDart(date.weekday));
    }
    if (kind == monthly || kind == everyNMonths) {
      if (isEveryNMonths && !_inCycleMonth(date)) return false;
      return monthSlots.any(
        (slot) => occurrenceDayFor(date.year, date.month, slot) == date.day,
      );
    }
    return false;
  }

  bool _inCycleMonth(DateTime date) {
    final origin = effectiveCycleFrom;
    final delta =
        (date.year * 12 + date.month) - (origin.year * 12 + origin.month);
    return delta % uiMonthInterval == 0;
  }

  int? occurrenceDay(int year, int month) =>
      occurrenceDayFor(year, month, monthSlots.first);

  int? occurrenceDayFor(int year, int month, ScheduleMonthSlot slot) {
    final dartDay = weekdays.indexOf(slot.weekday) + 1;
    final days = _weekdayDaysInMonth(year, month, dartDay);
    if (days.isEmpty) return null;
    if (slot.placement == 'last') return days.last;
    final index = placements.indexOf(slot.placement);
    if (index < 0 || index >= days.length) return null;
    return days[index];
  }

  static List<int> _weekdayDaysInMonth(int year, int month, int dartWeekday) {
    final last = DateTime(year, month + 1, 0).day;
    return [
      for (var day = 1; day <= last; day++)
        if (DateTime(year, month, day).weekday == dartWeekday) day,
    ];
  }

  static List<String> _uniqueWeekdays(List<String> raw) {
    final seen = <String>{};
    final ordered = <String>[];
    for (final day in weekdays) {
      if (raw.contains(day) && seen.add(day)) ordered.add(day);
    }
    return ordered;
  }

  static List<String> _parseWeekdays(String raw) {
    return _uniqueWeekdays([
      for (final token in raw.split(','))
        if (token.trim().isNotEmpty) _weekday(token.trim()),
    ]);
  }

  static List<ScheduleMonthSlot> _parseMonthSlots(List<String> rest) {
    if (rest.isEmpty) {
      return const [ScheduleMonthSlot(placement: 'first', weekday: 'mon')];
    }
    if (rest.length >= 2 &&
        !rest.first.contains(',') &&
        !rest.first.contains('.')) {
      return [
        ScheduleMonthSlot(
          placement: placements.contains(rest[0]) ? rest[0] : 'first',
          weekday: _weekday(rest[1]),
        ),
      ];
    }
    final slots = <ScheduleMonthSlot>[];
    for (final token in rest.first.split(',')) {
      final bits = token.split('.');
      if (bits.length != 2) continue;
      slots.add(
        ScheduleMonthSlot(
          placement: placements.contains(bits[0]) ? bits[0] : 'first',
          weekday: _weekday(bits[1]),
        ),
      );
    }
    return slots.isEmpty
        ? const [ScheduleMonthSlot(placement: 'first', weekday: 'mon')]
        : slots;
  }

  static ({List<String> parts, DateTime? origin}) _stripOrigin(
    List<String> parts,
  ) {
    if (parts.length >= 2 && parts[parts.length - 2] == 'from') {
      final origin = _parseYearMonth(parts.last);
      return (parts: parts.sublist(0, parts.length - 2), origin: origin);
    }
    return (parts: parts, origin: null);
  }

  static DateTime? _parseYearMonth(String raw) {
    final match = RegExp(r'^(\d{4})-(\d{2})$').firstMatch(raw);
    if (match == null) return null;
    final month = int.parse(match.group(2)!);
    if (month < 1 || month > 12) return null;
    return DateTime(int.parse(match.group(1)!), month);
  }

  static String _yearMonth(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    return '${date.year}-$month';
  }

  static bool _isTime(String raw) =>
      RegExp(r'^\d{1,2}:\d{2}$').hasMatch(raw.trim());

  static String _weekday(String raw) {
    if (weekdays.contains(raw)) return raw;
    for (final entry in weekdayKeys.entries) {
      if (entry.value == raw) return entry.key;
    }
    return 'mon';
  }

  static String _normaliseTime(String raw) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(raw.trim());
    if (match == null) return '08:00';
    final hour = int.parse(match.group(1)!).clamp(0, 23);
    final minute = int.parse(match.group(2)!).clamp(0, 59);
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}
