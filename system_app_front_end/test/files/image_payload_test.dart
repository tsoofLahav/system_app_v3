import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/image_payload.dart';

void main() {
  group('ImageObjectPayload', () {
    test('single url is one pane', () {
      expect(
        ImageObjectPayload.panesOf({'url': '/a.png', 'caption': 'A'}),
        [
          {'url': '/a.png', 'caption': 'A'},
        ],
      );
    });

    test('merge mirrors first pane on url', () {
      final out = ImageObjectPayload.merge(
        {'url': '/a.png', 'caption': 'A', 'width': 0.5, 'look': 'frame'},
        {'url': '/b.png', 'caption': 'B'},
      );
      expect(out['url'], '/a.png');
      expect(out['width'], 0.5);
      expect(out['look'], 'frame');
      expect((out['images'] as List).length, 2);
      expect(out['images'][1]['url'], '/b.png');
    });
  });
}
