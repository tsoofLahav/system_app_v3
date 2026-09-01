import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/text_formatting.dart';
import 'package:system_app_front_end/areas/ui/app_colors.dart';

void main() {
  test('strikethrough toggles on the marked range only', () {
    const text = 'abcde';
    final on = applyFormatActionToRange(
      const [],
      start: 1,
      end: 4,
      textLength: text.length,
      action: 'text:strikethrough',
      baseFontSize: 16,
    );
    expect(on, hasLength(1));
    expect(on.single['start'], 1);
    expect(on.single['end'], 4);
    expect(on.single['strikethrough'], isTrue);

    final off = applyFormatActionToRange(
      on,
      start: 1,
      end: 4,
      textLength: text.length,
      action: 'text:strikethrough',
      baseFontSize: 16,
    );
    expect(off, isEmpty);
  });

  test('strikethrough and underline can sit on the same glyphs', () {
    const text = 'hello';
    final underlined = applyFormatActionToRange(
      const [],
      start: 0,
      end: text.length,
      textLength: text.length,
      action: 'text:underline',
      baseFontSize: 16,
    );
    final both = applyFormatActionToRange(
      underlined,
      start: 0,
      end: text.length,
      textLength: text.length,
      action: 'text:strikethrough',
      baseFontSize: 16,
    );
    expect(both, hasLength(1));
    expect(both.single['underline'], isTrue);
    expect(both.single['strikethrough'], isTrue);

    final style = TextSpanBuilder.build(
      text: text,
      baseStyle: const TextStyle(),
      spans: both,
    ).children!.single.style!;
    expect(style.decoration, TextDecoration.combine([
      TextDecoration.underline,
      TextDecoration.lineThrough,
    ]));
  });

  test('description-linked glyphs are italic teal and keep strikethrough', () {
    const text = 'hello';
    final span = TextSpanBuilder.build(
      text: text,
      baseStyle: const TextStyle(
        decoration: TextDecoration.lineThrough,
        color: Color(0xFF9D988F),
      ),
      spans: [
        {'start': 0, 'end': text.length, 'descriptionLink': true},
      ],
    );
    final style = span.children!.single.style!;
    expect(style.fontStyle, FontStyle.italic);
    expect(style.color, AppColors.descriptionLink);
    expect(style.decoration, TextDecoration.lineThrough);
    expect(style.decoration, isNot(TextDecoration.underline));
    expect(
      style.decoration?.contains(TextDecoration.underline) ?? false,
      isFalse,
    );
  });
}
