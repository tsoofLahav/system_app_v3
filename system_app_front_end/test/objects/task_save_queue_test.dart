import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_save_queue.dart';
import 'package:system_app_front_end/core/services/api_service.dart';

const original = Task(id: 1, title: 'old', status: 'active', revision: 1);
void main() {
  test(
    'typing and rapid toggles during a save drain without losing newer edits',
    () async {
      var server = original;
      final gate = Completer<void>();
      final sent = <Map<String, dynamic>>[];
      final drafts = <Task>[];
      final queue = TaskSaveQueue(
        baseline: original,
        read: () async => server,
        publish: (draft, _) => drafts.add(draft),
        write: (patch, revision) async {
          sent.add(patch);
          if (sent.length == 1) await gate.future;
          expect(revision, server.revision);
          server = applyTaskFields(server, patch, revision: revision + 1);
          return server;
        },
      );
      final first = queue.edit({'title': 'first', 'status': 'done'});
      final second = queue.edit({'title': 'newest', 'status': 'active'});
      expect(identical(first, second), isTrue);
      expect(drafts.last.title, 'newest');
      gate.complete();
      await first;
      expect(server.title, 'newest');
      expect(server.status, 'active');
      expect(sent.length, 2);
      expect(queue.dirty, isFalse);
    },
  );

  test(
    'timeout after commit is reconciled without a duplicate write',
    () async {
      var server = original;
      var writes = 0;
      final queue = TaskSaveQueue(
        baseline: original,
        read: () async => server,
        publish: (_, fields) {},
        write: (patch, revision) async {
          writes++;
          server = applyTaskFields(server, patch, revision: revision + 1);
          throw TimeoutException('lost response');
        },
      );
      await queue.edit({'status': 'done'});
      expect(writes, 1);
      expect(queue.dirty, isFalse);
      expect(queue.draft.revision, 2);
    },
  );

  test(
    'failed save retains the draft and retry rereads before writing',
    () async {
      var server = original;
      var fail = true;
      var reads = 0;
      final queue = TaskSaveQueue(
        baseline: original,
        read: () async {
          reads++;
          return server;
        },
        publish: (_, fields) {},
        write: (patch, revision) async {
          if (fail) throw TimeoutException('offline');
          return server = applyTaskFields(
            server,
            patch,
            revision: revision + 1,
          );
        },
      );
      await expectLater(
        queue.edit({'title': 'mine'}),
        throwsA(isA<TimeoutException>()),
      );
      expect(queue.draft.title, 'mine');
      expect(queue.dirty, isTrue);
      fail = false;
      await queue.flush();
      expect(reads, 2);
      expect(server.title, 'mine');
    },
  );

  test(
    'non-overlapping conflict rebases but same-field conflict needs a decision',
    () async {
      var server = original.copyWith(status: 'done', revision: 2);
      final queue = TaskSaveQueue(
        baseline: original,
        read: () async => server,
        publish: (_, fields) {},
        write: (patch, revision) async {
          if (revision != server.revision)
            throw ApiException('conflict', statusCode: 409);
          return server = applyTaskFields(
            server,
            patch,
            revision: revision + 1,
          );
        },
      );
      await queue.edit({'title': 'mine'});
      expect(server.status, 'done');
      server = server.copyWith(title: 'remote', revision: 4);
      await expectLater(
        queue.edit({'title': 'new mine'}),
        throwsA(isA<TaskSaveConflict>()),
      );
      expect(server.title, 'remote');
      await queue.resolve(keepLocal: false);
      expect(queue.draft.title, 'remote');
      expect(queue.dirty, isFalse);
    },
  );

  test('old poll cannot lower the acknowledged revision', () async {
    final queue = TaskSaveQueue(
      baseline: original,
      read: () async => original,
      publish: (_, fields) {},
      write: (patch, revision) async =>
          applyTaskFields(original, patch, revision: 2),
    );
    await queue.edit({'status': 'done'});
    queue.observe(original);
    expect(queue.draft.status, 'done');
  });
}
