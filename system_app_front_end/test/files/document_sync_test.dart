import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/document_sync.dart';

void main() {
  test('older reads do not replace the acknowledged version', () async {
    final sync = DocumentSync(const DocumentVersion('new', 4));
    await sync.synchronize(
      read: () async => const DocumentVersion('old', 3),
      write: (_, _) async => throw StateError('unexpected write'),
      review: (_) async => null,
    );
    expect(sync.draft, 'new');
    expect(sync.baseline.revision, 4);
  });

  test(
    'typing during keyboard-idle wait is rechecked before adoption',
    () async {
      final sync = DocumentSync(const DocumentVersion('base', 1));
      var server = const DocumentVersion('remote', 2);
      final entered = Completer<void>();
      final release = Completer<void>();
      var gates = 0;
      var reviews = 0;
      final adopted = <String>[];
      final run = sync.synchronize(
        read: () async => server,
        write: (body, revision) async =>
            server = DocumentVersion(body, revision + 1),
        review: (_) async {
          reviews++;
          return 'resolved';
        },
        beforeAdopt: () async {
          if (gates++ == 0) {
            entered.complete();
            await release.future;
          }
        },
        onAdopt: () => adopted.add(sync.draft),
      );
      await entered.future;
      sync.edit('typed while waiting');
      release.complete();
      await run;
      expect(reviews, 1);
      expect(adopted, isNot(contains('remote')));
      expect(server.body, 'resolved');
    },
  );

  test('an unavailable review keeps both baseline and local draft', () async {
    final sync = DocumentSync(const DocumentVersion('base', 1));
    sync.edit('local');
    await expectLater(
      sync.synchronize(
        read: () async => const DocumentVersion('remote', 2),
        write: (_, _) async => throw StateError('must not write'),
        review: (_) async => null,
      ),
      throwsA(isA<DocumentSyncNeedsReview>()),
    );
    expect(sync.draft, 'local');
    expect(sync.baseline.body, 'base');
    expect(sync.dirty, true);
  });

  test(
    'typing during PATCH remains dirty and is saved in a second pass',
    () async {
      final sync = DocumentSync(const DocumentVersion('a', 1));
      sync.edit('ab');
      var server = const DocumentVersion('a', 1);
      final entered = Completer<void>();
      final release = Completer<void>();
      final writes = <String>[];
      final run = sync.synchronize(
        read: () async => server,
        write: (body, revision) async {
          writes.add(body);
          if (writes.length == 1) {
            entered.complete();
            await release.future;
          }
          expect(revision, server.revision);
          return server = DocumentVersion(body, revision + 1);
        },
        review: (_) async => throw StateError('unexpected conflict'),
      );
      await entered.future;
      sync.edit('abc');
      release.complete();
      await run;
      expect(writes, ['ab', 'abc']);
      expect(sync.draft, 'abc');
      expect(sync.dirty, false);
    },
  );

  test('simultaneous triggers share the same operation', () async {
    final sync = DocumentSync(const DocumentVersion('a', 1));
    final release = Completer<DocumentVersion>();
    var reads = 0;
    Future<void> run() => sync.synchronize(
      read: () {
        reads++;
        return release.future;
      },
      write: (_, _) async => throw StateError('unexpected write'),
      review: (_) async => null,
    );
    final a = run();
    final b = run();
    expect(identical(a, b), true);
    release.complete(const DocumentVersion('a', 1));
    await a;
    expect(reads, 1);
  });

  test('409 fetches again and asks about the new remote content', () async {
    final sync = DocumentSync(const DocumentVersion('a', 1));
    sync.edit('local');
    var server = const DocumentVersion('a', 1);
    var writes = 0;
    var reviews = 0;
    await sync.synchronize(
      read: () async => server,
      write: (body, revision) async {
        writes++;
        if (writes == 1) {
          server = const DocumentVersion('remote', 2);
          throw const DocumentWriteConflict();
        }
        expect(revision, 2);
        return server = DocumentVersion(body, 3);
      },
      review: (result) async {
        reviews++;
        return result.localSided;
      },
    );
    expect(reviews, 1);
    expect(writes, 2);
  });

  test('failed save preserves baseline and draft for retry', () async {
    final sync = DocumentSync(const DocumentVersion('a', 1));
    sync.edit('a\n\nnew');
    await expectLater(
      sync.synchronize(
        read: () async => const DocumentVersion('a', 1),
        write: (_, _) async => throw StateError('offline'),
        review: (_) async => null,
      ),
      throwsStateError,
    );
    expect(sync.baseline.body, 'a');
    expect(sync.draft, 'a\n\nnew');
    expect(sync.dirty, true);
    expect(sync.running, false);
  });
}
