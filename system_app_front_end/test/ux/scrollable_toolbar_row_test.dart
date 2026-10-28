import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/shell/scrollable_toolbar_row.dart';

void main() {
  for (final direction in TextDirection.values) {
    testWidgets('toolbar scrolls without overlapping in $direction', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Directionality(
        textDirection: direction,
        child: const Align(alignment: Alignment.topLeft, child: SizedBox(
          width: 240,
          child: ScrollableToolbarRow(
            leading: SizedBox(key: ValueKey('leading'), width: 100, height: 48),
            content: SizedBox(key: ValueKey('tools'), width: 600, height: 48),
          ),
        )),
      ))));
      expect(tester.takeException(), isNull);
      final leading = tester.getRect(find.byKey(const ValueKey('leading')));
      final tools = tester.getRect(find.byKey(const ValueKey('tools')));
      expect(leading.overlaps(tools), isFalse);
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable));
      expect(scroll.position.maxScrollExtent, greaterThan(400));
      await tester.drag(find.byType(SingleChildScrollView),
        Offset(direction == TextDirection.ltr ? -180 : 180, 0));
      await tester.pumpAndSettle();
      expect(scroll.position.pixels, greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  }
}
