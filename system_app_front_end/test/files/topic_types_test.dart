import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/topic.dart';
import 'package:system_app_front_end/areas/files/data/topic_type.dart';
import 'package:system_app_front_end/areas/files/data/app_file.dart';

void main() {
  test('a topic type carries its template pointer', () {
    final type = TopicType.fromJson({
      'id': 2,
      'workspace_id': 1,
      'name': 'process',
      'order_index': 1,
      'template_topic_id': 9,
    });
    expect(type.name, 'process');
    expect(type.templateTopicId, 9);
  });

  test('a topic stores its type id, not a magic tag', () {
    final topic = Topic.fromJson({
      'id': 4,
      'workspace_id': 1,
      'name': 'Onboarding',
      'topic_type_id': 2,
    });
    expect(topic.topicTypeId, 2);
  });

  test('a file keeps its template slot through JSON', () {
    final file = AppFile.fromJson({
      'id': 8,
      'topic_id': 4,
      'name': 'Doc',
      'meta': {'template_slot': 'doc'},
    });
    expect(file.templateSlot, 'doc');
  });
}
