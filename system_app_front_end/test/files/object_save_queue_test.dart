import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/object_save_queue.dart';

void main() {
  test(
    'typing during PATCH drains newest draft; own echo is identified',
    () async {
      final queue = ObjectSaveQueue();
      var draft = 'first';
      var baseline = 'base';
      final requests = <String>[];
      final gate = Completer<void>();
      Future<void> flush() => queue.flush(
        needsSave: () => draft != baseline,
        capture: () => draft,
        write: (snapshot) async {
          requests.add(snapshot);
          expect(queue.isLocalEcho(snapshot), isTrue);
          expect(queue.isLocalEcho('external'), isFalse);
          if (requests.length == 1) await gate.future;
        },
        acknowledge: (snapshot) => baseline = snapshot,
      );
      final first = flush();
      draft = 'second';
      expect(queue.isLocalEcho('first'), isTrue);
      final second = flush();
      final third = flush();
      expect(identical(first, second), isTrue);
      expect(identical(first, third), isTrue);
      gate.complete();
      await Future.wait([first, second, third]);
      expect(requests, ['first', 'second']);
      expect(baseline, 'second');
      expect(queue.isLocalEcho('first'), isFalse);
      expect(queue.isLocalEcho('second'), isFalse);
    },
  );

  test(
    'failure retains draft and baseline, releases queue for retry',
    () async {
      final queue = ObjectSaveQueue();
      var baseline = 'base';
      var fail = true;
      Future<void> flush() => queue.flush(
        needsSave: () => baseline != 'draft',
        capture: () => 'draft',
        write: (_) async {
          if (fail) throw StateError('offline');
        },
        acknowledge: (snapshot) => baseline = snapshot,
      );
      await expectLater(flush(), throwsStateError);
      expect(baseline, 'base');
      expect(queue.isLocalEcho('draft'), isFalse);
      fail = false;
      await flush();
      expect(baseline, 'draft');
    },
  );
}
