class Topic {
  const Topic({
    required this.id,
    required this.name,
    required this.type,
    this.icon,
    this.color,
    this.parentId,
    this.createdAt,
  });

  final int id;
  final String name;
  final String type;
  final String? icon;
  final String? color;
  final int? parentId;
  final String? createdAt;

  bool get isMain => name == 'main';

  factory Topic.fromJson(Map<String, dynamic> json) {
    return Topic(
      id: json['id'] as int,
      name: json['name'] as String,
      type: json['type'] as String,
      icon: json['icon'] as String?,
      color: json['color'] as String?,
      parentId: json['parent_id'] as int?,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        if (icon != null) 'icon': icon,
        if (color != null) 'color': color,
        if (parentId != null) 'parent_id': parentId,
      };
}
