class AppFile {
  const AppFile({
    required this.id,
    required this.topicId,
    required this.name,
    this.body = '',
    this.isEssence = false,
    this.orderIndex = 0,
    this.meta = const {},
    this.archivedAt,
    this.createdAt,
  });

  final int id;
  final int topicId;
  final String name;
  final String body;
  final bool isEssence;
  final int orderIndex;
  final Map<String, dynamic> meta;
  final String? archivedAt;
  final String? createdAt;

  bool get isArchived => archivedAt != null;

  factory AppFile.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['meta'];
    return AppFile(
      id: json['id'] as int,
      topicId: json['topic_id'] as int,
      name: json['name'] as String,
      body: json['body'] as String? ?? '',
      isEssence: json['is_essence'] as bool? ?? false,
      orderIndex: json['order_index'] as int? ?? 0,
      meta: rawMeta is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawMeta)
          : const {},
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  AppFile copyWith({
    String? name,
    String? body,
    bool? isEssence,
    int? orderIndex,
    Map<String, dynamic>? meta,
    String? archivedAt,
  }) {
    return AppFile(
      id: id,
      topicId: topicId,
      name: name ?? this.name,
      body: body ?? this.body,
      isEssence: isEssence ?? this.isEssence,
      orderIndex: orderIndex ?? this.orderIndex,
      meta: meta ?? this.meta,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson({bool includeBody = true}) => {
    'topic_id': topicId,
    'name': name,
    if (includeBody) 'body': body,
    'is_essence': isEssence,
    'order_index': orderIndex,
    if (meta.isNotEmpty) 'meta': meta,
    if (archivedAt != null) 'archived_at': archivedAt,
  };
}
