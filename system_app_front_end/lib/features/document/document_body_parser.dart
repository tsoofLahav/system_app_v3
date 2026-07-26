class DocumentSegment {
  const DocumentSegment.text(this.text, {required this.lineIndex})
    : marker = null,
      isText = true;

  const DocumentSegment.marker(this.marker, {required this.lineIndex})
    : text = null,
      isText = false;

  final bool isText;
  final String? text;
  final String? marker;
  final int lineIndex;
}

class DocumentBodyParser {
  static final _task = RegExp(r'^\{\{task:(\d+)\}\}$');
  static final _info = RegExp(r'^\{\{info:(\d+)\}\}$');

  static List<DocumentSegment> parse(String body) {
    final lines = body.split('\n');
    if (lines.isEmpty) {
      return [DocumentSegment.text('', lineIndex: 0)];
    }
    final segments = <DocumentSegment>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (_task.hasMatch(line.trim()) || _info.hasMatch(line.trim())) {
        segments.add(DocumentSegment.marker(line.trim(), lineIndex: i));
      } else {
        segments.add(DocumentSegment.text(line, lineIndex: i));
      }
    }
    return segments;
  }
}
