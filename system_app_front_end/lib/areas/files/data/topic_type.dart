class TopicType {
  const TopicType({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.orderIndex = 0,
    this.templateTopicId,
  });

  final int id;
  final int workspaceId;
  final String name;
  final int orderIndex;
  final int? templateTopicId;

  factory TopicType.fromJson(Map<String, dynamic> json) => TopicType(
    id: json['id'] as int,
    workspaceId: json['workspace_id'] as int,
    name: json['name'] as String,
    orderIndex: json['order_index'] as int? ?? 0,
    templateTopicId: json['template_topic_id'] as int?,
  );

  TopicType copyWith({
    String? name,
    int? orderIndex,
    int? templateTopicId,
    bool clearTemplate = false,
  }) {
    return TopicType(
      id: id,
      workspaceId: workspaceId,
      name: name ?? this.name,
      orderIndex: orderIndex ?? this.orderIndex,
      templateTopicId: clearTemplate
          ? null
          : (templateTopicId ?? this.templateTopicId),
    );
  }
}
