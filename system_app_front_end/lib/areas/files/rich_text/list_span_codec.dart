import '../model/document_codec.dart';
import '../model/document_model.dart';
import './text_formatting.dart';

/// Flatten list items into one multiline string with merged spans.
({String text, List<Map<String, dynamic>> spans}) flattenListItems(
  List<ListItem> items,
) {
  if (items.isEmpty) {
    return (text: '', spans: const []);
  }
  final buffer = StringBuffer();
  final spans = <Map<String, dynamic>>[];
  var offset = 0;

  for (var i = 0; i < items.length; i++) {
    if (i > 0) {
      buffer.write('\n');
      offset++;
    }
    final item = items[i];
    final text = item.text;
    buffer.write(text);
    for (final span in item.spans) {
      spans.add({
        ...span.toJson(),
        'start': span.start + offset,
        'end': span.end + offset,
      });
    }
    offset += text.length;
  }

  return (text: buffer.toString(), spans: normalizeSpans(spans, offset));
}

/// Parse flat multiline text back into list items, preserving ids when possible.
List<ListItem> parseFlatListText(
  String text,
  List<Map<String, dynamic>> spans,
  List<ListItem> previousItems,
) {
  final lines = text.isEmpty ? [''] : text.split('\n');
  final items = <ListItem>[];

  var lineStart = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    final lineEnd = lineStart + line.length;
    final lineSpans = <TextSpanMark>[
      for (final span in spans)
        if ((span['end'] as int? ?? 0) > lineStart &&
            (span['start'] as int? ?? 0) < lineEnd)
          TextSpanMark.fromJson({
            ...span,
            'start': ((span['start'] as int) - lineStart).clamp(0, line.length),
            'end': ((span['end'] as int) - lineStart).clamp(0, line.length),
          }),
    ];
    final prev = i < previousItems.length ? previousItems[i] : null;
    items.add(
      ListItem(
        id: prev?.id ?? DocumentCodec.newId('li'),
        text: line,
        indent: prev?.indent ?? 0,
        spans: lineSpans,
      ),
    );
    lineStart = lineEnd + 1;
  }

  if (items.isEmpty) {
    items.add(ListItem(id: DocumentCodec.newId('li'), text: ''));
  }
  return items;
}
