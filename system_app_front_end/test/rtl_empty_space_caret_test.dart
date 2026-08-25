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
  });
}
