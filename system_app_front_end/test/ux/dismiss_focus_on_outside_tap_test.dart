import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ui/app_colors.dart';
import 'package:system_app_front_end/areas/ux/shell/app_bottom_bar.dart';
import 'package:system_app_front_end/areas/ux/shell/dismiss_focus_on_outside_tap.dart';
import 'package:system_app_front_end/areas/ux/shell/phone_visible_file.dart';

void main() {
  test('phone edge ombre is grey on Home and views; topic-tinted otherwise', () {
    const accent = Color(0xFF3B82F6);
    expect(
      AppColors.phoneEdgeColor(topicAccent: accent, isMainTopic: true),
      AppColors.phoneCanvas,
    );
    expect(
      AppColors.phoneEdgeColor(
        topicAccent: accent,
        isMainTopic: false,
        neutral: true,
      ),
      AppColors.phoneCanvas,
    );
    final topic = AppColors.phoneEdgeColor(
      topicAccent: accent,
      isMainTopic: false,
    );
    expect(topic, isNot(equals(AppColors.phoneCanvas)));
    final fade = AppColors.phoneEdgeOmbre(edge: topic, atTop: true);
    expect(fade.colors.first.a, greaterThan(fade.colors.last.a));
  });

  test('phone visible file name is chrome-only and idempotent', () {
    PhoneVisibleFile.setName(null);
    PhoneVisibleFile.setName('Notes');
    expect(PhoneVisibleFile.name.value, 'Notes');
    PhoneVisibleFile.setName('Notes');
    PhoneVisibleFile.setName(null);
    expect(PhoneVisibleFile.name.value, isNull);
  });

  test('phone bar is one row, not a vertical stack', () {
    expect(
      AppBottomBarMetrics.phoneBarHeight,
      AppBottomBarMetrics.phoneFloatMargin * 2 +
          AppBottomBarMetrics.phoneSegmentHeight,
    );
  });

  testWidgets('tapping outside a focused field unfocuses it', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DismissFocusOnOutsideTap(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focus),
                const SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: Text('outside'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('outside'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('tapping the focused field itself keeps focus', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DismissFocusOnOutsideTap(
          child: Scaffold(
            body: TextField(focusNode: focus),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });

  testWidgets('tapping another field moves focus there', (tester) async {
    final first = FocusNode();
    final second = FocusNode();
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DismissFocusOnOutsideTap(
          child: Scaffold(
            body: Column(
              children: [
                TextField(key: const Key('first'), focusNode: first),
                TextField(key: const Key('second'), focusNode: second),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('first')));
    await tester.pump();
    expect(first.hasFocus, isTrue);

    await tester.tap(find.byKey(const Key('second')));
    await tester.pump();
    expect(second.hasFocus, isTrue);
    expect(first.hasFocus, isFalse);
  });

  testWidgets('tapping the bottom menu keeps editor focus', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: DismissFocusOnOutsideTap(
          child: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: focus),
                KeepEditorFocus(
                  child: GestureDetector(
                    onTap: () {},
                    child: const SizedBox(
                      width: double.infinity,
                      height: 48,
                      child: Text('bottom-menu'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byType(TextField));
    await tester.pump();
    expect(focus.hasFocus, isTrue);

    await tester.tap(find.text('bottom-menu'));
    await tester.pump();
    expect(focus.hasFocus, isTrue);
  });
}
