class AppFile {
  const AppFile({
    required this.id,
    required this.topicId,
    required this.name,
    required this.type,
    this.orderIndex,
    this.isMain,
    this.archivedAt,
    this.createdAt,
  });

  final int id;
  final int? topicId;
  final String name;
  final String type;
  final int? orderIndex;
  final bool? isMain;
  final String? archivedAt;
  final String? createdAt;
  bool get isArchived => archivedAt != null;

  factory AppFile.fromJson(Map<String, dynamic> json) {
    return AppFile(
      id: json['id'] as int,
      topicId: json['topic_id'] as int?,
      name: json['name'] as String,
      type: json['type'] as String,
      orderIndex: json['order_index'] as int?,
      isMain: json['is_main'] as bool?,
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  AppFile copyWith({
    int? id,
    int? topicId,
    String? name,
    String? type,
    int? orderIndex,
    bool? isMain,
    String? archivedAt,
    String? createdAt,
  }) {
    return AppFile(
      id: id ?? this.id,
      topicId: topicId ?? this.topicId,
      name: name ?? this.name,
      type: type ?? this.type,
      orderIndex: orderIndex ?? this.orderIndex,
      isMain: isMain ?? this.isMain,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    if (topicId != null) 'topic_id': topicId,
    'name': name,
    'type': type,
    if (orderIndex != null) 'order_index': orderIndex,
    if (isMain != null) 'is_main': isMain,
    if (archivedAt != null) 'archived_at': archivedAt,
  };
}
