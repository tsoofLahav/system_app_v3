class Block {
  const Block({
    required this.id,
    required this.fileId,
    required this.type,
    required this.content,
    this.orderIndex,
    this.archivedAt,
    this.createdAt,
  });

  final int id;
  final int? fileId;
  final String type;
  final Map<String, dynamic> content;
  final int? orderIndex;
  final String? archivedAt;
  final String? createdAt;

  String get text => content['text'] as String? ?? '';

  Block copyWith({
    int? id,
    int? fileId,
    String? type,
    Map<String, dynamic>? content,
    int? orderIndex,
    String? archivedAt,
    String? createdAt,
  }) {
    return Block(
      id: id ?? this.id,
      fileId: fileId ?? this.fileId,
      type: type ?? this.type,
      content: content ?? this.content,
      orderIndex: orderIndex ?? this.orderIndex,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  factory Block.fromJson(Map<String, dynamic> json) {
    final raw = json['content'];
    return Block(
      id: json['id'] as int,
      fileId: json['file_id'] as int?,
      type: json['type'] as String,
      content: raw is Map<String, dynamic>
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{},
      orderIndex: json['order_index'] as int?,
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    if (fileId != null) 'file_id': fileId,
    'type': type,
    'content': content,
    if (orderIndex != null) 'order_index': orderIndex,
    if (archivedAt != null) 'archived_at': archivedAt,
  };
}
