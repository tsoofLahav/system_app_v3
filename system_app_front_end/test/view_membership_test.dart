import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/app_view.dart';
import 'package:system_app_front_end/areas/objects/data/view_layout.dart';

void main() {
  test('ViewMembership keeps topic_order_index apart from order_index', () {
    final row = ViewMembership.fromJson({
      'id': 1,
      'view_id': 2,
      'task_id': 3,
      'section_name': 'Later',
      'order_index': 4,
      'topic_order_index': 9,
      'topic_key': 'topic_1',
    });
    expect(row.orderIndex, 4);
    expect(row.topicOrderIndex, 9);
    expect(row.toReplaceJson()['topic_order_index'], 9);
    expect(row.toReplaceJson()['order_index'], 4);
  });

  test('ViewMembership falls back to order_index when topic column is absent', () {
    final row = ViewMembership.fromJson({
      'id': 1,
      'view_id': 2,
      'task_id': 3,
      'order_index': 5,
    });
    expect(row.topicOrderIndex, 5);
  });

  test('copyWith can clear section without touching topic order', () {
    const row = ViewMembership(
      id: 1,
      viewId: 2,
      taskId: 3,
      sectionName: 'Later',
      orderIndex: 1,
      topicOrderIndex: 8,
    );
    final next = row.copyWith(clearSection: true);
    expect(next.sectionName, isNull);
    expect(next.topicOrderIndex, 8);
    expect(next.orderIndex, 1);
  });

  test('membership with empty topic_key stays in No topic', () {
    expect(
      ViewLayoutConfig.topicBucketKey(
        hasMembership: true,
        membershipTopicKey: null,
        homeTopicId: 7,
      ),
      'no_topic',
    );
    expect(
      ViewLayoutConfig.topicBucketKey(
        hasMembership: true,
        membershipTopicKey: 'topic_3',
      ),
      'topic_3',
    );
    expect(
      ViewLayoutConfig.topicBucketKey(
        hasMembership: false,
        homeTopicId: 7,
      ),
      'topic_7',
    );
  });

  test('assigning a view inherits the home topic when membership key is empty', () {
    expect(
      ViewLayoutConfig.topicKeyForAssign(
        existingMembershipKey: null,
        homeTopicId: 7,
      ),
      'topic_7',
    );
    expect(
      ViewLayoutConfig.topicKeyForAssign(
        existingMembershipKey: '',
        homeTopicKey: 'topic_4',
      ),
      'topic_4',
    );
    expect(
      ViewLayoutConfig.topicKeyForAssign(
        existingMembershipKey: 'topic_9',
        homeTopicId: 7,
      ),
      'topic_9',
    );
    expect(
      ViewLayoutConfig.topicKeyForAssign(existingMembershipKey: null),
      isNull,
    );
  });

  test('one section can be the default', () {
    const inbox = ViewSectionDef(name: 'Inbox', isDefault: true);
    const later = ViewSectionDef(name: 'Later');
    expect(inbox.toJson()['default'], isTrue);
    expect(later.toJson().containsKey('default'), isFalse);
    final restored = ViewSectionDef.fromJson(inbox.toJson(), 0);
    expect(restored.isDefault, isTrue);
    final next = ViewLayoutConfig.withSingleDefault(
      [inbox, later],
      defaultName: 'Later',
    );
    expect(next[0].isDefault, isFalse);
    expect(next[1].isDefault, isTrue);
    expect(
      ViewLayoutConfig.defaultSection({
        'sections': [for (final s in next) s.toJson()],
      })?.name,
      'Later',
    );
  });
}
