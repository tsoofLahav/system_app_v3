class AppTag {
  const AppTag({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.color,
    this.icon,
  });

  final int id;
  final int workspaceId;
  final String name;
  final String? color;
  final String? icon;

  factory AppTag.fromJson(Map<String, dynamic> json) {
    return AppTag(
      id: json['id'] as int,
      workspaceId: json['workspace_id'] as int,
      name: json['name'] as String,
      color: json['color'] as String?,
      icon: json['icon'] as String?,
    );
  }

  AppTag copyWith({
    String? name,
    String? color,
    String? icon,
  }) {
    return AppTag(
      id: id,
      workspaceId: workspaceId,
      name: name ?? this.name,
      color: color ?? this.color,
      icon: icon ?? this.icon,
    );
  }
}
