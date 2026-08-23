import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ui/app_icons.dart';
import 'package:system_app_front_end/areas/ux/shell/app_bottom_bar.dart';

void main() {
  testWidgets('object pad stays LTR under a Hebrew UI', (tester) async {
    AxisDirection? nudged;

    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: ObjectArrowPad(
            leftTooltip: 'Left',
            downTooltip: 'Down',
            upTooltip: 'Up',
            rightTooltip: 'Right',
            enterLeaveTooltip: 'Enter',
            leave: false,
            onNudge: (d) => nudged = d,
            onEnterOrLeave: () {},
          ),
        ),
      ),
    );

    expect(
      Directionality.of(tester.element(find.byKey(ObjectArrowPad.padKey))),
      TextDirection.ltr,
    );

    final buttons = tester
        .widgetList<IconButton>(
          find.descendant(
            of: find.byKey(ObjectArrowPad.padKey),
            matching: find.byType(IconButton),
          ),
        )
        .toList();
    final icons = buttons.map((b) => (b.icon as AppIcon).icon).toList();
    expect(icons[0], AppIcons.arrowLeft);
    expect(icons[1], AppIcons.arrowDown);
    expect(icons[2], AppIcons.arrowUp);
    expect(icons[3], AppIcons.arrowRight);

    for (final button in buttons) {
      expect((button.icon as AppIcon).textDirection, TextDirection.ltr);
    }

    await tester.tap(find.byTooltip('Left'));
    expect(nudged, AxisDirection.left);
  });
}
