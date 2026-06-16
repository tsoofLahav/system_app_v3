import 'package:flutter/material.dart';

import 'app_language.dart';

/// UI strings and English DB-key → display label maps.
/// Database values stay in English; only on-screen labels are translated.
class AppStrings {
  const AppStrings._(
    this.language,
    this._ui,
    this._views,
    this._topicTypes,
    this._fileNames,
    this._fileTypes,
    this._layouts,
  );

  final AppLanguage language;

  bool get isRtl => language == AppLanguage.he;
  TextDirection get textDirection =>
      isRtl ? TextDirection.rtl : TextDirection.ltr;

  final Map<String, String> _ui;
  final Map<String, String> _views;
  final Map<String, String> _topicTypes;
  final Map<String, String> _fileNames;
  final Map<String, String> _fileTypes;
  final Map<String, String> _layouts;

  static AppStrings forLanguage(AppLanguage language) =>
      language == AppLanguage.he ? he : en;

  static const AppStrings en = AppStrings._(
    AppLanguage.en,
    _uiEn,
    _viewsEn,
    _topicTypesEn,
    _fileNamesEn,
    _fileTypesEn,
    _layoutsEn,
  );

  static const AppStrings he = AppStrings._(
    AppLanguage.he,
    _uiHe,
    _viewsHe,
    _topicTypesHe,
    _fileNamesHe,
    _fileTypesHe,
    _layoutsHe,
  );

  String operator [](String key) => _ui[key] ?? key;

  String viewLabel(String type) => _views[type] ?? type;
  String topicTypeLabel(String type) => _topicTypes[type] ?? type;
  String fileNameLabel(String englishName) =>
      _fileNames[englishName] ?? englishName;
  String fileTypeLabel(String type) => _fileTypes[type] ?? type;
  String layoutLabel(String id) => _layouts[id] ?? id;

  String displayTopicName(String? topicName) {
    if (topicName == null || topicName == 'main') return this['main'];
    return topicName;
  }

  String deleteTopicMessage(String name) =>
      this['deleteTopicBody'].replaceAll('{name}', name);

  String deleteFileMessage(String name) =>
      this['deleteFileBody'].replaceAll('{name}', name);

  String moreFiles(int count) =>
      this['moreFiles'].replaceAll('{count}', count.toString());

  String newSectionTitle(String viewLabel) =>
      this['newSectionTitle'].replaceAll('{view}', viewLabel);

  String noTasksInView(String viewLabel) =>
      this['noTasksInView'].replaceAll('{view}', viewLabel);

  String tableRows(int count) =>
      this['tableRows'].replaceAll('{count}', count.toString());

  String unsupportedBlock(String type) =>
      this['unsupportedBlock'].replaceAll('{type}', type);

  String unknownBlock(String type) =>
      this['unknownBlock'].replaceAll('{type}', type);

  String fileTypeOption(String name, String type) =>
      '${fileNameLabel(name)} (${fileTypeLabel(type)})';

  // --- UI keys (use strings['key']) ---

  static const _uiEn = {
    'main': 'Main',
    'views': 'Views',
    'projects': 'Projects',
    'processes': 'Processes',
    'areas': 'Areas',
    'newTopic': 'New topic',
    'edit': 'Edit',
    'delete': 'Delete',
    'retry': 'Retry',
    'selectTopic': 'Select a topic',
    'noFilesYet': 'No files yet. Add a file to get started.',
    'moreFiles': 'More files ({count})',
    'layout': 'Layout',
    'paneDrag': 'Reorder panes',
    'paneDragOn': 'Reorder panes — drag any pane',
    'reorderMode': 'Reorder mode',
    'showOnMain': 'Show on main canvas',
    'moveToMoreFiles': 'Move to more files',
    'addFile': 'Add file',
    'selectView': 'Select a view',
    'bySection': 'By section',
    'byTopic': 'By topic',
    'addSection': 'Add section',
    'newSectionTitle': 'New section — {view}',
    'sectionName': 'Section name',
    'cancel': 'Cancel',
    'add': 'Add',
    'noTasksInView':
        'No tasks in {view} yet.\nRight-click a task and choose Add to…',
    'uncategorized': 'Uncategorized',
    'noTasks': 'No tasks',
    'addTo': 'Add to…',
    'removeFromView': 'Remove from view',
    'editTopic': 'Edit topic',
    'name': 'Name',
    'type': 'Type',
    'emoji': 'Emoji',
    'color': 'Color',
    'filesToInclude': 'Files to include',
    'create': 'Create',
    'save': 'Save',
    'deleteTopicTitle': 'Delete topic?',
    'deleteTopicBody': 'Delete "{name}" and its files?',
    'deleteFileTitle': 'Delete file?',
    'deleteFileBody': 'Delete "{name}"?',
    'allFilesExist': 'All available files already exist for this topic.',
    'ok': 'OK',
    'addText': 'Add text',
    'addHeader': 'Add header',
    'addSummary': 'Add summary',
    'addChecklist': 'Add checklist',
    'addImage': 'Add image',
    'addTable': 'Add table',
    'addList': 'Add points',
    'addGraph': 'Add graph',
    'addTaskList': 'Add task list',
    'addRow': 'Add row',
    'addColumn': 'Add column',
    'addPoint': 'Add point',
    'deleteFile': 'Delete file',
    'newTaskHint': 'New task...',
    'dropHere': 'Drop here',
    'emptySlot': 'Empty slot',
    'writeHere': '...',
    'summaryHint': 'Summary...',
    'headerHint': 'Header',
    'addItem': 'Add item',
    'unsupportedBlock': 'Unsupported block: {type}',
    'noImage': 'No image',
    'measurement': 'Measurement',
    'tableRows': 'Table: {count} rows',
    'graphPlaceholder': 'Graph placeholder',
    'unknownBlock': 'Unknown block: {type}',
    'searchEmoji': 'Search emoji',
    'language': 'Language',
    'preferences': 'Preferences',
    'english': 'English',
    'hebrew': 'עברית',
    'ai': 'AI',
    'aiConsult': 'Consult',
    'aiSummarize': 'Summarize to doc',
    'aiSmartList': 'Add to list',
    'aiImage': 'Create image',
    'aiGraph': 'Create graph',
    'aiReview': 'Review',
    'aiNoContext': 'Select text or focus a paragraph, task, or list item.',
    'aiRunning': 'Running…',
    'aiDone': 'Done',
    'aiReviewSoon': 'Review and analyze — coming soon.',
  };

  static const _uiHe = {
    'main': 'ראשי',
    'views': 'תצוגות',
    'projects': 'פרויקטים',
    'processes': 'תהליכים',
    'areas': 'תחומים',
    'newTopic': 'נושא חדש',
    'edit': 'עריכה',
    'delete': 'מחיקה',
    'retry': 'נסה שוב',
    'selectTopic': 'בחר נושא',
    'noFilesYet': 'אין קבצים עדיין. הוסף קובץ כדי להתחיל.',
    'moreFiles': 'קבצים נוספים ({count})',
    'layout': 'פריסה',
    'paneDrag': 'סידור חלוניות',
    'paneDragOn': 'סידור חלוניות — גרור חלונית',
    'reorderMode': 'סידור קבצים',
    'showOnMain': 'הצג בקנבס הראשי',
    'moveToMoreFiles': 'העבר לקבצים נוספים',
    'addFile': 'הוסף קובץ',
    'selectView': 'בחר תצוגה',
    'bySection': 'לפי מדור',
    'byTopic': 'לפי נושא',
    'addSection': 'הוסף מדור',
    'newSectionTitle': 'מדור חדש — {view}',
    'sectionName': 'שם מדור',
    'cancel': 'ביטול',
    'add': 'הוסף',
    'noTasksInView':
        'אין משימות ב-{view} עדיין.\nלחץ לחיצה ימנית על משימה ובחר הוסף ל…',
    'uncategorized': 'ללא קטגוריה',
    'noTasks': 'אין משימות',
    'addTo': 'הוסף ל…',
    'removeFromView': 'הסר מהתצוגה',
    'editTopic': 'עריכת נושא',
    'name': 'שם',
    'type': 'סוג',
    'emoji': 'אמוג\'י',
    'color': 'צבע',
    'filesToInclude': 'קבצים לכלול',
    'create': 'צור',
    'save': 'שמור',
    'deleteTopicTitle': 'למחוק נושא?',
    'deleteTopicBody': 'למחוק את "{name}" ואת הקבצים שלו?',
    'deleteFileTitle': 'למחוק קובץ?',
    'deleteFileBody': 'למחוק את "{name}"?',
    'allFilesExist': 'כל הקבצים הזמינים כבר קיימים לנושא זה.',
    'ok': 'אישור',
    'addText': 'הוסף טקסט',
    'addHeader': 'הוסף כותרת',
    'addSummary': 'הוסף תקציר',
    'addChecklist': 'הוסף רשימת סימון',
    'addImage': 'הוסף תמונה',
    'addTable': 'הוסף טבלה',
    'addList': 'הוסף נקודות',
    'addGraph': 'הוסף גרף',
    'addTaskList': 'הוסף רשימת משימות',
    'addRow': 'הוסף שורה',
    'addColumn': 'הוסף עמודה',
    'addPoint': 'הוסף נקודה',
    'deleteFile': 'מחק קובץ',
    'newTaskHint': 'משימה חדשה...',
    'dropHere': 'שחרר כאן',
    'emptySlot': 'מקום ריק',
    'writeHere': '...',
    'summaryHint': 'תקציר...',
    'headerHint': 'כותרת',
    'addItem': 'הוסף פריט',
    'unsupportedBlock': 'בלוק לא נתמך: {type}',
    'noImage': 'אין תמונה',
    'measurement': 'מדידה',
    'tableRows': 'טבלה: {count} שורות',
    'graphPlaceholder': 'מציין מקום לגרף',
    'unknownBlock': 'בלוק לא ידוע: {type}',
    'searchEmoji': 'חפש אמוג\'י',
    'language': 'שפה',
    'preferences': 'העדפות',
    'english': 'English',
    'hebrew': 'עברית',
    'ai': 'AI',
    'aiConsult': 'ייעוץ',
    'aiSummarize': 'סיכום לתיעוד',
    'aiSmartList': 'הוסף לרשימה',
    'aiImage': 'צור תמונה',
    'aiGraph': 'צור גרף',
    'aiReview': 'סקירה',
    'aiNoContext': 'בחר טקסט או מקם את הסמן בפסקה, משימה או פריט רשימה.',
    'aiRunning': 'מריץ…',
    'aiDone': 'בוצע',
    'aiReviewSoon': 'סקירה וניתוח — בקרוב.',
  };

  static const _viewsEn = {
    'daily': 'Daily',
    'weekly': 'Weekly',
    'monthly': 'Monthly',
    'quarterly': 'Quarterly',
    'arrangements': 'Arrangements',
    'missions': 'Missions',
  };

  static const _viewsHe = {
    'daily': 'יומי',
    'weekly': 'שבועי',
    'monthly': 'חודשי',
    'quarterly': 'רבעוני',
    'arrangements': 'סידורים',
    'missions': 'משימות',
  };

  static const _topicTypesEn = {
    'project': 'Project',
    'process': 'Process',
    'area': 'Area',
  };

  static const _topicTypesHe = {
    'project': 'פרויקט',
    'process': 'תהליך',
    'area': 'תחום',
  };

  static const _fileNamesEn = {
    'Daily': 'Daily',
    'Text': 'Text',
    'Overview': 'Recap',
    'Recap': 'Recap',
    'Plan': 'Plan',
    'Tasks': 'Tasks',
    'Documentation': 'Documentation',
    'Data': 'Data',
    'Protocol': 'Protocol',
  };

  static const _fileNamesHe = {
    'Daily': 'יומי',
    'Text': 'טקסט',
    'Overview': 'סיכום',
    'Recap': 'סיכום',
    'Plan': 'תכנית',
    'Tasks': 'משימות',
    'Documentation': 'תיעוד',
    'Data': 'נתונים',
    'Protocol': 'פרוטוקול',
  };

  static const _fileTypesEn = {
    'main': 'main',
    'text': 'text',
    'overview': 'recap',
    'plan': 'plan',
    'tasks': 'tasks',
    'doc': 'doc',
    'data': 'data',
    'protocol': 'protocol',
  };

  static const _fileTypesHe = {
    'main': 'ראשי',
    'text': 'טקסט',
    'overview': 'סיכום',
    'plan': 'תכנית',
    'tasks': 'משימות',
    'doc': 'תיעוד',
    'data': 'נתונים',
    'protocol': 'פרוטוקול',
  };

  static const _layoutsEn = {
    'single': 'Single file',
    'split': 'Split half',
    'hero_left': 'Large left',
    'hero_right': 'Large right',
    'grid': 'Grid',
    'row': 'Row',
  };

  static const _layoutsHe = {
    'single': 'קובץ יחיד',
    'split': 'שני חצאים',
    'hero_left': 'גדול משמאל',
    'hero_right': 'גדול מימין',
    'grid': 'רשת',
    'row': 'שורה',
  };
}
