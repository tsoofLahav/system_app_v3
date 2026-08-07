import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../areas/files/editor/document_editor_controller.dart';
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
import '../areas/objects/data/view_layout.dart';
import '../areas/objects/data/view_service.dart';
import '../areas/ux/layout/topic_file_slots.dart';
import '../areas/ux/shortcuts/shortcut_binding.dart';
import '../areas/ux/shortcuts/shortcut_bindings_store.dart';
import '../areas/ux/topic/topic_appearance.dart';
import '../areas/ui/app_colors.dart';

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

  bool isDiagramMode = false;
  ObjectGraphData? objectGraph;
  final Set<int> diagramFilterTagIds = {};
  /// Objects map node tint: topic wash vs first-tag color.
  DiagramColorMode diagramColorMode = DiagramColorMode.byTopic;
  final Map<int, List<Map<String, dynamic>>> descriptionLinksByFileId = {};
  int? pendingFocusObjectId;

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

  Future<void> setShortcutBinding(String actionId, dynamic binding) async {
    if (binding is! ShortcutBinding) return;
    await shortcutBindings.setBinding(actionId, binding);
    shortcutRebuildListenable.notifyListeners();
    notifyListeners();
  }

  Future<void> resetShortcut(String actionId) async {
    await shortcutBindings.resetBinding(actionId);
    shortcutRebuildListenable.notifyListeners();
    notifyListeners();
  }

  Future<void> resetAllShortcuts() async {
    await shortcutBindings.resetAll();
    shortcutRebuildListenable.notifyListeners();
    notifyListeners();
  }

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

  static const topicTypeTagNames = {'project', 'process', 'area', 'other'};

  /// Freeform object tags (excludes topic classification tags).
  List<AppTag> get objectTags =>
      allTags.where((t) => !topicTypeTagNames.contains(t.name)).toList();

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
    isDiagramMode = false;
    selectedViewType = null;
    selectedView = null;
    final home = allTopics.where((t) => t.isMain).firstOrNull ?? allTopics.firstOrNull;
    if (home != null) await selectTopic(home);
  }

  Future<void> selectTopic(Topic topic) async {
    isViewMode = false;
    isArchiveMode = false;
    isDiagramMode = false;
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
    isDiagramMode = false;
    selectedViewType = viewType;
    selectedView = userViews.where((v) => v.type == viewType).firstOrNull;
    viewPaneReady = selectedView != null;
    if (selectedView != null) {
      viewDisplayMode = _displayModeFromConfig(selectedView!.layoutConfig);
    }
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

  ViewDisplayMode _displayModeFromConfig(Map<String, dynamic> config) {
    return ViewLayoutConfig.displayMode(config) == ViewLayoutConfig.modeByTopic
        ? ViewDisplayMode.byTopic
        : ViewDisplayMode.bySection;
  }

  Future<void> _persistViewLayout(Map<String, dynamic> layoutConfig) async {
    if (selectedView == null) return;
    final updated = await _views.updateView(
      selectedView!.id,
      layoutConfig: layoutConfig,
    );
    userViews = [
      for (final v in userViews) v.id == updated.id ? updated : v,
    ];
    selectedView = updated;
  }

  Future<void> selectArchiveTopic(Topic topic) async {
    isArchiveMode = true;
    isViewMode = false;
    isDiagramMode = false;
    selectedArchiveTopic = topic;
    notifyListeners();
  }

  Future<void> openDiagram() async {
    isDiagramMode = true;
    isViewMode = false;
    isArchiveMode = false;
    selectedViewType = null;
    selectedView = null;
    notifyListeners();
    await loadObjectGraph();
  }

  Future<void> loadObjectGraph() async {
    if (workspaceId == null) return;
    try {
      objectGraph = await _objects.loadGraph(workspaceId: workspaceId!);
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  void toggleDiagramFilterTag(int tagId) {
    if (diagramFilterTagIds.contains(tagId)) {
      diagramFilterTagIds.remove(tagId);
    } else {
      diagramFilterTagIds.add(tagId);
    }
    notifyListeners();
  }

  void setDiagramColorMode(DiagramColorMode mode) {
    if (diagramColorMode == mode) return;
    diagramColorMode = mode;
    notifyListeners();
  }

  /// Patch info content from the objects map without leaving diagram mode.
  ///
  /// Does not [notifyListeners] — the expanded map card owns local controllers,
  /// and a rebuild mid-keystroke desyncs [HardwareKeyboard].
  Future<void> updateInfoFromDiagram({
    required int informationId,
    required int objectId,
    required String title,
    required String body,
  }) async {
    await _api.patch('/information/$informationId', {
      'title': title,
      'body': body,
    });
    final graph = objectGraph;
    if (graph == null) return;
    objectGraph = ObjectGraphData(
      nodes: [
        for (final n in graph.nodes)
          if (n.objectId == objectId)
            n.copyWith(title: title, body: body)
          else
            n,
      ],
      edges: graph.edges,
    );
  }

  Future<AppTag?> createWorkspaceTag({
    required String name,
    String? color,
    String? icon,
  }) async {
    if (workspaceId == null) return null;
    final tag = await _tags.createTag(
      workspaceId: workspaceId!,
      name: name,
      color: color,
      icon: icon,
    );
    allTags = [...allTags, tag];
    notifyListeners();
    return tag;
  }

  Future<void> setObjectTags(ObjectEmbed embed, List<int> tagIds) async {
    final tags = await _objects.replaceObjectTags(embed.id, tagIds);
    await loadEmbedsForFile(embed.fileId);
    // Keep tags on the cached embed even if list reload races.
    final list = embedsByFileId[embed.fileId];
    if (list != null) {
      final i = list.indexWhere((e) => e.id == embed.id);
      if (i >= 0) {
        embedsByFileId[embed.fileId] = [
          for (var j = 0; j < list.length; j++)
            j == i ? list[j].copyWith(tags: tags) : list[j],
        ];
      }
    }
    notifyListeners();
  }

  Future<void> addRelatedObjectLink(
    ObjectEmbed embed, {
    required int targetObjectId,
  }) async {
    await _objects.createRelatedLink(
      embed.id,
      targetObjectId: targetObjectId,
    );
    await loadEmbedsForFile(embed.fileId);
  }

  Future<void> removeObjectLink(ObjectEmbed embed, int linkId) async {
    await _objects.deleteLink(embed.id, linkId);
    await loadEmbedsForFile(embed.fileId);
  }

  Future<void> createDescriptionLink({
    required int infoObjectId,
    required Map<String, dynamic> anchor,
    String? label,
  }) async {
    await _objects.createDescriptionLink(
      infoObjectId,
      anchor: anchor,
      label: label,
    );
    final fileId = anchor['file_id'] as int?;
    if (fileId != null) {
      await loadDescriptionLinksForFile(fileId);
    }
    final infoFileId = embedsByFileId.entries
        .where((e) => e.value.any((o) => o.id == infoObjectId))
        .map((e) => e.key)
        .firstOrNull;
    if (infoFileId != null) {
      await loadEmbedsForFile(infoFileId);
    }
  }

  Future<void> loadDescriptionLinksForFile(int fileId) async {
    if (fileId <= 0) return;
    try {
      descriptionLinksByFileId[fileId] =
          await _objects.listFileDescriptionLinks(fileId);
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  List<Map<String, dynamic>> descriptionLinksForSegment({
    required int fileId,
    required String segmentId,
  }) {
    final links = descriptionLinksByFileId[fileId] ?? const [];
    return [
      for (final link in links)
        if (link['kind'] == 'description' &&
            (link['anchor'] is Map) &&
            '${(link['anchor'] as Map)['segment_id']}' == segmentId)
          link,
    ];
  }

  /// Open the topic/file that hosts [objectId] and focus its embed.
  Future<void> openObjectInFile({
    required int objectId,
    int? fileId,
  }) async {
    var resolvedFileId = fileId;
    if (resolvedFileId == null || resolvedFileId <= 0) {
      final embed = await _objects.getObject(objectId);
      resolvedFileId = embed.fileId;
    }
    pendingFocusObjectId = objectId;
    final file = await _files.getFile(resolvedFileId);
    final topic = allTopics.where((t) => t.id == file.topicId).firstOrNull;
    if (topic == null) {
      pendingFocusObjectId = null;
      return;
    }
    await selectTopic(topic);
    setEditingFileId(resolvedFileId);
    notifyListeners();
  }

  int? takePendingFocusObjectId() {
    final id = pendingFocusObjectId;
    pendingFocusObjectId = null;
    return id;
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
      final changes = agent is Map ? agent['proposed_changes'] : null;
      if (changes is List &&
          changes.any((c) => c is Map && c['review'] != null)) {
        pendingAgentReview = Map<String, dynamic>.from(agent as Map);
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
    try {
      descriptionLinksByFileId[fileId] =
          await _objects.listFileDescriptionLinks(fileId);
    } catch (_) {
      // Older backends without description-links still load embeds.
    }
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
          if (i == index) current.copyWith(payload: payload) else list[i],
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
    String status = 'active',
    bool notify = true,
  }) async {
    final task = await _tasks.createInList(
      taskListId: taskListId,
      title: title,
      status: status,
    );
    // Insert into the matching zone after [afterTaskId], then the other zone.
    final existing = await _tasks.listForTaskList(taskListId);
    final others = existing.where((t) => t.id != task.id).toList();
    final active = others.where((t) => !t.isDone).map((t) => t.id).toList();
    final done = others.where((t) => t.isDone).map((t) => t.id).toList();
    final targetDone = status == 'done';
    final ordered = <int>[];
    if (targetDone) {
      ordered.addAll(active);
      if (afterTaskId != null && done.contains(afterTaskId)) {
        for (final id in done) {
          ordered.add(id);
          if (id == afterTaskId) ordered.add(task.id);
        }
      } else {
        ordered
          ..addAll(done)
          ..add(task.id);
      }
    } else {
      if (afterTaskId != null && active.contains(afterTaskId)) {
        for (final id in active) {
          ordered.add(id);
          if (id == afterTaskId) ordered.add(task.id);
        }
      } else {
        ordered
          ..addAll(active)
          ..add(task.id);
      }
      ordered.addAll(done);
    }
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

  /// Update one view membership's section and/or topic placement.
  Future<void> updateViewTaskPlacement({
    required int taskId,
    String? sectionName,
    String? sectionFlag,
    String? topicKey,
    bool clearSection = false,
    bool clearTopic = false,
    bool notify = true,
  }) async {
    if (selectedView == null) return;
    final memberships = <Map<String, dynamic>>[];
    var index = 0;
    for (final m in viewMemberships) {
      final isTarget = m.taskId == taskId;
      memberships.add({
        'task_id': m.taskId,
        'section_name': isTarget
            ? (clearSection ? null : (sectionName ?? m.sectionName))
            : m.sectionName,
        'order_index': index++,
        'section_flag': isTarget
            ? (clearSection ? null : (sectionFlag ?? m.sectionFlag))
            : m.sectionFlag,
        'topic_key': isTarget
            ? (clearTopic ? null : (topicKey ?? m.topicKey))
            : m.topicKey,
      });
    }
    await reorderViewMemberships(memberships, notify: notify);
  }

  Future<List<ViewMembership>> loadTaskMemberships(int taskId) async {
    final rows = await _tasks.getTaskMemberships(taskId);
    return rows.map((e) => ViewMembership.fromJson(e)).toList();
  }

  /// A task belongs to at most one view — [viewId] replaces any previous one.
  Future<void> setTaskView(int taskId, int? viewId) async {
    final existing = await loadTaskMemberships(taskId);
    final previousIds = {for (final m in existing) m.viewId};
    if (viewId == null) {
      if (existing.isEmpty) return;
      await _tasks.replaceTaskMemberships(taskId, const []);
    } else {
      final keep = existing.where((m) => m.viewId == viewId).firstOrNull;
      if (existing.length == 1 && keep != null) return;
      await _tasks.replaceTaskMemberships(taskId, [
        {
          'view_id': viewId,
          'section_name': keep?.sectionName,
          'order_index': 0,
          'section_flag': keep?.sectionFlag,
          'topic_key': keep?.topicKey,
        },
      ]);
      previousIds.add(viewId);
    }
    if (isViewMode &&
        selectedView != null &&
        previousIds.contains(selectedView!.id)) {
      viewMemberships = await _views.listMemberships(selectedView!.id);
    }
    notifyListeners();
  }

  Future<void> assignTaskToView(int taskId, int viewId) =>
      setTaskView(taskId, viewId);

  Future<void> removeTaskFromView(int taskId, int viewId) async {
    final existing = await loadTaskMemberships(taskId);
    if (!existing.any((m) => m.viewId == viewId)) return;
    // One-view rule: removing the current view clears membership entirely.
    await setTaskView(taskId, null);
  }

  /// Clears home-list membership (orphan). Used when a view topic change
  /// leaves the original list.
  Future<void> clearTaskHomeList(int taskId) async {
    await _tasks.updateTask(taskId, {'task_list_id': null});
    await _reloadEmbedsForOpenFiles(notify: true);
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
    await addRelatedObjectLink(embed, targetObjectId: targetId);
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
    bool notify = false,
  }) async {
    try {
      await _api.patch('/tasks/${task.id}', {'title': title});
    } on ApiException catch (e) {
      if (e.statusCode == 404) return;
      rethrow;
    }
    // Patch caches in place — never reload embeds mid-keystroke (that rebuilds
    // text fields and desyncs HardwareKeyboard: KeyDownEvent already pressed).
    _patchCachedTaskTitle(task.id, title);
    if (notify) notifyListeners();
  }

  void _patchCachedTaskTitle(int taskId, String title) {
    for (final entry in embedsByFileId.entries.toList()) {
      final embeds = entry.value;
      var changed = false;
      final next = <ObjectEmbed>[];
      for (final embed in embeds) {
        final tasks = embed.tasks;
        if (tasks == null) {
          next.add(embed);
          continue;
        }
        final newTasks = <Task>[];
        var taskChanged = false;
        for (final t in tasks) {
          if (t.id == taskId) {
            newTasks.add(t.copyWith(title: title));
            taskChanged = true;
          } else {
            newTasks.add(t);
          }
        }
        if (taskChanged) {
          changed = true;
          next.add(embed.copyWith(tasks: newTasks));
        } else {
          next.add(embed);
        }
      }
      if (changed) embedsByFileId[entry.key] = next;
    }
    if (isViewMode) {
      viewMemberships = [
        for (final m in viewMemberships)
          if (m.taskId == taskId && m.task != null)
            m.copyWith(task: {...m.task!, 'title': title})
          else
            m,
      ];
    }
  }

  Future<void> deleteTask(Task task, {bool notify = true}) async {
    await _tasks.deleteTask(task.id);
    if (isViewMode && selectedView != null) {
      viewMemberships = await _views.listMemberships(selectedView!.id);
    }
    await _reloadEmbedsForOpenFiles(notify: notify);
  }

  /// Create a task and membership in the open view (after optional sibling).
  ///
  /// Defaults to an orphan (`task_list_id` null). Pass [taskListId] only when
  /// placing into a home list that already appears in the same frame.
  Future<Task> createTaskInView({
    String title = '',
    String status = 'active',
    int? afterTaskId,
    int? taskListId,
    String? sectionName,
    String? sectionFlag,
    String? topicKey,
    bool notify = true,
  }) async {
    if (selectedView == null) {
      throw StateError('No view selected');
    }
    final task = await _views.createTaskInView(
      selectedView!.id,
      title: title,
      status: status,
      afterTaskId: afterTaskId,
      taskListId: taskListId,
      sectionName: sectionName,
      sectionFlag: sectionFlag,
      topicKey: topicKey,
    );
    viewMemberships = await _views.listMemberships(selectedView!.id);
    await _reloadEmbedsForOpenFiles(notify: notify);
    return task;
  }

  Future<void> updateTaskListTitle(
    int taskListId,
    String title, {
    bool notify = false,
  }) async {
    await _api.patch('/task-lists/$taskListId', {'title': title});
    for (final file in selectedDetail?.files ?? const <AppFile>[]) {
      final embeds = embedsByFileId[file.id];
      if (embeds == null) continue;
      embedsByFileId[file.id] = [
        for (final e in embeds)
          e.taskListId == taskListId ? e.copyWith(taskListTitle: title) : e,
      ];
    }
    if (isViewMode && selectedView != null) {
      viewMemberships = [
        for (final m in viewMemberships)
          if (m.task != null && m.task!['task_list_id'] == taskListId)
            m.copyWith(task: {...m.task!, 'task_list_title': title})
          else
            m,
      ];
    }
    if (notify) notifyListeners();
  }

  /// Place an orphan (or any) view task into a home list.
  Future<void> assignViewTaskToList(Task task, int taskListId) async {
    await _tasks.moveToListZone(
      taskId: task.id,
      targetTaskListId: taskListId,
      insertIndexInZone: 0,
      targetDone: task.isDone,
    );
    await _reloadEmbedsForOpenFiles(notify: true);
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

  List<ViewSectionDef> sectionsForSelectedView() {
    final view = selectedView;
    if (view == null) return const [];
    final defined = ViewLayoutConfig.sections(view.layoutConfig);
    final known = {for (final s in defined) s.name};
    final extras = <ViewSectionDef>[];
    var order = defined.length;
    for (final m in viewMemberships) {
      final name = m.sectionName?.trim();
      if (name == null || name.isEmpty || known.contains(name)) continue;
      known.add(name);
      extras.add(
        ViewSectionDef(
          name: name,
          flag: m.sectionFlag,
          orderIndex: order++,
        ),
      );
    }
    return [...defined, ...extras];
  }

  /// Legacy helper — section names only.
  List<String> sectionsForViewType(String viewType) => [
        for (final s in sectionsForSelectedView()) s.name,
      ];

  Future<void> setViewDisplayMode(ViewDisplayMode mode) async {
    if (mode == ViewDisplayMode.flat) mode = ViewDisplayMode.bySection;
    viewDisplayMode = mode;
    if (selectedView != null) {
      final next = ViewLayoutConfig.withDisplayMode(
        selectedView!.layoutConfig,
        mode == ViewDisplayMode.byTopic
            ? ViewLayoutConfig.modeByTopic
            : ViewLayoutConfig.modeBySection,
      );
      await _persistViewLayout(next);
    }
    notifyListeners();
  }

  Future<void> createViewSection(
    String viewType,
    String name, {
    String? flag,
    String? colorHex,
  }) async {
    final trimmed = name.trim();
    if (selectedView == null || trimmed.isEmpty) return;
    final sections = [...sectionsForSelectedView()];
    if (sections.any((s) => s.name == trimmed)) return;
    sections.add(
      ViewSectionDef(
        name: trimmed,
        flag: flag,
        colorHex: colorHex,
        orderIndex: sections.length,
      ),
    );
    await _persistViewLayout(
      ViewLayoutConfig.withSections(selectedView!.layoutConfig, sections),
    );
    notifyListeners();
  }

  Future<void> updateViewSection({
    required String oldName,
    required ViewSectionDef next,
  }) async {
    if (selectedView == null) return;
    final sections = [
      for (final s in sectionsForSelectedView())
        s.name == oldName ? next : s,
    ];
    await _persistViewLayout(
      ViewLayoutConfig.withSections(selectedView!.layoutConfig, sections),
    );

    final flag = next.flag;
    final memberships = [
      for (final m in viewMemberships)
        {
          'task_id': m.taskId,
          'section_name':
              m.sectionName == oldName ? next.name : m.sectionName,
          'order_index': m.orderIndex,
          'section_flag':
              m.sectionName == oldName || m.sectionName == next.name
                  ? flag
                  : m.sectionFlag,
          'topic_key': m.topicKey,
        },
    ];
    viewMemberships =
        await _views.replaceMemberships(selectedView!.id, memberships);
    notifyListeners();
  }

  Future<void> deleteViewSection(String section) async {
    if (selectedView == null) return;
    final sections = [
      for (final s in sectionsForSelectedView())
        if (s.name != section) s,
    ];
    final removedKey = 'section:$section';
    final order = [
      for (final key in ViewLayoutConfig.sectionOrder(selectedView!.layoutConfig))
        if (key != removedKey) key,
    ];
    var layout = ViewLayoutConfig.withSections(
      selectedView!.layoutConfig,
      sections,
    );
    layout = ViewLayoutConfig.withSectionOrder(layout, order);
    await _persistViewLayout(layout);
    final memberships = [
      for (final m in viewMemberships)
        {
          'task_id': m.taskId,
          'section_name': m.sectionName == section ? null : m.sectionName,
          'order_index': m.orderIndex,
          'section_flag':
              m.sectionName == section ? null : m.sectionFlag,
          'topic_key': m.topicKey,
        },
    ];
    viewMemberships =
        await _views.replaceMemberships(selectedView!.id, memberships);
    notifyListeners();
  }

  Future<void> setViewSectionImportance(String section, bool important) async {
    final current = sectionsForSelectedView()
        .where((s) => s.name == section)
        .firstOrNull;
    if (current == null) {
      await updateViewSection(
        oldName: section,
        next: ViewSectionDef(
          name: section,
          flag: important ? 'important' : null,
        ),
      );
      return;
    }
    await updateViewSection(
      oldName: section,
      next: current.copyWith(
        flag: important ? 'important' : null,
        clearFlag: !important,
      ),
    );
  }

  Future<void> reorderViewSections(String viewType, int from, int to) async {
    if (selectedView == null) return;
    final sections = [...sectionsForSelectedView()];
    if (from < 0 || from >= sections.length) return;
    var target = to;
    if (target < 0) target = 0;
    if (target > sections.length) target = sections.length;
    final item = sections.removeAt(from);
    if (target > from) target -= 1;
    if (target < 0 || target > sections.length) return;
    sections.insert(target, item);
    await replaceViewSections(sections);
  }

  Future<void> replaceViewSections(List<ViewSectionDef> sections) async {
    if (selectedView == null) return;
    await _persistViewLayout(
      ViewLayoutConfig.withSections(selectedView!.layoutConfig, sections),
    );
    notifyListeners();
  }

  Future<void> reorderViewTopicKeys(List<String> keys) async {
    if (selectedView == null) return;
    await _persistViewLayout(
      ViewLayoutConfig.withTopicOrder(selectedView!.layoutConfig, keys),
    );
    notifyListeners();
  }

  Future<void> reorderViewSectionKeys(List<String> keys) async {
    if (selectedView == null) return;
    // Keep section defs in sync with the new frame order (metadata preserved).
    final byName = {
      for (final s in sectionsForSelectedView()) s.name: s,
    };
    final defs = <ViewSectionDef>[];
    for (final key in keys) {
      if (!key.startsWith('section:')) continue;
      final name = key.substring('section:'.length);
      if (name.isEmpty) continue;
      final existing = byName[name];
      defs.add(
        (existing ?? ViewSectionDef(name: name)).copyWith(orderIndex: defs.length),
      );
    }
    var layout = ViewLayoutConfig.withSectionOrder(
      selectedView!.layoutConfig,
      keys,
    );
    if (defs.isNotEmpty) {
      layout = ViewLayoutConfig.withSections(layout, defs);
    }
    await _persistViewLayout(layout);
    notifyListeners();
  }

  Color? topicAccentForTask(Task task) {
    final hex = task.topicColor;
    if (hex == null || hex.isEmpty) return null;
    return TopicAppearance.colorFromHex(hex);
  }

  bool topicIsMain(Task task) => false;

  Color? sectionAccent(ViewSectionDef section) {
    final hex = section.colorHex;
    if (hex == null || hex.isEmpty) return null;
    return AppColors.tryParseHex(hex) ?? AppColors.colorFromHex(hex);
  }

  Future<void> createView({required String name}) async {
    if (workspaceId == null) return;
    final view = await _views.createView(workspaceId: workspaceId!, name: name);
    userViews = [...userViews, view];
    notifyListeners();
  }

  Future<void> renameView(AppView view, {required String name}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == view.name) return;
    final updated = await _views.updateView(view.id, name: trimmed);
    userViews = [
      for (final v in userViews) v.id == updated.id ? updated : v,
    ];
    if (selectedView?.id == updated.id) {
      selectedView = updated;
    }
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
    String? applyMode,
  }) async {
    if (workspaceId == null) return null;
    aiRunning = true;
    notifyListeners();
    try {
      final focusedFileId = DocumentEditorRegistry.activeFileId;
      final result = await _agent.run(
        prompt: prompt,
        workspaceId: workspaceId!,
        scope: {
          if (selectedTopic != null) 'topic_ids': [selectedTopic!.id],
          if (selectedDetail != null)
            'file_ids': selectedDetail!.files.map((f) => f.id).toList(),
        },
        hints: {
          if (focusedFileId != null) 'focused_file_id': focusedFileId,
        },
        applyMode: applyMode,
      );
      final changes = result['proposed_changes'];
      if (changes is List &&
          changes.any((c) => c is Map && c['review'] != null)) {
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
  }) async {
    return createTaskInView(sectionName: section, title: '');
  }

  Future<void> deleteTaskInView(Task task) async {
    await deleteTask(task, notify: true);
  }

  Future<void> pasteTasksInViewAfter({
    required List<String> lines,
    required String viewType,
    required String section,
    required int afterOrder,
  }) async {
    int? afterId;
    for (final line in lines) {
      final created = await createTaskInView(
        title: line,
        sectionName: section,
        afterTaskId: afterId,
        notify: false,
      );
      afterId = created.id;
    }
    notifyListeners();
  }

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
