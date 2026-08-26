import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/embed_caret_bridge.dart';
import 'package:system_app_front_end/areas/ui/app_colors.dart';
import 'package:system_app_front_end/areas/ux/shell/app_bottom_bar.dart';
import 'package:system_app_front_end/areas/ux/shell/dismiss_focus_on_outside_tap.dart';

void main() {
  test('phone header is off-white; topic ombre only off Home and views', () {
    const accent = Color(0xFF3B82F6);
    final home = AppColors.phoneHeaderDecoration(
      topicAccent: accent,
      isMainTopic: true,
    );
    final view = AppColors.phoneHeaderDecoration(
      topicAccent: accent,
      isMainTopic: false,
      neutral: true,
    );
    final topic = AppColors.phoneHeaderDecoration(
      topicAccent: accent,
      isMainTopic: false,
    );
    expect(home.color, AppColors.phoneStripe);
    expect(home.gradient, isNull);
    expect(view.color, AppColors.phoneStripe);
    expect(view.gradient, isNull);
    expect(topic.gradient, isNotNull);
    expect(topic.gradient!.colors.first, AppColors.phoneStripe);
    expect(topic.gradient!.colors.last, isNot(equals(AppColors.phoneStripe)));
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
          child: Scaffold(body: TextField(focusNode: focus)),
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

  testWidgets('tapping object chrome unfocuses the inner field', (
    tester,
  ) async {
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
                  height: 80,
                  child: Text('object-chrome'),
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

    await tester.tap(find.text('object-chrome'));
    await tester.pump();
    expect(focus.hasFocus, isFalse);
  });

  testWidgets('EmbedEditScope is not a keep-focus island', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: EmbedEditScope(nodeId: 'embed:1', child: Text('object')),
      ),
    );
    expect(find.byType(KeepEditorFocus), findsNothing);
  });
}
