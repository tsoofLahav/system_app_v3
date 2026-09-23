import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/areas/objects/data/object_embed.dart';
import 'package:system_app_front_end/areas/files/editor/embeds/table_embed.dart';

class DelayedState extends AppState {
  final gates = <Completer<void>>[];
  final writes = <Map<String, dynamic>>[];

  @override
  Future<void> updateObjectPayload(
    int id,
    Map<String, dynamic> payload, {
    bool notify = false,
  }) {
    writes.add(payload);
    final old = embedsByFileId[1]!.single;
    embedsByFileId[1] = [old.copyWith(payload: payload)];
    final gate = Completer<void>();
    gates.add(gate);
    return gate.future;
  }

  void poll() => notifyListeners();
}

void main() {
  testWidgets('own pending table save never opens a conflict while typing', (
    tester,
  ) async {
    final state = DelayedState();
    const embed = ObjectEmbed(
      id: 1,
      fileId: 1,
      type: 'table',
      payload: {
        'rows': [
          [
            {'text': 'base'},
          ],
        ],
      },
    );
    state.embedsByFileId[1] = [embed];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEmbed(
            embed: embed,
            blockId: 'embed:1',
            state: state,
            onPayloadChanged: (_) {},
          ),
        ),
      ),
    );
    final field = find.byType(TextField).first;
    await tester.enterText(field, 'first');
    await tester.pump(const Duration(milliseconds: 450));
    expect(state.writes, hasLength(1));
    await tester.enterText(field, 'second');
    state.poll();
    await tester.pump();
    await tester.pump();
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text(state.strings['editConflictTitle']), findsNothing);
    expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
    state.gates.first.complete();
    await tester.pump();
    expect(state.writes, hasLength(2));
    expect(state.writes.last['rows'][0][0]['text'], 'second');
    state.gates.last.complete();
    await tester.pump(const Duration(milliseconds: 500));
    state.poll();
    await tester.pump();
    expect(tester.widget<TextField>(field).controller!.text, 'second');
    expect(find.text(state.strings['editConflictTitle']), findsNothing);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
    expect(tester.takeException(), isNull);
  });
}
