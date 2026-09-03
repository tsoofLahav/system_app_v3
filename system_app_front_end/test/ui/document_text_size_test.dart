import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ui/app_typography.dart';
import 'package:system_app_front_end/areas/ux/shell/app_bottom_bar.dart';
import 'package:system_app_front_end/core/document_text_size.dart';
import 'package:system_app_front_end/core/l10n/app_language.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() {
    AppTypography.configure(
      appLanguage: AppLanguage.en,
      textSize: DocumentTextSize.pt12_5,
    );
  });

  test('stored text size names round-trip', () {
    expect(DocumentTextSize.fromStorage('medium'), DocumentTextSize.pt14);
    expect(DocumentTextSize.fromStorage('large'), DocumentTextSize.pt16);
    expect(DocumentTextSize.fromStorage('small'), DocumentTextSize.pt12_5);
    expect(DocumentTextSize.fromStorage('pt15'), DocumentTextSize.pt15);
  });

  test('document body size follows the chosen step', () {
    AppTypography.configure(
      appLanguage: AppLanguage.en,
      textSize: DocumentTextSize.pt12_5,
    );
    expect(AppTypography.documentBodySize, 12.5);
    AppTypography.configure(
      appLanguage: AppLanguage.en,
      textSize: DocumentTextSize.pt14,
    );
    expect(AppTypography.documentBodySize, 14);
    AppTypography.configure(
      appLanguage: AppLanguage.en,
      textSize: DocumentTextSize.pt16,
    );
    expect(AppTypography.documentBodySize, 16);
    AppTypography.configure(
      appLanguage: AppLanguage.en,
      textSize: DocumentTextSize.pt18,
    );
    expect(AppTypography.documentBodySize, 18);
  });

  test('phone chrome floats on a fade, not a reserved footer stripe', () {
    expect(
      AppBottomBarMetrics.phoneBarHeight,
      AppBottomBarMetrics.phoneFloatMargin * 2 +
          AppBottomBarMetrics.phoneSegmentHeight,
    );
    expect(AppBottomBarMetrics.phoneOmbreFade, greaterThan(0));
    expect(AppBottomBarMetrics.phonePeekInset, greaterThan(0));
  });
}
