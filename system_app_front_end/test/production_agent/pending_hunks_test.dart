import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';
import 'package:system_app_front_end/areas/production_agent/lookalike_review_dialog.dart';
import 'package:system_app_front_end/areas/production_agent/pending_review_service.dart';
import 'package:system_app_front_end/areas/production_agent/review_marks.dart';

PendingReviewHunk hunk({
  required String id,
  String op = 'change',
  List<String> oldLines = const [],
  List<String> newLines = const [],
  required int oldStart,
  required int oldEnd,
  required int newStart,
  required int newEnd,
}) {
  return PendingReviewHunk(
    id: id,
    op: op,
    oldLines: oldLines,
    newLines: newLines,
    oldStart: oldStart,
    oldEnd: oldEnd,
    newStart: newStart,
    newEnd: newEnd,
  );
}

void main() {
  test('Finish gate requires every hunk decided', () {
    expect(pendingHunksFullyDecided([], {}), isTrue);
    expect(pendingHunksFullyDecided(['a', 'b'], {'a': 'accept'}), isFalse);
    expect(
      pendingHunksFullyDecided(['a', 'b'], {'a': 'accept', 'b': 'reject'}),
      isTrue,
    );
    expect(pendingHunksFullyDecided(['a'], {'a': 'maybe'}), isFalse);
  });

  test('a change on one table row marks that row and not the embed', () {
    // [TABLE id="7"] / row 1 / row 2 / [/TABLE] — the change is on row 2 only.
    final hunks = [
      hunk(
        id: 'change-3-3',
        oldLines: const ['b1\\tb2'],
        newLines: const ['b1\\tB2'],
        oldStart: 3,
        oldEnd: 3,
        newStart: 3,
        newEnd: 3,
      ),
    ];
    final marks = hunkMarksByLine(hunks, oldSide: false);

    expect(marks[2]?.hunkId, 'change-3-3');
    expect(marks[1], isNull);
    // The row alone is marked; the whole fence (lines 0..3) is not.
    expect(markForRange(marks, 2, 2)?.hunkId, 'change-3-3');
    expect(markForRange(marks, 0, 3), isNull);
  });

  test('a change over a whole fence marks the embed as one', () {
    final hunks = [
      hunk(
        id: 'add-1-4',
        op: 'add',
        newLines: const ['[TABLE id="7"]', 'a', 'b', '[/TABLE]'],
        oldStart: 1,
        oldEnd: 0,
        newStart: 1,
        newEnd: 4,
      ),
    ];
    final marks = hunkMarksByLine(hunks, oldSide: false);
    expect(markForRange(marks, 0, 3)?.op, 'add');
    // An add leaves nothing to mark on the current side.
    expect(hunkMarksByLine(hunks, oldSide: true), isEmpty);
  });

  test('deciding advances to the next undecided change, then wraps', () {
    final hunks = [
      hunk(id: 'a', oldStart: 1, oldEnd: 1, newStart: 1, newEnd: 1),
      hunk(id: 'b', oldStart: 2, oldEnd: 2, newStart: 2, newEnd: 2),
      hunk(id: 'c', oldStart: 3, oldEnd: 3, newStart: 3, newEnd: 3),
    ];
    final choices = <String, ReviewChoice>{};

    expect(nextUndecidedHunkId(hunks, choices), 'a');

    choices['b'] = ReviewChoice.accept;
    expect(nextUndecidedHunkId(hunks, choices, fromId: 'a'), 'c');

    choices['c'] = ReviewChoice.reject;
    // Nothing below 'c' is undecided, so it comes back up to 'a'.
    expect(nextUndecidedHunkId(hunks, choices, fromId: 'c'), 'a');

    choices['a'] = ReviewChoice.accept;
    expect(nextUndecidedHunkId(hunks, choices, fromId: 'a'), isNull);
  });

  test('flipping a decided change leaves the other decisions alone', () {
    final choices = <String, ReviewChoice>{
      'a': ReviewChoice.accept,
      'b': ReviewChoice.reject,
    };
    choices['a'] = ReviewChoice.reject;

    expect(choices['b'], ReviewChoice.reject);
    expect(
      changeStateFor(hunkId: 'a', activeHunkId: 'a', choices: choices),
      ChangeState.rejected,
    );
    expect(
      changeStateFor(hunkId: 'c', activeHunkId: 'c', choices: choices),
      ChangeState.active,
    );
    expect(
      changeStateFor(hunkId: 'c', activeHunkId: 'a', choices: choices),
      ChangeState.pending,
    );
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

  testWidgets('a change starting on an undrawn line still gets a bubble',
      (tester) async {
    // The hunk starts on `DONE:`, which is a section header the view never
    // draws on its own; the anchor must fall to the task line below it.
    const oldText = '[TASK_LIST id="4"]\nACTIVE:\n- [ ] Stretch\n[/TASK_LIST]';
    const newText = '[TASK_LIST id="4"]\nACTIVE:\n- [ ] Stretch\n'
        'DONE:\n- [x] Warm up\n[/TASK_LIST]';
    final pending = PendingReview(
      id: 2,
      fileId: 4,
      oldAgentText: oldText,
      newAgentText: newText,
      hunks: [
        hunk(
          id: 'add-4-5',
          op: 'add',
          newLines: const ['DONE:', '- [x] Warm up'],
          oldStart: 4,
          oldEnd: 3,
          newStart: 4,
          newEnd: 5,
        ),
      ],
    );

    var finished = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => LookalikeReviewDialog.show(
              context,
              pending: pending,
              strings: AppStrings.en,
              onFinish: (_) async => finished = true,
              onDiscard: () async {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Warm up'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(finished, isTrue);
  });

  testWidgets('the dialog draws real content and walks changes with the bubble',
      (tester) async {
    const oldText = '## Plan\nRun daily\n[TABLE id="7"]\nDay\\tLoad\n'
        'Monday\\t5\n[/TABLE]';
    const newText = '## Plan\nRun twice daily\n[TABLE id="7"]\nDay\\tLoad\n'
        'Monday\\t8\n[/TABLE]';
    final pending = PendingReview(
      id: 1,
      fileId: 3,
      oldAgentText: oldText,
      newAgentText: newText,
      hunks: [
        hunk(
          id: 'change-2-2',
          oldLines: const ['Run daily'],
          newLines: const ['Run twice daily'],
          oldStart: 2,
          oldEnd: 2,
          newStart: 2,
          newEnd: 2,
        ),
        hunk(
          id: 'change-5-5',
          oldLines: const [r'Monday\t5'],
          newLines: const [r'Monday\t8'],
          oldStart: 5,
          oldEnd: 5,
          newStart: 5,
          newEnd: 5,
        ),
      ],
    );

    List<Map<String, String>>? finished;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => LookalikeReviewDialog.show(
              context,
              pending: pending,
              strings: AppStrings.en,
              fileName: 'Training',
              onFinish: (decisions) async => finished = decisions,
              onDiscard: () async {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Blocks are drawn, not marker text.
    expect(find.text('Plan'), findsNWidgets(2));
    expect(find.textContaining('[TABLE'), findsNothing);
    expect(find.text('Monday'), findsNWidgets(2));
    expect(find.text('8'), findsOneWidget);

    // The bubble starts on the first change.
    expect(find.text('1 / 2'), findsOneWidget);
    expect(find.text('0 of 2 decided'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    expect(find.text('1 of 2 decided'), findsOneWidget);

    await tester.tap(find.byTooltip('Reject'));
    await tester.pumpAndSettle();

    // Last decision made: the bubble steps aside for Finish.
    expect(find.byTooltip('Accept'), findsNothing);
    expect(find.text('2 of 2 decided'), findsOneWidget);

    // Touching a decided change brings it back so the choice can be flipped.
    await tester.tap(find.text('Run twice daily'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Accept'), findsOneWidget);
    expect(find.text('1 / 2'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Accept'), findsNothing);

    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(finished, [
      {'hunk_id': 'change-2-2', 'choice': 'accept'},
      {'hunk_id': 'change-5-5', 'choice': 'reject'},
    ]);
  });
}
