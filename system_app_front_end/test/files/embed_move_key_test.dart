import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/embed_move_bubble.dart';

void main() {
  test('arrows nudge and may repeat', () {
    expect(
      embedMoveKeyCommandFor(LogicalKeyboardKey.arrowUp, isRepeat: false),
      EmbedMoveKeyCommand.moveUp,
    );
    expect(
      embedMoveKeyCommandFor(LogicalKeyboardKey.arrowLeft, isRepeat: false),
      EmbedMoveKeyCommand.moveUp,
    );
    expect(
      embedMoveKeyCommandFor(LogicalKeyboardKey.arrowDown, isRepeat: true),
      EmbedMoveKeyCommand.moveDown,
    );
    expect(
      embedMoveKeyCommandFor(LogicalKeyboardKey.arrowRight, isRepeat: false),
      EmbedMoveKeyCommand.moveDown,
    );
  });

  test('Enter and Esc end Move Mode only on the first press', () {
    expect(
      embedMoveKeyCommandFor(LogicalKeyboardKey.enter, isRepeat: false),
      EmbedMoveKeyCommand.done,
    );
    expect(
      embedMoveKeyCommandFor(LogicalKeyboardKey.escape, isRepeat: false),
      EmbedMoveKeyCommand.done,
    );
    expect(
      embedMoveKeyCommandFor(LogicalKeyboardKey.enter, isRepeat: true),
      isNull,
    );
    expect(embedMoveModeConsumesKey(LogicalKeyboardKey.enter), isTrue);
  });

  test('other keys are left for Super Editor', () {
    expect(embedMoveModeConsumesKey(LogicalKeyboardKey.keyA), isFalse);
    expect(
      embedMoveKeyCommandFor(LogicalKeyboardKey.keyA, isRepeat: false),
      isNull,
    );
  });
}
