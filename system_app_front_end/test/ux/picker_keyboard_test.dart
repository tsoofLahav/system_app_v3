import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_app_front_end/areas/ui/color_dialog.dart';
import 'package:system_app_front_end/areas/ux/create_topic/icon_category_picker.dart';
import 'package:system_app_front_end/areas/ux/topic/topic_appearance.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  testWidgets('colour dialog arrows walk presets and enter chooses', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () async {
                picked = await showAppColorDialog(
                  context: context,
                  strings: AppStrings.en,
                  selectedHex: TopicAppearance.presetColors.first,
                  presetHexes: TopicAppearance.presetColors,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'color-presets',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, TopicAppearance.presetColors[1]);
  });

  testWidgets('colour dialog tab moves from presets to the spectrum', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return TextButton(
              onPressed: () {
                showAppColorDialog(
                  context: context,
                  strings: AppStrings.en,
                  selectedHex: TopicAppearance.presetColors.first,
                  presetHexes: TopicAppearance.presetColors,
                );
              },
              child: const Text('open'),
            );
          },
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'color-spectrum',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text(TopicAppearance.presetColors.first), findsNothing);
  });

  testWidgets('emoji picker tab moves from the grid to the section bar', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 420,
            child: IconCategoryPicker(
              selectedId: '😀',
              onSelected: _noop,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFocus(tester, 'emoji-grid');
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'emoji-grid',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(
      tester.binding.focusManager.primaryFocus?.debugLabel,
      'emoji-sections',
    );
  });

  testWidgets('colour preset arrows stay physical in RTL', (tester) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () async {
                  picked = await showAppColorDialog(
                    context: context,
                    strings: AppStrings.he,
                    selectedHex: TopicAppearance.presetColors.first,
                    presetHexes: TopicAppearance.presetColors,
                  );
                },
                child: const Text('open'),
              );
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(picked, TopicAppearance.presetColors[1]);
  });

  testWidgets('emoji picker enter chooses the highlighted cell', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 420,
            child: IconCategoryPicker(
              selectedId: '😀',
              onSelected: (emoji) => picked = emoji,
            ),
          ),
        ),
      ),
    );

    await _pumpUntilFocus(tester, 'emoji-grid');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(picked, isNotNull);
    expect(picked, isNotEmpty);
  });
}

void _noop(String _) {}

Future<void> _pumpUntilFocus(WidgetTester tester, String label) async {
  for (var i = 0; i < 40; i++) {
    await tester.pump(const Duration(milliseconds: 50));
    if (tester.binding.focusManager.primaryFocus?.debugLabel == label) {
      return;
    }
  }
  fail(
    'timed out waiting for focus "$label" '
    '(have ${tester.binding.focusManager.primaryFocus?.debugLabel})',
  );
}
