class Part {
  const Part({
    required this.id,
    required this.topicId,
    required this.name,
    required this.orderIndex,
    this.archivedAt,
    this.createdAt,
  });

  final int id;
  final int topicId;
  final String name;
  final int orderIndex;
  final String? archivedAt;
  final String? createdAt;

  Part copyWith({
    int? id,
    int? topicId,
    String? name,
    int? orderIndex,
    String? archivedAt,
    String? createdAt,
  }) {
    return Part(
      id: id ?? this.id,
      topicId: topicId ?? this.topicId,
      name: name ?? this.name,
      orderIndex: orderIndex ?? this.orderIndex,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Part.fromJson(Map<String, dynamic> json) {
    return Part(
      id: json['id'] as int,
      topicId: json['topic_id'] as int,
      name: json['name'] as String,
      orderIndex: json['order_index'] as int? ?? 0,
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }
}
