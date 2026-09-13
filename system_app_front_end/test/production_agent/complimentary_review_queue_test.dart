import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';
import 'package:system_app_front_end/areas/automations/complimentary_review_queue.dart';
import 'package:system_app_front_end/areas/production_agent/pending_review_service.dart';

class ReviewState extends AppState {
  bool completed = false;
  final opened = <int>[];
  @override
  AppStrings get strings => AppStrings.en;
  @override
  Future<Map<String, dynamic>> complimentaryReviewStatus(int id) async => {
    'topics': [
      {
        'id': 1,
        'name': 'Fitness',
        'color': '#448866',
        'files': [
          {'id': 10, 'name': 'Plan'},
        ],
      },
      {'id': 2, 'name': 'Sleep', 'color': '#886644', 'files': []},
    ],
  };
  @override
  Future<PendingReview?> pendingReviewForFile(int id) async {
    opened.add(id);
    return PendingReview(
      id: 1,
      fileId: id,
      oldAgentText: 'Old',
      newAgentText: 'New',
      hunks: const [
        PendingReviewHunk(
          id: 'one',
          op: 'change',
          oldLines: ['Old'],
          newLines: ['New'],
          oldStart: 1,
          oldEnd: 1,
          newStart: 1,
          newEnd: 1,
        ),
      ],
    );
  }

  @override
  Future<void> finishPendingReview(
    int id,
    List<Map<String, String>> decisions,
  ) async {}
  @override
  Future<Map<String, dynamic>> completeComplimentaryReview(int id) async {
    completed = true;
    return {'completed': true};
  }

  @override
  Future<void> loadAutomations() async {}
}

void main() {
  testWidgets(
    'queue survives task unmount and acknowledges a topic with no changes',
    (tester) async {
      final state = ReviewState();
      final showTask = ValueNotifier(true);
      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<bool>(
            valueListenable: showTask,
            builder: (context, show, _) => show
                ? Builder(
                    builder: (taskContext) => TextButton(
                      onPressed: () =>
                          openComplimentaryReviewQueue(taskContext, state, 1),
                      child: const Text('Review'),
                    ),
                  )
                : const SizedBox(),
          ),
        ),
      );
      await tester.tap(find.text('Review'));
      await tester.pumpAndSettle();
      expect(state.reviewInteractionActive, isTrue);
      expect(find.text('Fitness'), findsOneWidget);
      // A section refresh can remove the task widget while its dialog is open.
      showTask.value = false;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(find.text('Fitness'), findsOneWidget);
      expect(find.text('Plan'), findsOneWidget);
      await tester.tap(find.byTooltip('Accept'));
      await tester.pump(); // no repeated click or animation completion required
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Finish'))
            .onPressed,
        isNotNull,
      );
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.text('Sleep'), findsOneWidget);
      expect(find.text('This topic has no changes pending.'), findsOneWidget);
      expect(state.reviewInteractionActive, isTrue);
      expect(state.completed, isFalse);
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      expect(state.opened, [10]);
      expect(state.reviewInteractionActive, isFalse);
      expect(state.completed, isTrue);
      expect(tester.takeException(), isNull);
      showTask.dispose();
      state.dispose();
    },
  );
}
