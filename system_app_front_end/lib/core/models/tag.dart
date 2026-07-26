class AppTag {
  const AppTag({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.color,
  });

  final int id;
  final int workspaceId;
  final String name;
  final String? color;

  factory AppTag.fromJson(Map<String, dynamic> json) {
    return AppTag(
      id: json['id'] as int,
      workspaceId: json['workspace_id'] as int,
      name: json['name'] as String,
      color: json['color'] as String?,
    );
  }
}
