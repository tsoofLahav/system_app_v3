import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/features/document/document_body_parser.dart';

void main() {
  test('parses task markers on their own lines', () {
    const body = 'Hello\n{{task:42}}\nWorld';
    final segments = DocumentBodyParser.parse(body);
    expect(segments.length, 3);
    expect(segments[1].marker, '{{task:42}}');
  });
}
