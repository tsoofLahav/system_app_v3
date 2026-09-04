import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../../objects/data/object_embed.dart';
import '../../objects/data/task.dart';
import '../../../core/models/tag.dart';
import './app_file.dart';
import './topic.dart';

/// Last open topic + sidebar chrome, written under app documents for first paint.
class LaunchSnapshot {
  const LaunchSnapshot({
    required this.workspaceId,
    required this.selectedTopicId,
    required this.topics,
    required this.files,
    required this.embedsByFileId,
    this.homeVisitFileIds = const [],
    this.homeCanvasOrderIds = const [],
  });

  static const version = 1;

  final int workspaceId;
  final int selectedTopicId;
  final List<Topic> topics;
  final List<AppFile> files;
  final Map<int, List<ObjectEmbed>> embedsByFileId;
  final List<int> homeVisitFileIds;
  final List<int> homeCanvasOrderIds;

  Map<String, dynamic> toJson() => {
    'version': version,
    'workspaceId': workspaceId,
    'selectedTopicId': selectedTopicId,
    'topics': [for (final topic in topics) _topicJson(topic)],
    'files': [for (final file in files) _fileJson(file)],
    'embedsByFileId': {
      for (final entry in embedsByFileId.entries)
        '${entry.key}': [for (final embed in entry.value) _embedJson(embed)],
    },
    'homeVisitFileIds': homeVisitFileIds,
    'homeCanvasOrderIds': homeCanvasOrderIds,
  };

  static LaunchSnapshot? fromJson(Map<String, dynamic> json) {
    final workspaceId = json['workspaceId'] as int?;
    final selectedTopicId = json['selectedTopicId'] as int?;
    final rawTopics = json['topics'];
    final rawFiles = json['files'];
    if (workspaceId == null ||
        selectedTopicId == null ||
        rawTopics is! List ||
        rawFiles is! List) {
      return null;
    }
    final topics = <Topic>[];
    for (final raw in rawTopics) {
      if (raw is! Map) continue;
      topics.add(Topic.fromJson(Map<String, dynamic>.from(raw)));
    }
    final files = <AppFile>[];
    for (final raw in rawFiles) {
      if (raw is! Map) continue;
      files.add(AppFile.fromJson(Map<String, dynamic>.from(raw)));
    }
    if (topics.isEmpty || files.isEmpty) return null;
    if (!topics.any((t) => t.id == selectedTopicId)) return null;
    return LaunchSnapshot(
      workspaceId: workspaceId,
      selectedTopicId: selectedTopicId,
      topics: topics,
      files: files,
      embedsByFileId: _embedsFromJson(json['embedsByFileId']),
      homeVisitFileIds: _idsFromJson(json['homeVisitFileIds']),
      homeCanvasOrderIds: _idsFromJson(json['homeCanvasOrderIds']),
    );
  }
}

/// Take inbound metadata and body. Session SoT for a dirty editor stays in
/// Super Editor; hiding the server body here blocked 3-way merge.
AppFile mergeTopicFileForRefresh({
  required AppFile local,
  required AppFile inbound,
  required bool bodyDirty,
}) {
  // [local] / [bodyDirty] kept so callers stay stable; body always inbound.
  return inbound;
}

bool isScratchFile(AppFile file) => file.meta['automation_scratch'] == true;

class LaunchSnapshotStore {
  LaunchSnapshotStore({Directory? directory}) : _directory = directory;

  static const fileName = 'launch_snapshot.json';

  final Directory? _directory;

  Future<LaunchSnapshot?> load() async {
    try {
      final file = await _snapshotFile();
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return null;
      return LaunchSnapshot.fromJson(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  Future<void> save(LaunchSnapshot snapshot) async {
    try {
      final file = await _snapshotFile();
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode(snapshot.toJson()));
    } catch (_) {}
  }

  Future<File> _snapshotFile() async {
    final dir = _directory ?? await getApplicationDocumentsDirectory();
    return File('${dir.path}/$fileName');
  }
}

Map<int, List<ObjectEmbed>> _embedsFromJson(dynamic raw) {
  if (raw is! Map) return const {};
  final out = <int, List<ObjectEmbed>>{};
  for (final entry in raw.entries) {
    final id = int.tryParse('${entry.key}');
    final list = entry.value;
    if (id == null || list is! List) continue;
    out[id] = [
      for (final item in list)
        if (item is Map) ObjectEmbed.fromJson(Map<String, dynamic>.from(item)),
    ];
  }
  return out;
}

List<int> _idsFromJson(dynamic raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is int) item else if (item is num) item.toInt(),
  ];
}

Map<String, dynamic> _topicJson(Topic topic) => {
  'id': topic.id,
  'workspace_id': topic.workspaceId,
  'name': topic.name,
  if (topic.icon != null) 'icon': topic.icon,
  if (topic.color != null) 'color': topic.color,
  'order_index': topic.orderIndex,
  'file_layout': topic.fileLayout,
  if (topic.topicTypeId != null) 'topic_type_id': topic.topicTypeId,
  'is_template': topic.isTemplate,
};

Map<String, dynamic> _fileJson(AppFile file) => {
  'id': file.id,
  'topic_id': file.topicId,
  'name': file.name,
  'document_json': file.documentJson,
  'order_index': file.orderIndex,
  if (file.meta.isNotEmpty) 'meta': file.meta,
  if (file.archivedAt != null) 'archived_at': file.archivedAt,
  if (file.createdAt != null) 'created_at': file.createdAt,
};

Map<String, dynamic> _embedJson(ObjectEmbed embed) => {
  'id': embed.id,
  'file_id': embed.fileId,
  'type': embed.type,
  if (embed.taskListId != null) 'task_list_id': embed.taskListId,
  if (embed.taskListTitle.isNotEmpty)
    'task_list': {'title': embed.taskListTitle},
  if (embed.informationId != null) 'information_id': embed.informationId,
  'anchor': embed.anchor,
  'sort_key': embed.sortKey,
  if (embed.tasks != null)
    'tasks': [for (final task in embed.tasks!) _taskJson(task)],
  if (embed.information != null) 'information': embed.information,
  if (embed.connections.isNotEmpty) 'connections': embed.connections,
  if (embed.tags.isNotEmpty)
    'tags': [for (final tag in embed.tags) _tagJson(tag)],
  if (embed.payload != null) 'payload': embed.payload,
};

Map<String, dynamic> _taskJson(Task task) => {
  'id': task.id,
  if (task.taskListId != null) 'task_list_id': task.taskListId,
  'title': task.title,
  'status': task.status,
  'list_order_index': task.listOrderIndex,
  if (task.dueDate != null) 'due_date': task.dueDate,
};

Map<String, dynamic> _tagJson(AppTag tag) => {
  'id': tag.id,
  'workspace_id': tag.workspaceId,
  'name': tag.name,
  if (tag.color != null) 'color': tag.color,
  if (tag.icon != null) 'icon': tag.icon,
};
