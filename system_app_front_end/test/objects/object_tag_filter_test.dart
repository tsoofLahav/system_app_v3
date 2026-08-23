import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/data/topic_type.dart';
import 'package:system_app_front_end/areas/objects/tags/object_tag_filter.dart';
import 'package:system_app_front_end/core/models/tag.dart';

void main() {
  AppTag tag(int id, String name) => AppTag(
        id: id,
        workspaceId: 1,
        name: name,
      );

  test('object-tag UI drops leftover topic-type names', () {
    final tags = objectTagsExcludingTopicTypes(
      tags: [
        tag(1, 'project'),
        tag(2, 'Process'),
        tag(3, 'people'),
        tag(4, 'פרויקט'),
      ],
      topicTypes: const [],
    );
    expect(tags.map((t) => t.name), ['people']);
  });

  test('object-tag UI drops the current topic-type names', () {
    final tags = objectTagsExcludingTopicTypes(
      tags: [
        tag(1, 'client work'),
        tag(2, 'workshop'),
        tag(3, 'סדנה'),
      ],
      topicTypes: const [
        TopicType(id: 1, workspaceId: 1, name: 'workshop', nameHe: 'סדנה'),
      ],
    );
    expect(tags.map((t) => t.id), [1]);
  });
}
