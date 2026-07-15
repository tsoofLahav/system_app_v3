import 'package:flutter/services.dart';

import 'shortcut_binding.dart';

enum ShortcutCategory {
  navigation,
  ai,
  text,
  blocks,
}

enum ShortcutContextRequirement {
  none,
  topicMode,
  mainTopic,
  aiContext,
  textFocus,
  insertBlock,
}

class ShortcutAction {
  const ShortcutAction({
    required this.id,
    required this.category,
    required this.labelKey,
    required this.defaultBinding,
    this.context = ShortcutContextRequirement.none,
    this.blockType,
    this.aiTool,
    this.textAction,
  });

  final String id;
  final ShortcutCategory category;
  final String labelKey;
  final ShortcutBinding defaultBinding;
  final ShortcutContextRequirement context;
  final String? blockType;
  final String? aiTool;
  final String? textAction;
}

abstract final class ShortcutActionIds {
  static const goHome = 'go_home';
  static const bringFile = 'bring_file';
  static const openArrange = 'open_arrange';
  static const cycleMainFiles = 'cycle_main_files';
  static const addFile = 'add_file';
  static const addTopic = 'add_topic';

  static const aiConsult = 'ai_consult';
  static const aiSummarize = 'ai_summarize';
  static const aiSmartList = 'ai_smart_list';
  static const aiImage = 'ai_image';
  static const aiGraph = 'ai_graph';
  static const aiMoveFile = 'ai_move_file';

  static const textBold = 'text_bold';
  static const textItalic = 'text_italic';
  static const textUnderline = 'text_underline';
  static const textCut = 'text_cut';
  static const textCopy = 'text_copy';
  static const textPaste = 'text_paste';
  static const textSizeUp = 'text_size_up';
  static const textSizeDown = 'text_size_down';

  static const insertText = 'insert_text';
  static const insertHeader = 'insert_header';
  static const insertSummary = 'insert_summary';
  static const insertList = 'insert_list';
  static const insertImage = 'insert_image';
  static const insertTable = 'insert_table';
  static const insertGraph = 'insert_graph';
}

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
    defaultBinding: _m(LogicalKeyboardKey.keyA, shift: true),
    context: ShortcutContextRequirement.topicMode,
  ),
  ShortcutAction(
    id: ShortcutActionIds.cycleMainFiles,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutCycleMainFiles',
    defaultBinding: _m(LogicalKeyboardKey.bracketRight),
    context: ShortcutContextRequirement.topicMode,
  ),
  ShortcutAction(
    id: ShortcutActionIds.addFile,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutAddFile',
    defaultBinding: _m(LogicalKeyboardKey.keyF, shift: true),
    context: ShortcutContextRequirement.topicMode,
  ),
  ShortcutAction(
    id: ShortcutActionIds.addTopic,
    category: ShortcutCategory.navigation,
    labelKey: 'shortcutAddTopic',
    defaultBinding: _m(LogicalKeyboardKey.keyN, shift: true),
  ),
  ShortcutAction(
    id: ShortcutActionIds.aiConsult,
    category: ShortcutCategory.ai,
    labelKey: 'aiConsult',
    defaultBinding: _m(LogicalKeyboardKey.digit1, shift: true),
    context: ShortcutContextRequirement.aiContext,
    aiTool: 'consult',
  ),
  ShortcutAction(
    id: ShortcutActionIds.aiSummarize,
    category: ShortcutCategory.ai,
    labelKey: 'aiSummarize',
    defaultBinding: _m(LogicalKeyboardKey.digit2, shift: true),
    context: ShortcutContextRequirement.aiContext,
    aiTool: 'summarize_to_doc',
  ),
  ShortcutAction(
    id: ShortcutActionIds.aiSmartList,
    category: ShortcutCategory.ai,
    labelKey: 'aiSmartList',
    defaultBinding: _m(LogicalKeyboardKey.digit3, shift: true),
    context: ShortcutContextRequirement.aiContext,
    aiTool: 'smart_list',
  ),
  ShortcutAction(
    id: ShortcutActionIds.aiImage,
    category: ShortcutCategory.ai,
    labelKey: 'aiImage',
    defaultBinding: _m(LogicalKeyboardKey.digit4, shift: true),
    context: ShortcutContextRequirement.aiContext,
    aiTool: 'create_image',
  ),
  ShortcutAction(
    id: ShortcutActionIds.aiGraph,
    category: ShortcutCategory.ai,
    labelKey: 'aiGraph',
    defaultBinding: _m(LogicalKeyboardKey.digit5, shift: true),
    context: ShortcutContextRequirement.aiContext,
    aiTool: 'create_graph',
  ),
  ShortcutAction(
    id: ShortcutActionIds.aiMoveFile,
    category: ShortcutCategory.ai,
    labelKey: 'aiMoveFile',
    defaultBinding: _m(LogicalKeyboardKey.digit6, shift: true),
    context: ShortcutContextRequirement.aiContext,
    aiTool: 'move_file_to_topic',
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
  ShortcutAction(
    id: ShortcutActionIds.insertText,
    category: ShortcutCategory.blocks,
    labelKey: 'addText',
    defaultBinding: _m(LogicalKeyboardKey.keyT, shift: true),
    context: ShortcutContextRequirement.insertBlock,
    blockType: 'text',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertHeader,
    category: ShortcutCategory.blocks,
    labelKey: 'addHeader',
    defaultBinding: _m(LogicalKeyboardKey.keyH, shift: true),
    context: ShortcutContextRequirement.insertBlock,
    blockType: 'header',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertSummary,
    category: ShortcutCategory.blocks,
    labelKey: 'addSummary',
    defaultBinding: _m(LogicalKeyboardKey.keyS, shift: true),
    context: ShortcutContextRequirement.insertBlock,
    blockType: 'summary',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertList,
    category: ShortcutCategory.blocks,
    labelKey: 'addList',
    defaultBinding: _m(LogicalKeyboardKey.keyL, shift: true),
    context: ShortcutContextRequirement.insertBlock,
    blockType: 'list',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertImage,
    category: ShortcutCategory.blocks,
    labelKey: 'addImage',
    defaultBinding: _m(LogicalKeyboardKey.keyI, shift: true),
    context: ShortcutContextRequirement.insertBlock,
    blockType: 'image',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertTable,
    category: ShortcutCategory.blocks,
    labelKey: 'addTable',
    defaultBinding: _m(LogicalKeyboardKey.keyU, shift: true),
    context: ShortcutContextRequirement.insertBlock,
    blockType: 'table',
  ),
  ShortcutAction(
    id: ShortcutActionIds.insertGraph,
    category: ShortcutCategory.blocks,
    labelKey: 'addGraph',
    defaultBinding: _m(LogicalKeyboardKey.keyG, shift: true),
    context: ShortcutContextRequirement.insertBlock,
    blockType: 'graph',
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
    ShortcutCategory.blocks => 'shortcutCategoryBlocks',
  };
}
