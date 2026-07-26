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
}

sealed class DocumentNode {
  const DocumentNode({required this.id});

  final String id;

  String get type;
  Map<String, dynamic> toJson();
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
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'text': text,
    'spans': spans.map((s) => s.toJson()).toList(),
  };
}

class TableNode extends DocumentNode {
  const TableNode({required super.id, required this.rows});

  final List<List<String>> rows;

  @override
  String get type => 'table';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'rows': rows,
  };
}

class ListNode extends DocumentNode {
  const ListNode({
    required super.id,
    required this.items,
    this.listStyle = 'bullet',
  });

  final List<String> items;
  final String listStyle;

  @override
  String get type => 'list';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'items': items,
    'list_style': listStyle,
  };
}

class ImageNode extends DocumentNode {
  const ImageNode({required super.id, required this.url, this.width});

  final String url;
  final double? width;

  @override
  String get type => 'image';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'url': url,
    if (width != null) 'width': width,
  };
}

class GraphNode extends DocumentNode {
  const GraphNode({
    required super.id,
    required this.labels,
    required this.values,
  });

  final List<String> labels;
  final List<double> values;

  @override
  String get type => 'graph';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'labels': labels,
    'values': values,
  };
}

class ObjectNode extends DocumentNode {
  const ObjectNode({
    required super.id,
    required this.objectType,
    required this.objectId,
  });

  final String objectType;
  final int objectId;

  @override
  String get type => 'object';

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type,
    'object_type': objectType,
    'object_id': objectId,
  };
}

class RichDocument {
  const RichDocument({required this.version, required this.nodes});

  final int version;
  final List<DocumentNode> nodes;

  RichDocument copyWith({List<DocumentNode>? nodes}) {
    return RichDocument(version: version, nodes: nodes ?? this.nodes);
  }

  Map<String, dynamic> toJson() => {
    'version': version,
    'nodes': nodes.map((n) => n.toJson()).toList(),
  };
}
