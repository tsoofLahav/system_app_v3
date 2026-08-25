import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/embeds/object_look.dart';

void main() {
  group('ObjectLook', () {
    test('omitted look uses the type default', () {
      expect(ObjectLook.infoOf(null), ObjectLook.infoCard);
      expect(ObjectLook.tableOf({}), ObjectLook.tableGrid);
      expect(ObjectLook.imageOf({'url': 'x'}), ObjectLook.imageNone);
    });

    test('withLook writes payload.look', () {
      final next = ObjectLook.withLook({'url': 'x'}, ObjectLook.imageFrame);
      expect(next['url'], 'x');
      expect(next['look'], ObjectLook.imageFrame);
    });

    test('image frame and greyscale flags', () {
      expect(ObjectLook.imageHasFrame(ObjectLook.imageFrame), isTrue);
      expect(ObjectLook.imageIsGreyscale(ObjectLook.imageGreyscale), isTrue);
      expect(
        ObjectLook.imageHasFrame(ObjectLook.imageFrameGreyscale) &&
            ObjectLook.imageIsGreyscale(ObjectLook.imageFrameGreyscale),
        isTrue,
      );
      expect(ObjectLook.imageHasFrame(ObjectLook.imageNone), isFalse);
    });
  });
}
