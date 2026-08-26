import '../../../core/models/tag.dart';

class Topic {
  const Topic({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.icon,
    this.color,
    this.orderIndex = 0,
    this.fileLayout = 'auto',
    this.topicTypeId,
    this.isTemplate = false,
    this.archivedAt,
    this.createdAt,
    this.tags = const [],
  });

  final int id;
  final int workspaceId;
  final String name;
  final String? icon;
  final String? color;
  final int orderIndex;

  /// How this topic arranges its files, and with that how many it shows at all.
  final String fileLayout;

  /// User-defined kind. Home stays untyped.
  final int? topicTypeId;

  /// Hidden type template — not listed in the sidebar.
  final bool isTemplate;

  final String? archivedAt;
  final String? createdAt;
  final List<AppTag> tags;

  bool get isMain => name.toLowerCase() == 'home';
  bool get isArchived => archivedAt != null;

  String? get primaryTag => tags.isNotEmpty ? tags.first.name : null;

  factory Topic.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    return Topic(
      id: json['id'] as int,
      workspaceId: json['workspace_id'] as int,
      name: json['name'] as String,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      orderIndex: json['order_index'] as int? ?? 0,
      fileLayout: json['file_layout'] as String? ?? 'auto',
      topicTypeId: json['topic_type_id'] as int?,
      isTemplate: json['is_template'] as bool? ?? false,
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
      tags: rawTags is List
          ? rawTags
                .map((e) => AppTag.fromJson(e as Map<String, dynamic>))
                .toList()
          : const [],
    );
  }

  Topic copyWith({
    String? name,
    String? icon,
    String? color,
    int? orderIndex,
    String? fileLayout,
    int? topicTypeId,
    bool clearTopicType = false,
    List<AppTag>? tags,
  }) {
    return Topic(
      id: id,
      workspaceId: workspaceId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      orderIndex: orderIndex ?? this.orderIndex,
      fileLayout: fileLayout ?? this.fileLayout,
      topicTypeId: clearTopicType ? null : (topicTypeId ?? this.topicTypeId),
      isTemplate: isTemplate,
      archivedAt: archivedAt,
      createdAt: createdAt,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    if (icon != null) 'icon': icon,
    if (color != null) 'color': color,
    'order_index': orderIndex,
    'file_layout': fileLayout,
    if (topicTypeId != null) 'topic_type_id': topicTypeId,
    if (archivedAt != null) 'archived_at': archivedAt,
  };
}

/// A task-list object living in a live file of a topic.
class TopicTaskList {
  const TopicTaskList({
    required this.id,
    required this.title,
    this.objectId,
    this.fileId,
  });

  final int id;
  final String title;
  final int? objectId;
  final int? fileId;

  factory TopicTaskList.fromJson(Map<String, dynamic> json) {
    return TopicTaskList(
      id: json['id'] as int,
      title: (json['title'] as String?) ?? '',
      objectId: json['object_id'] as int?,
      fileId: json['file_id'] as int?,
    );
  }
}
