import 'package:system_app_front_end/areas/objects/data/object_service.dart';
import 'package:system_app_front_end/areas/objects/links/add_connection_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/links/info_pick_rank.dart';

void main() {
  test('archive metadata survives parsing and excludes connection choices', () {
    final archived = ObjectGraphNode.fromJson({
      'object_id': 10, 'file_id': 1, 'type': 'info',
      'title': 'Archived info', 'is_archived': true,
    });
    final live = ObjectGraphNode.fromJson({
      'object_id': 11, 'file_id': 2, 'type': 'info', 'title': 'Live info',
    });
    expect(archived.copyWith(title: 'Renamed').isArchived, isTrue);
    expect(namedInfoNodes([archived, live]).map((node) => node.objectId), [11]);
    expect(namedInfoNodes([archived, live], query: 'Archived'), isEmpty);
  });

  test('same name ranks above a different title', () {
    expect(textSimilarity('Milk', 'Milk'), 1);
    expect(isSimilarName('Buy milk', 'Milk'), isTrue);
    expect(isSimilarName('Project plan', 'totally other'), isFalse);
  });

  test('empty search offers similar names, then topic, then the rest', () {
    final ranked = rankInfoPicks(
      items: const [
        (title: 'Zebra', topicId: 9),
        (title: 'Milk', topicId: 2),
        (title: 'Buy milk list', topicId: 9),
        (title: 'Alpha', topicId: 1),
      ],
      titleOf: (i) => i.title,
      topicOf: (i) => i.topicId,
      similarTo: 'Milk',
      topicId: 1,
    );
    expect(ranked.map((i) => i.title).toList(), [
      'Milk',
      'Buy milk list',
      'Alpha',
      'Zebra',
    ]);
  });

  test(
    'a typed search drops similar-text offers and lists the topic first',
    () {
      final ranked = rankInfoPicks(
        items: const [
          (title: 'Milk run', topicId: 9),
          (title: 'Alpha milk', topicId: 1),
          (title: 'Milk', topicId: 2),
        ],
        titleOf: (i) => i.title,
        topicOf: (i) => i.topicId,
        query: 'milk',
        similarTo: 'Milk',
        topicId: 1,
      );
      expect(ranked.map((i) => i.title).toList(), [
        'Alpha milk',
        'Milk',
        'Milk run',
      ]);
    },
  );
}
