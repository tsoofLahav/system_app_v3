import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/embeds/image_display_size.dart';

void main() {
  test('missing width is full size', () {
    expect(ImageDisplaySize.scaleOf(null), 1);
    expect(ImageDisplaySize.scaleOf({}), 1);
  });

  test('legacy pixel width is treated as full', () {
    expect(ImageDisplaySize.scaleOf({'width': 320}), 1);
  });

  test('smaller and larger step by a tenth of the pane', () {
    final smaller = ImageDisplaySize.apply('image:smaller', {'width': 1.0});
    expect(ImageDisplaySize.scaleOf(smaller), 0.9);
    final larger = ImageDisplaySize.apply('image:larger', smaller);
    expect(ImageDisplaySize.scaleOf(larger), 1.0);
  });

  test('smaller stops at tiny', () {
    final next = ImageDisplaySize.apply('image:smaller', {
      'width': ImageDisplaySize.tiny,
    });
    expect(ImageDisplaySize.scaleOf(next), ImageDisplaySize.tiny);
  });

  test('named sizes set the fraction', () {
    expect(
      ImageDisplaySize.scaleOf(
        ImageDisplaySize.apply('image:size:tiny', {}),
      ),
      ImageDisplaySize.tiny,
    );
    expect(
      ImageDisplaySize.scaleOf(
        ImageDisplaySize.apply('image:size:quarter', {}),
      ),
      ImageDisplaySize.quarter,
    );
    expect(
      ImageDisplaySize.scaleOf(
        ImageDisplaySize.apply('image:size:half', {}),
      ),
      ImageDisplaySize.half,
    );
    expect(
      ImageDisplaySize.scaleOf(
        ImageDisplaySize.apply('image:size:full', {'width': 0.25}),
      ),
      ImageDisplaySize.full,
    );
  });
}
