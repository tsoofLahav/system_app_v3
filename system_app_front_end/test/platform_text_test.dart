import 'package:characters/characters.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/shared/utils/platform_text.dart';

void main() {
  group('sanitizePlatformText', () {
    test('drops lone high surrogate', () {
      const broken = 'a\uD83Da';
      expect(sanitizePlatformText(broken), 'aa');
    });

    test('keeps valid emoji', () {
      const emoji = '🔥';
      expect(sanitizePlatformText(emoji), emoji);
    });
  });

  group('normalizeTextSelection', () {
    test('keeps a reverse range so Shift+arrows do not flip the caret', () {
      const text = 'hello world';
      const reverse = TextSelection(baseOffset: 11, extentOffset: 6);
      expect(normalizeTextSelection(text, reverse), reverse);
    });

    test('expands a range that splits a ZWJ emoji', () {
      const text = 'a\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}b';
      final start = 1;
      final grapheme = text.characters.elementAt(1);
      final next = normalizeTextSelection(
        text,
        TextSelection(baseOffset: start, extentOffset: start + 1),
      );
      expect(text.substring(next.start, next.end), grapheme);
    });
  });

  group('grapheme steps', () {
    test('arrow over emoji jumps both UTF-16 units', () {
      const text = 'a😀b';
      final start = text.indexOf('😀');
      final after = start + '😀'.length;
      expect(graphemeOffsetAfter(text, start), after);
      expect(graphemeOffsetBefore(text, after), start);
    });
  });

  group('safeSubstring', () {
    test('expands partial emoji selection to full emoji', () {
      const text = 'a🔥b';
      final emojiStart = text.indexOf('🔥');
      final partialEnd = emojiStart + 1;
      expect(safeSubstring(text, emojiStart, partialEnd), '🔥');
    });

    test('never returns lone surrogate', () {
      const broken = 'a\uD83Db';
      expect(safeSubstring(broken, 1, 2), '');
    });
  });

  group('insertableEmojis', () {
    test('returns first grapheme from reply', () {
      expect(insertableEmojis('  🎯 extra '), '🎯');
    });

    test('ignores trailing words', () {
      expect(insertableEmojis('🎯 done'), '🎯');
    });

    test('returns up to two graphemes', () {
      expect(insertableEmojis('🍕🍺'), '🍕🍺');
      expect(insertableEmojis('☀️ 🌧️'), '☀️🌧️');
    });

    test('caps at two graphemes', () {
      expect(insertableEmojis('🎯✅🔥'), '🎯✅');
    });

    test('returns null for broken reply', () {
      expect(insertableEmojis('\uD83D'), isNull);
    });
  });
}
