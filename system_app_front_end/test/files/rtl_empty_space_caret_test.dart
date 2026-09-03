import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/rtl.dart';

void main() {
  group('emptySpaceCaretOffsetFromBoxes', () {
    test('empty boxes → null (Flutter keeps the hit-test)', () {
      expect(
        emptySpaceCaretOffsetFromBoxes(
          boxes: const [],
          local: const Offset(40, 18),
          textLength: 10,
        ),
        isNull,
      );
    });

    test('center of a short line in a tall cell → null', () {
      // Glyphs near the top of a 36px cell; tap is the cell center, below ink.
      expect(
        emptySpaceCaretOffsetFromBoxes(
          boxes: const [Rect.fromLTRB(8, 2, 80, 16)],
          local: const Offset(44, 18),
          textLength: 8,
        ),
        isNull,
      );
    });

    test('beside glyphs → logical line end via glyph-center probe', () {
      Offset? probed;
      expect(
        emptySpaceCaretOffsetFromBoxes(
          boxes: const [Rect.fromLTRB(40, 0, 120, 20)],
          local: const Offset(10, 10),
          textLength: 10,
          logicalLineEndAt: (local) {
            probed = local;
            return 10;
          },
        ),
        10,
      );
      expect(probed, const Offset(80, 10));
    });

    test(
      'beside glyphs in RTL (padding on the left) → line end, not whole field',
      () {
        expect(
          emptySpaceCaretOffsetFromBoxes(
            boxes: const [Rect.fromLTRB(80, 0, 160, 20)],
            local: const Offset(20, 10),
            textLength: 24,
            logicalLineEndAt: (_) => 12,
          ),
          12,
        );
      },
    );

    test('on glyphs → null (Flutter keeps the hit-test)', () {
      expect(
        emptySpaceCaretOffsetFromBoxes(
          boxes: const [Rect.fromLTRB(40, 0, 120, 20)],
          local: const Offset(80, 10),
          textLength: 10,
        ),
        isNull,
      );
    });

    test('gap between BiDi runs probes the nearest glyph, not line end', () {
      const hebrew = Rect.fromLTRB(80, 0, 160, 20);
      const number = Rect.fromLTRB(20, 0, 50, 20);
      expect(
        bidiGapCaretProbe(
          boxes: const [hebrew, number],
          local: const Offset(65, 10),
        ),
        const Offset(80.5, 10),
      );
      expect(
        emptySpaceCaretOffsetFromBoxes(
          boxes: const [hebrew, number],
          local: const Offset(65, 10),
          textLength: 12,
        ),
        isNull,
      );
    });
  });

  group('bidiAwareOffsetFromBoxes', () {
    test('tap in padding beside the line → logical line end', () {
      expect(
        bidiAwareOffsetFromBoxes(
          boxes: const [Rect.fromLTRB(80, 0, 160, 20)],
          local: const Offset(20, 10),
          textLength: 24,
          paddingGoesToLineEnd: true,
          offsetAt: (_) => 8,
          logicalLineEndAt: (_) => 24,
        ),
        24,
      );
    });

    test('mark in padding beside the line → nearer visual edge, not line end', () {
      expect(
        bidiAwareOffsetFromBoxes(
          boxes: const [Rect.fromLTRB(80, 0, 160, 20)],
          local: const Offset(20, 10),
          textLength: 24,
          paddingGoesToLineEnd: false,
          offsetAt: (probe) => probe.dx < 90 ? 0 : 12,
          logicalLineEndAt: (_) => 24,
        ),
        0,
      );
    });

    test('gap next to a number run snaps to the nearest glyph', () {
      const hebrew = Rect.fromLTRB(80, 0, 160, 20);
      const number = Rect.fromLTRB(20, 0, 50, 20);
      Offset? probed;
      expect(
        bidiAwareOffsetFromBoxes(
          boxes: const [hebrew, number],
          local: const Offset(65, 10),
          textLength: 12,
          paddingGoesToLineEnd: false,
          offsetAt: (probe) {
            probed = probe;
            return probe.dx >= 80 ? 4 : 8;
          },
          logicalLineEndAt: (_) => 12,
        ),
        4,
      );
      expect(probed, const Offset(80.5, 10));
    });

    test('phone word mark in a Hebrew+English line follows the nearest run', () {
      const text = 'שלום Flutter';
      // RTL line: Hebrew on the right, English on the left.
      const hebrew = Rect.fromLTRB(80, 0, 160, 20);
      const english = Rect.fromLTRB(0, 0, 70, 20);
      int offsetAt(Offset probe) => probe.dx >= 80 ? 2 : 8;
      expect(
        phoneObjectWordMarkFromBoxes(
          boxes: const [hebrew, english],
          local: const Offset(120, 10),
          text: text,
          offsetAt: offsetAt,
        )?.textInside(text),
        'שלום',
      );
      expect(
        phoneObjectWordMarkFromBoxes(
          boxes: const [hebrew, english],
          local: const Offset(30, 10),
          text: text,
          offsetAt: offsetAt,
        )?.textInside(text),
        'Flutter',
      );
      expect(
        phoneObjectWordMarkFromBoxes(
          boxes: const [hebrew, english],
          local: const Offset(75, 10),
          text: text,
          offsetAt: offsetAt,
        )?.textInside(text),
        'שלום',
      );
    });
  });
}
