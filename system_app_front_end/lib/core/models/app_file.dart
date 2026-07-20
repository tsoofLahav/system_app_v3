class AppFile {
  const AppFile({
    required this.id,
    required this.topicId,
    required this.name,
    required this.type,
    this.anchorTopicId,
    this.orderIndex,
    this.isMain,
    this.archivedAt,
    this.createdAt,
    this.settings = const {},
  });

  final int id;
  final int? topicId;
  final int? anchorTopicId;
  final String name;
  final String type;
  final int? orderIndex;
  final bool? isMain;
  final String? archivedAt;
  final String? createdAt;
  final Map<String, dynamic> settings;
  bool get isArchived => archivedAt != null;

  bool get tasksFlipByView => settings['tasks_flip_by_view'] == true;

  factory AppFile.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];
    return AppFile(
      id: json['id'] as int,
      topicId: json['topic_id'] as int?,
      anchorTopicId: json['anchor_topic_id'] as int?,
      name: json['name'] as String,
      type: json['type'] as String,
      orderIndex: json['order_index'] as int?,
      isMain: json['is_main'] as bool?,
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
      settings: rawSettings is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawSettings)
          : const {},
    );
  }

  AppFile copyWith({
    int? id,
    int? topicId,
    int? anchorTopicId,
    String? name,
    String? type,
    int? orderIndex,
    bool? isMain,
    String? archivedAt,
    String? createdAt,
    Map<String, dynamic>? settings,
  }) {
    return AppFile(
      id: id ?? this.id,
      topicId: topicId ?? this.topicId,
      anchorTopicId: anchorTopicId ?? this.anchorTopicId,
      name: name ?? this.name,
      type: type ?? this.type,
      orderIndex: orderIndex ?? this.orderIndex,
      isMain: isMain ?? this.isMain,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      settings: settings ?? this.settings,
    );
  }

  Map<String, dynamic> toJson() => {
    if (topicId != null) 'topic_id': topicId,
    if (anchorTopicId != null) 'anchor_topic_id': anchorTopicId,
    'name': name,
    'type': type,
    if (orderIndex != null) 'order_index': orderIndex,
    if (isMain != null) 'is_main': isMain,
    if (archivedAt != null) 'archived_at': archivedAt,
    if (settings.isNotEmpty) 'settings': settings,
  };
}
