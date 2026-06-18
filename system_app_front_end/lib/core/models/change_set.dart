class ChangeSet {
  const ChangeSet({required this.version, required this.documents});

  factory ChangeSet.fromJson(Map<String, dynamic> json) {
    final rawDocs = json['documents'];
    return ChangeSet(
      version: json['version'] as int? ?? 1,
      documents: rawDocs is List
          ? rawDocs
                .whereType<Map>()
                .map(
                  (doc) =>
                      ChangeDocument.fromJson(Map<String, dynamic>.from(doc)),
                )
                .toList()
          : const [],
    );
  }

  final int version;
  final List<ChangeDocument> documents;
}

class ChangeDocument {
  const ChangeDocument({
    required this.key,
    required this.title,
    required this.units,
    required this.changes,
  });

  factory ChangeDocument.fromJson(Map<String, dynamic> json) {
    return ChangeDocument(
      key: json['key'] as String? ?? '',
      title: json['title'] as String? ?? '',
      units: _units(json['units']),
      changes: _changes(json['changes']),
    );
  }

  final String key;
  final String title;
  final List<ChangeUnit> units;
  final List<ChangeItem> changes;

  Map<String, ChangeItem> get changesByUnitId {
    final map = <String, ChangeItem>{};
    for (final change in changes) {
      map[change.unitId] = change;
    }
    return map;
  }
}

class ChangeUnit {
  const ChangeUnit({required this.id, required this.kind, required this.text});

  factory ChangeUnit.fromJson(Map<String, dynamic> json) {
    return ChangeUnit(
      id: json['id'] as String? ?? '',
      kind: json['kind'] as String? ?? 'paragraph',
      text: json['text'] as String? ?? '',
    );
  }

  final String id;
  final String kind;
  final String text;
}

class ChangeItem {
  const ChangeItem({
    required this.id,
    required this.action,
    required this.unitId,
    required this.oldText,
    required this.newText,
    this.reason,
  });

  factory ChangeItem.fromJson(Map<String, dynamic> json) {
    return ChangeItem(
      id: json['id'] as String? ?? '',
      action: json['action'] as String? ?? 'replace',
      unitId: json['unit_id'] as String? ?? '',
      oldText: json['old_text'] as String? ?? '',
      newText: json['new_text'] as String? ?? '',
      reason: json['reason'] as String?,
    );
  }

  final String id;
  final String action;
  final String unitId;
  final String oldText;
  final String newText;
  final String? reason;
}

List<ChangeUnit> _units(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => ChangeUnit.fromJson(Map<String, dynamic>.from(item)))
      .toList();
}

List<ChangeItem> _changes(dynamic raw) {
  if (raw is! List) return const [];
  return raw
      .whereType<Map>()
      .map((item) => ChangeItem.fromJson(Map<String, dynamic>.from(item)))
      .toList();
}
