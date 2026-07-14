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
    this._automationNames,
    this._automationDescriptions,
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
  final Map<String, String> _automationNames;
  final Map<String, String> _automationDescriptions;

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
    _automationNamesEn,
    _automationDescriptionsEn,
  );

  static const AppStrings he = AppStrings._(
    AppLanguage.he,
    _uiHe,
    _viewsHe,
    _topicTypesHe,
    _fileNamesHe,
    _fileTypesHe,
    _layoutsHe,
    _automationNamesHe,
    _automationDescriptionsHe,
  );

  String operator [](String key) => _ui[key] ?? key;

  String viewLabel(String type) => _views[type] ?? type;
  String topicTypeLabel(String type) => _topicTypes[type] ?? type;
  String fileNameLabel(String englishName) =>
      _fileNames[englishName] ?? englishName;
  String fileTypeLabel(String type) => _fileTypes[type] ?? type;
  String layoutLabel(String id) => _layouts[id] ?? id;

  /// Built-in automation name by English definition [key] (from backend).
  String automationNameLabel(String key, {String? fallback}) =>
      _automationNames[key] ?? fallback ?? key;

  /// Built-in automation description by English definition [key].
  String automationDescriptionLabel(String key, {String? fallback}) =>
      _automationDescriptions[key] ?? fallback ?? '';

  String displayTopicName(String? topicName) {
    if (topicName == 'automations') return _views['automations'] ?? topicName!;
    if (topicName == null || topicName == 'main') return this['main'];
    return topicName;
  }

  String deleteTopicMessage(String name) =>
      this['deleteTopicBody'].replaceAll('{name}', name);

  String deleteFileMessage(String name) =>
      this['deleteFileBody'].replaceAll('{name}', name);

  String archiveDeleteBody(int count) =>
      this['archiveDeleteBody'].replaceAll('{count}', '$count');

  String moreFiles(int count) =>
      this['moreFiles'].replaceAll('{count}', count.toString());

  String arrangePosition(int current, int total) => this['arrangePosition']
      .replaceAll('{current}', current.toString())
      .replaceAll('{total}', total.toString());

  String bringFileFromTopicNamed(String topic) =>
      this['bringFileFromTopicNamed'].replaceAll('{topic}', topic);

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

  String processUpdateProgress(int current, int total) =>
      this['processUpdateProgress']
          .replaceAll('{current}', '$current')
          .replaceAll('{total}', '$total');

  String automationScopeLabel(String scope) =>
      this['automationScope'].replaceAll('{scope}', scope);

  String automationScopeForDefinition(Map<String, dynamic> scopeFixed) {
    final kind = scopeFixed['kind'] as String? ?? 'all';
    final scope = switch (kind) {
      'topic_type' => topicTypeLabel(
        scopeFixed['topic_type'] as String? ?? 'process',
      ),
      'topic' => displayTopicName(scopeFixed['topic_name'] as String?),
      _ => this['allTopics'],
    };
    return automationScopeLabel(scope);
  }

  String taskResetAckTitle(String viewLabel) =>
      this['taskResetAckTitle'].replaceAll('{view}', viewLabel);

  String taskResetAckBody({
    required int resetCount,
    required int missedCount,
  }) => this['taskResetAckBody']
      .replaceAll('{reset}', '$resetCount')
      .replaceAll('{missed}', '$missedCount');

  String taskResetScheduleSummary(int enabledCount) =>
      this['taskResetScheduleSummary'].replaceAll('{count}', '$enabledCount');

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
    'arrangeFiles': 'Arrange files',
    'arrangeDone': 'Done',
    'arrangeTapMainHint': 'Tap a file to move it first',
    'arrangeTapAdditionalHint': 'Tap to add centered file to main',
    'moveFileEarlier': 'Move file earlier',
    'moveFileLater': 'Move file later',
    'arrangePosition': '{current} / {total}',
    'paneDrag': 'Reorder panes',
    'paneDragOn': 'Reorder panes — drag any pane',
    'reorderMode': 'Reorder mode',
    'showOnMain': 'Show on main canvas',
    'moveToMoreFiles': 'Move to more files',
    'moveFileToTopic': 'Move file to topic',
    'addFile': 'Add file',
    'bringFile': 'Bring file',
    'bringFileSearchHint': 'topic file name',
    'bringFileEmpty': 'No matching files from other topics.',
    'bringFileFromTopic': 'Tap to bring',
    'bringFileFromTopicNamed': 'From {topic}',
    'bringFileDismiss': 'Dismiss brought file',
    'bringFilePreviewLoading': 'Loading preview…',
    'bringFilePreviewEmpty': 'No content yet',
    'selectView': 'Select a view',
    'bySection': 'By section',
    'byTopic': 'By topic',
    'addSection': 'Add section',
    'sections': 'Sections',
    'assignToTopic': 'Assign to topic',
    'newSectionTitle': 'New section — {view}',
    'sectionName': 'Section name',
    'markSectionImportant': 'Mark section as important',
    'unmarkSectionImportant': 'Remove important mark',
    'cancel': 'Cancel',
    'add': 'Add',
    'noTasksInView':
        'No tasks in {view} yet.\nRight-click a task and choose Add to…',
    'uncategorized': 'Uncategorized',
    'noTopic': 'No topic',
    'noTasks': 'No tasks',
    'addTo': 'Add to…',
    'addToViewLabel': 'Add to {view}',
    'removeFromView': 'Remove from view',
    'copyAllTasks': 'Copy all tasks',
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
    'addBlock': 'Add block',
    'addPart': 'Add part',
    'addNewPart': 'New part…',
    'addExistingPart': 'Existing part…',
    'partName': 'Part name',
    'partNameHint': 'e.g. Auth flow',
    'noPartsAvailable': 'No other parts to add',
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
    'addRowAbove': 'Add row above',
    'addRowBelow': 'Add row below',
    'addColumnBefore': 'Add column before',
    'addColumnAfter': 'Add column after',
    'deleteBlock': 'Delete block',
    'bulletList': 'Bullet list',
    'numberedList': 'Numbered list',
    'cut': 'Cut',
    'copy': 'Copy',
    'paste': 'Paste',
    'bold': 'Bold',
    'italic': 'Italic',
    'underline': 'Underline',
    'textSizeUp': 'Larger text',
    'textSizeDown': 'Smaller text',
    'graphBar': 'Bar chart',
    'graphLine': 'Line chart',
    'graphPie': 'Pie chart',
    'graphAddVariable': 'Add variable',
    'graphRemoveVariable': 'Remove variable',
    'graphChangeColors': 'Change colors',
    'graphVariable': 'Variable',
    'editGraph': 'Edit graph data',
    'replaceImage': 'Replace image',
    'resetImageWidth': 'Reset image width',
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
    'boardAddImage': 'Add image',
    'boardEmptyHint': 'Add images and drag them anywhere on the board',
    'boardDeleteImage': 'Remove',
    'boardCrop': 'Crop image',
    'boardAiPromptTitle': 'Describe the image',
    'boardAiPromptHint': 'Write what you want the AI to generate…',
    'boardCopyImage': 'Copy image',
    'boardPasteImage': 'Paste image',
    'boardBackground': 'Background',
    'boardBackgroundCustom': 'Custom color…',
    'boardBgWhite': 'White',
    'boardBgLightGray': 'Light gray',
    'boardBgSky': 'Sky',
    'boardBgCream': 'Cream',
    'measurement': 'Measurement',
    'tableRows': 'Table: {count} rows',
    'graphPlaceholder': 'Enter values below',
    'graphDuplicateDay': 'Only one grade per day is allowed',
    'unknownBlock': 'Unknown block: {type}',
    'searchEmoji': 'Search emoji',
    'chooseEmoji': 'Choose an emoji',
    'chooseColor': 'Choose color',
    'moreColors': 'More colors',
    'choose': 'Choose',
    'language': 'Language',
    'preferences': 'Preferences',
    'english': 'English',
    'hebrew': 'עברית',
    'ai': 'AI',
    'aiConsult': 'Consult',
    'aiSummarize': 'Add to doc',
    'aiSmartList': 'Add to list',
    'aiImage': 'Create image',
    'aiGraph': 'Create graph',
    'aiReview': 'Review',
    'aiNoContext': 'Select text or place the caret on a line, task, or list item.',
    'aiRunning': 'Running…',
    'aiDone': 'Done',
    'aiReviewSoon': 'Review and analyze — coming soon.',
    'archive': 'Archive',
    'automations': 'Automations',
    'dailyRotation': 'Daily rotation',
    'updateAllProcesses': 'Update all processes',
    'enabled': 'Enabled',
    'disabled': 'Disabled',
    'schedule': 'Schedule',
    'frequency': 'Frequency',
    'mainAutomations': 'Main automations',
    'noAutomations': 'No main automations yet.',
    'editTime': 'Edit time',
    'runNow': 'Run now',
    'automationRan': 'Automation started.',
    'automationUncheckToRun': 'Uncheck this task to run the automation.',
    'automationNotTriggerTask': 'This is not the automation trigger task.',
    'automationCompleted': 'Automation finished.',
    'automationRunning': 'Running…',
    'automationRunFailed': 'Automation failed.',
    'summaryTasksReadOnly': 'Summary tasks are not editable, only markable.',
    'onceADay': 'Once a day',
    'onceAWeek': 'Once a week',
    'onceAMonth': 'Once a month',
    'time': 'Time',
    'chooseDay': 'Choose day',
    'dayOfWeek': 'Day of week',
    'placementInMonth': 'Placement in month',
    'first': 'First',
    'second': 'Second',
    'third': 'Third',
    'last': 'Last',
    'monday': 'Monday',
    'tuesday': 'Tuesday',
    'wednesday': 'Wednesday',
    'thursday': 'Thursday',
    'friday': 'Friday',
    'saturday': 'Saturday',
    'sunday': 'Sunday',
    'automationTimeHelp': 'HH:MM',
    'triggerByTime': 'By time',
    'triggerByChanges': 'By changes',
    'triggerByTask': 'By task',
    'automationScope': 'Scope: {scope}',
    'allTopics': 'All topics',
    'automationTrigger': 'Activation',
    'automationTriggerView': 'View',
    'automationTriggerSection': 'Section',
    'automationTriggerSectionHelp':
        'Create a section in this view if none exist.',
    'automationTaskPlacement': 'Task placement',
    'automationResetTargetView': 'View to reset',
    'automationResetGroupedHelp':
        'Manage reset schedules per task view inside this automation.',
    'automationResetQuarterly': 'Quarterly',
    'automationResetQuarterlyInterval': 'Quarterly jump',
    'automationResetEvery3Months': 'Every 3 months',
    'automationResetEvery4Months': 'Every 4 months',
    'automationResetSyncMonthly': 'Sync with monthly timing',
    'automationResetSyncedMonthlyTime':
        'Uses the monthly placement, day, and time.',
    'taskResetScheduleSummary': '{count} view schedules configured',
    'createSection': 'Create section',
    'aiProposals': 'AI suggestions',
    'approve': 'Approve',
    'reject': 'Reject',
    'pendingSuggestions': 'Pending suggestions',
    'processUpdateReview': 'Review process update',
    'reviewPlan': 'Plan',
    'reviewTasks': 'Tasks',
    'planReviewComplete': 'Plan review complete',
    'continueToTasks': 'Continue to tasks',
    'applySuggestion': 'Apply',
    'finishReview': 'Finish refresh',
    'finishUpdate': 'Finish update',
    'previousProcess': 'Previous process',
    'nextProcess': 'Next process',
    'processUpdateProgress': 'Process {current} of {total}',
    'processRefreshSkipped': 'Automatic process update skipped',
    'processDocumentationInputLabel': 'Daily input',
    'processDocumentationInputHint': 'What happened in this process today?',
    'processDocumentationGradeLabel': 'Progress grade (1–10)',
    'processDocumentationInputRequired':
        'Enter daily input and choose a grade before saving.',
    'processDocumentationMissingDoc':
        'This process has no documentation file. Skip to continue.',
    'processDocumentationDuplicateGrade':
        'A grade already exists for this date. Change it in the graph.',
    'skip': 'Skip',
    'dismiss': 'Dismiss',
    'unchanged': 'Unchanged',
    'suggestedChange': 'Suggested change',
    'automationAbandonTitle': 'Discard suggested changes?',
    'automationAbandonBody':
        'Marking this task done will discard all pending updates from this automation run.',
    'automationAbandonConfirm': 'Discard changes',
    'archiveSearchHint': 'Search archived files…',
    'archiveNoFiles': 'No archived files in this topic.',
    'archiveNoSearchResults': 'No archived files match your search.',
    'archiveSelectFile': 'Select a file to preview',
    'archiveDeleteSelect': 'Select archived files to delete',
    'archiveDeleteConfirm': 'Delete selected files',
    'archiveDeleteTitle': 'Delete archived files?',
    'archiveDeleteBody': 'Delete {count} archived files permanently?',
    'archiveDeleteDone': 'Cancel selection',
    'taskResetAckTitle': '{view} tasks reset',
    'taskResetAckBody':
        '{reset} completed tasks were unchecked. {missed} tasks were already unchecked and were recorded as missed.',
    'taskResetMissedTitle': 'Missed tasks',
    'taskResetReportArchived': 'A detailed report was saved in Archive.',
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
    'arrangeFiles': 'סידור קבצים',
    'arrangeDone': 'סיום',
    'arrangeTapMainHint': 'הקש על קובץ כדי להעביר אותו לראשון',
    'arrangeTapAdditionalHint': 'הקש כדי להוסיף את הקובץ במרכז לראשי',
    'moveFileEarlier': 'הזז קובץ קדימה',
    'moveFileLater': 'הזז קובץ אחורה',
    'arrangePosition': '{current} / {total}',
    'paneDrag': 'סידור חלוניות',
    'paneDragOn': 'סידור חלוניות — גרור חלונית',
    'reorderMode': 'סידור קבצים',
    'showOnMain': 'הצג בקנבס הראשי',
    'moveToMoreFiles': 'העבר לקבצים נוספים',
    'moveFileToTopic': 'העבר קובץ לנושא',
    'addFile': 'הוסף קובץ',
    'bringFile': 'הבא קובץ',
    'bringFileSearchHint': 'נושא שם קובץ',
    'bringFileEmpty': 'לא נמצאו קבצים תואמים מנושאים אחרים.',
    'bringFileFromTopic': 'לחץ להבאה',
    'bringFileFromTopicNamed': 'מ{topic}',
    'bringFileDismiss': 'הסר קובץ מובא',
    'bringFilePreviewLoading': 'טוען תצוגה מקדימה…',
    'bringFilePreviewEmpty': 'אין עדיין תוכן לתצוגה',
    'selectView': 'בחר תצוגה',
    'bySection': 'לפי מדור',
    'byTopic': 'לפי נושא',
    'addSection': 'הוסף מדור',
    'sections': 'מדורים',
    'assignToTopic': 'שייך לנושא',
    'newSectionTitle': 'מדור חדש — {view}',
    'sectionName': 'שם מדור',
    'markSectionImportant': 'סמן מדור כחשוב',
    'unmarkSectionImportant': 'הסר סימון חשוב',
    'cancel': 'ביטול',
    'add': 'הוסף',
    'noTasksInView':
        'אין משימות ב-{view} עדיין.\nלחץ לחיצה ימנית על משימה ובחר הוסף ל…',
    'uncategorized': 'ללא קטגוריה',
    'noTopic': 'ללא נושא',
    'noTasks': 'אין משימות',
    'addTo': 'הוסף ל…',
    'addToViewLabel': 'הוסף ל{view}',
    'removeFromView': 'הסר מהתצוגה',
    'copyAllTasks': 'העתק את כל המשימות',
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
    'addBlock': 'הוסף בלוק',
    'addPart': 'הוסף חלק',
    'addNewPart': 'חלק חדש…',
    'addExistingPart': 'חלק קיים…',
    'partName': 'שם החלק',
    'partNameHint': 'לדוגמה: זרימת הרשמה',
    'noPartsAvailable': 'אין חלקים נוספים להוספה',
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
    'addRowAbove': 'הוסף שורה מעל',
    'addRowBelow': 'הוסף שורה מתחת',
    'addColumnBefore': 'הוסף עמודה לפני',
    'addColumnAfter': 'הוסף עמודה אחרי',
    'deleteBlock': 'מחק בלוק',
    'bulletList': 'רשימת נקודות',
    'numberedList': 'רשימה ממוספרת',
    'cut': 'גזור',
    'copy': 'העתק',
    'paste': 'הדבק',
    'bold': 'מודגש',
    'italic': 'נטוי',
    'underline': 'קו תחתון',
    'textSizeUp': 'טקסט גדול יותר',
    'textSizeDown': 'טקסט קטן יותר',
    'graphBar': 'גרף עמודות',
    'graphLine': 'גרף קו',
    'graphPie': 'גרף עוגה',
    'graphAddVariable': 'הוסף משתנה',
    'graphRemoveVariable': 'הסר משתנה',
    'graphChangeColors': 'שנה צבעים',
    'graphVariable': 'משתנה',
    'editGraph': 'ערוך נתוני גרף',
    'replaceImage': 'החלף תמונה',
    'resetImageWidth': 'אפס רוחב תמונה',
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
    'boardAddImage': 'הוסף תמונה',
    'boardEmptyHint': 'הוסף תמונות וגרור אותן לכל מקום על הלוח',
    'boardDeleteImage': 'הסר',
    'boardCrop': 'חתוך תמונה',
    'boardAiPromptTitle': 'תאר את התמונה',
    'boardAiPromptHint': 'כתוב מה תרצה שה-AI ייצור…',
    'boardCopyImage': 'העתק תמונה',
    'boardPasteImage': 'הדבק תמונה',
    'boardBackground': 'רקע',
    'boardBackgroundCustom': 'צבע מותאם…',
    'boardBgWhite': 'לבן',
    'boardBgLightGray': 'אפור בהיר',
    'boardBgSky': 'תכלת',
    'boardBgCream': 'קרם',
    'measurement': 'מדידה',
    'tableRows': 'טבלה: {count} שורות',
    'graphPlaceholder': 'הזן ערכים למטה',
    'graphDuplicateDay': 'מותר ציון אחד בלבד ליום',
    'unknownBlock': 'בלוק לא ידוע: {type}',
    'searchEmoji': 'חפש אמוג\'י',
    'chooseEmoji': 'בחר אמוג\'י',
    'chooseColor': 'בחר צבע',
    'moreColors': 'עוד צבעים',
    'choose': 'בחר',
    'language': 'שפה',
    'preferences': 'העדפות',
    'english': 'English',
    'hebrew': 'עברית',
    'ai': 'AI',
    'aiConsult': 'ייעוץ',
    'aiSummarize': 'הוסף לתיעוד',
    'aiSmartList': 'הוסף לרשימה',
    'aiImage': 'צור תמונה',
    'aiGraph': 'צור גרף',
    'aiReview': 'סקירה',
    'aiNoContext': 'בחר טקסט או מקם את הסמן בשורה, משימה או פריט רשימה.',
    'aiRunning': 'מריץ…',
    'aiDone': 'בוצע',
    'aiReviewSoon': 'סקירה וניתוח — בקרוב.',
    'archive': 'ארכיון',
    'automations': 'אוטומציות',
    'dailyRotation': 'החלפת מסמך יומי',
    'updateAllProcesses': 'עדכון כל התהליכים',
    'enabled': 'פעיל',
    'disabled': 'כבוי',
    'schedule': 'תזמון',
    'frequency': 'תדירות',
    'mainAutomations': 'אוטומציות ראשיות',
    'noAutomations': 'אין עדיין אוטומציות ראשיות.',
    'editTime': 'ערוך זמן',
    'runNow': 'הרץ עכשיו',
    'automationRan': 'האוטומציה הופעלה.',
    'automationUncheckToRun': 'בטל סימון של משימה זו כדי להפעיל את האוטומציה.',
    'automationNotTriggerTask': 'זו לא משימת ההפעלה של האוטומציה.',
    'automationCompleted': 'האוטומציה הסתיימה.',
    'automationRunning': 'רצה…',
    'automationRunFailed': 'האוטומציה נכשלה.',
    'summaryTasksReadOnly': 'משימות בסיכום אינן ניתנות לעריכה, רק לסימון.',
    'onceADay': 'פעם ביום',
    'onceAWeek': 'פעם בשבוע',
    'onceAMonth': 'פעם בחודש',
    'time': 'שעה',
    'chooseDay': 'בחר יום',
    'dayOfWeek': 'יום בשבוע',
    'placementInMonth': 'מיקום בחודש',
    'first': 'ראשון',
    'second': 'שני',
    'third': 'שלישי',
    'last': 'אחרון',
    'monday': 'שני',
    'tuesday': 'שלישי',
    'wednesday': 'רביעי',
    'thursday': 'חמישי',
    'friday': 'שישי',
    'saturday': 'שבת',
    'sunday': 'ראשון',
    'automationTimeHelp': 'HH:MM',
    'triggerByTime': 'לפי זמן',
    'triggerByChanges': 'לפי שינויים',
    'triggerByTask': 'לפי משימה',
    'automationScope': 'היקף: {scope}',
    'allTopics': 'כל הנושאים',
    'automationTrigger': 'הפעלה',
    'automationTriggerView': 'תצוגה',
    'automationTriggerSection': 'מדור',
    'automationTriggerSectionHelp': 'צור מדור בתצוגה זו אם אין.',
    'automationTaskPlacement': 'מיקום המשימה',
    'automationResetTargetView': 'תצוגה לאיפוס',
    'automationResetGroupedHelp':
        'נהל תזמוני איפוס לכל תצוגת משימות בתוך האוטומציה הזו.',
    'automationResetQuarterly': 'רבעוני',
    'automationResetQuarterlyInterval': 'קפיצה רבעונית',
    'automationResetEvery3Months': 'כל 3 חודשים',
    'automationResetEvery4Months': 'כל 4 חודשים',
    'automationResetSyncMonthly': 'סנכרן עם התזמון החודשי',
    'automationResetSyncedMonthlyTime':
        'משתמש במיקום, ביום ובשעה של התזמון החודשי.',
    'taskResetScheduleSummary': '{count} תזמוני תצוגות מוגדרים',
    'createSection': 'צור מדור',
    'aiProposals': 'הצעות AI',
    'approve': 'אשר',
    'reject': 'דחה',
    'pendingSuggestions': 'הצעות ממתינות',
    'processUpdateReview': 'סקירת עדכון תהליך',
    'reviewPlan': 'תכנית',
    'reviewTasks': 'משימות',
    'planReviewComplete': 'סקירת התכנית הושלמה',
    'continueToTasks': 'המשך למשימות',
    'applySuggestion': 'החל',
    'finishReview': 'סיים רענון',
    'finishUpdate': 'סיים עדכון',
    'previousProcess': 'תהליך קודם',
    'nextProcess': 'תהליך הבא',
    'processUpdateProgress': 'תהליך {current} מתוך {total}',
    'processRefreshSkipped': 'עדכון תהליך אוטומטי דולג',
    'processDocumentationInputLabel': 'קלט יומי',
    'processDocumentationInputHint': 'מה קרה בתהליך הזה היום?',
    'processDocumentationGradeLabel': 'ציון התקדמות (1–10)',
    'processDocumentationInputRequired':
        'יש להזין קלט יומי ולבחור ציון לפני השמירה.',
    'processDocumentationMissingDoc':
        'לתהליך זה אין קובץ תיעוד. דלג כדי להמשיך.',
    'processDocumentationDuplicateGrade':
        'כבר קיים ציון לתאריך הזה. עדכן אותו בגרף.',
    'skip': 'דלג',
    'dismiss': 'סגור',
    'unchanged': 'ללא שינוי',
    'suggestedChange': 'שינוי מוצע',
    'automationAbandonTitle': 'לבטל את השינויים שהוצעו?',
    'automationAbandonBody':
        'סימון המשימה כבוצעה יבטל את כל העדכונים הממתינים מהרצת האוטומציה.',
    'automationAbandonConfirm': 'בטל שינויים',
    'archiveSearchHint': 'חיפוש קבצים בארכיון…',
    'archiveNoFiles': 'אין קבצים בארכיון בנושא זה.',
    'archiveNoSearchResults': 'לא נמצאו קבצים בארכיון התואמים לחיפוש.',
    'archiveSelectFile': 'בחר קובץ לתצוגה מקדימה',
    'archiveDeleteSelect': 'בחר קבצים בארכיון למחיקה',
    'archiveDeleteConfirm': 'מחק קבצים שנבחרו',
    'archiveDeleteTitle': 'למחוק קבצים מהארכיון?',
    'archiveDeleteBody': 'למחוק {count} קבצים מהארכיון לצמיתות?',
    'archiveDeleteDone': 'ביטול בחירה',
    'taskResetAckTitle': 'משימות {view} אופסו',
    'taskResetAckBody':
        '{reset} משימות שהושלמו סומנו שוב כפעילות. {missed} משימות כבר היו פעילות ונרשמו כמשימות שפוספסו.',
    'taskResetMissedTitle': 'משימות שפוספסו',
    'taskResetReportArchived': 'דוח מפורט נשמר בארכיון.',
  };

  static const _viewsEn = {
    'daily': 'Daily',
    'weekly': 'Weekly',
    'monthly': 'Monthly',
    'quarterly': 'Quarterly',
    'arrangements': 'Arrangements',
    'missions': 'Missions',
    'automations': 'Automations',
  };

  static const _viewsHe = {
    'daily': 'יומי',
    'weekly': 'שבועי',
    'monthly': 'חודשי',
    'quarterly': 'רבעוני',
    'arrangements': 'סידורים',
    'missions': 'משימות',
    'automations': 'אוטומציות',
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

  static const _automationNamesEn = {
    'daily_rotation': 'Daily rotation',
    'process_refresh': 'Update all processes',
    'process_recap_update': 'Update process recap',
    'project_summary_update': 'Update project summary',
    'view_task_reset': 'Reset view tasks',
    'process_documentation_input': 'Process documentation input',
  };

  static const _automationNamesHe = {
    'daily_rotation': 'החלפת מסמך יומי',
    'process_refresh': 'עדכון כל התהליכים',
    'process_recap_update': 'עדכון סיכום תהליך',
    'project_summary_update': 'עדכון סיכום פרויקט',
    'view_task_reset': 'איפוס משימות בתצוגה',
    'process_documentation_input': 'קלט תיעוד תהליכים',
  };

  static const _automationDescriptionsEn = {
    'daily_rotation':
        'Archive the current main Daily file and create a fresh one.',
    'process_refresh':
        'For each process topic, run a smart update on plan, doc, and tasks files.',
    'process_recap_update':
        'When plan, documentation, or tasks change, regenerate the process '
        'recap with an AI summary and recent update notes.',
    'project_summary_update':
        'When project plan, execution, documentation, or tasks change, regenerate the project summary from its current structure.',
    'view_task_reset':
        'Manage daily, weekly, monthly, and quarterly schedules that uncheck completed tasks and record active tasks as missed.',
    'process_documentation_input':
        'For each process topic, collect daily documentation text and a progress grade on schedule or via a trigger task, then write them into the doc table and graph.',
  };

  static const _automationDescriptionsHe = {
    'daily_rotation': 'ארכב את קובץ היומי הראשי הנוכחי וצור אחד חדש.',
    'process_refresh':
        'עבור כל תהליך, הרץ עדכון חכם על קבצי התוכנית, התיעוד והמשימות.',
    'process_recap_update':
        'כשהתוכנית, התיעוד או המשימות משתנים, צור מחדש את סיכום התהליך '
        'עם סיכום AI והערות עדכון אחרונות.',
    'project_summary_update':
        'כשהתוכנית, הביצוע, התיעוד או המשימות של פרויקט משתנים, צור מחדש את סיכום הפרויקט לפי המבנה הנוכחי.',
    'view_task_reset':
        'נהל תזמונים יומיים, שבועיים, חודשיים ורבעוניים שמבטלים סימון משימות שהושלמו ורושמים משימות פעילות כמשימות שפוספסו.',
    'process_documentation_input':
        'עבור כל תהליך, אסוף קלט תיעוד יומי וציון התקדמות לפי תזמון או משימת טריגר, וכתוב אותם לטבלת התיעוד ולגרף.',
  };

  static const _fileNamesEn = {
    'Daily': 'Daily',
    'Text': 'Text',
    'Overview': 'Recap',
    'Recap': 'Recap',
    'Summary': 'Summary',
    'Plan': 'Plan',
    'Tasks': 'Tasks',
    'Documentation': 'Documentation',
    'Board': 'Board',
    'Execution': 'Execution',
    'Data': 'Data',
    'Protocol': 'Protocol',
  };

  static const _fileNamesHe = {
    'Daily': 'יומי',
    'Text': 'טקסט',
    'Overview': 'סיכום',
    'Recap': 'סיכום',
    'Summary': 'סיכום',
    'Plan': 'תכנית',
    'Tasks': 'משימות',
    'Documentation': 'תיעוד',
    'Board': 'לוח',
    'Execution': 'ביצוע',
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
    'board': 'board',
    'execution': 'execution',
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
    'board': 'לוח',
    'execution': 'ביצוע',
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
