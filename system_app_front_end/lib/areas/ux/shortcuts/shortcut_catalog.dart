import 'package:flutter/services.dart';

import './shortcut_binding.dart';

enum ShortcutCategory {
  navigation,
  ai,
  text,
  objects,
}

enum ShortcutContextRequirement {
  none,
  topicMode,
  mainTopic,
  aiContext,
  textFocus,
  /// Insert an object into the active file (via [DocumentEditorRegistry]).
  insertObject,
  toggleLayoutMode,
}

class ShortcutAction {
  const ShortcutAction({
    required this.id,
    required this.category,
    required this.labelKey,
    required this.defaultBinding,
    this.context = ShortcutContextRequirement.none,
    this.insertType,
    this.textAction,
  });

  final String id;
  final ShortcutCategory category;
  final String labelKey;
  final ShortcutBinding defaultBinding;
  final ShortcutContextRequirement context;

  /// Value for [DocumentEditorController.insertAtBlock] (object or structure).
  final String? insertType;
  final String? textAction;
}

abstract final class ShortcutActionIds {
  static const goHome = 'go_home';
  static const bringFile = 'bring_file';
  static const openArrange = 'open_arrange';
  static const cycleMainFiles = 'cycle_main_files';
  static const cycleMainFilesBack = 'cycle_main_files_back';
  static const addFile = 'add_file';
  static const addTopic = 'add_topic';
  static const addView = 'add_view';
  static const assignTaskView = 'assign_task_view';

  static const aiConsult = 'ai_consult';

  /// One id per seat on the AI bar. The key belongs to the **slot**, so moving
  /// an action moves its shortcut with it and there is nothing to pick.
  static String aiActionSlot(int slot) => 'ai_action_$slot';

  /// The slot an id stands for, or null when the id is something else.
  static int? slotOfAiAction(String actionId) {
    final match = _aiActionSlotRe.firstMatch(actionId);
    return match == null ? null : int.parse(match.group(1)!);
  }

  static const textBold = 'text_bold';
  static const textItalic = 'text_italic';
  static const textUnderline = 'text_underline';
  static const textCut = 'text_cut';
  static const textCopy = 'text_copy';
  static const textPaste = 'text_paste';
  static const textSizeUp = 'text_size_up';
  static const textSizeDown = 'text_size_down';

  static const insertInfo = 'insert_info';
  static const insertImage = 'insert_image';
  static const insertTable = 'insert_table';
  static const insertGraph = 'insert_graph';
  static const insertTaskList = 'insert_task_list';
  static const toggleLayoutMode = 'toggle_layout_mode';
  static const toggleLanguage = 'toggle_language';
  static const addConnection = 'add_connection';
  static const toggleReorderMode = 'toggle_reorder_mode';
  static const toggleEmbedMoveMode = 'toggle_embed_move_mode';
}

final _aiActionSlotRe = RegExp(r'^ai_action_(\d+)$');

/// Cmd+Shift+2 .. Cmd+Shift+7 — the digit is the slot plus one, because
/// Cmd+Shift+1 belongs to the agent button that is always on the bar.
const _aiActionSlotKeys = [
  LogicalKeyboardKey.digit2,
  LogicalKeyboardKey.digit3,
  LogicalKeyboardKey.digit4,
  LogicalKeyboardKey.digit5,
  LogicalKeyboardKey.digit6,
  LogicalKeyboardKey.digit7,
];

ShortcutBinding _m(
  LogicalKeyboardKey key, {
  bool shift = false,
  bool alt = false,
}) {
  return ShortcutBinding(
    keyId: key.keyId,
    meta: true,
    shift: shift,
    alt: alt,
  );
}

final List<ShortcutAction> kShortcutCatalog = [
  ShortcutAction(
    id: ShortcutActionIds.goHome,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutGoHome',
    defaultBinding: _m(LogicalKeyboardKey.keyH),
  ),
  ShortcutAction(
    id: ShortcutActionIds.bringFile,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutBringFile',
    defaultBinding: _m(LogicalKeyboardKey.keyK),
    context: ShortcutContextRequirement.mainTopic,
  ),
  ShortcutAction(
    id: ShortcutActionIds.openArrange,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutOpenArrange',
    defaultBinding: _m(LogicalKeyboardKey.keyR),
    context: ShortcutContextRequirement.topicMode,
  ),
  ShortcutAction(
    id: ShortcutActionIds.cycleMainFiles,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutCycleMainFiles',
    defaultBinding: _m(LogicalKeyboardKey.bracketLeft),
    context: ShortcutContextRequirement.topicMode,
  ),
  ShortcutAction(
    id: ShortcutActionIds.cycleMainFilesBack,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutCycleMainFilesBack',
    defaultBinding: _m(LogicalKeyboardKey.bracketRight),
    context: ShortcutContextRequirement.topicMode,
  ),
  ShortcutAction(
    id: ShortcutActionIds.addFile,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutAddFile',
    defaultBinding: _m(LogicalKeyboardKey.keyF),
    context: ShortcutContextRequirement.topicMode,
  ),
  ShortcutAction(
    id: ShortcutActionIds.addTopic,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutAddTopic',
    defaultBinding: _m(LogicalKeyboardKey.keyN),
  ),
  ShortcutAction(
    id: ShortcutActionIds.addView,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutAddView',
    defaultBinding: _m(LogicalKeyboardKey.keyW, shift: true),
  ),
  ShortcutAction(
    id: ShortcutActionIds.assignTaskView,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutAssignTaskView',
    defaultBinding: _m(LogicalKeyboardKey.keyJ),
  ),
  ShortcutAction(
    id: ShortcutActionIds.aiConsult,
    category: ShortcutCategory.ai,
    labelKey: 'aiAgent',
    defaultBinding: _m(LogicalKeyboardKey.digit1, shift: true),
    context: ShortcutContextRequirement.aiContext,
  ),
  for (var slot = 1; slot <= _aiActionSlotKeys.length; slot++)
    ShortcutAction(
      id: ShortcutActionIds.aiActionSlot(slot),
      category: ShortcutCategory.ai,
      labelKey: 'aiActionSlot$slot',
      defaultBinding: _m(_aiActionSlotKeys[slot - 1], shift: true),
      context: ShortcutContextRequirement.aiContext,
    ),
  ShortcutAction(
    id: ShortcutActionIds.textBold,
    category: ShortcutCategory.text,
    labelKey: 'bold',
    defaultBinding: _m(LogicalKeyboardKey.keyB),
    context: ShortcutContextRequirement.textFocus,
    textAction: 'text:bold',
  ),
  ShortcutAction(
    id: ShortcutActionIds.textItalic,
    category: ShortcutCategory.text,
    labelKey: 'italic',
    defaultBinding: _m(LogicalKeyboardKey.keyI),
    context: ShortcutContextRequirement.textFocus,
    textAction: 'text:italic',
  ),
  ShortcutAction(
    id: ShortcutActionIds.textUnderline,
    category: ShortcutCategory.text,
    labelKey: 'underline',
    defaultBinding: _m(LogicalKeyboardKey.keyU),
    context: ShortcutContextRequirement.textFocus,
    textAction: 'text:underline',
  ),
  ShortcutAction(
    id: ShortcutActionIds.textCut,
    category: ShortcutCategory.text,
    labelKey: 'cut',
    defaultBinding: _m(LogicalKeyboardKey.keyX),
    context: ShortcutContextRequirement.textFocus,
    textAction: 'text:cut',
  ),
  ShortcutAction(
    id: ShortcutActionIds.textCopy,
    category: ShortcutCategory.text,
    labelKey: 'copy',
    defaultBinding: _m(LogicalKeyboardKey.keyC),
    context: ShortcutContextRequirement.textFocus,
    textAction: 'text:copy',
  ),
  ShortcutAction(
    id: ShortcutActionIds.textPaste,
    category: ShortcutCategory.text,
    labelKey: 'paste',
    defaultBinding: _m(LogicalKeyboardKey.keyV),
    context: ShortcutContextRequirement.textFocus,
    textAction: 'text:paste',
  ),
  ShortcutAction(
    id: ShortcutActionIds.textSizeUp,
    category: ShortcutCategory.text,
    labelKey: 'textSizeUp',
    defaultBinding: _m(LogicalKeyboardKey.equal, shift: true),
    context: ShortcutContextRequirement.textFocus,
    textAction: 'text:size_up',
  ),
  ShortcutAction(
    id: ShortcutActionIds.textSizeDown,
    category: ShortcutCategory.text,
    labelKey: 'textSizeDown',
    defaultBinding: _m(LogicalKeyboardKey.minus, shift: true),
    context: ShortcutContextRequirement.textFocus,
    textAction: 'text:size_down',
  ),
  // Letter matches the English object name. Task + Table both want T —
  // Table keeps ⌥ so the key stays T without stealing italic / new-tab.
  ShortcutAction(
    id: ShortcutActionIds.insertInfo,
    category: ShortcutCategory.objects,
    labelKey: 'addDetails',
    defaultBinding: _m(LogicalKeyboardKey.keyD),
    context: ShortcutContextRequirement.insertObject,
    insertType: 'info',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertTaskList,
    category: ShortcutCategory.objects,
    labelKey: 'addTaskList',
    defaultBinding: _m(LogicalKeyboardKey.keyT),
    context: ShortcutContextRequirement.insertObject,
    insertType: 'task_list',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertTable,
    category: ShortcutCategory.objects,
    labelKey: 'addTable',
    defaultBinding: _m(LogicalKeyboardKey.keyT, alt: true),
    context: ShortcutContextRequirement.insertObject,
    insertType: 'table',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertGraph,
    category: ShortcutCategory.objects,
    labelKey: 'addGraph',
    defaultBinding: _m(LogicalKeyboardKey.keyG),
    context: ShortcutContextRequirement.insertObject,
    insertType: 'graph',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertImage,
    category: ShortcutCategory.objects,
    labelKey: 'addImage',
    defaultBinding: _m(LogicalKeyboardKey.keyI, shift: true),
    context: ShortcutContextRequirement.insertObject,
    insertType: 'image',
  ),
  ShortcutAction(
    id: ShortcutActionIds.toggleLayoutMode,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutToggleLayoutMode',
    defaultBinding: _m(LogicalKeyboardKey.keyM, shift: true),
    context: ShortcutContextRequirement.toggleLayoutMode,
  ),
  ShortcutAction(
    id: ShortcutActionIds.toggleLanguage,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutToggleLanguage',
    defaultBinding: _m(LogicalKeyboardKey.keyE),
  ),
  ShortcutAction(
    id: ShortcutActionIds.addConnection,
    category: ShortcutCategory.objects,
    labelKey: 'shortcutAddConnection',
    defaultBinding: _m(LogicalKeyboardKey.keyL),
  ),
  ShortcutAction(
    id: ShortcutActionIds.toggleReorderMode,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutReorderMode',
    defaultBinding: _m(LogicalKeyboardKey.keyO),
  ),
  ShortcutAction(
    id: ShortcutActionIds.toggleEmbedMoveMode,
    category: ShortcutCategory.objects,
    labelKey: 'shortcutMoveObject',
    defaultBinding: _m(LogicalKeyboardKey.keyO, shift: true),
  ),
];

ShortcutAction? shortcutActionById(String id) {
  for (final action in kShortcutCatalog) {
    if (action.id == id) return action;
  }
  return null;
}

Map<String, ShortcutAction> shortcutCatalogById() {
  return {for (final action in kShortcutCatalog) action.id: action};
}

String shortcutCategoryLabelKey(ShortcutCategory category) {
  return switch (category) {
    ShortcutCategory.navigation => 'shortcutCategoryNavigation',
    ShortcutCategory.ai => 'shortcutCategoryAi',
    ShortcutCategory.text => 'shortcutCategoryText',
    ShortcutCategory.objects => 'shortcutCategoryObjects',
  };
}
