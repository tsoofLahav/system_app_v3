import '../../areas/files/data/app_file.dart';
import '../../areas/files/data/topic.dart';

class ArchiveTopicEntry {
  const ArchiveTopicEntry({
    required this.topic,
    this.archivedFileCount = 0,
    this.files = const [],
  });

  final Topic topic;
  final int archivedFileCount;
  final List<AppFile> files;
}

class ArchiveIndex {
  const ArchiveIndex({this.daily, this.topics = const []});

  final ArchiveTopicEntry? daily;
  final List<ArchiveTopicEntry> topics;

  static const empty = ArchiveIndex();

  bool get isEmpty => daily == null && topics.isEmpty;

  List<ArchiveTopicEntry> topicsOfType(int typeId) => [
    for (final entry in topics)
      if (entry.topic.topicTypeId == typeId) entry,
  ];

  List<ArchiveTopicEntry> get untypedTopics => [
    for (final entry in topics)
      if (entry.topic.topicTypeId == null) entry,
  ];
}
