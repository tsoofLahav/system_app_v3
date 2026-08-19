class TopicType {
  const TopicType({
    required this.id,
    required this.workspaceId,
    required this.name,
    this.nameHe = '',
    this.orderIndex = 0,
    this.templateTopicId,
  });

  final int id;
  final int workspaceId;

  /// English name — also the stable unique key.
  final String name;

  /// Hebrew name shown when the app language is Hebrew.
  final String nameHe;
  final int orderIndex;
  final int? templateTopicId;

  factory TopicType.fromJson(Map<String, dynamic> json) => TopicType(
        id: json['id'] as int,
        workspaceId: json['workspace_id'] as int,
        name: json['name'] as String,
        nameHe: json['name_he'] as String? ?? '',
        orderIndex: json['order_index'] as int? ?? 0,
        templateTopicId: json['template_topic_id'] as int?,
      );

  TopicType copyWith({
    String? name,
    String? nameHe,
    int? orderIndex,
    int? templateTopicId,
    bool clearTemplate = false,
  }) {
    return TopicType(
      id: id,
      workspaceId: workspaceId,
      name: name ?? this.name,
      nameHe: nameHe ?? this.nameHe,
      orderIndex: orderIndex ?? this.orderIndex,
      templateTopicId: clearTemplate
          ? null
          : (templateTopicId ?? this.templateTopicId),
    );
  }
}
