import 'package:flutter/painting.dart';
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
}
