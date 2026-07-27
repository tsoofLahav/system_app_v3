class TextSpanMark {
  const TextSpanMark({
    required this.start,
    required this.end,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.size,
    this.color,
    this.link,
  });

  final int start;
  final int end;
  final bool bold;
  final bool italic;
  final bool underline;
  final double? size;
  final String? color;
  final String? link;

  TextSpanMark copyWith({
    int? start,
    int? end,
    bool? bold,
    bool? italic,
    bool? underline,
    double? size,
    String? color,
    String? link,
  }) {
    return TextSpanMark(
      start: start ?? this.start,
      end: end ?? this.end,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      size: size ?? this.size,
      color: color ?? this.color,
      link: link ?? this.link,
    );
  }

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
    if (bold) 'bold': true,
    if (italic) 'italic': true,
    if (underline) 'underline': true,
    if (size != null) 'size': size,
    if (color != null && color!.isNotEmpty) 'color': color,
    if (link != null) 'link': link,
  };

  factory TextSpanMark.fromJson(Map<String, dynamic> json) {
    return TextSpanMark(
      start: json['start'] as int,
      end: json['end'] as int,
      bold: json['bold'] as bool? ?? false,
      italic: json['italic'] as bool? ?? false,
      underline: json['underline'] as bool? ?? false,
      size: (json['size'] as num?)?.toDouble(),
      color: json['color'] as String?,
      link: json['link'] as String?,
    );
  }
}

class ListItem {
  const ListItem({
    required this.id,
    required this.text,
    this.indent = 0,
    this.spans = const [],
  });

  final String id;
  final String text;
  final int indent;
  final List<TextSpanMark> spans;

  ListItem copyWith({
    String? id,
    String? text,
    int? indent,
    List<TextSpanMark>? spans,
  }) {
    return ListItem(
      id: id ?? this.id,
      text: text ?? this.text,
      indent: indent ?? this.indent,
      spans: spans ?? this.spans,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'indent': indent,
    'spans': spans.map((s) => s.toJson()).toList(),
  };

  factory ListItem.fromJson(Map<String, dynamic> json) {
    return ListItem(
      id: json['id'] as String,
      text: json['text'] as String? ?? '',
      indent: json['indent'] as int? ?? 0,
      spans: [
        for (final s in json['spans'] as List? ?? const [])
          TextSpanMark.fromJson(s as Map<String, dynamic>),
      ],
    );
  }
}

class DocumentTableCell {
  const DocumentTableCell({required this.text, this.spans = const []});

  final String text;
  final List<TextSpanMark> spans;

  DocumentTableCell copyWith({String? text, List<TextSpanMark>? spans}) {
    return DocumentTableCell(text: text ?? this.text, spans: spans ?? this.spans);
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'spans': spans.map((s) => s.toJson()).toList(),
  };

  factory DocumentTableCell.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return DocumentTableCell(
        text: json['text'] as String? ?? '',
        spans: [
          for (final s in json['spans'] as List? ?? const [])
            TextSpanMark.fromJson(s as Map<String, dynamic>),
        ],
      );
    }
    return DocumentTableCell(text: json?.toString() ?? '');
  }
}

sealed class DocumentNode {
  const DocumentNode({required this.id});

  final String id;

  String get type;
  Map<String, dynamic> toJson();

  DocumentNode copyWithId(String newId);
}

class ParagraphNode extends DocumentNode {
  const ParagraphNode({
    required super.id,
    required this.text,
    this.spans = const [],
  });

  final String text;
  final List<TextSpanMark> spans;

  @override
  String get type => 'paragraph';

  ParagraphNode copyWith({String? text, List<TextSpanMark>? spans}) {
    return ParagraphNode(
      id: id,
      text: text ?? this.text,
      spans: spans ?? this.spans,
    );
  }

  @override
  ParagraphNode copyWithId(String newId) => ParagraphNode(id: newId, text: text, spans: spans);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'text': text,
    'spans': spans.map((s) => s.toJson()).toList(),
  };
}

class HeadingNode extends DocumentNode {
  const HeadingNode({
    required super.id,
    required this.level,
    required this.text,
    this.spans = const [],
  });

  final int level;
  final String text;
  final List<TextSpanMark> spans;

  @override
  String get type => 'heading';

  HeadingNode copyWith({int? level, String? text, List<TextSpanMark>? spans}) {
    return HeadingNode(
      id: id,
      level: level ?? this.level,
      text: text ?? this.text,
      spans: spans ?? this.spans,
    );
  }

  @override
  HeadingNode copyWithId(String newId) =>
      HeadingNode(id: newId, level: level, text: text, spans: spans);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'level': level,
    'text': text,
    'spans': spans.map((s) => s.toJson()).toList(),
  };
}

class ListNode extends DocumentNode {
  const ListNode({
    required super.id,
    required this.items,
    this.listStyle = 'bullet',
  });

  final List<ListItem> items;
  final String listStyle;

  bool get isOrdered => listStyle == 'numbered' || listStyle == 'ordered';

  @override
  String get type => isOrdered ? 'ordered_list' : 'bullet_list';

  ListNode copyWith({List<ListItem>? items, String? listStyle}) {
    return ListNode(
      id: id,
      items: items ?? this.items,
      listStyle: listStyle ?? this.listStyle,
    );
  }

  @override
  ListNode copyWithId(String newId) => ListNode(id: newId, items: items, listStyle: listStyle);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'items': items.map((i) => i.toJson()).toList(),
  };
}

class TableNode extends DocumentNode {
  const TableNode({required super.id, required this.rows});

  final List<List<DocumentTableCell>> rows;

  @override
  String get type => 'table';

  TableNode copyWith({List<List<DocumentTableCell>>? rows}) {
    return TableNode(id: id, rows: rows ?? this.rows);
  }

  @override
  TableNode copyWithId(String newId) => TableNode(id: newId, rows: rows);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'rows': [
      for (final row in rows)
        row.map((c) => c.toJson()).toList(),
    ],
  };
}

class EmbedNode extends DocumentNode {
  const EmbedNode({required super.id, required this.objectId});

  final int objectId;

  @override
  String get type => 'embed';

  EmbedNode copyWith({int? objectId}) {
    return EmbedNode(id: id, objectId: objectId ?? this.objectId);
  }

  @override
  EmbedNode copyWithId(String newId) => EmbedNode(id: newId, objectId: objectId);

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'object_id': objectId,
  };
}

class RichDocument {
  const RichDocument({required this.version, required this.blocks});

  static const int documentVersion = 3;

  final int version;
  final List<DocumentNode> blocks;

  RichDocument copyWith({List<DocumentNode>? blocks}) {
    return RichDocument(version: version, blocks: blocks ?? this.blocks);
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'blocks': blocks.map((n) => n.toJson()).toList(),
  };
}
