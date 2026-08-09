import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/rtl.dart';

void main() {
  group('detectParagraphTextDirection', () {
    test('Hebrew-first paragraph is RTL even with Latin and digits later', () {
      expect(
        detectParagraphTextDirection('אני משתמש ב-Flutter 3.29 היום'),
        TextDirection.rtl,
      );
    });

    test('English-first paragraph is LTR even with Hebrew later', () {
      expect(
        detectParagraphTextDirection('I use עברית today'),
        TextDirection.ltr,
      );
    });

    test('digits and punctuation alone do not set a direction', () {
      expect(detectParagraphTextDirection('3.29 — '), isNull);
      expect(detectParagraphTextDirection(''), isNull);
      expect(detectParagraphTextDirection('   '), isNull);
    });

    test('skips leading neutrals until the first strong character', () {
      expect(detectParagraphTextDirection('  42 שלום'), TextDirection.rtl);
      expect(detectParagraphTextDirection('...Hello'), TextDirection.ltr);
    });
  });
}
