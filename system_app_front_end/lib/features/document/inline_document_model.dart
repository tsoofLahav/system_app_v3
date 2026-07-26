class TextSpanMark {
  const TextSpanMark({
    required this.start,
    required this.end,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.size,
  });

  final int start;
  final int end;
  final bool bold;
  final bool italic;
  final bool underline;
  final double? size;

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    if (underline) 'underline': true,
    if (size != null) 'size': size,
  };

  factory TextSpanMark.fromJson(Map<String, dynamic> json) {
    return TextSpanMark(
      start: json['start'] as int,
      end: json['end'] as int,
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      underline: json['underline'] as bool? ?? false,
      size: (json['size'] as num?)?.toDouble(),
    );
  }

  TextSpanMark shift(int delta) {
    return TextSpanMark(
      start: start + delta,
      end: end + delta,
      bold: bold,
      italic: italic,
      underline: underline,
      size: size,
    );
  }
}

class DocumentRegion {
  const DocumentRegion({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    this.listStyle = 'bullet',
    this.rows = const [['', '']],
  });

  final String id;
  final String kind;
  final int start;
  final int end;
  final String listStyle;
  final List<List<String>> rows;

  DocumentRegion copyWith({int? start, int? end}) {
    return DocumentRegion(
      id: id,
      kind: kind,
      start: start ?? this.start,
      end: end ?? this.end,
      listStyle: listStyle,
      rows: rows,
    );
  }

  factory DocumentRegion.fromJson(Map<String, dynamic> json) {
    return DocumentRegion(
      id: json['id'] as String,
      kind: json['kind'] as String,
      start: json['start'] as int,
      end: json['end'] as int,
      listStyle: json['list_style'] as String? ?? 'bullet',
      rows: json['rows'] is List
          ? [
              for (final row in json['rows'] as List)
                if (row is List)
                  [for (final c in row) c?.toString() ?? '']
                else
                  [''],
            ]
          : const [['', '']],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'start': start,
    'end': end,
    if (kind == 'list') 'list_style': listStyle,
    if (kind == 'table') 'rows': rows,
  };
}

class DocumentEmbed {
  const DocumentEmbed({
    required this.id,
    required this.kind,
    required this.offset,
    this.objectType,
    this.objectId,
    this.url,
    this.width,
    this.labels = const [],
    this.values = const [],
  });

  final String id;
  final String kind;
  final int offset;
  final String? objectType;
  final int? objectId;
  final String? url;
  final double? width;
  final List<String> labels;
  final List<double> values;

  DocumentEmbed copyWith({int? offset, String? url, double? width}) {
    return DocumentEmbed(
      id: id,
      kind: kind,
      offset: offset ?? this.offset,
      objectType: objectType,
      objectId: objectId,
      url: url ?? this.url,
      width: width ?? this.width,
      labels: labels,
      values: values,
    );
  }

  factory DocumentEmbed.fromJson(Map<String, dynamic> json) {
    return DocumentEmbed(
      id: json['id'] as String,
      kind: json['kind'] as String,
      offset: json['offset'] as int,
      objectType: json['object_type'] as String?,
      objectId: json['object_id'] as int?,
      url: json['url'] as String?,
      width: (json['width'] as num?)?.toDouble(),
      labels: json['labels'] is List
          ? [for (final l in json['labels'] as List) l.toString()]
          : const [],
      values: json['values'] is List
          ? [for (final v in json['values'] as List) (v as num).toDouble()]
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'offset': offset,
    if (objectType != null) 'object_type': objectType,
    if (objectId != null) 'object_id': objectId,
    if (url != null) 'url': url,
    if (width != null) 'width': width,
    if (kind == 'graph') 'labels': labels,
    if (kind == 'graph') 'values': values,
  };
}

class InlineDocument {
  const InlineDocument({
    required this.version,
    required this.text,
    this.spans = const [],
    this.regions = const [],
    this.embeds = const [],
  });

  static const embedChar = '\uFFFC';
  static const documentVersion = 2;

  final int version;
  final String text;
  final List<TextSpanMark> spans;
  final List<DocumentRegion> regions;
  final List<DocumentEmbed> embeds;

  InlineDocument copyWith({
    String? text,
    List<TextSpanMark>? spans,
    List<DocumentRegion>? regions,
    List<DocumentEmbed>? embeds,
  }) {
    return InlineDocument(
      version: version,
      text: text ?? this.text,
      spans: spans ?? this.spans,
      regions: regions ?? this.regions,
      embeds: embeds ?? this.embeds,
    );
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'text': text,
    'spans': spans.map((s) => s.toJson()).toList(),
    'regions': regions.map((r) => r.toJson()).toList(),
    'embeds': embeds.map((e) => e.toJson()).toList(),
  };
}
