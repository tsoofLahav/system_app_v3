import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/connect_info.dart';

void main() {
  test('cutting the middle of a connected span keeps both sides', () {
    final left = descriptionLinkRemainders(
      linkStart: 0,
      linkEnd: 20,
      markStart: 6,
      markEnd: 11,
    );
    expect(left, [
      (start: 0, end: 6),
      (start: 11, end: 20),
    ]);
  });

  test('cutting the whole connected span drops it', () {
    expect(
      descriptionLinkRemainders(
        linkStart: 4,
        linkEnd: 10,
        markStart: 4,
        markEnd: 10,
      ),
      isEmpty,
    );
  });

  test('a mark that misses the span leaves it alone', () {
    expect(
      descriptionLinkRemainders(
        linkStart: 10,
        linkEnd: 16,
        markStart: 0,
        markEnd: 4,
      ),
      [(start: 10, end: 16)],
    );
  });
}
