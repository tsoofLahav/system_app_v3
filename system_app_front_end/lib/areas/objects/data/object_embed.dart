import '../../../core/models/tag.dart';
import './task.dart';

class ObjectEmbed {
  const ObjectEmbed({
    required this.id,
    required this.fileId,
    required this.type,
    this.taskListId,
    this.taskListTitle = '',
    this.informationId,
    this.anchor = const {},
    this.sortKey = 0,
    this.tasks,
    this.information,
    this.links,
    this.connections = const [],
    this.tags = const [],
    this.payload,
  });

  final int id;
  final int fileId;
  final String type;
  final int? taskListId;
  final String taskListTitle;
  final int? informationId;
  final Map<String, dynamic> anchor;
  final int sortKey;
  final List<Task>? tasks;
  final Map<String, dynamic>? information;
  final List<Map<String, dynamic>>? links;
  final List<Map<String, dynamic>> connections;
  final List<AppTag> tags;
  final Map<String, dynamic>? payload;

  ObjectEmbed copyWith({
    List<Task>? tasks,
    Map<String, dynamic>? information,
    List<Map<String, dynamic>>? links,
    List<Map<String, dynamic>>? connections,
    List<AppTag>? tags,
    Map<String, dynamic>? payload,
    String? taskListTitle,
  }) {
    return ObjectEmbed(
      id: id,
      fileId: fileId,
      type: type,
      taskListId: taskListId,
      taskListTitle: taskListTitle ?? this.taskListTitle,
      informationId: informationId,
      anchor: anchor,
      sortKey: sortKey,
      tasks: tasks ?? this.tasks,
      information: information ?? this.information,
      links: links ?? this.links,
      connections: connections ?? this.connections,
      tags: tags ?? this.tags,
      payload: payload ?? this.payload,
    );
  }

  factory ObjectEmbed.fromJson(Map<String, dynamic> json) {
    final taskList = json['task_list'];
    final listTitle = taskList is Map ? '${taskList['title'] ?? ''}' : '';
    final connectionRaw = json['connections'] ?? json['links'];
    return ObjectEmbed(
      id: json['id'] as int,
      fileId: json['file_id'] as int,
      type: json['type'] as String,
      taskListId: json['task_list_id'] as int?,
      taskListTitle: listTitle,
      informationId: json['information_id'] as int?,
      anchor: json['anchor'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['anchor'] as Map)
          : const {},
      sortKey: json['sort_key'] as int? ?? 0,
      tasks: json['tasks'] is List
          ? [
              for (final t in json['tasks'] as List)
                Task.fromJson(t as Map<String, dynamic>),
            ]
          : null,
      information: json['information'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['information'] as Map)
          : null,
      links: connectionRaw is List
          ? [
              for (final l in connectionRaw)
                Map<String, dynamic>.from(l as Map),
            ]
          : null,
      connections: connectionRaw is List
          ? [
              for (final l in connectionRaw)
                Map<String, dynamic>.from(l as Map),
            ]
          : const [],
      tags: json['tags'] is List
          ? [
              for (final t in json['tags'] as List)
                AppTag.fromJson(Map<String, dynamic>.from(t as Map)),
            ]
          : const [],
      payload: json['payload'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : null,
    );
  }
}
