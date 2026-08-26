import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/embeds/object_look.dart';

void main() {
  group('ObjectLook', () {
    test('omitted look uses the type default', () {
      expect(ObjectLook.infoOf(null), ObjectLook.card);
      expect(ObjectLook.tableOf({}), ObjectLook.grid);
      expect(ObjectLook.imageOf({'url': 'x'}), ObjectLook.plain);
    });

    test('withLook writes payload.look', () {
      final next = ObjectLook.withLook({'url': 'x'}, ObjectLook.card);
      expect(next['url'], 'x');
      expect(next['look'], ObjectLook.card);
    });

    test('legacy ids map onto the shared looks', () {
      expect(
        ObjectLook.tableOf({'look': ObjectLook.tableOpen}),
        ObjectLook.plain,
      );
      expect(
        ObjectLook.imageOf({'look': ObjectLook.imageNone}),
        ObjectLook.plain,
      );
      expect(
        ObjectLook.imageOf({'look': ObjectLook.imageFrame}),
        ObjectLook.card,
      );
      expect(
        ObjectLook.imageOf({'look': ObjectLook.imageFrameGreyscale}),
        ObjectLook.card,
      );
      expect(
        ObjectLook.imageGreyscaleOf({'look': ObjectLook.imageGreyscale}),
        isTrue,
      );
      expect(ObjectLook.imageGreyscaleOf({'greyscale': true}), isTrue);
    });

    test('image frame and greyscale flags', () {
      expect(ObjectLook.imageHasFrame(ObjectLook.card), isTrue);
      expect(ObjectLook.imageHasFrame(ObjectLook.glass), isTrue);
      expect(ObjectLook.imageHasFrame(ObjectLook.plain), isFalse);
      expect(ObjectLook.imageIsGreyscale(ObjectLook.imageGreyscale), isTrue);
      expect(ObjectLook.imageHasFrame(ObjectLook.imageNone), isFalse);
    });

    test('new looks are offered per type', () {
      expect(ObjectLook.looksFor('info'), contains(ObjectLook.glass));
      expect(ObjectLook.looksFor('info'), contains(ObjectLook.outline));
      expect(ObjectLook.looksFor('info'), contains(ObjectLook.fill));
      expect(ObjectLook.looksFor('table'), contains(ObjectLook.glass));
      expect(ObjectLook.looksFor('image'), isNot(contains(ObjectLook.ruled)));
    });
  });
}
