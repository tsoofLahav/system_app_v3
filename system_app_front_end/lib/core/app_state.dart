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
import '../areas/files/data/topic_type.dart';
import '../areas/automations/automation_service.dart';
import '../areas/production_agent/agent_run_defaults.dart';
import '../areas/production_agent/agent_service.dart';
import '../areas/production_agent/ai_action.dart';
import '../areas/production_agent/ai_action_service.dart';
import '../areas/production_agent/agent_time_hints.dart';
import '../areas/production_agent/pending_review_service.dart';
import './services/api_service.dart';
import './services/bootstrap_service.dart';
import './services/image_service.dart';
import '../shared/utils/hardware_keyboard_guard.dart';
import '../areas/files/data/file_service.dart';
import '../areas/objects/data/object_service.dart';
import '../areas/objects/tags/object_tag_filter.dart';
import './services/tag_service.dart';
import '../areas/objects/data/task_service.dart';
import '../areas/files/data/topic_service.dart';
import '../areas/files/data/topic_type_service.dart';
import '../areas/objects/data/view_layout.dart';
import '../areas/objects/data/view_service.dart';
import '../areas/ux/bring_file/bring_file_catalog.dart';
import '../areas/ux/bring_file/brought_file_store.dart';
import '../areas/ux/layout/file_layouts.dart';
import '../areas/ux/layout/topic_file_slots.dart';
import '../areas/ux/shortcuts/shortcut_binding.dart';
import '../areas/ux/shortcuts/shortcut_bindings_store.dart';
import './platform/app_form_factor.dart';
import '../areas/ux/topic/topic_appearance.dart';
import '../areas/ui/app_colors.dart';

class TopicDetail {
  const TopicDetail({required this.topic, required this.files});

  final Topic topic;
  final List<AppFile> files;
}

class _TypeTemplateEdit {
  _TypeTemplateEdit({required this.topicId, required this.files});

  final int topicId;
  final Map<int, Map<String, dynamic>> files;
}

enum ViewDisplayMode { bySection, byTopic, flat }

class AppState extends ChangeNotifier {
  AppState() : _api = ApiService() {
    _bootstrap = BootstrapService(_api);
    _topics = TopicService(_api);
    _topicTypes = TopicTypeService(_api);
    _files = FileService(_api);
    _objects = ObjectService(_api);
    _views = ViewService(_api);
    _tasks = TaskService(_api);
    _tags = TagService(_api);
    _agent = AgentService(_api);
    _pendingReviews = PendingReviewService(_api);
    _automations = AutomationService(_api);
    _aiActions = AiActionService(_api);
    _images = ImageService(_api);
  }

  final ApiService _api;
  late final BootstrapService _bootstrap;
  late final TopicService _topics;
  late final TopicTypeService _topicTypes;
  late final FileService _files;
  late final ObjectService _objects;
  late final ViewService _views;
  late final TaskService _tasks;
  late final TagService _tags;
  late final AgentService _agent;
  late final PendingReviewService _pendingReviews;
  late final AutomationService _automations;
  late final AiActionService _aiActions;
  late final ImageService _images;

  AppLanguage _language = AppLanguage.en;
  bool loading = false;
  String? error;
  bool appReady = false;
  int? workspaceId;

  List<Topic> allTopics = [];
  List<TopicType> topicTypes = [];
  List<AppTag> allTags = [];
  List<AppView> userViews = [];
  List<AiAction> aiActions = [];
  List<Automation> automations = [];
  Topic? selectedTopic;
  TopicDetail? selectedDetail;
  bool topicDetailStale = false;

  bool isViewMode = false;
  bool viewPaneReady = false;

  /// Drag handles on sidebar topics and views — off until ⌘O or Preferences.
  bool sidebarReorderMode = false;
  String? selectedViewType;
  AppView? selectedView;
  List<ViewMembership> viewMemberships = [];
  ViewDisplayMode viewDisplayMode = ViewDisplayMode.bySection;

  /// Live task rows by id. File lists and views both read this map so a title,
  /// done flag, or description link is the same task everywhere.
  final Map<int, Task> tasksById = {};

  bool isArchiveMode = false;
  Topic? selectedArchiveTopic;
  ArchiveIndex archiveIndex = ArchiveIndex.empty;
  static const archivePageSize = 24;
  List<AppFile> archiveFilesForTopic = const [];
  final Map<int, List<String>> archiveHeadingTextsByFileId = {};
  final Map<int, String> archiveAgentTextByFileId = {};
  AppFile? selectedArchiveFile;
  String archiveSearchQuery = '';
  List<AppFile> archiveRemoteSearchResults = const [];
  var archiveBrowseHasMore = false;
  var archiveSearchHasMore = false;
  var archiveLoading = false;
  Timer? _archiveSearchDebounce;

  bool isDiagramMode = false;
  ObjectGraphData? objectGraph;
  final Set<int> diagramFilterTagIds = {};

  /// Objects map node tint: topic wash vs first-tag color.
  DiagramColorMode diagramColorMode = DiagramColorMode.byTopic;

  /// Isolated info objects stay off the map until the user opts in.
  var diagramShowUnconnected = false;
  var diagramLayoutEpoch = 0;
  final Map<int, List<Map<String, dynamic>>> descriptionLinksByFileId = {};
  int? pendingFocusObjectId;
  int? pendingFocusFileId;

  final Map<int, List<ObjectEmbed>> embedsByFileId = {};
  int? editingFileId;
  String? _automationNotice;
  bool aiRunning = false;
  bool archiveDeleteMode = false;
  final Set<int> archiveDeleteSelection = {};
  Map<String, dynamic>? pendingAgentReview;
  _TypeTemplateEdit? _typeTemplateEdit;

  /// Files visiting Home — still belong to their source topics, not Home.
  /// Order among Home files is [homeCanvasOrderIds], not this list alone.
  List<AppFile> broughtFiles = [];
  final Map<int, Topic> broughtTopics = {};

  /// Mixed Home canvas order (visits interleaved with Home files). Empty when
  /// there are no visits.
  List<int> homeCanvasOrderIds = [];
  final BroughtFileStore broughtFileStore = BroughtFileStore();

  /// File id whose lookalike pending dialog is currently open (anti double-open).
  int? _pendingReviewDialogFileId;

  bool tryBeginPendingReviewDialog(int fileId) {
    if (_pendingReviewDialogFileId == fileId) return false;
    if (_pendingReviewDialogFileId != null) return false;
    _pendingReviewDialogFileId = fileId;
    return true;
  }

  void endPendingReviewDialog(int fileId) {
    if (_pendingReviewDialogFileId == fileId) {
      _pendingReviewDialogFileId = null;
    }
  }

  bool isFileOnScreen(int fileId) {
    final topic = selectedTopic;
    final detail = selectedDetail;
    if (topic == null ||
        detail == null ||
        isViewMode ||
        isArchiveMode ||
        isDiagramMode) {
      return false;
    }
    if (isPhoneLayout) {
      return orderedFilesFor(topic, detail.files).any((f) => f.id == fileId);
    }
    return shownFilesFor(topic, detail.files).any((f) => f.id == fileId);
  }

  void toggleArchiveDeleteMode() {
    archiveDeleteMode = !archiveDeleteMode;
    if (!archiveDeleteMode) archiveDeleteSelection.clear();
    notifyListeners();
  }

  void toggleArchiveDeleteSelection(AppFile file) {
    if (archiveDeleteSelection.contains(file.id)) {
      archiveDeleteSelection.remove(file.id);
    } else {
      archiveDeleteSelection.add(file.id);
    }
    notifyListeners();
  }

  Future<void> deleteSelectedArchiveFiles() async {
    final ids = archiveDeleteSelection.toList();
    for (final id in ids) {
      await _files.deleteFile(id);
      archiveAgentTextByFileId.remove(id);
    }
    archiveDeleteSelection.clear();
    archiveDeleteMode = false;
    final topic = selectedArchiveTopic;
    await loadArchive();
    if (topic != null && _archiveIndexHasTopic(topic.id)) {
      await selectArchiveTopic(topic);
    } else {
      _leaveArchive();
    }
  }

  Future<void> deleteArchiveFile(AppFile file) async {
    archiveDeleteSelection
      ..clear()
      ..add(file.id);
    await deleteSelectedArchiveFiles();
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

  List<Topic> get activeTopics => [
    for (final topic in allTopics)
      if (!topic.isArchived && !topic.isTemplate) topic,
  ];

  List<Topic> get untypedTopics => [
    for (final topic in activeTopics)
      if (!topic.isMain && topic.topicTypeId == null) topic,
  ];

  List<Topic> topicsOfType(int typeId) => [
    for (final topic in activeTopics)
      if (!topic.isMain && topic.topicTypeId == typeId) topic,
  ];

  TopicType? topicTypeById(int? id) {
    if (id == null) return null;
    for (final type in topicTypes) {
      if (type.id == id) return type;
    }
    return null;
  }

  String topicTypeDisplayName(TopicType type) {
    if (language == AppLanguage.he && type.nameHe.trim().isNotEmpty) {
      return type.nameHe.trim();
    }
    return strings.topicTypeLabel(type.name);
  }

  String aiActionDisplayName(AiAction action) {
    if (language == AppLanguage.he && action.nameHe.trim().isNotEmpty) {
      return action.nameHe.trim();
    }
    return action.name;
  }

  String automationDisplayName(Automation automation) {
    if (language == AppLanguage.he && automation.nameHe.trim().isNotEmpty) {
      return automation.nameHe.trim();
    }
    return automation.name;
  }

  /// Origin line for a brought file: `{type} - {topic}{emoji}`, or just
  /// `{topic}{emoji}` when the source topic has no type.
  String broughtFileOriginLabel(Topic topic) {
    final type = topicTypeById(topic.topicTypeId);
    return TopicAppearance.broughtOriginLabel(
      topicName: topicDisplayName(topic),
      icon: topic.icon,
      typeDisplay: type == null ? null : topicTypeDisplayName(type),
    );
  }

  /// Object tags are freeform. Types live on `topic_types`, not as tags.
  List<AppTag> get objectTags =>
      objectTagsExcludingTopicTypes(tags: allTags, topicTypes: topicTypes);

  Future<void> initialize() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadLanguage();
      await _loadDiagramPrefs();
      await shortcutBindings.restore();
      shortcutRebuildListenable.notifyListeners();
      await _bootstrap.bootstrap();
      final status = await _bootstrap.status();
      workspaceId = status['workspace_id'] as int?;
      await _reloadAll();
      await _migrateImplicitSingleLayouts();
      await _restoreBroughtFile();
      await settleHardwareKeyboardForLaunch();
      appReady = true;
      await loadAiActions();
      await loadAutomations();
      if (selectedTopic == null && allTopics.isNotEmpty) {
        final home =
            allTopics.where((t) => t.isMain).firstOrNull ??
            activeTopics.firstOrNull ??
            allTopics.first;
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
    topicTypes = await _topicTypes.list(workspaceId: workspaceId);
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

  void toggleSidebarReorderMode() {
    sidebarReorderMode = !sidebarReorderMode;
    notifyListeners();
  }

  static const _languagePrefsKey = 'app_language';
  static const _fileLayoutAutoMigrationKey = 'migrated_file_layout_auto_v1';
  static const _diagramShowUnconnectedKey = 'diagram_show_unconnected';

  /// Old topics stored `single` as the create default. Treat that as [auto]
  /// once so 2/3+ files pick split / large-left until the user chooses.
  Future<void> _migrateImplicitSingleLayouts() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_fileLayoutAutoMigrationKey) == true) return;
    for (final topic in List<Topic>.from(allTopics)) {
      if (topic.fileLayout == FileLayouts.single || topic.fileLayout.isEmpty) {
        await updateTopic(topic, fileLayout: FileLayouts.auto);
      }
    }
    await prefs.setBool(_fileLayoutAutoMigrationKey, true);
  }

  Future<void> _persistLanguage(AppLanguage language) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languagePrefsKey, language.name);
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    _language = AppLanguage.fromStorage(prefs.getString(_languagePrefsKey));
  }

  Future<void> _loadDiagramPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    diagramShowUnconnected = prefs.getBool(_diagramShowUnconnectedKey) ?? false;
  }

  String topicDisplayName(Topic topic) => strings.displayTopicName(topic.name);

  /// Header / phone title. A type template is "Template for {type}", not the
  /// internal topic name.
  String topicHeadline(Topic topic) {
    if (!topic.isTemplate) return topicDisplayName(topic);
    final type = typeForTemplateTopic(topic);
    if (type == null) return strings['template'];
    return strings.templateForType(topicTypeDisplayName(type));
  }

  TopicType? typeForTemplateTopic(Topic topic) {
    if (!topic.isTemplate) return null;
    for (final type in topicTypes) {
      if (type.templateTopicId == topic.id) return type;
    }
    return null;
  }

  /// Opened from Preferences / the types list — Save and Cancel sit on a glass bar.
  bool get isEditingTypeTemplate {
    final id = selectedTopic?.id;
    return id != null && _typeTemplateEdit?.topicId == id;
  }

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
    final home =
        allTopics.where((t) => t.isMain).firstOrNull ??
        activeTopics.firstOrNull;
    if (home != null) await selectTopic(home);
  }

  Future<void> selectTopic(Topic topic) async {
    if (_typeTemplateEdit != null && topic.id != _typeTemplateEdit!.topicId) {
      _typeTemplateEdit = null;
    }
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
    final next = userViews.where((v) => v.type == viewType).firstOrNull;
    if (next?.id != selectedView?.id) viewMemberships = [];
    selectedView = next;
    viewPaneReady = selectedView != null;
    if (selectedView != null) {
      viewDisplayMode = _displayModeFromConfig(selectedView!.layoutConfig);
    }
    loading = true;
    notifyListeners();
    try {
      if (selectedView != null) {
        await _refreshViewMemberships();
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
    userViews = [for (final v in userViews) v.id == updated.id ? updated : v];
    selectedView = updated;
  }

  Future<void> selectArchiveTopic(Topic topic) async {
    isArchiveMode = true;
    isViewMode = false;
    isDiagramMode = false;
    selectedArchiveTopic = topic;
    _resetArchiveBrowse();
    notifyListeners();
    await _loadArchiveBrowsePage(append: false);
  }

  void _leaveArchive() {
    isArchiveMode = false;
    selectedArchiveTopic = null;
    selectedArchiveFile = null;
    _resetArchiveBrowse();
    notifyListeners();
  }

  void _resetArchiveBrowse() {
    archiveFilesForTopic = const [];
    archiveRemoteSearchResults = const [];
    archiveSearchQuery = '';
    archiveBrowseHasMore = false;
    archiveSearchHasMore = false;
    archiveLoading = false;
    archiveDeleteMode = false;
    archiveDeleteSelection.clear();
    selectedArchiveFile = null;
    _archiveSearchDebounce?.cancel();
  }

  bool _archiveIndexHasTopic(int topicId) {
    if (archiveIndex.daily?.topic.id == topicId) return true;
    return archiveIndex.topics.any((entry) => entry.topic.id == topicId);
  }

  List<AppFile> get displayArchiveFiles {
    final query = archiveSearchQuery.trim();
    if (query.isEmpty) return archiveFilesForTopic;
    final seen = <int>{};
    final out = <AppFile>[];
    for (final file in archiveFilesForTopic) {
      if (_archiveFileMatchesQuery(file, query) && seen.add(file.id)) {
        out.add(file);
      }
    }
    for (final file in archiveRemoteSearchResults) {
      if (seen.add(file.id)) out.add(file);
    }
    return out;
  }

  String archiveFileSearchLabel(AppFile file) {
    final title = fileDisplayName(file.name);
    final headings = archiveHeadingTextsByFileId[file.id] ?? const [];
    if (headings.isEmpty) return title;
    return '$title ${headings.join(' ')}';
  }

  bool _archiveFileMatchesQuery(AppFile file, String query) {
    return archiveFileSearchLabel(
      file,
    ).toLowerCase().contains(query.toLowerCase());
  }

  void onArchiveSearchQueryChanged(String query) {
    archiveSearchQuery = query;
    archiveRemoteSearchResults = const [];
    archiveSearchHasMore = false;
    notifyListeners();
    _archiveSearchDebounce?.cancel();
    if (query.trim().isEmpty) return;
    _archiveSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      unawaited(_fetchArchiveSearchPage(reset: true));
    });
  }

  Future<void> loadMoreArchiveContent() async {
    if (archiveLoading) return;
    if (archiveSearchQuery.trim().isNotEmpty) {
      if (!archiveSearchHasMore) return;
      await _fetchArchiveSearchPage(reset: false);
      return;
    }
    if (!archiveBrowseHasMore) return;
    await _loadArchiveBrowsePage(append: true);
  }

  Future<void> selectArchiveFile(AppFile file) async {
    selectedArchiveFile = file;
    notifyListeners();
    await _loadArchivePreviewForFile(file);
  }

  String? archiveAgentTextFor(int fileId) => archiveAgentTextByFileId[fileId];

  /// Expanded agent text for the shared read-only file preview. Never marker text.
  Future<String> loadPreviewAgentText(int fileId) async {
    try {
      return await _files.agentTextForFile(fileId);
    } catch (e) {
      error = e.toString();
      return '';
    }
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
      _pruneDiagramFilter();
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  void _pruneDiagramFilter() {
    final allowed = {for (final tag in objectTags) tag.id};
    diagramFilterTagIds.removeWhere((id) => !allowed.contains(id));
  }

  /// Persist map coordinates. Does not [notifyListeners] — the pane owns layout.
  Future<void> saveDiagramPositions(Map<int, Offset> positions) async {
    if (workspaceId == null || positions.isEmpty) return;
    await _objects.saveDiagramPositions(
      workspaceId: workspaceId!,
      positions: [
        for (final entry in positions.entries)
          (objectId: entry.key, x: entry.value.dx, y: entry.value.dy),
      ],
    );
    final graph = objectGraph;
    if (graph == null) return;
    objectGraph = ObjectGraphData(
      nodes: [
        for (final n in graph.nodes)
          if (positions.containsKey(n.objectId))
            n.copyWith(
              diagramX: positions[n.objectId]!.dx,
              diagramY: positions[n.objectId]!.dy,
            )
          else
            n,
      ],
      edges: graph.edges,
    );
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

  void setDiagramShowUnconnected(bool value) {
    if (diagramShowUnconnected == value) return;
    diagramShowUnconnected = value;
    notifyListeners();
    unawaited(_persistDiagramShowUnconnected(value));
  }

  /// Ask the objects map to throw away saved spots and arrange from the links.
  void requestDiagramRelayout() {
    diagramLayoutEpoch += 1;
    notifyListeners();
  }

  Future<void> _persistDiagramShowUnconnected(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_diagramShowUnconnectedKey, value);
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
    await _objects.createRelatedLink(embed.id, targetObjectId: targetObjectId);
    await loadEmbedsForFile(embed.fileId);
    await loadObjectGraph();
  }

  Future<void> removeObjectLink(ObjectEmbed embed, int linkId) async {
    await _objects.deleteLink(embed.id, linkId);
    await loadEmbedsForFile(embed.fileId);
  }

  Future<void> createDescriptionLink({
    required int hostObjectId,
    required int targetObjectId,
    required Map<String, dynamic> anchor,
    String? label,
    bool alsoRelated = false,
  }) async {
    await _objects.createDescriptionLink(
      hostObjectId,
      targetObjectId: targetObjectId,
      anchor: anchor,
      label: label,
    );
    if (alsoRelated) {
      await _objects.createRelatedLink(
        hostObjectId,
        targetObjectId: targetObjectId,
      );
    }
    final fileId = anchor['file_id'] as int?;
    if (fileId != null) {
      await loadDescriptionLinksForFile(fileId);
    }
    final hostFileId = embedsByFileId.entries
        .where((e) => e.value.any((o) => o.id == hostObjectId))
        .map((e) => e.key)
        .firstOrNull;
    if (hostFileId != null && hostFileId != fileId) {
      await loadDescriptionLinksForFile(hostFileId);
    }
    if (hostFileId != null) {
      await loadEmbedsForFile(hostFileId);
    }
    if (alsoRelated) {
      await loadObjectGraph();
    }
  }

  Future<void> createTaskDescriptionLink({
    required int taskId,
    required int targetObjectId,
    required Map<String, dynamic> anchor,
    String? label,
  }) async {
    await _tasks.createDescriptionLink(
      taskId,
      targetObjectId: targetObjectId,
      anchor: anchor,
      label: label,
    );
    final fileId = anchor['file_id'] as int?;
    if (fileId != null) {
      await loadDescriptionLinksForFile(fileId);
    }
    await refreshOpenTaskSurfaces(notify: true);
  }

  Future<List<Map<String, dynamic>>> listObjectLinks(int objectId) {
    return _objects.listLinks(objectId);
  }

  Future<void> loadDescriptionLinksForFile(int fileId) async {
    if (fileId <= 0) return;
    try {
      descriptionLinksByFileId[fileId] = await _objects
          .listFileDescriptionLinks(fileId);
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
  Future<void> openObjectInFile({required int objectId, int? fileId}) async {
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

  int? takePendingFocusFileId() {
    final id = pendingFocusFileId;
    pendingFocusFileId = null;
    return id;
  }

  Future<void> loadArchive() async {
    final entries = <ArchiveTopicEntry>[];
    ArchiveTopicEntry? daily;
    try {
      for (final topic in allTopics) {
        final page = await _files.listArchivedForTopic(topic.id, limit: 0);
        if (page.total == 0) continue;
        final entry = ArchiveTopicEntry(
          topic: topic,
          archivedFileCount: page.total,
        );
        if (topic.isMain) {
          daily = entry;
        } else {
          entries.add(entry);
        }
      }
      archiveIndex = ArchiveIndex(daily: daily, topics: entries);
    } catch (e) {
      error = e.toString();
    }
    notifyListeners();
  }

  void _mergeArchiveHeadings(Map<int, List<String>> incoming) {
    archiveHeadingTextsByFileId.addAll(incoming);
  }

  Future<void> _loadArchiveBrowsePage({required bool append}) async {
    final topic = selectedArchiveTopic;
    if (topic == null) return;
    archiveLoading = true;
    notifyListeners();
    try {
      final offset = append ? archiveFilesForTopic.length : 0;
      final page = await _files.listArchivedForTopic(
        topic.id,
        limit: archivePageSize,
        offset: offset,
      );
      archiveFilesForTopic = append
          ? [...archiveFilesForTopic, ...page.files]
          : page.files;
      _mergeArchiveHeadings(page.headerTextsByFileId);
      archiveBrowseHasMore = page.hasMore;
      if (selectedArchiveFile == null && archiveFilesForTopic.isNotEmpty) {
        await selectArchiveFile(archiveFilesForTopic.first);
        return;
      }
    } catch (e) {
      error = e.toString();
    } finally {
      archiveLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchArchiveSearchPage({required bool reset}) async {
    final topic = selectedArchiveTopic;
    final query = archiveSearchQuery.trim();
    if (topic == null || query.isEmpty) return;
    archiveLoading = true;
    notifyListeners();
    try {
      final offset = reset ? 0 : archiveRemoteSearchResults.length;
      final page = await _files.listArchivedForTopic(
        topic.id,
        limit: archivePageSize,
        offset: offset,
        query: query,
      );
      _mergeArchiveHeadings(page.headerTextsByFileId);
      archiveRemoteSearchResults = reset
          ? page.files
          : [...archiveRemoteSearchResults, ...page.files];
      archiveSearchHasMore = page.hasMore;
    } catch (e) {
      error = e.toString();
    } finally {
      archiveLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadArchivePreviewForFile(AppFile file) async {
    if (archiveAgentTextByFileId.containsKey(file.id)) return;
    final text = await loadPreviewAgentText(file.id);
    archiveAgentTextByFileId[file.id] = text;
    if (selectedArchiveFile?.id == file.id) notifyListeners();
  }

  Future<void> unarchiveFile(AppFile file) async {
    await _files.updateFile(file.id, {'archived_at': null});
    archiveAgentTextByFileId.remove(file.id);
    final topic = selectedArchiveTopic;
    if (selectedDetail?.topic.id == file.topicId) {
      await _refreshTopicFiles(selectedDetail!.topic);
    }
    await loadArchive();
    if (topic != null && _archiveIndexHasTopic(topic.id)) {
      await selectArchiveTopic(topic);
    } else {
      _leaveArchive();
    }
  }

  /// Every file of the topic in the one order that decides placement.
  /// On Home this includes visiting files, interleaved with Home's own.
  List<AppFile> orderedFilesFor(Topic topic, List<AppFile> files) {
    if (!topic.isMain || broughtFiles.isEmpty) return orderedFiles(files);
    return mergeHomeCanvasFiles(
      homeFiles: files,
      visits: broughtFiles,
      storedOrder: homeCanvasOrderIds,
    );
  }

  /// The files the topic's layout has room for.
  List<AppFile> shownFilesFor(Topic topic, List<AppFile> files) =>
      shownFiles(orderedFilesFor(topic, files), layoutFor(topic));

  /// The files past the last slot — off screen until the topic is rearranged.
  List<AppFile> hiddenFilesFor(Topic topic, List<AppFile> files) =>
      hiddenFiles(orderedFilesFor(topic, files), layoutFor(topic));

  bool isBroughtFile(int fileId) =>
      broughtFiles.any((file) => file.id == fileId);

  /// Visiting panes only exist on Home. The same file on its own topic is not a visit.
  bool isBroughtFileOnCanvas(Topic topic, int fileId) =>
      topic.isMain && isBroughtFile(fileId);

  Topic canvasTopicFor(Topic openTopic, AppFile file) =>
      broughtTopics[file.id] ?? openTopic;

  AppFile? broughtFileById(int fileId) =>
      broughtFiles.where((file) => file.id == fileId).firstOrNull;

  String layoutFor(Topic topic) => topic.fileLayout;

  Future<void> setLayoutForTopic(Topic topic, String layoutId) async {
    final fileCount = orderedFilesFor(
      topic,
      selectedDetail?.topic.id == topic.id
          ? selectedDetail!.files
          : const <AppFile>[],
    ).length;
    final stored = FileLayouts.storedLayoutId(layoutId, fileCount);
    if (topic.fileLayout == stored) return;
    await updateTopic(topic, fileLayout: stored);
  }

  Future<void> createTopic({
    required String name,
    int? topicTypeId,
    int? cloneFromTopicId,
    String? icon,
    String? color,
    List<int>? tagIds,
  }) async {
    if (workspaceId == null) return;
    final topic = await _topics.createTopic(
      name: name,
      workspaceId: workspaceId!,
      icon: icon,
      color: color,
      topicTypeId: topicTypeId,
      cloneFromTopicId: cloneFromTopicId,
      tagIds: tagIds,
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
    int? topicTypeId,
    bool clearTopicType = false,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (icon != null) body['icon'] = icon;
    if (color != null) body['color'] = color;
    if (fileLayout != null) body['file_layout'] = fileLayout;
    if (clearTopicType) {
      body['topic_type_id'] = null;
    } else if (topicTypeId != null) {
      body['topic_type_id'] = topicTypeId;
    }
    final updated = await _topics.updateTopic(topic.id, body);
    allTopics = allTopics.map((t) => t.id == updated.id ? updated : t).toList();
    _sortTopics();
    if (selectedTopic?.id == updated.id) selectedTopic = updated;
    if (selectedDetail?.topic.id == updated.id) {
      selectedDetail = TopicDetail(
        topic: updated,
        files: selectedDetail!.files,
      );
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

  Future<void> reorderTopics(List<Topic> ordered) async {
    await Future.wait([
      for (var i = 0; i < ordered.length; i++)
        _topics.updateTopic(ordered[i].id, {'order_index': i}),
    ]);
    final nextIndex = <int, int>{
      for (var i = 0; i < ordered.length; i++) ordered[i].id: i,
    };
    allTopics = [
      for (final topic in allTopics)
        if (nextIndex.containsKey(topic.id))
          topic.copyWith(orderIndex: nextIndex[topic.id])
        else
          topic,
    ];
    _sortTopics();
    notifyListeners();
  }

  void _sortTopics() {
    allTopics.sort((a, b) {
      final byOrder = a.orderIndex.compareTo(b.orderIndex);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
  }

  Future<void> duplicateTopic(Topic topic) async {
    await createTopic(
      name: '${topic.name} copy',
      topicTypeId: topic.topicTypeId,
      cloneFromTopicId: topic.id,
      icon: topic.icon,
      color: topic.color,
      tagIds: [for (final tag in topic.tags) tag.id],
    );
  }

  Future<List<AppFile>> filesForTopic(int topicId) =>
      _files.listFilesForTopic(topicId);

  Future<Topic> loadTopic(int id) => _topics.getTopic(id);

  Future<List<TopicTaskList>> listTaskListsForTopic(int topicId) =>
      _topics.listTaskLists(topicId);

  Future<List<AppFile>> templateFilesForType(TopicType type) async {
    final templateId = type.templateTopicId;
    if (templateId == null) return const [];
    return filesForTopic(templateId);
  }

  // --- Topic types ----------------------------------------------------------

  Future<void> loadTopicTypes() async {
    if (workspaceId == null) return;
    topicTypes = await _topicTypes.list(workspaceId: workspaceId);
    notifyListeners();
  }

  Future<TopicType> createTopicType({
    required String name,
    required String nameHe,
  }) async {
    if (workspaceId == null) {
      throw StateError('workspace not ready');
    }
    final type = await _topicTypes.create(
      workspaceId: workspaceId!,
      name: name,
      nameHe: nameHe,
    );
    topicTypes = [...topicTypes, type];
    notifyListeners();
    return type;
  }

  Future<void> updateTopicType(
    TopicType type,
    Map<String, dynamic> changes,
  ) async {
    if (changes.isEmpty) return;
    final updated = await _topicTypes.update(type.id, changes);
    topicTypes = [
      for (final row in topicTypes)
        if (row.id == updated.id) updated else row,
    ];
    _sortTopicTypes();
    notifyListeners();
  }

  Future<void> openTypeTemplate(TopicType type) async {
    final topic = await _topicTypes.ensureTemplate(type.id);
    await loadTopicTypes();
    if (!allTopics.any((row) => row.id == topic.id)) {
      allTopics = [...allTopics, topic];
    } else {
      allTopics = [
        for (final row in allTopics)
          if (row.id == topic.id) topic else row,
      ];
    }
    await selectTopic(topic);
    _typeTemplateEdit = _TypeTemplateEdit(
      topicId: topic.id,
      files: await _snapshotTypeTemplateFiles(topic.id),
    );
    notifyListeners();
  }

  Future<void> saveTypeTemplateEdit() async {
    await DocumentEditorRegistry.flushActive();
    _typeTemplateEdit = null;
    await goHome();
  }

  Future<void> cancelTypeTemplateEdit() async {
    await DocumentEditorRegistry.flushActive();
    final session = _typeTemplateEdit;
    if (session != null) {
      await _restoreTypeTemplateFiles(session);
      _typeTemplateEdit = null;
    }
    await goHome();
  }

  Future<Map<int, Map<String, dynamic>>> _snapshotTypeTemplateFiles(
    int topicId,
  ) async {
    final files = await filesForTopic(topicId);
    final snaps = <int, Map<String, dynamic>>{};
    for (final file in files) {
      final snap = await snapshotFileForAutomation(file.id);
      snap['name'] = file.name;
      snap['order_index'] = file.orderIndex;
      snaps[file.id] = snap;
    }
    return snaps;
  }

  Future<void> _restoreTypeTemplateFiles(_TypeTemplateEdit session) async {
    final live = await filesForTopic(session.topicId);
    for (final file in live) {
      final snap = session.files[file.id];
      if (snap == null) {
        await _files.deleteFile(file.id);
        embedsByFileId.remove(file.id);
        continue;
      }
      final restored = await applyFileSnippet(file.id, snap);
      await updateFile(restored, {
        'name': snap['name'],
        'order_index': snap['order_index'],
      }, notify: false);
    }
  }

  Future<void> reorderTopicTypes(List<TopicType> ordered) async {
    topicTypes = [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(orderIndex: i),
    ];
    notifyListeners();
    await Future.wait([
      for (var i = 0; i < ordered.length; i++)
        _topicTypes.update(ordered[i].id, {'order_index': i}),
    ]);
  }

  void _sortTopicTypes() {
    topicTypes.sort((a, b) {
      final byOrder = a.orderIndex.compareTo(b.orderIndex);
      return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
    });
  }

  Future<void> deleteTopicType(TopicType type) async {
    await _topicTypes.delete(type.id);
    topicTypes = topicTypes.where((t) => t.id != type.id).toList();
    notifyListeners();
  }

  List<Automation> automationsForType(int typeId) => [
    for (final automation in automations)
      if (AutomationScope.kindOf(automation.scope) ==
              AutomationScope.topicType &&
          AutomationScope.typeIdOf(automation.scope) == typeId)
        automation,
  ];

  List<AiAction> aiActionsForType(int? typeId) => [
    for (final action in aiActions)
      if (action.topicTypeId == typeId) action,
  ];

  // --- Saved AI actions: prompts on buttons ---------------------------------

  /// Actions with a seat on the AI bar, in slot order, for what is open.
  List<AiAction> get barAiActions {
    final visits = _aiActionVisitIds;
    final pinned = [
      for (final action in aiActions)
        if (action.isOnBar &&
            action.visibleIn(
              openTopicId: selectedTopic?.id,
              openTypeId: selectedTopic?.topicTypeId,
              visitingTopicIds: visits.topicIds,
              visitingTypeIds: visits.typeIds,
            ))
          action,
    ]..sort((a, b) => a.barSlot!.compareTo(b.barSlot!));
    return pinned;
  }

  /// Globals plus actions matching the open topic, its type, or a visiting file.
  List<AiAction> get visibleAiActions {
    final visits = _aiActionVisitIds;
    return [
      for (final action in aiActions)
        if (action.visibleIn(
          openTopicId: selectedTopic?.id,
          openTypeId: selectedTopic?.topicTypeId,
          visitingTopicIds: visits.topicIds,
          visitingTypeIds: visits.typeIds,
        ))
          action,
    ];
  }

  ({Set<int> topicIds, Set<int> typeIds}) get _aiActionVisitIds {
    final open = selectedTopic;
    if (open == null || !open.isMain) {
      return (topicIds: <int>{}, typeIds: <int>{});
    }
    final topicIds = <int>{};
    final typeIds = <int>{};
    for (final file in broughtFiles) {
      final source = canvasTopicFor(open, file);
      topicIds.add(source.id);
      final typeId = source.topicTypeId;
      if (typeId != null) typeIds.add(typeId);
    }
    return (topicIds: topicIds, typeIds: typeIds);
  }

  AiAction? aiActionInSlot(int slot) {
    for (final action in aiActions) {
      if (action.barSlot == slot) return action;
    }
    return null;
  }

  /// The lowest bar slot nobody holds, or null when all six are taken.
  int? get firstFreeAiBarSlot {
    final taken = {
      for (final action in aiActions)
        if (action.isOnBar) action.barSlot!,
    };
    for (var slot = 1; slot <= aiBarSlotCount; slot++) {
      if (!taken.contains(slot)) return slot;
    }
    return null;
  }

  Future<void> loadAiActions() async {
    if (workspaceId == null) return;
    aiActions = await _aiActions.list(workspaceId: workspaceId);
    notifyListeners();
  }

  Future<AiAction> createAiAction({
    required String name,
    required String nameHe,
    required String prompt,
    required String applyMode,
    String icon = '',
    int? barSlot,
    int? topicTypeId,
    int? topicId,
  }) async {
    if (workspaceId == null) {
      throw StateError('workspace not ready');
    }
    final action = await _aiActions.create(
      workspaceId: workspaceId!,
      name: name,
      nameHe: nameHe,
      prompt: prompt,
      applyMode: applyMode,
      icon: icon,
      barSlot: barSlot,
      topicTypeId: topicTypeId,
      topicId: topicId,
    );
    // A new pin takes its slot from whoever had it, so reload rather than
    // append — the other rows changed too.
    if (barSlot != null) {
      await loadAiActions();
      return aiActions.firstWhere(
        (a) => a.id == action.id,
        orElse: () => action,
      );
    }
    aiActions = [...aiActions, action];
    notifyListeners();
    return action;
  }

  /// Reloads rather than patching the list, because a change of seat moves
  /// whoever held it too.
  Future<void> updateAiAction(
    AiAction action,
    Map<String, dynamic> changes,
  ) async {
    if (changes.isEmpty) return;
    await _aiActions.update(action.id, changes);
    await loadAiActions();
  }

  /// Gives an action a bar slot, or takes it off the bar with `slot: null`.
  /// Whoever held that slot goes back to the menu (the server decides).
  Future<void> setAiActionSlot(AiAction action, {int? slot}) async {
    await _aiActions.update(action.id, {'bar_slot': slot});
    await loadAiActions();
  }

  Future<void> setAiActionBarOrder(List<int> orderedIds) async {
    if (workspaceId == null) return;
    aiActions = await _aiActions.setBarOrder(
      workspaceId: workspaceId!,
      orderedIds: orderedIds,
    );
    notifyListeners();
  }

  Future<void> deleteAiAction(AiAction action) async {
    await _aiActions.delete(action.id);
    aiActions = aiActions.where((a) => a.id != action.id).toList();
    notifyListeners();
  }

  /// Runs a saved action on what is open right now — the same scope and hints
  /// the agent dialog sends.
  Future<Map<String, dynamic>> runAiAction(
    AiAction action, {
    String? selectedText,
  }) async {
    aiRunning = true;
    notifyListeners();
    try {
      await DocumentEditorRegistry.flushActive();
      final result = await _aiActions.run(
        action.id,
        scope: agentRunScope(),
        hints: agentRunHints(selectedText: selectedText),
      );
      final changes = result['proposed_changes'];
      if (changes is List &&
          changes.any((c) => c is Map && c['review'] != null)) {
        pendingAgentReview = Map<String, dynamic>.from(result);
      }
      return result;
    } finally {
      aiRunning = false;
      notifyListeners();
    }
  }

  // --- Automations: scope, trigger, a series of steps -----------------------

  Future<void> loadAutomations() async {
    if (workspaceId == null) return;
    automations = await _automations.list(workspaceId: workspaceId);
    notifyListeners();
  }

  Future<Automation> createAutomation({
    required String name,
    required String nameHe,
    required Map<String, dynamic> scope,
    required Map<String, dynamic> trigger,
    required List<Map<String, dynamic>> steps,
    String? schedule,
    String timezone = 'UTC',
    bool enabled = true,
  }) async {
    if (workspaceId == null) {
      throw StateError('workspace not ready');
    }
    final automation = await _automations.create(
      workspaceId: workspaceId!,
      name: name,
      nameHe: nameHe,
      scope: scope,
      trigger: trigger,
      steps: steps,
      schedule: schedule,
      timezone: timezone,
      enabled: enabled,
    );
    automations = [...automations, automation];
    notifyListeners();
    return automation;
  }

  Future<void> updateAutomation(
    Automation automation,
    Map<String, dynamic> changes,
  ) async {
    if (changes.isEmpty) return;
    final saved = await _automations.update(automation.id, changes);
    automations = [for (final a in automations) a.id == saved.id ? saved : a];
    notifyListeners();
  }

  Future<void> deleteAutomation(Automation automation) async {
    await _automations.delete(automation.id);
    automations = automations.where((a) => a.id != automation.id).toList();
    notifyListeners();
  }

  /// Run it now, on its stored scope — what the clock would have done.
  Future<Map<String, dynamic>> runAutomationNow(Automation automation) async {
    aiRunning = true;
    notifyListeners();
    try {
      await DocumentEditorRegistry.flushActive();
      return await _automations.run(automation.id);
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
    if (topic.isMain && broughtFiles.isNotEmpty) {
      final canvas = orderedFilesFor(topic, existing);
      homeCanvasOrderIds = [file.id, for (final placed in canvas) placed.id];
      await _persistBroughtFileLayout();
    }
    await _refreshTopicFiles(topic);
    pendingFocusFileId = file.id;
    notifyListeners();
    return file;
  }

  Future<void> updateFile(
    AppFile file,
    Map<String, dynamic> body, {
    bool notify = true,
  }) async {
    final updated = await _files.updateFile(file.id, body);
    _patchFileInDetail(updated);
    final broughtIndex = broughtFiles.indexWhere((f) => f.id == updated.id);
    if (broughtIndex >= 0) {
      broughtFiles = [
        for (var i = 0; i < broughtFiles.length; i++)
          i == broughtIndex ? updated : broughtFiles[i],
      ];
    }
    // Silent document autosaves must not notify — MaterialApp's Consumer and
    // other listeners rebuilding mid-keystroke desync HardwareKeyboard.
    if (notify) notifyListeners();
  }

  Future<void> archiveFile(AppFile file) async {
    await _files.updateFile(file.id, {
      'archived_at': DateTime.now().toUtc().toIso8601String(),
    });
    if (isBroughtFile(file.id)) {
      await dismissBroughtFile(file.id);
    }
    if (selectedDetail != null) {
      await _refreshTopicFiles(selectedDetail!.topic);
    }
    await loadArchive();
  }

  Future<void> deleteFile(AppFile file) async {
    await _files.deleteFile(file.id);
    if (isBroughtFile(file.id)) {
      await dismissBroughtFile(file.id);
    }
    if (selectedDetail != null) {
      await _refreshTopicFiles(selectedDetail!.topic);
    }
    await loadArchive();
  }

  /// A throwaway file for the fill-file snippet editor. Not added to the open topic.
  Future<AppFile> createScratchFile({
    required int topicId,
    required String name,
  }) async {
    final file = await _files.createFile(
      topicId: topicId,
      name: name,
      orderIndex: 9999,
      meta: const {'automation_scratch': true},
    );
    await loadEmbedsForFile(file.id, notify: false);
    pendingFocusFileId = file.id;
    return file;
  }

  Future<AppFile> applyFileSnippet(
    int fileId,
    Map<String, dynamic> snapshot, {
    bool append = false,
  }) async {
    final objects = snapshot['objects'];
    final file = await _files.applySnippet(
      fileId,
      documentJson: snapshot['document_json'] as String? ?? '',
      objects: [
        if (objects is List)
          for (final row in objects)
            if (row is Map) Map<String, dynamic>.from(row),
      ],
      append: append,
    );
    await loadEmbedsForFile(file.id, notify: false);
    return file;
  }

  Future<Map<String, dynamic>> snapshotFileForAutomation(int fileId) async {
    await DocumentEditorRegistry.flushActive();
    final file = await _files.getFile(fileId);
    final embeds = await loadEmbedsForFile(fileId, notify: false);
    return {
      'document_json': file.documentJson,
      'objects': [for (final embed in embeds) _automationObjectSnapshot(embed)],
    };
  }

  Future<void> discardScratchFile(int fileId) async {
    try {
      await _files.deleteFile(fileId);
    } catch (_) {}
    embedsByFileId.remove(fileId);
    descriptionLinksByFileId.remove(fileId);
  }

  Map<String, dynamic> _automationObjectSnapshot(ObjectEmbed embed) {
    return {
      'id': embed.id,
      'type': embed.type,
      'sort_key': embed.sortKey,
      if (embed.payload != null) 'payload': embed.payload,
      if (embed.information != null) 'information': embed.information,
      if (embed.type == 'task_list')
        'task_list': {
          'title': embed.taskListTitle,
          'tasks': [
            for (final task in embed.tasks ?? const <Task>[])
              {
                'title': task.title,
                'status': task.status,
                if (task.dueDate != null) 'due_date': task.dueDate,
                'list_order_index': task.listOrderIndex,
              },
          ],
        },
    };
  }

  Future<void> _refreshTopicFiles(Topic topic) async {
    final files = await _files.listFilesForTopic(topic.id);
    // Prefer the topic already in state. Callers often hand in a snapshot from
    // when a dialog opened; using that here would undo a layout (or rename)
    // that finished just before this refresh.
    final fresh =
        allTopics.where((t) => t.id == topic.id).firstOrNull ??
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
      files: selectedDetail!.files
          .map((f) => f.id == file.id ? file : f)
          .toList(),
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
    _ingestTasks([for (final embed in embeds) ...?embed.tasks]);
    try {
      descriptionLinksByFileId[fileId] = await _objects
          .listFileDescriptionLinks(fileId);
    } catch (_) {
      // Older backends without description-links still load embeds.
    }
    if (notify) notifyListeners();
    return embeds;
  }

  Future<AppFile> reloadFile(int fileId, {bool notify = true}) async {
    final updated = await _files.getFile(fileId);
    _patchFileInDetail(updated);
    if (notify) notifyListeners();
    return updated;
  }

  Future<void> deleteObjectEmbed(int objectId) async {
    try {
      await _objects.deleteEmbed(objectId);
    } on ApiException catch (e) {
      // Already gone (e.g. file PATCH purged the orphan first).
      if (e.statusCode != 404) rethrow;
    }
    await _reloadEmbedsForOpenFiles();
    // Diagram lists every info row — refresh so deleted nodes disappear.
    if (objectGraph != null) {
      await loadObjectGraph();
    }
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
    // Patch cache first so a remount never re-seeds from a stale payload while
    // the network round-trip is in flight (same pattern as [updateInfoObject]).
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
    try {
      await _api.patch('/objects/$objectId', {'payload': payload});
    } on ApiException catch (e) {
      // Late write after delete (empty graph exit, prune, etc.).
      if (e.statusCode == 404) return;
      rethrow;
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
    // Silent — the file editor reloads the document and focuses the new
    // object itself. Notifying here rebuilds Super Editor mid-handoff and
    // breaks the IME (one letter then stuck).
    await loadEmbedsForFile(file.id, notify: false);
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
    _ingestTask(task);
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
    _applyViewMemberships(
      await _views.replaceMemberships(selectedView!.id, memberships),
    );
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
    for (final m in viewMemberships) {
      final isTarget = m.taskId == taskId;
      memberships.add(
        (isTarget
                ? m.copyWith(
                    sectionName: sectionName,
                    sectionFlag: sectionFlag,
                    topicKey: topicKey,
                    clearSection: clearSection,
                    clearTopic: clearTopic,
                  )
                : m)
            .toReplaceJson(),
      );
    }
    await reorderViewMemberships(memberships, notify: notify);
  }

  Future<List<ViewMembership>> loadTaskMemberships(int taskId) async {
    final rows = await _tasks.getTaskMemberships(taskId);
    return rows.map((e) => ViewMembership.fromJson(e)).toList();
  }

  /// A task belongs to at most one view — [viewId] replaces any previous one.
  Future<void> setTaskView(int taskId, int? viewId) =>
      setTaskViews([taskId], viewId);

  /// Same as [setTaskView] for every id; one notify at the end.
  Future<void> setTaskViews(Iterable<int> taskIds, int? viewId) async {
    final ids = <int>{...taskIds};
    if (ids.isEmpty) return;
    final previousIds = <int>{};
    var wrote = false;
    for (final taskId in ids) {
      final existing = await loadTaskMemberships(taskId);
      previousIds.addAll(existing.map((m) => m.viewId));
      if (viewId == null) {
        if (existing.isEmpty) continue;
        await _tasks.replaceTaskMemberships(taskId, const []);
        wrote = true;
        continue;
      }
      final keep = existing.where((m) => m.viewId == viewId).firstOrNull;
      if (existing.length == 1 && keep != null) continue;
      await _tasks.replaceTaskMemberships(taskId, [
        {
          'view_id': viewId,
          'section_name': keep?.sectionName,
          'order_index': keep?.orderIndex ?? 0,
          'topic_order_index': keep?.topicOrderIndex ?? 0,
          'section_flag': keep?.sectionFlag,
          'topic_key': keep?.topicKey,
        },
      ]);
      previousIds.add(viewId);
      wrote = true;
    }
    if (!wrote) return;
    if (isViewMode &&
        selectedView != null &&
        previousIds.contains(selectedView!.id)) {
      await _refreshViewMemberships();
    }
    notifyListeners();
  }

  /// Apply view → section → topic → list on the view page Place dialog.
  Future<void> placeViewTasks({
    required List<int> taskIds,
    required int? viewId,
    String? sectionName,
    String? sectionFlag,
    bool uncategorized = false,
    String? topicKey,
    bool noTopic = false,
    int? taskListId,
    bool noList = false,
  }) async {
    final ids = [...taskIds];
    if (ids.isEmpty) return;

    await setTaskViews(ids, viewId);
    if (viewId != null) {
      for (final taskId in ids) {
        final existing = await loadTaskMemberships(taskId);
        final keep = existing.where((m) => m.viewId == viewId).firstOrNull;
        if (keep == null) continue;
        await _tasks.replaceTaskMemberships(taskId, [
          {
            'view_id': viewId,
            'section_name': uncategorized ? null : sectionName,
            'order_index': keep.orderIndex,
            'topic_order_index': keep.topicOrderIndex,
            'section_flag': uncategorized ? null : sectionFlag,
            'topic_key': noTopic ? null : topicKey,
          },
        ]);
      }
    }

    for (final taskId in ids) {
      final current = viewTasks.where((t) => t.id == taskId).firstOrNull;
      if (noList || noTopic) {
        if (current?.taskListId != null) {
          await clearTaskHomeList(taskId);
        }
        continue;
      }
      if (taskListId == null) continue;
      if (current?.taskListId == taskListId) continue;
      await assignViewTaskToList(
        current ?? Task(id: taskId, title: '', status: 'active'),
        taskListId,
      );
    }

    if (isViewMode && selectedView != null) {
      await _refreshViewMemberships();
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
    // Patch cache *before* the network round-trip so a remount during drag/drop
    // never re-seeds from stale empty title/body.
    patchInfoObjectCache(embed, title: title, body: body, spans: spans);
    await _api.patch('/information/${embed.informationId}', {
      'title': title,
      'body': body,
      'metadata': {'spans': spans ?? []},
    });
    if (notify) {
      await loadEmbedsForFile(embed.fileId);
    }
  }

  /// Synchronous in-memory update used by info editors before structural rebuild.
  void patchInfoObjectCache(
    ObjectEmbed embed, {
    required String title,
    required String body,
    List<Map<String, dynamic>>? spans,
  }) {
    final list = embedsByFileId[embed.fileId];
    if (list == null) return;
    final i = list.indexWhere((e) => e.id == embed.id);
    if (i < 0) return;
    final current = list[i];
    final prevInfo = current.information ?? const <String, dynamic>{};
    final prevMeta = prevInfo['metadata'];
    final meta = prevMeta is Map
        ? Map<String, dynamic>.from(prevMeta)
        : <String, dynamic>{};
    meta['spans'] = spans ?? [];
    embedsByFileId[embed.fileId] = [
      for (var j = 0; j < list.length; j++)
        j == i
            ? current.copyWith(
                information: {
                  ...prevInfo,
                  'title': title,
                  'body': body,
                  'metadata': meta,
                },
              )
            : list[j],
    ];
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
    _patchCachedTask(task.id, status: task.isDone ? 'active' : 'done');
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
    _patchCachedTask(task.id, title: title);
    if (notify) notifyListeners();
  }

  Task? taskById(int id) => tasksById[id];

  Task hydrateTask(Task task) => tasksById[task.id] ?? task;

  Task? taskForMembership(ViewMembership membership) {
    final id = membership.taskId;
    if (id != null) {
      final cached = tasksById[id];
      if (cached != null) return cached;
    }
    if (membership.task != null) return Task.fromJson(membership.task!);
    return null;
  }

  void _ingestTask(Task task) {
    tasksById[task.id] = task;
  }

  void _ingestTasks(Iterable<Task> tasks) {
    for (final task in tasks) {
      _ingestTask(task);
    }
  }

  void _dropCachedTask(int taskId) {
    tasksById.remove(taskId);
  }

  void _ingestMembershipTasks() {
    for (final membership in viewMemberships) {
      if (membership.task == null) continue;
      _ingestTask(Task.fromJson(membership.task!));
    }
  }

  void _applyViewMemberships(List<ViewMembership> rows) {
    viewMemberships = rows;
    _ingestMembershipTasks();
  }

  Future<void> _refreshViewMemberships() async {
    if (selectedView == null) return;
    _applyViewMemberships(await _views.listMemberships(selectedView!.id));
  }

  void _patchCachedTask(
    int taskId, {
    String? title,
    String? status,
    List<Map<String, dynamic>>? descriptionLinks,
    int? taskListId,
    String? taskListTitle,
  }) {
    final prev = tasksById[taskId];
    final next =
        (prev ??
                Task(
                  id: taskId,
                  title: title ?? '',
                  status: status ?? 'active',
                ))
            .copyWith(
              title: title,
              status: status,
              descriptionLinks: descriptionLinks,
              taskListId: taskListId,
              taskListTitle: taskListTitle,
            );
    _ingestTask(next);
    for (final entry in embedsByFileId.entries.toList()) {
      final embeds = entry.value;
      var changed = false;
      final patched = <ObjectEmbed>[];
      for (final embed in embeds) {
        final tasks = embed.tasks;
        if (tasks == null) {
          patched.add(embed);
          continue;
        }
        var taskChanged = false;
        final newTasks = <Task>[];
        for (final t in tasks) {
          if (t.id == taskId) {
            newTasks.add(hydrateTask(t));
            taskChanged = true;
          } else {
            newTasks.add(t);
          }
        }
        if (taskChanged) {
          changed = true;
          patched.add(embed.copyWith(tasks: newTasks));
        } else {
          patched.add(embed);
        }
      }
      if (changed) embedsByFileId[entry.key] = patched;
    }
    viewMemberships = [
      for (final m in viewMemberships)
        if (m.taskId == taskId && m.task != null)
          m.copyWith(
            task: {
              ...m.task!,
              if (title != null) 'title': title,
              if (status != null) 'status': status,
              if (taskListId != null) 'task_list_id': taskListId,
              if (taskListTitle != null) 'task_list_title': taskListTitle,
              if (descriptionLinks != null)
                'description_links': descriptionLinks,
            },
          )
        else
          m,
    ];
  }

  Future<void> deleteTask(Task task, {bool notify = true}) async {
    await _tasks.deleteTask(task.id);
    _dropCachedTask(task.id);
    if (selectedView != null) {
      await _refreshViewMemberships();
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
    _ingestTask(task);
    await _refreshViewMemberships();
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
    for (final task in tasksById.values.toList()) {
      if (task.taskListId == taskListId) {
        _patchCachedTask(task.id, taskListTitle: title);
      }
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
      await _refreshViewMemberships();
    }
    if (notify) notifyListeners();
  }

  /// Reload open-file embeds and the selected view's memberships.
  Future<void> refreshOpenTaskSurfaces({bool notify = true}) =>
      _reloadEmbedsForOpenFiles(notify: notify);

  /// Writes the topic's file order. The layout then decides how far down that
  /// order the screen reaches.
  ///
  /// Visiting files on Home are not Home's files — their `order_index` on the
  /// source topic is left alone. The mixed canvas order is stored locally.
  Future<String?> reorderTopicFiles(
    Topic topic, {
    required List<AppFile> ordered,
  }) async {
    final visitIds = {for (final file in broughtFiles) file.id};
    final owned = [
      for (final file in ordered)
        if (!topic.isMain || !visitIds.contains(file.id)) file,
    ];
    for (var index = 0; index < owned.length; index++) {
      await _files.updateFile(owned[index].id, {'order_index': index});
    }
    if (topic.isMain) {
      broughtFiles = [
        for (final file in ordered)
          if (visitIds.contains(file.id)) file,
      ];
      homeCanvasOrderIds = broughtFiles.isEmpty
          ? const []
          : [for (final file in ordered) file.id];
      await _persistBroughtFileLayout();
    }
    await _refreshTopicFiles(topic);
    return null;
  }

  Future<List<AppFile>> loadBringFilePreviews(List<AppFile> files) async =>
      files;

  Future<List<BrowseFileEntry>> loadBringFileCatalog() async {
    final files = await _files.listAllFiles();
    return buildBringFileCatalog(
      topics: allTopics,
      files: files,
      mainTopic: allTopics.where((t) => t.isMain).firstOrNull,
      excludeFileIds: {for (final file in broughtFiles) file.id},
    );
  }

  Future<void> setBroughtFile(BrowseFileEntry entry) async {
    final live = await _files.getFile(entry.file.id);
    final topic =
        allTopics.where((t) => t.id == live.topicId).firstOrNull ?? entry.topic;
    final home = allTopics.where((t) => t.isMain).firstOrNull;
    final homeFiles = home != null && selectedDetail?.topic.id == home.id
        ? selectedDetail!.files
        : const <AppFile>[];
    final canvas = home == null
        ? <AppFile>[live]
        : orderedFilesFor(home, homeFiles);
    broughtFiles = [
      live,
      for (final file in broughtFiles)
        if (file.id != live.id) file,
    ];
    broughtTopics
      ..removeWhere((id, _) => id == live.id)
      ..[live.id] = topic;
    homeCanvasOrderIds = [
      live.id,
      for (final file in canvas)
        if (file.id != live.id) file.id,
    ];
    await loadEmbedsForFile(live.id, notify: false);
    await _persistBroughtFileLayout();
    notifyListeners();
  }

  Future<void> dismissBroughtFile(int fileId) async {
    final home = allTopics.where((t) => t.isMain).firstOrNull;
    final homeFiles = home != null && selectedDetail?.topic.id == home.id
        ? selectedDetail!.files
        : const <AppFile>[];
    final canvas = home == null
        ? broughtFiles
        : orderedFilesFor(home, homeFiles);
    broughtFiles = [
      for (final file in broughtFiles)
        if (file.id != fileId) file,
    ];
    broughtTopics.remove(fileId);
    homeCanvasOrderIds = broughtFiles.isEmpty
        ? const []
        : [
            for (final file in canvas)
              if (file.id != fileId) file.id,
          ];
    await _persistBroughtFileLayout();
    notifyListeners();
  }

  Future<void> _persistBroughtFileLayout() async {
    final id = workspaceId;
    if (id == null) return;
    await broughtFileStore.save(
      id,
      BroughtFileLayout(
        visitIds: [for (final file in broughtFiles) file.id],
        order: homeCanvasOrderIds,
      ),
    );
  }

  Future<void> _restoreBroughtFile() async {
    final id = workspaceId;
    if (id == null) return;
    final stored = await broughtFileStore.load(id);
    if (stored.isEmpty) {
      broughtFiles = [];
      broughtTopics.clear();
      homeCanvasOrderIds = [];
      return;
    }
    final home = allTopics.where((t) => t.isMain).firstOrNull;
    final byId = <int, AppFile>{};
    final nextTopics = <int, Topic>{};
    for (final fileId in stored.visitIds) {
      try {
        final file = await _files.getFile(fileId);
        final topic = allTopics.where((t) => t.id == file.topicId).firstOrNull;
        if (file.isArchived ||
            topic == null ||
            topic.isArchived ||
            topic.isMain ||
            (home != null && file.topicId == home.id)) {
          continue;
        }
        byId[file.id] = file;
        nextTopics[file.id] = topic;
        await loadEmbedsForFile(file.id, notify: false);
      } catch (_) {
        continue;
      }
    }
    final homeFiles = home == null
        ? const <AppFile>[]
        : selectedDetail?.topic.id == home.id
        ? selectedDetail!.files
        : await _files.listFilesForTopic(home.id);
    final visits = [
      for (final fileId in stored.visitIds)
        if (byId[fileId] != null) byId[fileId]!,
    ];
    final canvas = mergeHomeCanvasFiles(
      homeFiles: homeFiles,
      visits: visits,
      storedOrder: stored.order,
    );
    broughtFiles = [
      for (final file in canvas)
        if (byId.containsKey(file.id)) file,
    ];
    broughtTopics
      ..clear()
      ..addAll(nextTopics);
    homeCanvasOrderIds = broughtFiles.isEmpty
        ? const []
        : [for (final file in canvas) file.id];
    final nextIds = [for (final file in broughtFiles) file.id];
    final orderChanged =
        homeCanvasOrderIds.length != stored.order.length ||
        !_sameIds(homeCanvasOrderIds, stored.order);
    if (nextIds.length != stored.visitIds.length ||
        !_sameIds(nextIds, stored.visitIds) ||
        orderChanged) {
      await _persistBroughtFileLayout();
    }
  }

  static bool _sameIds(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  List<Task> get viewTasks {
    return [
      for (final m in viewMemberships)
        if (taskForMembership(m) case final task?) task,
    ];
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
        ViewSectionDef(name: name, flag: m.sectionFlag, orderIndex: order++),
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
      for (final s in sectionsForSelectedView()) s.name == oldName ? next : s,
    ];
    await _persistViewLayout(
      ViewLayoutConfig.withSections(selectedView!.layoutConfig, sections),
    );

    final flag = next.flag;
    final memberships = [
      for (final m in viewMemberships)
        {
          ...m.toReplaceJson(),
          'section_name': m.sectionName == oldName ? next.name : m.sectionName,
          'section_flag': m.sectionName == oldName || m.sectionName == next.name
              ? flag
              : m.sectionFlag,
        },
    ];
    _applyViewMemberships(
      await _views.replaceMemberships(selectedView!.id, memberships),
    );
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
      for (final key in ViewLayoutConfig.sectionOrder(
        selectedView!.layoutConfig,
      ))
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
        m.copyWith(clearSection: m.sectionName == section).toReplaceJson(),
    ];
    _applyViewMemberships(
      await _views.replaceMemberships(selectedView!.id, memberships),
    );
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
    final byName = {for (final s in sectionsForSelectedView()) s.name: s};
    final defs = <ViewSectionDef>[];
    for (final key in keys) {
      if (!key.startsWith('section:')) continue;
      final name = key.substring('section:'.length);
      if (name.isEmpty) continue;
      final existing = byName[name];
      defs.add(
        (existing ?? ViewSectionDef(name: name)).copyWith(
          orderIndex: defs.length,
        ),
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
    userViews = [for (final v in userViews) v.id == updated.id ? updated : v];
    if (selectedView?.id == updated.id) {
      selectedView = updated;
    }
    notifyListeners();
  }

  Future<void> reorderViews(List<AppView> ordered) async {
    await Future.wait([
      for (var i = 0; i < ordered.length; i++)
        _views.updateView(ordered[i].id, orderIndex: i),
    ]);
    userViews = [
      for (var i = 0; i < ordered.length; i++)
        ordered[i].copyWith(orderIndex: i),
    ];
    notifyListeners();
  }

  Future<void> deleteView(AppView view) async {
    await _views.deleteView(view.id);
    userViews = userViews.where((v) => v.id != view.id).toList();
    if (selectedView?.id == view.id || selectedViewType == view.type) {
      await goHome();
      return;
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

  /// The topic and files the run should look at first.
  Map<String, dynamic> agentRunScope() => {
    if (selectedTopic != null) 'topic_ids': [selectedTopic!.id],
    if (selectedDetail != null)
      'file_ids': selectedDetail!.files.map((f) => f.id).toList(),
  };

  /// Pointers into what is open: the clock, the file being edited, the mark.
  ///
  /// [selectedText] is the mark captured **before** a dialog stole focus.
  /// Call after flushing the editor when reading the live mark instead.
  Map<String, dynamic> agentRunHints({String? selectedText}) {
    final mark =
        (selectedText ?? DocumentEditorRegistry.activeMarkedTextForAgent())
            ?.trim();
    return {
      ...agentTimeHints(),
      'focused_file_id': ?DocumentEditorRegistry.activeFileId,
      if (mark != null && mark.isNotEmpty) 'selected_text': mark,
    };
  }

  Future<Map<String, dynamic>?> runAgentPrompt(
    String prompt, {
    String? applyMode,
    String? selectedText,
  }) async {
    if (workspaceId == null) return null;
    aiRunning = true;
    notifyListeners();
    try {
      // Persist the open editor first so open_file matches what the user sees,
      // and so a later apply reload is not racing a stale debounce save.
      await DocumentEditorRegistry.flushActive();
      final result = await _agent.run(
        prompt: prompt,
        workspaceId: workspaceId!,
        scope: agentRunScope(),
        hints: agentRunHints(selectedText: selectedText),
        applyMode: applyMode,
      );
      return result;
    } finally {
      aiRunning = false;
      notifyListeners();
    }
  }

  Future<PendingReview?> pendingReviewForFile(int fileId) {
    return _pendingReviews.getForFile(fileId);
  }

  Future<void> finishPendingReview(
    int fileId,
    List<Map<String, String>> decisions,
  ) async {
    await _pendingReviews.finish(fileId, decisions: decisions);
    if (selectedTopic != null) await selectTopic(selectedTopic!);
    await loadArchive();
  }

  Future<void> discardPendingReview(int fileId) async {
    await _pendingReviews.discard(fileId);
  }

  /// Restore a file after a direct_apply using the pre-apply document snapshot.
  Future<void> undoDirectApply({
    required int fileId,
    required String oldDocumentJson,
    int? topicId,
  }) async {
    await _files.applyAgentText(
      fileId,
      documentJson: oldDocumentJson,
      tool: 'undo',
    );
    if (selectedTopic != null &&
        (topicId == null || selectedTopic!.id == topicId)) {
      await selectTopic(selectedTopic!);
    }
  }

  Future<void> applyAgentReview() async {
    final changes = pendingAgentReview?['proposed_changes'] as List?;
    if (changes == null || selectedDetail == null) return;
    for (final change in changes) {
      if (change is! Map) continue;
      final fileId = change['file_id'] as int?;
      final newBody =
          change['new_document_json'] as String? ??
          change['new_body'] as String?;
      if (fileId == null || newBody == null) continue;
      final objectUpdates = change['object_updates'];
      await _files.applyAgentText(
        fileId,
        documentJson: newBody,
        objectUpdates: objectUpdates is Map
            ? Map<String, dynamic>.from(objectUpdates)
            : null,
        tool: change['tool'] as String?,
      );
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
  Future<void> finalizeProcessUpdate(
    dynamic proposal,
    dynamic decisions,
  ) async {}
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final iterator = this.iterator;
    if (!iterator.moveNext()) return null;
    return iterator.current;
  }
}
