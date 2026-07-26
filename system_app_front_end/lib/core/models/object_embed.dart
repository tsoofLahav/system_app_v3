import '../models/task.dart';

class ObjectEmbed {
  const ObjectEmbed({
    required this.id,
    required this.fileId,
    required this.type,
    this.taskId,
    this.informationId,
    this.anchor = const {},
    this.sortKey = 0,
    this.task,
    this.information,
  });

  final int id;
  final int fileId;
  final String type;
  final int? taskId;
  final int? informationId;
  final Map<String, dynamic> anchor;
  final int sortKey;
  final Task? task;
  final Map<String, dynamic>? information;

  factory ObjectEmbed.fromJson(Map<String, dynamic> json) {
    return ObjectEmbed(
      id: json['id'] as int,
      fileId: json['file_id'] as int,
      type: json['type'] as String,
      taskId: json['task_id'] as int?,
      informationId: json['information_id'] as int?,
      anchor: json['anchor'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['anchor'] as Map)
          : const {},
      sortKey: json['sort_key'] as int? ?? 0,
      task: json['task'] != null
          ? Task.fromJson(json['task'] as Map<String, dynamic>)
          : null,
      information: json['information'] is Map<String, dynamic>
          ? Map<String, dynamic>.from(json['information'] as Map)
          : null,
    );
  }
}
