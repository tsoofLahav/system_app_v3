import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/production_agent/agent_time_hints.dart';

void main() {
  test('sends the local day, weekday and offset-aware time', () {
    final hints = agentTimeHints(DateTime(2026, 8, 16, 9, 5, 3));
    final offset = DateTime(2026, 8, 16).timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    final expectedOffset = '$sign'
        '${(minutes ~/ 60).toString().padLeft(2, '0')}:'
        '${(minutes % 60).toString().padLeft(2, '0')}';

    expect(hints['today'], '2026-08-16');
    expect(hints['weekday'], 'Sunday');
    expect(hints['now'], '2026-08-16T09:05:03$expectedOffset');
  });

  test('a late evening run still reports the local date', () {
    // UTC would already be on the 17th; the user means the 16th.
    final hints = agentTimeHints(DateTime(2026, 8, 16, 23, 40));
    expect(hints['today'], '2026-08-16');
    expect(hints['weekday'], 'Sunday');
  });
}
