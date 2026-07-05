import 'topic.dart';

class ArchiveTopicEntry {
  const ArchiveTopicEntry({
    required this.topic,
    required this.archivedFileCount,
  });

  final Topic topic;
  final int archivedFileCount;
}

class ArchiveIndex {
  const ArchiveIndex({
    this.daily,
    this.projects = const [],
    this.processes = const [],
    this.areas = const [],
  });

  final ArchiveTopicEntry? daily;
  final List<ArchiveTopicEntry> projects;
  final List<ArchiveTopicEntry> processes;
  final List<ArchiveTopicEntry> areas;

  static const empty = ArchiveIndex();

  bool get isEmpty =>
      daily == null &&
      projects.isEmpty &&
      processes.isEmpty &&
      areas.isEmpty;
}
