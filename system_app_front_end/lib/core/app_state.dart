import 'package:flutter/material.dart';

import '../features/document/document_codec.dart';
import '../features/document/inline_document_model.dart';
import '../features/document/rich_text/list_text_parse.dart';
import 'l10n/app_language.dart';
import 'l10n/app_strings.dart';
import 'models/automation.dart';
import 'models/app_file.dart';
import 'models/app_view.dart';
import 'models/archive_index.dart';
import 'models/block.dart';
import 'models/object_embed.dart';
import 'models/tag.dart';
import 'models/task.dart';
import 'models/topic.dart';
import 'services/automation_service.dart';
import 'services/agent_service.dart';
import 'services/api_service.dart';
import 'services/bootstrap_service.dart';
import 'services/file_service.dart';
import 'services/object_service.dart';
import 'services/tag_service.dart';
import 'services/task_service.dart';
import 'services/topic_service.dart';
import 'services/view_service.dart';
import 'shortcuts/shortcut_bindings_store.dart';

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
    _language = language;
    notifyListeners();
  }

  Future<void> toggleLanguage() async {
    setLanguage(_language == AppLanguage.en ? AppLanguage.he : AppLanguage.en);
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

  List<AppFile> mainFilesFor(Topic topic, List<AppFile> files) {
    return files.where((f) => f.isEssence).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  List<AppFile> secondaryFilesFor(Topic topic, List<AppFile> files) {
    return files.where((f) => !f.isEssence).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  String layoutFor(Topic topic) => 'default';
  void setLayoutForTopic(Topic topic, String layoutId) {}

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
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    if (color != null) body['color'] = color;
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
        pendingAgentReview = Map<String, dynamic>.from(agent as Map);
      }
      return result;
    } finally {
      aiRunning = false;
      notifyListeners();
    }
  }

  Future<AppFile> addFile({
    required Topic topic,
    required String name,
    bool isEssence = false,
  }) async {
    final file = await _files.createFile(
      topicId: topic.id,
      name: name,
      isEssence: isEssence,
      orderIndex: selectedDetail?.files.length ?? 0,
    );
    await _refreshTopicFiles(topic);
    return file;
  }

  Future<void> updateFile(AppFile file, Map<String, dynamic> body) async {
    final updated = await _files.updateFile(file.id, body);
    _patchFileInDetail(updated);
    notifyListeners();
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
    selectedDetail = TopicDetail(topic: topic, files: files);
    notifyListeners();
  }

  void _patchFileInDetail(AppFile file) {
    if (selectedDetail == null) return;
    selectedDetail = TopicDetail(
      topic: selectedDetail!.topic,
      files: selectedDetail!.files.map((f) => f.id == file.id ? file : f).toList(),
    );
  }

  void setEditingFileId(int? fileId) {
    if (editingFileId == fileId) return;
    editingFileId = fileId;
    notifyListeners();
  }

  Future<List<ObjectEmbed>> loadEmbedsForFile(int fileId) async {
    final embeds = await _objects.listForFile(fileId);
    embedsByFileId[fileId] = embeds;
    notifyListeners();
    return embeds;
  }

  Future<ObjectEmbed> createObjectInDocument(
    AppFile file, {
    required String type,
    String? title,
    String? body,
    int? index,
    int? offset,
  }) async {
    final embed = await _objects.createObject(
      fileId: file.id,
      type: type,
      title: title,
      body: body,
      index: index,
      offset: offset,
    );
    final updated = await _files.getFile(file.id);
    _patchFileInDetail(updated);
    await loadEmbedsForFile(file.id);
    return embed;
  }

  Future<void> convertSelectionToTaskList(
    AppFile file, {
    required InlineDocument document,
    required int start,
    required int end,
    required void Function(InlineDocument doc) onDocumentChanged,
  }) async {
    final slice = document.text.substring(
      start.clamp(0, document.text.length),
      end.clamp(0, document.text.length),
    );
    final lines = parsePastedListText(slice);
    final cleared = DocumentCodec.replaceTextRange(document, start, end, '');
    onDocumentChanged(cleared);
    await updateFile(file, {'body': DocumentCodec.serialize(cleared)});

    final embed = await createObjectInDocument(
      file,
      type: 'task_list',
      offset: start,
    );
    if (embed.taskListId != null) {
      for (final line in lines) {
        await createTaskInList(embed.taskListId!, title: line);
      }
    }
    final updated = await _files.getFile(file.id);
    _patchFileInDetail(updated);
    onDocumentChanged(DocumentCodec.parse(updated.body));
  }

  Future<void> convertSelectionToInfo(
    AppFile file, {
    required InlineDocument document,
    required int start,
    required int end,
    required void Function(InlineDocument doc) onDocumentChanged,
  }) async {
    final slice = document.text.substring(
      start.clamp(0, document.text.length),
      end.clamp(0, document.text.length),
    );
    final titleLine = slice.split('\n').first.trim();
    final cleared = DocumentCodec.replaceTextRange(document, start, end, '');
    onDocumentChanged(cleared);
    await updateFile(file, {'body': DocumentCodec.serialize(cleared)});

    await createObjectInDocument(
      file,
      type: 'info',
      title: titleLine.isEmpty ? 'Info' : titleLine,
      body: slice,
      offset: start,
    );
    final updated = await _files.getFile(file.id);
    _patchFileInDetail(updated);
    onDocumentChanged(DocumentCodec.parse(updated.body));
  }

  Future<Task> createTaskInList(int taskListId, {String title = 'New task'}) async {
    final task = await _tasks.createInList(taskListId: taskListId, title: title);
    await _reloadEmbedsForOpenFiles();
    notifyListeners();
    return task;
  }

  Future<void> reorderTasksInList(int taskListId, List<int> orderedIds) async {
    await _tasks.reorderInList(taskListId, orderedIds);
    await _reloadEmbedsForOpenFiles();
    notifyListeners();
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
  }) async {
    if (embed.informationId == null) return;
    await _api.patch('/information/${embed.informationId}', {
      'title': title,
      'body': body,
      'metadata': {'spans': spans ?? []},
    });
    await _reloadEmbedsForOpenFiles();
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

  Future<void> toggleTaskStatus(Task task) async {
    await _api.post('/tasks/${task.id}/toggle', {});
    await _reloadEmbedsForOpenFiles();
    notifyListeners();
  }

  Future<void> updateTaskTitle(Task task, String title) async {
    await _api.patch('/tasks/${task.id}', {'title': title});
    await _reloadEmbedsForOpenFiles();
    notifyListeners();
  }

  Future<void> deleteTask(Task task) async {
    await _tasks.deleteTask(task.id);
    await _reloadEmbedsForOpenFiles();
    notifyListeners();
  }

  Future<void> _reloadEmbedsForOpenFiles() async {
    for (final file in selectedDetail?.files ?? const <AppFile>[]) {
      await loadEmbedsForFile(file.id);
    }
    if (isViewMode && selectedView != null) {
      viewMemberships = await _views.listMemberships(selectedView!.id);
    }
  }

  Future<String?> reorderTopicFiles(
    Topic topic, {
    required List<AppFile> main,
    required List<AppFile> additional,
  }) async {
    var index = 0;
    for (final file in [...main, ...additional]) {
      await _files.updateFile(file.id, {
        'order_index': index,
        'is_essence': main.contains(file),
      });
      index++;
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
      final newBody = change['new_body'] as String?;
      if (fileId != null && newBody != null) {
        await _files.updateFile(fileId, {'body': newBody});
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
