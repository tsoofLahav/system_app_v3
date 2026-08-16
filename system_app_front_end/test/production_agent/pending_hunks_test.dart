import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/production_agent/lookalike_review_dialog.dart';

void main() {
  test('Finish gate requires every hunk decided', () {
    expect(pendingHunksFullyDecided([], {}), isTrue);
    expect(
      pendingHunksFullyDecided(['a', 'b'], {'a': 'accept'}),
      isFalse,
    );
    expect(
      pendingHunksFullyDecided(
        ['a', 'b'],
        {'a': 'accept', 'b': 'reject'},
      ),
      isTrue,
    );
    expect(
      pendingHunksFullyDecided(['a'], {'a': 'maybe'}),
      isFalse,
    );
  });
}
