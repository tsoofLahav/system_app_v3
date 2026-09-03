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
      textSize: DocumentTextSize.small,
    );
  });

  test('stored text size names round-trip', () {
    expect(DocumentTextSize.fromStorage('medium'), DocumentTextSize.medium);
    expect(DocumentTextSize.fromStorage('large'), DocumentTextSize.large);
    expect(DocumentTextSize.fromStorage('small'), DocumentTextSize.small);
  });

  test('document body size follows the chosen step', () {
    AppTypography.configure(
      appLanguage: AppLanguage.en,
      textSize: DocumentTextSize.small,
    );
    expect(AppTypography.documentBodySize, 12.5);
    AppTypography.configure(
      appLanguage: AppLanguage.en,
      textSize: DocumentTextSize.medium,
    );
    expect(AppTypography.documentBodySize, 14);
    AppTypography.configure(
      appLanguage: AppLanguage.en,
      textSize: DocumentTextSize.large,
    );
    expect(AppTypography.documentBodySize, 16);
  });

  test('phone footer stripe disappears while the keyboard is open', () {
    expect(
      AppBottomBarMetrics.phoneFooterHeight(
        viewPaddingBottom: 34,
        viewInsetsBottom: 0,
      ),
      34 + AppBottomBarMetrics.phoneFooterStripe,
    );
    expect(
      AppBottomBarMetrics.phoneFooterHeight(
        viewPaddingBottom: 34,
        viewInsetsBottom: 280,
      ),
      0,
    );
  });
}
