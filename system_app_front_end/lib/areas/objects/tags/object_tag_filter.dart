import '../../../core/models/tag.dart';
import '../../files/data/topic_type.dart';

/// Leftover classification tag names from before `topic_types`.
///
/// Types are not tags. These rows may still exist in `tags` and must not
/// appear in object-tag UI (map filter, assign-tag dialog).
const leftoverTopicTypeTagNames = <String>{
  'project',
  'process',
  'area',
  'other',
  'others',
  'פרויקט',
  'תהליך',
  'תחום',
  'שונות',
};

Set<String> topicTypeTagBlocklist(Iterable<TopicType> types) {
  return {
    for (final type in types) ...[
      type.name.trim().toLowerCase(),
      if (type.nameHe.trim().isNotEmpty) type.nameHe.trim().toLowerCase(),
    ],
    for (final name in leftoverTopicTypeTagNames) name.toLowerCase(),
  };
}

bool isTopicTypeTagName(String name, Set<String> blocklist) =>
    blocklist.contains(name.trim().toLowerCase());

List<AppTag> objectTagsExcludingTopicTypes({
  required List<AppTag> tags,
  required List<TopicType> topicTypes,
}) {
  final blocked = topicTypeTagBlocklist(topicTypes);
  return [
    for (final tag in tags)
      if (!isTopicTypeTagName(tag.name, blocked)) tag,
  ];
}
