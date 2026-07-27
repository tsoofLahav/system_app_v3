import '../../../core/models/tag.dart';

class Topic {
  const Topic({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.icon,
    this.color,
    this.orderIndex = 0,
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
    List<AppTag>? tags,
  }) {
    return Topic(
      id: id,
      workspaceId: workspaceId,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      color: color ?? this.color,
      orderIndex: orderIndex ?? this.orderIndex,
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
    if (archivedAt != null) 'archived_at': archivedAt,
  };
}
