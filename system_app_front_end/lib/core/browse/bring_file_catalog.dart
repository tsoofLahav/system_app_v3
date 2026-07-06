import '../models/app_file.dart';
import '../models/topic.dart';

class BrowseFileEntry {
  const BrowseFileEntry({required this.topic, required this.file});

  final Topic topic;
  final AppFile file;

  String get topicLabel => topic.name;
  String get fileLabel => file.name;
}

List<BrowseFileEntry> buildBringFileCatalog({
  required List<Topic> topics,
  required List<AppFile> files,
  required Topic? mainTopic,
}) {
  if (mainTopic == null) return const [];

  final topicById = {for (final topic in topics) topic.id: topic};
  final entries = <BrowseFileEntry>[];

  for (final file in files) {
    if (file.archivedAt != null) continue;
    if (file.topicId == mainTopic.id) continue;
    final topic = topicById[file.topicId];
    if (topic == null || topic.isArchived) continue;
    entries.add(BrowseFileEntry(topic: topic, file: file));
  }

  entries.sort((a, b) {
    final topicCmp = a.topicLabel.toLowerCase().compareTo(b.topicLabel.toLowerCase());
    if (topicCmp != 0) return topicCmp;
    return a.fileLabel.toLowerCase().compareTo(b.fileLabel.toLowerCase());
  });
  return entries;
}

List<BrowseFileEntry> filterBringFileCatalog(
  List<BrowseFileEntry> entries,
  String query, {
  String Function(Topic topic)? topicLabel,
  String Function(AppFile file)? fileLabel,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return entries;

  final parts = trimmed.split(RegExp(r'\s+'));
  final topicQuery = parts.first.toLowerCase();
  final fileQuery = parts.length > 1
      ? parts.sublist(1).join(' ').toLowerCase()
      : '';

  return entries.where((entry) {
    final topicNames = <String>{
      entry.topicLabel.toLowerCase(),
      (topicLabel?.call(entry.topic) ?? entry.topicLabel).toLowerCase(),
    };
    final fileNames = <String>{
      entry.fileLabel.toLowerCase(),
      (fileLabel?.call(entry.file) ?? entry.fileLabel).toLowerCase(),
    };

    final topicMatch =
        topicQuery.isEmpty || topicNames.any((name) => name.contains(topicQuery));
    final fileMatch =
        fileQuery.isEmpty || fileNames.any((name) => name.contains(fileQuery));
    return topicMatch && fileMatch;
  }).toList();
}
