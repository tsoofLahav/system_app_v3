import './task.dart';

class ObjectEmbed {
  const ObjectEmbed({
    required this.id,
    required this.fileId,
    required this.type,
    this.taskListId,
    this.informationId,
    this.anchor = const {},
    this.sortKey = 0,
    this.tasks,
    this.information,
    this.links,
    this.payload,
  });

  final int id;
  final int fileId;
  final String type;
  final int? taskListId;
  final int? informationId;
  final Map<String, dynamic> anchor;
  final int sortKey;
  final List<Task>? tasks;
  final Map<String, dynamic>? information;
  final List<Map<String, dynamic>>? links;
  final Map<String, dynamic>? payload;

  factory ObjectEmbed.fromJson(Map<String, dynamic> json) {
    return ObjectEmbed(
      id: json['id'] as int,
      fileId: json['file_id'] as int,
      type: json['type'] as String,
      taskListId: json['task_list_id'] as int?,
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
      links: json['links'] is List
          ? [
              for (final l in json['links'] as List)
                Map<String, dynamic>.from(l as Map),
            ]
          : null,
      payload: json['payload'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['payload'] as Map)
          : null,
    );
  }
}
