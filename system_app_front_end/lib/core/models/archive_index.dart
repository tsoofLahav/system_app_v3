import 'app_file.dart';
import 'topic.dart';

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
  const ArchiveIndex({
    this.daily,
    this.topics = const [],
    this.projects = const [],
    this.processes = const [],
    this.areas = const [],
    this.others = const [],
  });

  final ArchiveTopicEntry? daily;
  final List<ArchiveTopicEntry> topics;
  final List<ArchiveTopicEntry> projects;
  final List<ArchiveTopicEntry> processes;
  final List<ArchiveTopicEntry> areas;
  final List<ArchiveTopicEntry> others;

  static const empty = ArchiveIndex();

  bool get isEmpty =>
      daily == null &&
      topics.isEmpty &&
      projects.isEmpty &&
      processes.isEmpty &&
      areas.isEmpty &&
      others.isEmpty;
}
