import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ui/app_colors.dart';

void main() {
  test('a file keeps its shade forever', () {
    // Reordering, reopening, and other devices all recompute this from the id
    // alone, so the same id must always give the same strength.
    expect(AppColors.fileTintStrength(42), AppColors.fileTintStrength(42));
  });

  test('every shade stays within the gentle range', () {
    for (var id = 1; id <= 500; id++) {
      final strength = AppColors.fileTintStrength(id);
      expect(strength, greaterThanOrEqualTo(AppColors.minFileTint));
      expect(strength, lessThanOrEqualTo(AppColors.maxFileTint));
    }
  });

  test('files created one after another do not come out alike', () {
    // Ids are consecutive in practice, so a weak hash would give a whole topic
    // nearly the same shade.
    final consecutive = [
      for (var id = 1; id <= 8; id++) AppColors.fileTintStrength(id),
    ];
    final spread =
        consecutive.reduce((a, b) => a > b ? a : b) -
        consecutive.reduce((a, b) => a < b ? a : b);
    final range = AppColors.maxFileTint - AppColors.minFileTint;
    expect(spread, greaterThan(range * 0.5));
  });
}
