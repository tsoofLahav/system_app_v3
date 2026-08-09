import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/rtl/rtl.dart';

void main() {
  group('emptySpaceCaretOffsetFromBoxes', () {
    test('below the last line → logical end of text', () {
      expect(
        emptySpaceCaretOffsetFromBoxes(
          boxes: const [Rect.fromLTRB(40, 0, 120, 20)],
          local: const Offset(80, 40),
          textLength: 10,
        ),
        10,
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
