import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/production_agent/topic_review_queue.dart';
import 'complimentary_review_queue_test.dart' show ReviewState;

class TopicState extends ReviewState {
  final acknowledgements = <int>[];
  @override
  Future<Map<String, dynamic>> topicPendingReviews(int topicId) async => {
    'topic': {'id': topicId, 'name': 'Fitness', 'color': '#448866'},
    'files': [{'id': 10, 'name': 'Visible plan'}, {'id': 20, 'name': 'Hidden log'}],
    'run_ids': [71],
  };
  @override
  Future<void> acknowledgeTopicReview(int topicId, List<int> runIds) async {
    expect(runIds, [71]);
    acknowledgements.add(topicId);
  }
}

void main() {
  testWidgets('topic entry reviews hidden files and acknowledges only after the full queue', (tester) async {
    final state = TopicState();
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => TextButton(
      onPressed: () => openTopicReviewQueue(context, state, 1), child: const Text('Open topic')))));
    await tester.tap(find.text('Open topic'));
    await tester.pumpAndSettle();
    expect(find.text('Visible plan'), findsOneWidget);
    expect(state.acknowledgements, isEmpty);
    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(find.text('Hidden log'), findsOneWidget);
    expect(state.acknowledgements, isEmpty);
    await tester.tap(find.byTooltip('Accept'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish'));
    await tester.pumpAndSettle();
    expect(state.opened, [10, 20]);
    expect(state.acknowledgements, [1]);
    expect(state.reviewInteractionActive, isFalse);
    state.dispose();
  });
}
