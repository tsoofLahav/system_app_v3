import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/files/data/topic.dart';
import 'package:system_app_front_end/areas/ux/shell/phone_top_bar.dart';
import 'package:system_app_front_end/areas/ux/shell/phone_visible_file.dart';
import 'package:system_app_front_end/areas/ux/widgets/topic_emoji.dart';

void main() {
  testWidgets('projected header shows Home above source and file with emoji', (
    tester,
  ) async {
    final state = AppState()
      ..selectedTopic = const Topic(id: 1, workspaceId: 1, name: 'Home');
    const source = Topic(id: 2, workspaceId: 1, name: 'Work', icon: '💼');
    PhoneVisibleFile.setName('Notes', source: source);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 390,
            child: PhoneTopBar(
              state: state,
              title: 'Home',
              onOpenMenu: () {},
              showAddFile: true,
              showBringFile: true,
              onAddFile: () {},
              onBringFile: () {},
            ),
          ),
        ),
      ),
    );
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('·'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Work')).dy -
          tester.getBottomLeft(find.text('Home')).dy,
      lessThanOrEqualTo(2),
    );
    expect(find.byType(TopicEmoji), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Home')).dy,
      lessThan(tester.getTopLeft(find.text('Work')).dy),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    PhoneVisibleFile.setName(null);
    state.dispose();
  });
}
