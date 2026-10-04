import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';
import 'package:system_app_front_end/areas/production_agent/lookalike_review_dialog.dart';
import 'package:system_app_front_end/areas/production_agent/pending_review_service.dart';
import 'package:system_app_front_end/areas/production_agent/review_text_edit.dart';

PendingReview review(String old, String proposed, {int line = 0}) =>
    PendingReview(
      id: 1,
      fileId: 1,
      oldAgentText: old,
      newAgentText: proposed,
      hunks: [
        PendingReviewHunk(
          id: 'change',
          op: 'change',
          oldLines: [old.split('\n')[line]],
          newLines: [proposed.split('\n')[line]],
          oldStart: line + 1,
          oldEnd: line + 1,
          newStart: line + 1,
          newEnd: line + 1,
        ),
      ],
    );

void main() {
  test('task markers preserved; object fences are not editable', () {
    final task = review(
      '[TASK_LIST id="1"]\n- [x] old\n[/TASK_LIST]',
      '[TASK_LIST id="1"]\n- [x] new\n[/TASK_LIST]',
      line: 1,
    );
    expect(reviewTextEdit(task, task.hunks.single)?.prefix, '- [x] ');
    final fence = review('[INFO id="1"]', '[INFO id="2"]');
    expect(reviewTextEdit(fence, fence.hunks.single), isNull);
  });

  for (final strings in [AppStrings.en, AppStrings.he]) {
    testWidgets(
      'rewrite is accepted and sent only on Finish (${strings.language})',
      (tester) async {
        List<Map<String, String>>? saved;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => TextButton(
                child: const Text('Open'),
                onPressed: () => LookalikeReviewDialog.show(
                  context,
                  pending: review('Old text', 'Suggested text'),
                  strings: strings,
                  onFinish: (decisions) async {
                    saved = decisions;
                  },
                  onDiscard: () async {},
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip(strings['edit']));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'My wording');
        // Review keyboard shortcuts must not intercept normal editing keys.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
        await tester.enterText(find.byType(TextField), 'My wording');
        await tester.tap(
          find.widgetWithText(FilledButton, strings['reviewAccept']),
        );
        await tester.pumpAndSettle();
        expect(saved, isNull);
        expect(find.text('My wording', findRichText: true), findsWidgets);
        await tester.tap(
          find.widgetWithText(FilledButton, strings['reviewFinish']),
        );
        await tester.pumpAndSettle();
        expect(saved, [
          {
            'hunk_id': 'change',
            'choice': 'accept',
            'replacement_text': 'My wording',
          },
        ]);
      },
    );
  }
  testWidgets('cancel leaves undecided; rejecting a rewrite keeps original', (
    tester,
  ) async {
    List<Map<String, String>>? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            child: const Text('Open'),
            onPressed: () => LookalikeReviewDialog.show(
              context,
              pending: review('Old text', 'Suggested text'),
              strings: AppStrings.en,
              onFinish: (decisions) async {
                saved = decisions;
              },
              onDiscard: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cancelled');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      'Suggested text',
    );
    await tester.enterText(find.byType(TextField), 'My wording');
    await tester.tap(find.widgetWithText(FilledButton, 'Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My wording', findRichText: true).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
    await tester.pumpAndSettle();
    expect(saved, [
      {'hunk_id': 'change', 'choice': 'reject'},
    ]);
  });
}
