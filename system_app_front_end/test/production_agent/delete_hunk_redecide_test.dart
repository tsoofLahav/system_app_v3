import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';
import 'package:system_app_front_end/areas/production_agent/lookalike_review_dialog.dart';
import 'package:system_app_front_end/areas/production_agent/pending_review_service.dart';

void main() {
  testWidgets('a pure deletion can be accepted, then re-decided by tapping it again',
      (tester) async {
    const oldText = 'Line1\nLine2\nLine3';
    const newText = 'Line1\nLine3';
    final pending = PendingReview(
      id: 1,
      fileId: 3,
      oldAgentText: oldText,
      newAgentText: newText,
      hunks: const [
        PendingReviewHunk(
          id: 'remove-1-1',
          op: 'remove',
          oldLines: ['Line2'],
          newLines: [],
          oldStart: 2,
          oldEnd: 2,
          newStart: 2,
          newEnd: 1,
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

    expect(find.text('Line2'), findsOneWidget);
    expect(find.text('1 / 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();

    // Last (only) decision made: bubble stands down, Finish takes over.
    expect(find.byTooltip('Accept'), findsNothing);
    expect(find.text('1 of 1 decided'), findsOneWidget);

    // Touching the now-decided deletion should bring the bubble back.
    await tester.tap(find.text('Line2'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Accept'), findsOneWidget);

    await tester.tap(find.byTooltip('Reject'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();

    expect(finished, [
      {'hunk_id': 'remove-1-1', 'choice': 'reject'},
    ]);
  });
}
