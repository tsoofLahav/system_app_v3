import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/text_formatting.dart';
import 'package:system_app_front_end/areas/files/rich_text/text_links.dart';

void main() {
  test('firstUrlIn finds http, https, and www', () {
    expect(firstUrlIn('see https://example.com now')?.url, 'https://example.com');
    expect(firstUrlIn('http://x.test/a')?.url, 'http://x.test/a');
    expect(firstUrlIn('visit www.example.com')?.url, 'https://www.example.com');
    expect(firstUrlIn('no url here'), isNull);
  });

  test('urlAtSpanOffset reads link on the covering span', () {
    const spans = [
      {'start': 4, 'end': 23, 'link': 'https://example.com'},
    ];
    expect(urlAtSpanOffset(spans, 4), 'https://example.com');
    expect(urlAtSpanOffset(spans, 10), 'https://example.com');
    expect(urlAtSpanOffset(spans, 23), isNull);
    expect(urlAtSpanOffset(spans, 0), isNull);
  });

  test('make-link writes link on the URL span only', () {
    const text = 'see https://example.com please';
    final spans = applyFormatActionToRange(
      const [],
      start: 0,
      end: text.length,
      textLength: text.length,
      action: 'text:make_link',
      baseFontSize: 16,
      sourceText: text,
    );
    expect(spans, hasLength(1));
    expect(spans.single['start'], 4);
    expect(spans.single['end'], 23);
    expect(spans.single['link'], 'https://example.com');
  });

  test('make-link is a no-op when the mark has no URL', () {
    final spans = applyFormatActionToRange(
      const [],
      start: 0,
      end: 5,
      textLength: 5,
      action: 'text:make_link',
      baseFontSize: 16,
      sourceText: 'hello',
    );
    expect(spans, isEmpty);
  });
}
