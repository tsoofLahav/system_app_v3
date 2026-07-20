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
