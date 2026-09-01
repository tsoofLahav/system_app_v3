import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/editor_key_handoff.dart';

void main() {
  testWidgets('runWhenKeyboardIdle runs now when no key is down', (tester) async {
    var ran = false;
    runWhenKeyboardIdle(() => ran = true);
    expect(ran, isTrue);
  });

  testWidgets('runWhenKeyboardIdle waits until the physical key is up', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyT);
    expect(hardwareKeysAreDown(), isTrue);

    var ran = false;
    runWhenKeyboardIdle(() => ran = true);
    await tester.pump();
    expect(ran, isFalse);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyT);
    await tester.pump();
    await tester.pump();
    expect(hardwareKeysAreDown(), isFalse);
    expect(ran, isTrue);
  });

  testWidgets('whenKeyboardIdle completes after keys are up', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyA);
    var done = false;
    final future = whenKeyboardIdle().then((_) => done = true);
    await tester.pump();
    expect(done, isFalse);

    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyA);
    await tester.pump();
    await tester.pump();
    await future;
    expect(done, isTrue);
  });
}
