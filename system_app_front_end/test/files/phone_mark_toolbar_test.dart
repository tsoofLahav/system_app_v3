import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:follow_the_leader/follow_the_leader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/phone_mark_toolbar.dart';
import 'package:system_app_front_end/areas/files/rich_text/connect_info.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/ux/widgets/app_context_menu.dart';
import 'package:system_app_front_end/core/l10n/app_strings.dart';
import 'package:system_app_front_end/core/platform/app_form_factor.dart';

void main() {
  test('mark toolbar always includes More, and Info when asked', () {
    final items = phoneMarkButtonItems(
      strings: AppStrings.en,
      onCut: () {},
      onCopy: () {},
      onPaste: () {},
      onMore: () {},
      onInfo: () {},
    );
    expect(items.map((i) => i.label), ['Cut', 'Copy', 'Paste', 'Info', 'More']);

    final withoutInfo = phoneMarkButtonItems(
      strings: AppStrings.he,
      onCut: () {},
      onCopy: () {},
      onPaste: () {},
      onMore: () {},
    );
    expect(withoutInfo.map((i) => i.label), ['גזור', 'העתק', 'הדבק', 'עוד']);
  });

  test('SE and object-field helpers emit the same Cut/Copy/Paste/Info/More buttons', () {
    expect(
      phoneMarkToolbarButtons(
        strings: AppStrings.en,
        onCut: () {},
        onCopy: () {},
        onPaste: () {},
        onMore: () {},
        onInfo: () {},
      ),
      hasLength(5),
    );
    expect(
      phoneMarkToolbarButtons(
        strings: AppStrings.en,
        onCut: () {},
        onCopy: () {},
        onPaste: () {},
        onMore: () {},
      ),
      hasLength(4),
    );
  });

  test('SE and object-field helpers emit the same Cut/Copy/Paste/Info/More list', () {
    List<String?> labels({VoidCallback? onInfo}) => phoneMarkButtonItems(
      strings: AppStrings.en,
      onCut: () {},
      onCopy: () {},
      onPaste: () {},
      onMore: () {},
      onInfo: onInfo,
    ).map((i) => i.label).toList();

    expect(labels(onInfo: () {}), ['Cut', 'Copy', 'Paste', 'Info', 'More']);
    expect(labels(), ['Cut', 'Copy', 'Paste', 'More']);
    expect(
      phoneMarkSystemItems(
        strings: AppStrings.en,
        onCut: () {},
        onCopy: () {},
        onPaste: () {},
        onMore: () {},
        onInfo: () {},
      ).map((i) => (i as IOSSystemContextMenuItemCustom).title),
      ['Cut', 'Copy', 'Paste', 'Info', 'More'],
    );
  });

  test('body drag to mark is off on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(phoneMarksWithHandlesOnly, isTrue);
    debugDefaultTargetPlatformOverride = null;
    expect(phoneMarksWithHandlesOnly, isFalse);
  });

  test('description covering offsets hits a connected span', () {
    final ranges = [
      const DescriptionTextRange(start: 2, end: 6, link: {'id': 4}),
    ];
    expect(
      descriptionRangeCoveringOffsets(ranges, start: 2, end: 6)?.link['id'],
      4,
    );
    expect(descriptionRangeCoveringOffsets(ranges, start: 0, end: 1), isNull);
  });

  testWidgets('modal context menu lists the text actions', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    late BuildContext dialogContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            dialogContext = context;
            return const Scaffold(body: SizedBox.expand());
          },
        ),
      ),
    );

    final future = AppContextMenu.showModal(
      context: dialogContext,
      isRtl: false,
      entries: [
        AppContextMenuItem(value: 'text:bold', label: AppStrings.en['bold']),
        AppContextMenuItem(
          value: 'list:make',
          label: AppStrings.en['makeList'],
        ),
      ],
    );
    await tester.pumpAndSettle();
    expect(find.text('Bold'), findsOneWidget);
    expect(find.text('Make list'), findsOneWidget);

    await tester.tap(find.text('Bold'));
    await tester.pumpAndSettle();
    expect(await future, 'text:bold');

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('SE mark toolbar paints its buttons without a leader size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PhoneIosMarkToolbar(
            focalPoint: LeaderLink(),
            strings: AppStrings.en,
            onCut: () {},
            onCopy: () {},
            onPaste: () {},
            onMore: () {},
          ),
        ),
      ),
    );
    expect(find.text('Cut'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    expect(find.text('Paste'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('object field body drag does not grow a mark on iOS', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            style: const TextStyle(fontSize: 16),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(FormattedTextField));
    await tester.pump();
    expect(controller.selection.isCollapsed, isTrue);
    await tester.drag(find.byType(FormattedTextField), const Offset(100, 0));
    await tester.pump();
    expect(controller.selection.isCollapsed, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone double-tap marks a word in an object field', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);
    var descriptionOpened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FormattedTextField(
            controller: controller,
            style: const TextStyle(fontSize: 16),
            descriptionRanges: const [
              DescriptionTextRange(start: 0, end: 5, link: {'id': 1}),
            ],
            onDescriptionDoubleTap: (_) => descriptionOpened++,
          ),
        ),
      ),
    );
    final field = find.byType(FormattedTextField);
    await tester.tap(field);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    expect(controller.selection.isCollapsed, isFalse);
    final marked = controller.selection.textInside(controller.text);
    expect(marked == 'hello' || marked == 'world', isTrue);
    expect(descriptionOpened, 0);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone double-tap on empty field opens paste menu without a mark', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 80,
            child: FormattedTextField(
              controller: controller,
              style: const TextStyle(fontSize: 16),
              hintText: 'note',
            ),
          ),
        ),
      ),
    );
    final field = find.byType(FormattedTextField);
    await tester.tap(field);
    await tester.pump();
    await tester.tap(field);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(controller.selection.isCollapsed, isTrue);
    expect(find.text('Paste'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
