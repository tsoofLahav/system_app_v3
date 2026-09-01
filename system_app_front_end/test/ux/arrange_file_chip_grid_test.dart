import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/arrange/arrange_file_chip_grid.dart';

void main() {
  test('dropping onto a later gap accounts for the removed index', () {
    expect(arrangeChipDest(from: 0, insertIndex: 4), 3);
    expect(arrangeChipDest(from: 3, insertIndex: 0), 0);
    expect(arrangeChipDest(from: 1, insertIndex: 1), 1);
    expect(arrangeChipDest(from: 1, insertIndex: 2), 1);
  });

  test('trailing gap of a wrap places the file last in that wrap', () {
    expect(arrangeTrailingDest(wrapEnd: 3), 2);
    expect(arrangeTrailingDest(wrapEnd: 1), 0);
  });
}
