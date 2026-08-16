import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/production_agent/lookalike_review_dialog.dart';
import 'package:system_app_front_end/areas/production_agent/pending_review_service.dart';

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

  test('side-by-side rows keep equals and mark a change as replace pair', () {
    final hunks = [
      PendingReviewHunk(
        id: 'change-1-1',
        op: 'change',
        oldLines: const ['b'],
        newLines: const ['B'],
        oldStart: 2,
        oldEnd: 2,
        newStart: 2,
        newEnd: 2,
      ),
    ];
    final rows = buildSideBySideRows(
      oldText: 'a\nb\nc\n',
      newText: 'a\nB\nc\n',
      hunks: hunks,
    );
    expect(rows.where((r) => !r.isChange).length, greaterThanOrEqualTo(2));
    final change = rows.where((r) => r.hunkId == 'change-1-1').toList();
    expect(change, hasLength(1));
    expect(change.first.oldText, 'b');
    expect(change.first.newText, 'B');
    // Must not present the edit as an add-only row (old null, new set).
    expect(change.any((r) => r.oldText == null && r.newText != null), isFalse);
  });

  test('wordDiffSpan marks changed tokens', () {
    final span = wordDiffSpan(
      'hello world',
      'hello there',
      highlightRemoved: false,
    );
    expect(span.children, isNotNull);
    expect(span.children!, isNotEmpty);
  });
}
