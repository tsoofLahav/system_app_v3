class AppFile {
  const AppFile({
    required this.id,
    required this.topicId,
    required this.name,
    this.documentJson = '',
    this.orderIndex = 0,
    this.contentRevision = 1,
    this.meta = const {},
    this.archivedAt,
    this.createdAt,
  });

  final int id;
  final int topicId;
  final String name;
  final String documentJson;

  /// Position inside the topic. The topic's layout decides how many of these
  /// positions are on screen; the rest are reached by rearranging.
  final int orderIndex;

  /// Optimistic concurrency token for [documentJson]. PATCH must send the
  /// revision this edit started from; mismatch → 409 + current file.
  final int contentRevision;
  final Map<String, dynamic> meta;
  final String? archivedAt;
  final String? createdAt;

  bool get isArchived => archivedAt != null;

  String? get templateSlot {
    final value = meta['template_slot'];
    if (value is String && value.trim().isNotEmpty) return value.trim();
    return null;
  }

  factory AppFile.fromJson(Map<String, dynamic> json) {
    final rawMeta = json['meta'];
    final rawRev = json['content_revision'];
    return AppFile(
      id: json['id'] as int,
      topicId: json['topic_id'] as int,
      name: json['name'] as String,
      documentJson: json['document_json'] as String? ?? '',
      orderIndex: json['order_index'] as int? ?? 0,
      contentRevision: rawRev is int
          ? rawRev
          : int.tryParse('$rawRev') ?? 1,
      meta: rawMeta is Map
          ? Map<String, dynamic>.from(rawMeta)
          : const {},
      archivedAt: json['archived_at'] as String?,
      createdAt: json['created_at'] as String?,
    );
  }

  AppFile copyWith({
    String? name,
    String? documentJson,
    int? orderIndex,
    int? contentRevision,
    Map<String, dynamic>? meta,
    String? archivedAt,
    bool clearArchivedAt = false,
  }) {
    return AppFile(
      id: id,
      topicId: topicId,
      name: name ?? this.name,
      documentJson: documentJson ?? this.documentJson,
      orderIndex: orderIndex ?? this.orderIndex,
      contentRevision: contentRevision ?? this.contentRevision,
      meta: meta ?? this.meta,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson({bool includeDocument = true}) => {
    'topic_id': topicId,
    'name': name,
    if (includeDocument) 'document_json': documentJson,
    'order_index': orderIndex,
    'content_revision': contentRevision,
    if (meta.isNotEmpty) 'meta': meta,
    if (archivedAt != null) 'archived_at': archivedAt,
  };
}
