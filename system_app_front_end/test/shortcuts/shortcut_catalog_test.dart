import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/shortcuts/shortcut_catalog.dart';

void main() {
  test('catalog default bindings are unique', () {
    final seen = <String, String>{};

    for (final action in kShortcutCatalog) {
      final label = action.defaultBinding.displayLabel();
      final owner = seen[label];
      expect(
        owner,
        isNull,
        reason:
            'Duplicate default binding $label on ${action.id} and $owner',
      );
      seen[label] = action.id;
    }
  });

  test('agent is labeled Agent and keeps Cmd+1', () {
    final agent = kShortcutCatalog
        .firstWhere((a) => a.id == ShortcutActionIds.aiConsult);
    expect(agent.labelKey, 'aiAgent');
    expect(agent.defaultBinding.keyId, LogicalKeyboardKey.digit1.keyId);
    expect(agent.defaultBinding.meta, isTrue);
    expect(agent.defaultBinding.shift, isFalse);
  });

  test('emoji defaults to Cmd+E', () {
    final action = shortcutActionById(ShortcutActionIds.insertEmoji)!;
    expect(action.defaultBinding.keyId, LogicalKeyboardKey.keyE.keyId);
    expect(action.defaultBinding.meta, isTrue);
    expect(action.defaultBinding.shift, isFalse);
    expect(action.context, ShortcutContextRequirement.insertObject);
  });

  test('language defaults to Cmd+Shift+E', () {
    final language = kShortcutCatalog
        .firstWhere((a) => a.id == ShortcutActionIds.toggleLanguage);
    expect(language.defaultBinding.keyId, LogicalKeyboardKey.keyE.keyId);
    expect(language.defaultBinding.meta, isTrue);
    expect(language.defaultBinding.shift, isTrue);
  });

  test('assign task view is not a text-format action', () {
    final action = kShortcutCatalog
        .firstWhere((a) => a.id == ShortcutActionIds.assignTaskView);
    expect(action.context, ShortcutContextRequirement.none);
    expect(action.textAction, isNull);
    expect(action.defaultBinding.keyId, LogicalKeyboardKey.keyJ.keyId);
  });

  test('cycle files uses [ forward and ] backward', () {
    final forward = kShortcutCatalog
        .firstWhere((a) => a.id == ShortcutActionIds.cycleMainFiles);
    final back = kShortcutCatalog
        .firstWhere((a) => a.id == ShortcutActionIds.cycleMainFilesBack);
    expect(forward.defaultBinding.keyId, LogicalKeyboardKey.bracketLeft.keyId);
    expect(back.defaultBinding.keyId, LogicalKeyboardKey.bracketRight.keyId);
    expect(forward.context, ShortcutContextRequirement.topicMode);
    expect(back.context, ShortcutContextRequirement.topicMode);
  });

  test('heavy-use navigation defaults are two keys', () {
    void expectCmd(String id, LogicalKeyboardKey key) {
      final action = shortcutActionById(id)!;
      expect(action.defaultBinding.keyId, key.keyId);
      expect(action.defaultBinding.meta, isTrue);
      expect(action.defaultBinding.shift, isFalse);
      expect(action.defaultBinding.alt, isFalse);
    }

    expectCmd(ShortcutActionIds.openFileLayout, LogicalKeyboardKey.keyR);
    expectCmd(ShortcutActionIds.toggleGridFileLayout, LogicalKeyboardKey.period);
    expectCmd(ShortcutActionIds.addFile, LogicalKeyboardKey.keyF);
    expectCmd(ShortcutActionIds.addTopic, LogicalKeyboardKey.keyN);
    expectCmd(ShortcutActionIds.insertInfo, LogicalKeyboardKey.keyD);
    expectCmd(ShortcutActionIds.insertTaskList, LogicalKeyboardKey.keyT);
    expectCmd(ShortcutActionIds.insertGraph, LogicalKeyboardKey.keyG);
    expectCmd(ShortcutActionIds.insertEmoji, LogicalKeyboardKey.keyE);
    expectCmd(ShortcutActionIds.addConnection, LogicalKeyboardKey.keyL);
    expectCmd(ShortcutActionIds.toggleReorderMode, LogicalKeyboardKey.keyO);
  });

  test('move object defaults to Cmd+Shift+O', () {
    final action = shortcutActionById(ShortcutActionIds.toggleEmbedMoveMode)!;
    expect(action.defaultBinding.keyId, LogicalKeyboardKey.keyO.keyId);
    expect(action.defaultBinding.meta, isTrue);
    expect(action.defaultBinding.shift, isTrue);
  });

  test('file layout defaults to Cmd+R and arrange to Cmd+Option+R', () {
    final layout = shortcutActionById(ShortcutActionIds.openFileLayout)!;
    expect(layout.defaultBinding.keyId, LogicalKeyboardKey.keyR.keyId);
    expect(layout.defaultBinding.meta, isTrue);
    expect(layout.defaultBinding.shift, isFalse);
    expect(layout.defaultBinding.alt, isFalse);
    expect(layout.context, ShortcutContextRequirement.topicMode);

    final arrange = shortcutActionById(ShortcutActionIds.openArrange)!;
    expect(arrange.defaultBinding.keyId, LogicalKeyboardKey.keyR.keyId);
    expect(arrange.defaultBinding.meta, isTrue);
    expect(arrange.defaultBinding.shift, isFalse);
    expect(arrange.defaultBinding.alt, isTrue);
  });

  test('grid layout toggle defaults to Cmd+.', () {
    final action = shortcutActionById(ShortcutActionIds.toggleGridFileLayout)!;
    expect(action.defaultBinding.keyId, LogicalKeyboardKey.period.keyId);
    expect(action.defaultBinding.meta, isTrue);
    expect(action.defaultBinding.shift, isFalse);
    expect(action.defaultBinding.alt, isFalse);
    expect(action.context, ShortcutContextRequirement.topicMode);
    expect(action.category, ShortcutCategory.navigation);
  });
}
