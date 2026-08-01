import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../areas/files/model/document_codec.dart';
import '../areas/files/model/document_model.dart';
import './l10n/app_language.dart';
import './l10n/app_strings.dart';
import '../areas/automations/automation.dart';
import '../areas/files/data/app_file.dart';
import '../areas/objects/data/app_view.dart';
import './models/archive_index.dart';
import './models/block.dart';
import '../areas/objects/data/object_embed.dart';
import './models/tag.dart';
import '../areas/objects/data/task.dart';
import '../areas/files/data/topic.dart';
import '../areas/automations/automation_service.dart';
import '../areas/production_agent/agent_service.dart';
import './services/api_service.dart';
import './services/bootstrap_service.dart';
import './services/image_service.dart';
import '../areas/files/data/file_service.dart';
import '../areas/objects/data/object_service.dart';
import './services/tag_service.dart';
import '../areas/objects/data/task_service.dart';
import '../areas/files/data/topic_service.dart';
import '../areas/objects/data/view_service.dart';
import '../areas/ux/layout/topic_file_slots.dart';
import '../areas/ux/shortcuts/shortcut_bindings_store.dart';

class TopicDetail {
  const TopicDetail({required this.topic, required this.files});

  final Topic topic;
  final List<AppFile> files;
}

enum ViewDisplayMode { bySection, byTopic, flat }

class AppState extends ChangeNotifier {
  AppState() : _api = ApiService() {
    _bootstrap = BootstrapService(_api);
    _topics = TopicService(_api);
    _files = FileService(_api);
    _objects = ObjectService(_api);
    _views = ViewService(_api);
    _tasks = TaskService(_api);
    _tags = TagService(_api);
    _agent = AgentService(_api);
    _automations = AutomationService(_api);
    _images = ImageService(_api);
  }

  final ApiService _api;
  late final BootstrapService _bootstrap;
  late final TopicService _topics;
  late final FileService _files;
  late final ObjectService _objects;
  late final ViewService _views;
  late final TaskService _tasks;
  late final TagService _tags;
  late final AgentService _agent;
  late final AutomationService _automations;
  late final ImageService _images;

  AppLanguage _language = AppLanguage.en;
  bool loading = false;
  String? error;
  bool appReady = false;
  int? workspaceId;

  List<Topic> allTopics = [];
  List<AppTag> allTags = [];
  List<AppView> userViews = [];
  List<Automation> automations = [];
  Topic? selectedTopic;
  TopicDetail? selectedDetail;
  bool topicDetailStale = false;

  bool isViewMode = false;
  bool viewPaneReady = false;
  String? selectedViewType;
  AppView? selectedView;
  List<ViewMembership> viewMemberships = [];
  ViewDisplayMode viewDisplayMode = ViewDisplayMode.bySection;

  bool isArchiveMode = false;
  Topic? selectedArchiveTopic;
  ArchiveIndex archiveIndex = ArchiveIndex.empty;

  final Map<int, List<ObjectEmbed>> embedsByFileId = {};
  int? editingFileId;
  String? _automationNotice;
  bool aiRunning = false;
  bool archiveDeleteMode = false;
  final Set<int> archiveDeleteSelection = {};
  Map<String, dynamic>? pendingAgentReview;

  void toggleArchiveDeleteMode() {
    archiveDeleteMode = !archiveDeleteMode;
    if (!archiveDeleteMode) archiveDeleteSelection.clear();
    notifyListeners();
  }

  Future<void> deleteSelectedArchiveFiles() async {
    archiveDeleteSelection.clear();
    archiveDeleteMode = false;
    notifyListeners();
  }

  Future<void> setShortcutBinding(String actionId, dynamic binding) async {}
  Future<void> resetShortcut(String actionId) async {}
  Future<void> resetAllShortcuts() async {}

  final ChangeNotifier shortcutRebuildListenable = ChangeNotifier();
  final ShortcutBindingsStore shortcutBindings = ShortcutBindingsStore();

  AppStrings get strings => AppStrings.forLanguage(_language);
  AppLanguage get language => _language;
  TextDirection get textDirection => strings.textDirection;
  bool get isRtl => strings.isRtl;

  List<Topic> get activeTopics => allTopics.where((t) => !t.isArchived).toList();
  List<Topic> get projects => _topicsForTag('project');
  List<Topic> get processes => _topicsForTag('process');
  List<Topic> get areas => _topicsForTag('area');
  List<Topic> get others => allTopics
      .where((t) => t.primaryTag == null || t.primaryTag == 'other')
      .toList();

  List<Topic> _topicsForTag(String tag) =>
      allTopics.where((t) => t.primaryTag == tag).toList();

  Future<void> initialize() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadLanguage();
      await _bootstrap.bootstrap();
      final status = await _bootstrap.status();
      workspaceId = status['workspace_id'] as int?;
      await _reloadAll();
      appReady = true;
      await loadAutomations();
      if (selectedTopic == null && allTopics.isNotEmpty) {
        final home = allTopics.where((t) => t.isMain).firstOrNull ?? allTopics.first;
        await selectTopic(home);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadAll() async {
    allTopics = await _topics.listTopics(workspaceId: workspaceId);
    allTags = await _tags.listTags(workspaceId: workspaceId);
    userViews = await _views.listViews(workspaceId: workspaceId);
    await loadArchive();
  }

  String? takeAutomationNotice() {
    final n = _automationNotice;
    _automationNotice = null;
    return n;
  }

  void setLanguage(AppLanguage language) {
    if (_language == language) return;
    _language = language;
    notifyListeners();
    unawaited(_persistLanguage(language));
  }

  Future<void> toggleLanguage() async {
    setLanguage(_language == AppLanguage.en ? AppLanguage.he : AppLanguage.en);
  }

  static const _languagePrefsKey = 'app_language';

  Future<void> _persistLanguage(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePrefsKey, language.name);
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _language = AppLanguage.fromStorage(prefs.getString(_languagePrefsKey));
  }

  String topicDisplayName(Topic topic) => strings.displayTopicName(topic.name);
  String fileDisplayName(String name) => strings.fileNameLabel(name);

  String viewLabel(String type) {
    if (type.startsWith('view_')) {
      final id = int.tryParse(type.substring(5));
      final view = userViews.where((v) => v.id == id).firstOrNull;
      return view?.name ?? type;
    }
    return strings.viewLabel(type);
  }

  Future<void> goHome() async {
    isViewMode = false;
    isArchiveMode = false;
    selectedViewType = null;
    selectedView = null;
    final home = allTopics.where((t) => t.isMain).firstOrNull ?? allTopics.firstOrNull;
    if (home != null) await selectTopic(home);
  }

  Future<void> selectTopic(Topic topic) async {
    isViewMode = false;
    isArchiveMode = false;
    selectedTopic = topic;
    selectedDetail = null;
    topicDetailStale = true;
    notifyListeners();
    try {
      final files = await _files.listFilesForTopic(topic.id);
      selectedDetail = TopicDetail(topic: topic, files: files);
      topicDetailStale = false;
      for (final file in files) {
        await loadEmbedsForFile(file.id);
      }
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  Future<void> selectView(String viewType) async {
    isViewMode = true;
    isArchiveMode = false;
    selectedViewType = viewType;
    selectedView = userViews.where((v) => v.type == viewType).firstOrNull;
    viewPaneReady = selectedView != null;
    loading = true;
    notifyListeners();
    try {
      if (selectedView != null) {
        viewMemberships = await _views.listMemberships(selectedView!.id);
      }
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> selectArchiveTopic(Topic topic) async {
    isArchiveMode = true;
    isViewMode = false;
    selectedArchiveTopic = topic;
    notifyListeners();
  }

  Future<void> loadArchive() async {
    final entries = <ArchiveTopicEntry>[];
    ArchiveTopicEntry? daily;
    for (final topic in allTopics) {
      final archived = await _files.listArchivedForTopic(topic.id);
      if (archived.isEmpty) continue;
      final entry = ArchiveTopicEntry(
        topic: topic,
        archivedFileCount: archived.length,
        files: archived,
      );
      if (topic.isMain) {
        daily = entry;
      } else {
        entries.add(entry);
      }
    }
    archiveIndex = ArchiveIndex(daily: daily, topics: entries);
    notifyListeners();
  }

  /// Every file of the topic in the one order that decides placement.
  List<AppFile> orderedFilesFor(Topic topic, List<AppFile> files) =>
      orderedFiles(files);

  /// The files the topic's layout has room for.
  List<AppFile> shownFilesFor(Topic topic, List<AppFile> files) =>
      shownFiles(orderedFiles(files), layoutFor(topic));

  /// The files past the last slot — off screen until the topic is rearranged.
  List<AppFile> hiddenFilesFor(Topic topic, List<AppFile> files) =>
      hiddenFiles(orderedFiles(files), layoutFor(topic));

  String layoutFor(Topic topic) => topic.fileLayout;

  Future<void> setLayoutForTopic(Topic topic, String layoutId) async {
    if (topic.fileLayout == layoutId) return;
    await updateTopic(topic, fileLayout: layoutId);
  }

  Future<void> createTopic({
    required String name,
    required String type,
    String? icon,
    String? color,
  }) async {
    if (workspaceId == null) return;
    final tag = allTags.where((t) => t.name == type).firstOrNull;
    final topic = await _topics.createTopic(
      name: name,
      workspaceId: workspaceId!,
      icon: icon,
      color: color,
      tagIds: tag != null ? [tag.id] : null,
    );
    allTopics = [...allTopics, topic];
    await selectTopic(topic);
  }

  Future<void> updateTopic(
    Topic topic, {
    String? name,
    String? icon,
    String? color,
    String? fileLayout,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    if (color != null) body['color'] = color;
    if (fileLayout != null) body['file_layout'] = fileLayout;
    final updated = await _topics.updateTopic(topic.id, body);
    allTopics = allTopics.map((t) => t.id == updated.id ? updated : t).toList();
    if (selectedTopic?.id == updated.id) selectedTopic = updated;
    if (selectedDetail?.topic.id == updated.id) {
      selectedDetail = TopicDetail(topic: updated, files: selectedDetail!.files);
    }
    notifyListeners();
  }

  Future<void> deleteTopic(Topic topic) async {
    await _topics.deleteTopic(topic.id);
    allTopics = allTopics.where((t) => t.id != topic.id).toList();
    if (selectedTopic?.id == topic.id) {
      selectedTopic = null;
      selectedDetail = null;
    }
    notifyListeners();
  }

  Future<void> duplicateTopic(Topic topic) async {
    await createTopic(
      name: '${topic.name} copy',
      type: topic.primaryTag ?? 'other',
    );
  }

  List<Automation> get manualAiActions =>
      automations.where((a) => a.isManual).toList();

  List<Automation> get scheduledAutomations =>
      automations.where((a) => a.isScheduled).toList();

  Future<void> loadAutomations() async {
    if (workspaceId == null) return;
    automations = await _automations.list(workspaceId: workspaceId);
    notifyListeners();
  }

  Future<Automation> createAutomation({
    required String name,
    required String prompt,
    required String applyMode,
    required bool isScheduled,
    String? schedule,
  }) async {
    if (workspaceId == null) {
      throw StateError('workspace not ready');
    }
    final scope = <String, dynamic>{
      if (selectedTopic != null) 'topic_ids': [selectedTopic!.id],
      if (selectedDetail != null)
        'file_ids': selectedDetail!.files.map((f) => f.id).toList(),
    };
    final automation = await _automations.create(
      workspaceId: workspaceId!,
      name: name,
      prompt: prompt,
      applyMode: applyMode,
      trigger: isScheduled
          ? {'type': 'schedule'}
          : {'type': 'manual'},
      scope: scope,
      schedule: schedule,
    );
    automations = [...automations, automation];
    notifyListeners();
    return automation;
  }

  Future<void> deleteAutomation(Automation automation) async {
    await _automations.delete(automation.id);
    automations = automations.where((a) => a.id != automation.id).toList();
    notifyListeners();
  }

  Future<Map<String, dynamic>> runAutomationRecord(Automation automation) async {
    aiRunning = true;
    notifyListeners();
    try {
      final result = await _automations.run(automation.id);
      final agent = result['agent'];
      if (agent is Map && (agent['proposed_changes'] as List?)?.isNotEmpty == true) {
        pendingAgentReview = Map<String, dynamic>.from(agent);
      }
      return result;
    } finally {
      aiRunning = false;
      notifyListeners();
    }
  }

  /// Adds a file at the front of the topic.
  ///
  /// A file you just created should be on screen, and every layout has at least
  /// one slot, so first is the only position that guarantees it.
  Future<AppFile> addFile({required Topic topic, required String name}) async {
    final existing = orderedFiles(selectedDetail?.files ?? const <AppFile>[]);
    final file = await _files.createFile(
      topicId: topic.id,
      name: name,
      orderIndex: 0,
    );
    for (var i = 0; i < existing.length; i++) {
      await _files.updateFile(existing[i].id, {'order_index': i + 1});
    }
    await _refreshTopicFiles(topic);
    return file;
  }

  Future<void> updateFile(
    AppFile file,
    Map<String, dynamic> body, {
    bool notify = true,
  }) async {
    final updated = await _files.updateFile(file.id, body);
    _patchFileInDetail(updated);
    // Silent document autosaves must not notify — MaterialApp's Consumer and
    // other listeners rebuilding mid-keystroke desync HardwareKeyboard.
    if (notify) notifyListeners();
  }

  Future<void> archiveFile(AppFile file) async {
    await _files.updateFile(file.id, {
      'archived_at': DateTime.now().toUtc().toIso8601String(),
    });
    await _refreshTopicFiles(selectedDetail!.topic);
    await loadArchive();
  }

  Future<void> deleteFile(AppFile file) async {
    await _files.deleteFile(file.id);
    await _refreshTopicFiles(selectedDetail!.topic);
  }

  Future<void> _refreshTopicFiles(Topic topic) async {
    final files = await _files.listFilesForTopic(topic.id);
    // Prefer the topic already in state. Callers often hand in a snapshot from
    // when a dialog opened; using that here would undo a layout (or rename)
    // that finished just before this refresh.
    final fresh = allTopics.where((t) => t.id == topic.id).firstOrNull ??
        (selectedDetail?.topic.id == topic.id ? selectedDetail!.topic : null) ??
        topic;
    selectedDetail = TopicDetail(topic: fresh, files: files);
    if (selectedTopic?.id == fresh.id) selectedTopic = fresh;
    notifyListeners();
  }

  void _patchFileInDetail(AppFile file) {
    if (selectedDetail == null) return;
    selectedDetail = TopicDetail(
      topic: selectedDetail!.topic,
      files: selectedDetail!.files.map((f) => f.id == file.id ? file : f).toList(),
    );
  }

  void setEditingFileId(int? fileId, {bool notify = true}) {
    if (editingFileId == fileId) return;
    editingFileId = fileId;
    if (notify) notifyListeners();
  }

  Future<List<ObjectEmbed>> loadEmbedsForFile(
    int fileId, {
    bool notify = true,
  }) async {
    final embeds = await _objects.listForFile(fileId);
    embedsByFileId[fileId] = embeds;
    if (notify) notifyListeners();
    return embeds;
  }

  Future<AppFile> reloadFile(int fileId) async {
    final updated = await _files.getFile(fileId);
    _patchFileInDetail(updated);
    notifyListeners();
    return updated;
  }

  Future<void> deleteObjectEmbed(int objectId) async {
    await _objects.deleteEmbed(objectId);
    await _reloadEmbedsForOpenFiles();
    notifyListeners();
  }

  Future<Map<String, dynamic>> uploadImageBytes(
    String filename,
    List<int> bytes,
  ) {
    return _images.uploadBytes(filename, bytes);
  }

  Future<void> updateObjectPayload(
    int objectId,
    Map<String, dynamic> payload, {
    bool notify = false,
  }) async {
    try {
      await _api.patch('/objects/$objectId', {'payload': payload});
    } on ApiException catch (e) {
      // Late write after delete (empty graph exit, prune, etc.).
      if (e.statusCode == 404) return;
      rethrow;
    }
    // Patch the local cache so typing does not rebuild the whole file mid-key.
    for (final entry in embedsByFileId.entries) {
      final list = entry.value;
      final index = list.indexWhere((e) => e.id == objectId);
      if (index < 0) continue;
      final current = list[index];
      embedsByFileId[entry.key] = [
        for (var i = 0; i < list.length; i++)
          if (i == index)
            ObjectEmbed(
              id: current.id,
              fileId: current.fileId,
              type: current.type,
              taskListId: current.taskListId,
              informationId: current.informationId,
              anchor: current.anchor,
              sortKey: current.sortKey,
              tasks: current.tasks,
              information: current.information,
              links: current.links,
              payload: payload,
            )
          else
            list[i],
      ];
      break;
    }
    if (notify) notifyListeners();
  }

  Future<ObjectEmbed> createObjectInDocument(
    AppFile file, {
    required String type,
    String? title,
    String? body,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? payload,
    int? blockIndex,
    int? index,
    int? offset,
  }) async {
    final embed = await _objects.createObject(
      fileId: file.id,
      type: type,
      title: title,
      body: body,
      metadata: metadata,
      payload: payload,
      blockIndex: blockIndex ?? index ?? offset,
    );
    final updated = await _files.getFile(file.id);
    _patchFileInDetail(updated);
    await loadEmbedsForFile(file.id);
    return embed;
  }

  Future<void> convertSelectionToTaskList(
    AppFile file, {
    required RichDocument document,
    required ListNode listBlock,
  }) async {
    final blockIndex = document.blocks.indexWhere((b) => b.id == listBlock.id);
    if (blockIndex < 0) return;
    final cleared = document.copyWith(
      blocks: [...document.blocks]..removeAt(blockIndex),
    );
    await updateFile(file, {'document_json': DocumentCodec.serialize(cleared)});

    final embed = await createObjectInDocument(
      file,
      type: 'task_list',
      blockIndex: blockIndex,
    );
    if (embed.taskListId != null) {
      for (final item in listBlock.items) {
        if (item.text.trim().isNotEmpty) {
          await createTaskInList(embed.taskListId!, title: item.text.trim());
        }
      }
    }
    await reloadFile(file.id);
  }

  Future<void> convertSelectionToInfo(
    AppFile file, {
    required RichDocument document,
    required String slice,
    required List<Map<String, dynamic>> spans,
    required int blockIndex,
  }) async {
    final titleLine = slice.split('\n').first.trim();
    await createObjectInDocument(
      file,
      type: 'info',
      title: titleLine.isEmpty ? 'Info' : titleLine,
      body: slice,
      metadata: {'spans': spans},
      blockIndex: blockIndex + 1,
    );
    await reloadFile(file.id);
  }

  Future<Task> createTaskInList(
    int taskListId, {
    String title = '',
    int? afterTaskId,
    bool notify = true,
  }) async {
    final task = await _tasks.createInList(
      taskListId: taskListId,
      title: title,
    );
    // Keep new tasks in the Active zone: insert after [afterTaskId] among
    // active tasks, otherwise append to active; then append done ids.
    final existing = await _tasks.listForTaskList(taskListId);
    final others = existing.where((t) => t.id != task.id).toList();
    final active = others.where((t) => !t.isDone).map((t) => t.id).toList();
    final done = others.where((t) => t.isDone).map((t) => t.id).toList();
    final ordered = <int>[];
    if (afterTaskId != null && active.contains(afterTaskId)) {
      for (final id in active) {
        ordered.add(id);
        if (id == afterTaskId) ordered.add(task.id);
      }
    } else {
      ordered.addAll(active);
      ordered.add(task.id);
    }
    ordered.addAll(done);
    await _tasks.reorderInList(taskListId, ordered);
    await _reloadEmbedsForOpenFiles(notify: notify);
    return task;
  }

  Future<void> reorderTasksInList(
    int taskListId,
    List<int> orderedIds, {
    bool notify = true,
  }) async {
    await _tasks.reorderInList(taskListId, orderedIds);
    await _reloadEmbedsForOpenFiles(notify: notify);
  }

  /// Persist view membership order (active ids then done ids among task rows).
  Future<void> reorderViewMemberships(
    List<Map<String, dynamic>> memberships, {
    bool notify = true,
  }) async {
    if (selectedView == null) return;
    viewMemberships =
        await _views.replaceMemberships(selectedView!.id, memberships);
    if (notify) notifyListeners();
  }

  Future<List<ViewMembership>> loadTaskMemberships(int taskId) async {
    final rows = await _tasks.getTaskMemberships(taskId);
    return rows.map((e) => ViewMembership.fromJson(e)).toList();
  }

  Future<void> assignTaskToView(int taskId, int viewId) async {
    final existing = await loadTaskMemberships(taskId);
    await _tasks.replaceTaskMemberships(taskId, [
      ...existing.map(
        (m) => {
          'view_id': m.viewId,
          'section_name': m.sectionName,
          'order_index': m.orderIndex,
          'section_flag': m.sectionFlag,
          'topic_key': m.topicKey,
        },
      ),
      {'view_id': viewId, 'order_index': existing.length},
    ]);
    notifyListeners();
  }

  Future<void> updateInfoObject(
    ObjectEmbed embed, {
    required String title,
    required String body,
    List<Map<String, dynamic>>? spans,
    bool notify = false,
  }) async {
    if (embed.informationId == null) return;
    await _api.patch('/information/${embed.informationId}', {
      'title': title,
      'body': body,
      'metadata': {'spans': spans ?? []},
    });
    // Keep the typed text on screen without reloading embeds (which would
    // notifyListeners and rebuild the document mid-keystroke).
    if (notify) {
      await loadEmbedsForFile(embed.fileId);
    }
  }

  Future<void> addInfoLink(
    ObjectEmbed embed,
    String targetType,
    int targetId,
  ) async {
    await _objects.createLink(
      embed.id,
      targetType: targetType,
      targetId: targetId,
    );
    await loadEmbedsForFile(embed.fileId);
  }

  Future<void> toggleTaskStatus(Task task, {bool notify = true}) async {
    await _api.post('/tasks/${task.id}/toggle', {});
    await _reloadEmbedsForOpenFiles(notify: notify);
  }

  /// Place [task] at [insertIndexInZone] in the Active/Done zone of its list.
  Future<void> moveTaskInListZone({
    required Task task,
    required bool targetDone,
    required int insertIndexInZone,
    bool notify = true,
  }) async {
    final listId = task.taskListId;
    if (listId == null) return;
    await _tasks.moveToListZone(
      taskId: task.id,
      targetTaskListId: listId,
      insertIndexInZone: insertIndexInZone,
      targetDone: targetDone,
    );
    await _reloadEmbedsForOpenFiles(notify: notify);
  }

  Future<void> updateTaskTitle(
    Task task,
    String title, {
    bool notify = true,
  }) async {
    try {
      await _api.patch('/tasks/${task.id}', {'title': title});
    } on ApiException catch (e) {
      if (e.statusCode == 404) return;
      rethrow;
    }
    await _reloadEmbedsForOpenFiles(notify: notify);
  }

  Future<void> deleteTask(Task task, {bool notify = true}) async {
    await _tasks.deleteTask(task.id);
    await _reloadEmbedsForOpenFiles(notify: notify);
  }

  Future<void> _reloadEmbedsForOpenFiles({bool notify = true}) async {
    for (final file in selectedDetail?.files ?? const <AppFile>[]) {
      await loadEmbedsForFile(file.id, notify: false);
    }
    if (isViewMode && selectedView != null) {
      viewMemberships = await _views.listMemberships(selectedView!.id);
    }
    if (notify) notifyListeners();
  }

  /// Reload open-file embeds and the selected view's memberships.
  Future<void> refreshOpenTaskSurfaces({bool notify = true}) =>
      _reloadEmbedsForOpenFiles(notify: notify);

  /// Writes the topic's file order. The layout then decides how far down that
  /// order the screen reaches.
  Future<String?> reorderTopicFiles(
    Topic topic, {
    required List<AppFile> ordered,
  }) async {
    for (var index = 0; index < ordered.length; index++) {
      await _files.updateFile(ordered[index].id, {'order_index': index});
    }
    await _refreshTopicFiles(topic);
    return null;
  }

  Future<List<AppFile>> loadBringFilePreviews(List<AppFile> files) async => files;

  List<Task> get viewTasks {
    return viewMemberships
        .where((m) => m.task != null)
        .map((m) => Task.fromJson(m.task!))
        .toList();
  }

  List<String> sectionsForViewType(String viewType) {
    final names = viewMemberships
        .map((m) => m.sectionName)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList();
    names.sort();
    return names;
  }

  void setViewDisplayMode(ViewDisplayMode mode) {
    viewDisplayMode = mode;
    notifyListeners();
  }

  Future<void> createViewSection(String viewType, String name) async {
    if (selectedView == null) return;
    final current = viewMemberships
        .map(
          (m) => {
            'task_id': m.taskId,
            'section_name': m.sectionName,
            'order_index': m.orderIndex,
            'section_flag': m.sectionFlag,
            'topic_key': m.topicKey,
          },
        )
        .toList();
    current.add({
      'task_id': null,
      'section_name': name,
      'order_index': current.length,
    });
    viewMemberships = await _views.replaceMemberships(selectedView!.id, current);
    notifyListeners();
  }

  Future<void> deleteViewSection(String section) async {
    if (selectedView == null) return;
    final memberships = viewMemberships
        .where((m) => m.sectionName != section)
        .map(
          (m) => {
            'task_id': m.taskId,
            'section_name': m.sectionName,
            'order_index': m.orderIndex,
            'section_flag': m.sectionFlag,
            'topic_key': m.topicKey,
          },
        )
        .toList();
    viewMemberships = await _views.replaceMemberships(selectedView!.id, memberships);
    notifyListeners();
  }

  Future<void> setViewSectionImportance(String section, bool important) async {
    if (selectedView == null) return;
    final flag = important ? 'important' : null;
    final memberships = viewMemberships
        .map(
          (m) => {
            'task_id': m.taskId,
            'section_name': m.sectionName,
            'order_index': m.orderIndex,
            'section_flag': m.sectionName == section ? flag : m.sectionFlag,
            'topic_key': m.topicKey,
          },
        )
        .toList();
    viewMemberships = await _views.replaceMemberships(selectedView!.id, memberships);
    notifyListeners();
  }

  Future<void> reorderViewSections(String viewType, int from, int to) async {}

  Color? topicAccentForTask(Task task) => null;
  bool topicIsMain(Task task) => false;

  Future<void> createView({required String name}) async {
    if (workspaceId == null) return;
    final view = await _views.createView(workspaceId: workspaceId!, name: name);
    userViews = [...userViews, view];
    notifyListeners();
  }

  bool get hasAiContext => workspaceId != null;
  bool get canUseAiTools => hasAiContext;
  bool canRunAiTool(String tool) => hasAiContext && !aiRunning;

  int get archiveTotalCount {
    final index = archiveIndex;
    var count = index.daily?.archivedFileCount ?? 0;
    for (final entry in index.topics) {
      count += entry.archivedFileCount;
    }
    return count;
  }

  Future<Map<String, dynamic>?> runAgentPrompt(
    String prompt, {
    String applyMode = 'review',
  }) async {
    if (workspaceId == null) return null;
    aiRunning = true;
    notifyListeners();
    try {
      final result = await _agent.run(
        prompt: prompt,
        workspaceId: workspaceId!,
        scope: {
          if (selectedTopic != null) 'topic_ids': [selectedTopic!.id],
          if (selectedDetail != null)
            'file_ids': selectedDetail!.files.map((f) => f.id).toList(),
        },
        applyMode: applyMode,
      );
      final changes = result['proposed_changes'];
      if (applyMode == 'review' && changes is List && changes.isNotEmpty) {
        pendingAgentReview = result;
      }
      return result;
    } finally {
      aiRunning = false;
      notifyListeners();
    }
  }

  Future<void> applyAgentReview() async {
    final changes = pendingAgentReview?['proposed_changes'] as List?;
    if (changes == null || selectedDetail == null) return;
    for (final change in changes) {
      if (change is! Map) continue;
      final fileId = change['file_id'] as int?;
      final newBody = change['new_document_json'] as String? ?? change['new_body'] as String?;
      if (fileId != null && newBody != null) {
        await _files.updateFile(fileId, {'document_json': newBody});
      }
    }
    pendingAgentReview = null;
    if (selectedTopic != null) await selectTopic(selectedTopic!);
  }

  void dismissAgentReview() {
    pendingAgentReview = null;
    notifyListeners();
  }

  dynamic get pendingTaskResetAcknowledgement => null;
  Future<void> approveTaskResetAcknowledgement({bool approve = true}) async {}
  Future<void> refreshCurrentView() async {
    if (selectedViewType != null) await selectView(selectedViewType!);
  }

  void setAiFocus({int? fileId, int? blockId, String? field}) {}
  AppFile? get aiFocusedFile => selectedDetail?.files.firstOrNull;
  Future<dynamic> runAiTool(String tool) async => null;
  Future<dynamic> runAiMoveFile(Topic topic, AppFile file) async => null;
  Future<bool> runUploadDetails() async => false;
  Block? taskRowBlockInFile(AppFile file, Task task) => null;
  Future<void> applyTaskDrop({
    required AppFile file,
    required Task task,
    required int index,
  }) async {}
  Future<Task> createTaskInViewZoneAfter({
    required String viewType,
    required String section,
    required int afterOrder,
  }) async =>
      Task(id: 0, blockId: null, title: '', status: 'active');
  Future<void> deleteTaskInView(Task task) async {}
  Future<void> pasteTasksInViewAfter({
    required List<String> lines,
    required String viewType,
    required String section,
    required int afterOrder,
  }) async {}
  Future<void> completeAutomationCompanion(int id) async {}
  Future<void> submitProcessDocumentationInput({
    required int id,
    required String text,
  }) async {}
  Future<void> finalizeProcessUpdate(dynamic proposal, dynamic decisions) async {}
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
