import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_context.dart';
import 'l10n/app_language.dart';
import 'l10n/app_strings.dart';
import 'models/ai_proposal.dart';
import 'models/app_file.dart';
import 'models/automation_rule.dart';
import 'models/block.dart';
import '../features/blocks/board_content.dart';
import '../features/blocks/line_task_sync.dart';
import 'models/task.dart';
import 'models/task_view_membership.dart';
import 'models/topic.dart';
import 'models/view_section.dart';
import 'models/view_section_flags.dart';
import 'registry/file_behavior_registry.dart';
import 'registry/file_registry.dart';
import 'registry/task_view_display.dart';
import 'registry/topic_appearance.dart';
import '../design_system/file_layouts.dart';
import 'services/ai_service.dart';
import 'services/ai_proposal_service.dart';
import 'services/api_service.dart';
import 'services/automation_service.dart';
import 'services/block_service.dart';
import 'services/bootstrap_service.dart';
import 'services/file_service.dart';
import 'services/image_service.dart';
import 'services/task_service.dart';
import 'services/task_view_service.dart';
import 'services/topic_service.dart';

class TopicDetail {
  TopicDetail({
    required this.topic,
    required this.files,
    required this.blocksByFileId,
    required this.tasksByBlockId,
  });

  final Topic topic;
  final List<AppFile> files;
  final Map<int, List<Block>> blocksByFileId;
  final Map<int, List<Task>> tasksByBlockId;
}

class _ViewSnapshot {
  const _ViewSnapshot({required this.tasks, required this.sections});

  final List<Task> tasks;
  final List<ViewSection> sections;
}

class AppState extends ChangeNotifier {
  AppState() {
    _bootstrap = BootstrapService(
      topicService: _topicService,
      fileService: _fileService,
      blockService: _blockService,
    );
  }

  final ApiService _api = ApiService();
  late final BootstrapService _bootstrap;
  late final TopicService _topicService = TopicService(_api);
  late final FileService _fileService = FileService(_api);
  late final BlockService _blockService = BlockService(_api);
  late final TaskService _taskService = TaskService(_api);
  late final TaskViewService _taskViewService = TaskViewService(_api);
  late final ImageService _imageService = ImageService(_api);
  late final AiService _aiService = AiService(_api);
  late final AutomationService _automationService = AutomationService(_api);
  late final AiProposalService _aiProposalService = AiProposalService(_api);

  bool loading = true;
  String? error;
  List<Topic> topics = [];
  Topic? mainTopic;
  Topic? selectedTopic;
  TopicDetail? selectedDetail;
  String? selectedViewType;
  List<Task> viewTasks = [];
  List<ViewSection> viewSections = [];
  final Map<String, _ViewSnapshot> _viewCache = {};
  bool _showViewPaneDuringLoad = false;
  bool _loadingTopicFromView = false;
  TaskViewDisplayMode viewDisplayMode = TaskViewDisplayMode.bySection;
  List<TaskViewMembership> _taskViewMemberships = [];
  List<AutomationRule> automationRules = [];
  List<AiProposal> pendingAiProposals = [];
  Map<int, List<AppFile>> archivedFilesByTopicId = {};
  bool moreFilesExpanded = false;
  bool paneDragMode = false;
  final Map<int, String> _layoutByTopicId = {};
  AppLanguage language = AppLanguage.en;
  AiFocus? aiFocus;
  int? pendingFocusBlockId;
  bool aiRunning = false;

  final Map<int, Timer?> _saveTimers = {};
  final Map<int, List<String>> _taskLineSnapshots = {};
  bool _syncingTasks = false;
  final Map<int, String?> _automationLastRunAtById = {};
  Timer? _automationRunPollTimer;
  bool _pollingAutomationRuns = false;

  AppStrings get strings => AppStrings.forLanguage(language);
  bool get isRtl => strings.isRtl;
  TextDirection get textDirection => strings.textDirection;

  String viewLabel(String type) => strings.viewLabel(type);
  String fileDisplayName(String name) => strings.fileNameLabel(name);
  String topicDisplayName(Topic topic) =>
      topic.isMain ? strings['main'] : topic.name;
  String taskTopicDisplayName(Task task) =>
      strings.displayTopicName(task.topicName);

  List<Topic> get archivedTopics =>
      topics.where((t) => t.isArchived && !t.isMain).toList();

  bool get hasArchive =>
      archivedTopics.isNotEmpty ||
      archivedFilesByTopicId.values.any((files) => files.isNotEmpty);

  Future<void> setLanguage(AppLanguage value) async {
    if (language == value) return;
    language = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', value.name);
    notifyListeners();
  }

  bool _aiFocusNotifyScheduled = false;

  void setAiFocus(AiFocus focus) {
    aiFocus = focus;
    if (_aiFocusNotifyScheduled) return;
    _aiFocusNotifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _aiFocusNotifyScheduled = false;
      notifyListeners();
    });
  }

  void requestBlockFocus(int blockId) {
    pendingFocusBlockId = blockId;
    notifyListeners();
  }

  void clearBlockFocus(int blockId) {
    if (pendingFocusBlockId != blockId) return;
    pendingFocusBlockId = null;
  }

  ResolvedAiContext? resolveAiContext() {
    final detail = selectedDetail;
    if (detail == null) return null;

    String? lastTaskTitle;
    int? lastTaskFileId;

    for (final file in detail.files) {
      if (file.type == 'tasks') {
        final blocks = detail.blocksByFileId[file.id] ?? [];
        for (final block in blocks) {
          if (block.type != 'task_list') continue;
          final tasks = detail.tasksByBlockId[block.id] ?? [];
          if (tasks.isNotEmpty) {
            lastTaskTitle = tasks.last.title;
            lastTaskFileId = file.id;
          }
        }
      }
    }

    return AiContextResolver.resolve(
      topicId: detail.topic.id,
      focus: aiFocus,
      lastTaskTitle: lastTaskTitle,
      lastTaskFileId: lastTaskFileId,
    );
  }

  bool get hasAiContext {
    final ctx = resolveAiContext();
    return ctx != null && ctx.text.trim().isNotEmpty;
  }

  bool get hasDataForGraph {
    final detail = selectedDetail;
    if (detail == null) return false;
    return detail.files.any((f) => f.type == 'data');
  }

  bool get canUseAiTools => !isViewMode && selectedDetail != null;

  bool canRunAiTool(String tool) {
    if (!canUseAiTools) return false;
    if (tool == 'review') return true;
    if (tool == 'create_graph') return hasAiContext || hasDataForGraph;
    return hasAiContext;
  }

  Future<AiRunResult?> runAiTool(
    String tool, {
    ResolvedAiContext? contextOverride,
  }) async {
    final topic = selectedTopic;
    if (topic == null) return null;

    var ctx = contextOverride ?? resolveAiContext();
    if (tool == 'create_graph' &&
        (ctx == null || ctx.text.trim().isEmpty) &&
        hasDataForGraph) {
      ctx = ResolvedAiContext(
        text: '',
        sourceType: AiSourceType.paragraph,
        topicId: topic.id,
      );
    }
    if (ctx == null) return null;
    if (tool != 'create_graph' && ctx.text.trim().isEmpty) return null;

    aiRunning = true;
    error = null;
    notifyListeners();
    try {
      final result = await _aiService.runTool(
        tool: tool,
        topicId: topic.id,
        context: ctx,
        locale: language.name,
      );
      await selectTopic(topic);
      return result;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      aiRunning = false;
      notifyListeners();
    }
  }

  Future<AiRunResult?> runAiToolWithText(
    String tool,
    String text, {
    int? fileId,
    int? blockId,
  }) {
    final topic = selectedTopic;
    if (topic == null || text.trim().isEmpty) return Future.value(null);
    return runAiTool(
      tool,
      contextOverride: ResolvedAiContext(
        text: text.trim(),
        sourceType: AiSourceType.paragraph,
        topicId: topic.id,
        fileId: fileId,
        blockId: blockId,
      ),
    );
  }

  Future<AiRunResult?> runBoardAiImage(
    AppFile file,
    Block boardBlock,
    String prompt,
  ) async {
    final topic = selectedTopic;
    if (topic == null || prompt.trim().isEmpty) return null;

    aiRunning = true;
    error = null;
    notifyListeners();
    try {
      final result = await _aiService.runTool(
        tool: 'create_image',
        topicId: topic.id,
        context: ResolvedAiContext(
          text: prompt.trim(),
          sourceType: AiSourceType.paragraph,
          topicId: topic.id,
          fileId: file.id,
          blockId: boardBlock.id,
        ),
        locale: language.name,
      );

      if (result.imagePath != null && result.imagePath!.isNotEmpty) {
        final blocks = await _blockService.listForFile(file.id);
        final board = blocks.where((b) => b.type == 'board').firstOrNull;
        if (board != null) {
          final items = boardItemsFromContent(board.content);
          final (x, y) = staggerBoardPlacement(items);
          final filename = result.imagePath!.split('/').last;
          final next = BoardItem(
            id: nextBoardItemId(items),
            imagePath: result.imagePath!,
            filename: filename,
            x: x,
            y: y,
            width: 220,
            height: 165,
            zIndex: nextBoardZIndex(items),
          );
          final content = boardContentFromItems(
            [...items, next],
            base: board.content,
          );
          await _blockService.updateBlock(board.id, {'content': content});
        }
        for (final block in blocks) {
          if (block.type == 'image') {
            await _blockService.deleteBlock(block.id);
          }
        }
      }

      await selectTopic(topic);
      return result;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      aiRunning = false;
      notifyListeners();
    }
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    language = AppLanguage.fromStorage(prefs.getString('app_language'));
  }

  List<Topic> get projects => topics
      .where((t) => t.type == 'project' && !t.isMain && !t.isArchived)
      .toList();

  List<Topic> get processes => topics
      .where((t) => t.type == 'process' && !t.isMain && !t.isArchived)
      .toList();

  List<Topic> get areas => topics
      .where((t) => t.type == 'area' && !t.isMain && !t.isArchived)
      .toList();

  bool get isViewMode => selectedViewType != null;

  /// True when the task view pane should be shown (not the topic canvas).
  bool get viewPaneReady {
    final viewType = selectedViewType;
    if (viewType == null) return false;
    if (!loading) return true;
    if (_viewCache.containsKey(viewType)) return true;
    return _showViewPaneDuringLoad;
  }

  void _cacheCurrentView() {
    final type = selectedViewType;
    if (type == null) return;
    final sections = sectionsForViewType(type);
    if (viewTasks.isEmpty && sections.isEmpty) return;
    _viewCache[type] = _ViewSnapshot(
      tasks: List<Task>.from(viewTasks),
      sections: List<ViewSection>.from(sections),
    );
  }

  void _restoreViewCache(String viewType) {
    final cached = _viewCache[viewType];
    if (cached == null) return;
    viewTasks = List<Task>.from(cached.tasks);
    viewSections = [
      ...viewSections.where((s) => s.viewType != viewType),
      ...cached.sections,
    ];
  }

  /// True while loading a topic after leaving a view (not topic-to-topic).
  bool get topicDetailStale {
    if (!_loadingTopicFromView) return false;
    final topic = selectedTopic;
    final detail = selectedDetail;
    if (!loading || topic == null) return false;
    return detail == null || detail.topic.id != topic.id;
  }

  Future<void> initialize() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadLanguage();
      mainTopic = await _bootstrap.ensureMainTopic();
      await refreshTopics();
      await refreshAutomationRules();
      await loadArchive();
      await _refreshTaskViewMemberships();
      await selectTopic(mainTopic!);
      _rememberAutomationRunState();
      _startAutomationRunPolling();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshTaskViewMemberships() async {
    _taskViewMemberships = await _taskViewService.listAll();
  }

  Future<List<TaskViewMembership>> membershipsForTask(int taskId) async {
    await _refreshTaskViewMemberships();
    return _taskViewMemberships.where((m) => m.taskId == taskId).toList();
  }

  TaskViewMembership? membershipForTaskInView(int taskId, String viewType) {
    for (final m in _taskViewMemberships) {
      if (m.taskId == taskId && m.viewType == viewType) return m;
    }
    return null;
  }

  List<ViewSection> sectionsForViewType(String viewType) {
    return viewSections.where((s) => s.viewType == viewType).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  Color topicAccentForTask(Task task) {
    Topic? topic;
    if (task.topicId != null) {
      for (final t in topics) {
        if (t.id == task.topicId) {
          topic = t;
          break;
        }
      }
    }
    if (topic == null) {
      for (final t in topics) {
        if (t.name == task.topicName) {
          topic = t;
          break;
        }
      }
    }
    return TopicAppearance.colorFromHex(topic?.color);
  }

  bool topicIsMain(Task task) => task.topicName == 'main';

  Future<List<ViewSection>> loadSectionsForView(String viewType) async {
    final loaded = await _taskViewService.listSectionsForView(viewType);
    final others = viewSections.where((s) => s.viewType != viewType);
    viewSections = [...others, ...loaded];
    return loaded;
  }

  void setViewDisplayMode(TaskViewDisplayMode mode) {
    viewDisplayMode = mode;
    notifyListeners();
  }

  Future<void> refreshTopics() async {
    topics = await _topicService.listTopics(includeArchived: true);
    mainTopic = topics.firstWhere(
      (t) => t.isMain && !t.isArchived,
      orElse: () => mainTopic!,
    );
    notifyListeners();
  }

  Future<void> loadArchive() async {
    final archive = <int, List<AppFile>>{};
    for (final topic in topics.where((t) => !t.isArchived)) {
      final files = await _fileService.listForTopic(
        topic.id,
        includeArchived: true,
      );
      final archived = files.where((f) => f.isArchived).toList();
      if (archived.isNotEmpty) archive[topic.id] = archived;
    }
    archivedFilesByTopicId = archive;
    notifyListeners();
  }

  Future<void> refreshAutomationRules() async {
    automationRules = await _automationService.listRules();
    if (await _ensureMainAutomationRules()) {
      automationRules = await _automationService.listRules();
    }
    notifyListeners();
  }

  Future<void> ensureMainAutomationRules() => refreshAutomationRules();

  Future<void> updateAutomationRule(
    AutomationRule rule, {
    bool? enabled,
    String? schedule,
  }) async {
    final patch = <String, dynamic>{};
    if (enabled != null) {
      patch['enabled'] = enabled;
    }
    if (schedule != null) {
      patch['schedule'] = schedule;
    }
    await _automationService.updateRule(rule.id, patch);
    await refreshAutomationRules();
  }

  Future<void> runAutomationRule(AutomationRule rule) async {
    await _automationService.runRule(rule.id);
    await refreshAutomationRules();
    _rememberAutomationRunState();
    await _refreshVisibleContentAfterAutomation();
  }

  void _startAutomationRunPolling() {
    _automationRunPollTimer?.cancel();
    _automationRunPollTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _pollAutomationRuns(),
    );
  }

  Future<void> _pollAutomationRuns() async {
    if (_pollingAutomationRuns) return;
    _pollingAutomationRuns = true;
    try {
      final previous = Map<int, String?>.from(_automationLastRunAtById);
      automationRules = await _automationService.listRules();
      if (await _ensureMainAutomationRules()) {
        automationRules = await _automationService.listRules();
      }

      final automationRan = automationRules.any((rule) {
        final previousLastRun = previous[rule.id];
        return previousLastRun != null &&
            rule.lastRunAt != null &&
            previousLastRun != rule.lastRunAt;
      });
      _rememberAutomationRunState();
      notifyListeners();

      if (automationRan && _hasOpenContent) {
        await _refreshVisibleContentAfterAutomation();
      }
    } catch (_) {
      // Scheduled automation checks should never interrupt editing.
    } finally {
      _pollingAutomationRuns = false;
    }
  }

  void _rememberAutomationRunState() {
    _automationLastRunAtById
      ..clear()
      ..addEntries(
        automationRules.map((rule) => MapEntry(rule.id, rule.lastRunAt)),
      );
  }

  bool get _hasOpenContent =>
      selectedDetail != null || selectedViewType != null;

  Future<void> _refreshVisibleContentAfterAutomation() async {
    final viewType = selectedViewType;
    final topic = selectedTopic;

    await refreshTopics();
    await loadArchive();

    if (viewType != null) {
      await selectView(viewType);
      return;
    }

    if (topic == null) return;
    Topic? updatedTopic;
    for (final item in topics) {
      if (item.id == topic.id) {
        updatedTopic = item;
        break;
      }
    }
    if (updatedTopic != null) {
      await selectTopic(updatedTopic, includeArchived: updatedTopic.isArchived);
    }
  }

  Future<void> approveAiProposal(AiProposal proposal) async {
    await _aiProposalService.approve(proposal.id);
    final topic = selectedTopic;
    if (topic != null) {
      await selectTopic(topic, includeArchived: topic.isArchived);
    }
  }

  Future<void> finalizeProcessUpdate(
    AiProposal proposal,
    Map<String, bool> decisions,
  ) async {
    await _aiProposalService.finalize(
      proposal.id,
      Map<String, dynamic>.from(decisions),
    );
    pendingAiProposals = pendingAiProposals
        .where((item) => item.id != proposal.id)
        .toList();
    final topic = selectedTopic;
    if (topic != null) {
      await selectTopic(topic, includeArchived: topic.isArchived);
    } else {
      await refreshTopics();
      await loadArchive();
      notifyListeners();
    }
  }

  Future<void> rejectAiProposal(AiProposal proposal) async {
    await _aiProposalService.reject(proposal.id);
    pendingAiProposals = pendingAiProposals
        .where((item) => item.id != proposal.id)
        .toList();
    notifyListeners();
  }

  Future<bool> _ensureMainAutomationRules() async {
    var created = false;
    final keys = automationRules.map((rule) => rule.key).toSet();
    if (!keys.contains('daily_rotation')) {
      await _automationService.createRule({
        'key': 'daily_rotation',
        'name': 'Daily rotation',
        'action_type': 'rotate_daily_main_file',
        'trigger_type': 'schedule',
        'schedule': 'daily 00:00',
        'timezone': 'UTC',
        'enabled': true,
        'params': {'topic_name': 'main', 'name': 'Daily', 'type': 'main'},
      });
      created = true;
    }
    if (!keys.contains('weekly_process_refresh')) {
      await _automationService.createRule({
        'key': 'weekly_process_refresh',
        'name': 'Weekly process refresh',
        'action_type': 'weekly_process_refresh',
        'trigger_type': 'schedule',
        'schedule': 'weekly mon 00:00',
        'timezone': 'UTC',
        'enabled': false,
        'params': {},
      });
      created = true;
    }
    return created;
  }

  Future<void> selectTopic(Topic topic, {bool includeArchived = false}) async {
    final fromView = selectedViewType != null;
    loading = true;
    error = null;
    selectedViewType = null;
    _showViewPaneDuringLoad = false;
    _loadingTopicFromView = fromView;
    selectedTopic = topic;
    notifyListeners();
    try {
      final files = await _fileService.listForTopic(
        topic.id,
        includeArchived: includeArchived || topic.isArchived,
      );
      final blocksByFileId = <int, List<Block>>{};
      final tasksByBlockId = <int, List<Task>>{};

      for (final file in files) {
        final loaded = await _blockService.listForFile(
          file.id,
          includeArchived: includeArchived || file.isArchived,
        );
        final ensured = file.type == 'board'
            ? await _ensureBoardBlock(file, loaded)
            : loaded;
        final normalized = file.type == 'board'
            ? ensured
            : await _removeAdjacentTextBlocks(file, ensured);
        final blocks = await _ensureTrailingDefaultBlock(file, normalized);
        blocksByFileId[file.id] = blocks;
        for (final block in blocks) {
          if (block.type == 'task' || block.type == 'task_list') {
            tasksByBlockId[block.id] = await _taskService.listForBlock(
              block.id,
            );
          }
        }
      }

      selectedDetail = TopicDetail(
        topic: topic,
        files: files,
        blocksByFileId: blocksByFileId,
        tasksByBlockId: tasksByBlockId,
      );
      pendingAiProposals = await _aiProposalService.listPending(
        topicId: topic.id,
      );
    } catch (e) {
      error = e.toString();
      selectedDetail = null;
    } finally {
      loading = false;
      _loadingTopicFromView = false;
      moreFilesExpanded = false;
      notifyListeners();
    }
  }

  Future<void> goHome() async {
    if (mainTopic != null) {
      await selectTopic(mainTopic!);
    }
  }

  Future<void> selectView(String viewType) async {
    _cacheCurrentView();
    final fromView = selectedViewType != null;
    final cached = _viewCache[viewType];

    error = null;
    selectedViewType = viewType;
    selectedTopic = null;
    _showViewPaneDuringLoad = fromView || cached != null;

    if (cached != null) {
      _restoreViewCache(viewType);
    } else {
      viewTasks = [];
      viewSections = viewSections.where((s) => s.viewType != viewType).toList();
    }

    loading = true;
    notifyListeners();
    try {
      final sections = await _taskViewService.listSectionsForView(viewType);
      final tasks = await _taskService.listByView(viewType);
      viewSections = [
        ...viewSections.where((s) => s.viewType != viewType),
        ...sections,
      ];
      viewTasks = tasks;
      _viewCache[viewType] = _ViewSnapshot(tasks: tasks, sections: sections);
    } catch (e) {
      error = e.toString();
      if (cached == null) viewTasks = [];
    } finally {
      loading = false;
      _showViewPaneDuringLoad = false;
      moreFilesExpanded = false;
      notifyListeners();
    }
  }

  List<AppFile> mainFilesFor(Topic topic, List<AppFile> files) {
    return _sorted(
      files.where(
        (f) => FileRegistry.fileIsMain(
          file: f,
          topicType: topic.type,
          isMainTopic: topic.isMain,
        ),
      ),
    );
  }

  List<AppFile> secondaryFilesFor(Topic topic, List<AppFile> files) {
    return _sorted(
      files.where(
        (f) => !FileRegistry.fileIsMain(
          file: f,
          topicType: topic.type,
          isMainTopic: topic.isMain,
        ),
      ),
    );
  }

  bool fileIsMain(Topic topic, AppFile file) {
    return FileRegistry.fileIsMain(
      file: file,
      topicType: topic.type,
      isMainTopic: topic.isMain,
    );
  }

  List<AppFile> _sorted(Iterable<AppFile> files) {
    final list = files.toList()
      ..sort((a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0));
    return list;
  }

  String layoutFor(Topic topic) {
    final count = selectedDetail?.topic.id == topic.id
        ? mainFilesFor(topic, selectedDetail!.files).length
        : 0;
    if (count < 1) return FileLayouts.single;

    final preferred = _layoutByTopicId[topic.id];
    if (preferred != null && FileLayouts.isAvailable(preferred, count)) {
      return preferred;
    }
    return FileLayouts.bestForFileCount(count);
  }

  void setLayoutForTopic(Topic topic, String layoutId) {
    _layoutByTopicId[topic.id] = layoutId;
    notifyListeners();
  }

  void toggleMoreFiles() {
    moreFilesExpanded = !moreFilesExpanded;
    notifyListeners();
  }

  void togglePaneDragMode() {
    paneDragMode = !paneDragMode;
    if (paneDragMode) {
      moreFilesExpanded = true;
    }
    notifyListeners();
  }

  void _applyOptimisticFiles(List<AppFile> files) {
    final detail = selectedDetail;
    if (detail == null) return;
    selectedDetail = TopicDetail(
      topic: detail.topic,
      files: files,
      blocksByFileId: detail.blocksByFileId,
      tasksByBlockId: detail.tasksByBlockId,
    );
    notifyListeners();
  }

  Future<String?> reorderTopicFiles(
    Topic topic,
    List<AppFile> ordered,
    int mainCount,
  ) async {
    final detail = selectedDetail;
    if (detail == null || detail.topic.id != topic.id) return null;

    try {
      for (var i = 0; i < ordered.length; i++) {
        final isMain = i < mainCount;
        await _fileService.updateFile(ordered[i].id, {
          'order_index': i,
          'is_main': isMain,
        });
      }

      final orderedIds = ordered.map((f) => f.id).toSet();
      final others = detail.files
          .where((f) => !orderedIds.contains(f.id))
          .toList();
      final updatedOrdered = [
        for (var i = 0; i < ordered.length; i++)
          ordered[i].copyWith(orderIndex: i, isMain: i < mainCount),
      ];
      _applyOptimisticFiles([...updatedOrdered, ...others]);
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  Future<void> setFileMainVisibility(
    Topic topic,
    AppFile file, {
    required bool isMain,
  }) async {
    final detail = selectedDetail;
    if (detail == null || detail.topic.id != topic.id) return;

    var mainFiles = mainFilesFor(topic, detail.files);
    final secondaryFiles = secondaryFilesFor(topic, detail.files);

    int? evictedId;
    if (isMain &&
        !fileIsMain(topic, file) &&
        mainFiles.length >= FileRegistry.maxMainFilesPerTopic) {
      final evicted = mainFiles.last;
      evictedId = evicted.id;
      await _fileService.updateFile(evicted.id, {'is_main': false});
      mainFiles = mainFiles.sublist(0, mainFiles.length - 1);
    }

    final orderIndex = isMain
        ? (mainFiles.isEmpty
              ? 0
              : (mainFiles.last.orderIndex ?? mainFiles.length - 1) + 1)
        : (secondaryFiles.isEmpty
              ? 0
              : (secondaryFiles.last.orderIndex ?? secondaryFiles.length - 1) +
                    1);

    await _fileService.updateFile(file.id, {
      'is_main': isMain,
      'order_index': orderIndex,
    });

    final updated = detail.files
        .map(
          (f) {
            if (f.id == file.id) {
              return f.copyWith(isMain: isMain, orderIndex: orderIndex);
            }
            if (evictedId != null && f.id == evictedId) {
              return f.copyWith(isMain: false);
            }
            return f;
          },
        )
        .toList();
    _applyOptimisticFiles(updated);
  }

  Future<void> promoteFileToMain(Topic topic, AppFile file) async {
    await setFileMainVisibility(topic, file, isMain: true);
  }

  Future<void> demoteFileToSecondary(Topic topic, AppFile file) async {
    await setFileMainVisibility(topic, file, isMain: false);
  }

  Future<void> createTopic({
    required String name,
    required String type,
    required String icon,
    required String color,
    required List<String> selectedFileTypes,
  }) async {
    final topic = await _topicService.createTopic(
      name: name,
      type: type,
      icon: icon,
      color: color,
    );

    final defs = FileRegistry.recommendedForTopicType(
      type,
    ).where((d) => selectedFileTypes.contains(d.type));

    for (final def in defs) {
      final file = await _fileService.createFile(
        topicId: topic.id,
        name: def.name,
        type: def.type,
        orderIndex: def.orderIndex,
        isMain: FileRegistry.isMainFile(
          topicType: type,
          fileType: def.type,
          isMainTopic: topic.isMain,
        ),
      );
      await _createDefaultBlocks(file);
    }

    await refreshTopics();
    await selectTopic(topic);
  }

  Future<void> updateTopic({
    required Topic topic,
    required String name,
    required String icon,
    required String color,
  }) async {
    final updated = await _topicService.updateTopic(topic.id, {
      'name': name,
      'icon': icon,
      'color': color,
    });
    await refreshTopics();
    if (selectedTopic?.id == topic.id) {
      await selectTopic(updated);
    }
  }

  Future<void> addFile({
    required Topic topic,
    required String type,
    required String name,
  }) async {
    final def = FileRegistry.definitionFor(
      topicType: topic.type,
      fileType: type,
      isMainTopic: topic.isMain,
    );
    final isMain = def?.isMain ??
        FileRegistry.isMainFile(
          topicType: topic.type,
          fileType: type,
          isMainTopic: topic.isMain,
        );
    final file = await _fileService.createFile(
      topicId: topic.id,
      name: name,
      type: type,
      orderIndex: def?.orderIndex,
      isMain: isMain,
    );
    await _createDefaultBlocks(file);
    await selectTopic(topic);
  }

  Future<void> updateFileName(Topic topic, AppFile file, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == file.name) return;
    await _fileService.updateFile(file.id, {'name': trimmed});
    await selectTopic(topic);
  }

  Future<void> _createDefaultBlocks(AppFile file) async {
    final defaults = FileBehaviorRegistry.defaultBlocksForFileType(file.type);
    for (var i = 0; i < defaults.length; i++) {
      final spec = defaults[i];
      await _blockService.createBlock(
        fileId: file.id,
        type: spec.type,
        content: spec.content,
        orderIndex: i,
      );
    }
  }

  Future<List<Block>> _ensureBoardBlock(
    AppFile file,
    List<Block> blocks,
  ) async {
    if (file.type != 'board' || file.isArchived) return blocks;
    if (blocks.any((b) => b.type == 'board')) return blocks;
    final block = await _blockService.createBlock(
      fileId: file.id,
      type: 'board',
      content: FileBehaviorRegistry.defaultContentForBlockType('board'),
      orderIndex: blocks.length,
    );
    return [...blocks, block];
  }

  Future<List<Block>> _removeAdjacentTextBlocks(
    AppFile file,
    List<Block> blocks,
  ) async {
    if (file.isArchived || blocks.length < 2) return blocks;
    var result = List<Block>.from(blocks);
    for (var i = result.length - 1; i >= 1; i--) {
      if (result[i].type == 'text' &&
          result[i - 1].type == 'text' &&
          _isEmptyTextBlock(result[i])) {
        await _blockService.deleteBlock(result[i].id);
        result.removeAt(i);
      }
    }
    return result;
  }

  Future<List<Block>> _ensureTrailingDefaultBlock(
    AppFile file,
    List<Block> blocks,
  ) async {
    if (file.isArchived) return blocks;
    final trailingType = FileBehaviorRegistry.inlineInsertForFileType(
      file.type,
    );
    if (trailingType == null || trailingType != 'text') return blocks;
    if (blocks.isNotEmpty && blocks.last.type == 'text') return blocks;
    final block = await _blockService.createBlock(
      fileId: file.id,
      type: trailingType,
      content: FileBehaviorRegistry.defaultContentForBlockType(trailingType),
      orderIndex: blocks.length,
    );
    return [...blocks, block];
  }

  Future<void> deleteTopic(Topic topic) async {
    if (topic.isMain) return;
    await _topicService.deleteTopic(topic.id);
    await refreshTopics();
    await goHome();
  }

  Future<void> deleteFile(Topic topic, AppFile file) async {
    await _fileService.deleteFile(file.id);
    await selectTopic(topic);
  }

  Future<void> addTextBlock(AppFile file) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final blocks = selectedDetail?.blocksByFileId[file.id] ?? [];
    if (blocks.isNotEmpty && blocks.last.type == 'text') {
      requestBlockFocus(blocks.last.id);
      return;
    }
    await _blockService.createBlock(
      fileId: file.id,
      type: 'text',
      content: {'text': ''},
      orderIndex: blocks.length,
    );
    await selectTopic(topic);
  }

  Future<void> addBlock(
    AppFile file,
    String type,
    Map<String, dynamic> content,
  ) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final blocks = selectedDetail?.blocksByFileId[file.id] ?? [];
    await _blockService.createBlock(
      fileId: file.id,
      type: type,
      content: content,
      orderIndex: blocks.length,
    );
    await selectTopic(topic);
  }

  Future<void> addDefaultBlock(AppFile file, String type) async {
    if (type == 'image') return;
    await addBlock(
      file,
      type,
      FileBehaviorRegistry.defaultContentForBlockType(type),
    );
  }

  Future<void> insertDefaultBlock(
    AppFile file,
    String type, {
    required int orderIndex,
  }) async {
    final topic = selectedTopic;
    if (topic == null || type == 'image') return;
    if (type == 'text') {
      final existing = _textBlockForInsertion(file, orderIndex);
      if (existing != null) {
        requestBlockFocus(existing.id);
        return;
      }
    }
    final targetIndex = await _shiftBlocksForInsert(
      file,
      _effectiveInsertIndex(file, orderIndex, type),
    );
    final block = await _blockService.createBlock(
      fileId: file.id,
      type: type,
      content: FileBehaviorRegistry.defaultContentForBlockType(type),
      orderIndex: targetIndex,
    );
    if (type == 'text') requestBlockFocus(block.id);
    await selectTopic(topic);
  }

  Block? _textBlockForInsertion(AppFile file, int orderIndex) {
    final blocks = selectedDetail?.blocksByFileId[file.id] ?? [];
    final targetIndex = orderIndex.clamp(0, blocks.length).toInt();
    if (targetIndex > 0 && blocks[targetIndex - 1].type == 'text') {
      return blocks[targetIndex - 1];
    }
    if (targetIndex < blocks.length && blocks[targetIndex].type == 'text') {
      return blocks[targetIndex];
    }
    return null;
  }

  int _effectiveInsertIndex(AppFile file, int orderIndex, String type) {
    final blocks = selectedDetail?.blocksByFileId[file.id] ?? [];
    final targetIndex = orderIndex.clamp(0, blocks.length).toInt();
    if (type == 'text') return targetIndex;
    if (targetIndex < blocks.length && _isEmptyTextBlock(blocks[targetIndex])) {
      return targetIndex;
    }
    if (targetIndex == blocks.length &&
        blocks.isNotEmpty &&
        _isEmptyTextBlock(blocks.last)) {
      return blocks.length - 1;
    }
    return targetIndex;
  }

  bool _isEmptyTextBlock(Block block) =>
      block.type == 'text' && block.text.trim().isEmpty;

  Future<int> _shiftBlocksForInsert(AppFile file, int orderIndex) async {
    final blocks = selectedDetail?.blocksByFileId[file.id] ?? [];
    final targetIndex = orderIndex.clamp(0, blocks.length).toInt();
    final shifted = blocks
        .where((b) => (b.orderIndex ?? 0) >= targetIndex)
        .toList();
    for (final block in shifted.reversed) {
      await _blockService.updateBlock(block.id, {
        'order_index': (block.orderIndex ?? 0) + 1,
      });
    }
    return targetIndex;
  }

  Future<void> addHeaderBlock(AppFile file) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final blocks = selectedDetail?.blocksByFileId[file.id] ?? [];
    await _blockService.createBlock(
      fileId: file.id,
      type: 'header',
      content: {'text': 'Section', 'level': 2},
      orderIndex: blocks.length,
    );
    await selectTopic(topic);
  }

  void scheduleBlockSave(Block block, Map<String, dynamic> content) {
    _saveTimers[block.id]?.cancel();
    _saveTimers[block.id] = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _blockService.updateBlock(block.id, {'content': content});
      } catch (e) {
        error = e.toString();
        notifyListeners();
      }
    });
  }

  Future<void> updateBlockContent(
    Block block,
    Map<String, dynamic> content, {
    bool notify = false,
  }) async {
    final detail = selectedDetail;
    if (detail == null) return;
    final updated = block.copyWith(content: content);
    final list = detail.blocksByFileId[block.fileId] ?? [];
    detail.blocksByFileId[block.fileId!] = list
        .map((b) => b.id == block.id ? updated : b)
        .toList();
    if (notify) notifyListeners();
    scheduleBlockSave(block, content);
  }

  Future<void> deleteBlock(AppFile file, Block block) async {
    final topic = selectedTopic;
    if (topic == null) return;
    if (block.type == 'task') {
      final taskId = block.content['task_id'] as int?;
      if (taskId != null) {
        try {
          await _taskService.deleteTask(taskId);
        } catch (_) {}
      }
    }
    await _blockService.deleteBlock(block.id);
    await selectTopic(topic);
  }

  Future<void> addTasksFromLines(Block listBlock, List<String> lines) async {
    for (final line in lines) {
      if (line.trim().isEmpty) continue;
      await addTask(listBlock, line);
    }
  }

  Future<void> addTask(Block block, String title) async {
    final detail = selectedDetail;
    if (detail == null || title.trim().isEmpty) return;
    await _createTaskBlock(
      listBlock: block,
      fileId: block.fileId!,
      title: title.trim(),
      orderIndex: detail.blocksByFileId[block.fileId]?.length ?? 0,
    );
    notifyListeners();
  }

  Future<void> insertTaskAfter({
    required AppFile file,
    required Block listBlock,
    required Block afterTaskBlock,
  }) async {
    final topic = selectedTopic;
    final detail = selectedDetail;
    if (topic == null || detail == null) return;

    final orderIndex = (afterTaskBlock.orderIndex ?? 0) + 1;
    final targetIndex = await _shiftBlocksForInsert(file, orderIndex);
    final taskBlock = await _createTaskBlock(
      listBlock: listBlock,
      fileId: file.id,
      title: '',
      orderIndex: targetIndex,
    );
    await selectTopic(topic);
    requestBlockFocus(taskBlock.id);
  }

  Future<void> deleteTaskWithBlock(
    Task task,
    Block? taskBlock, {
    Block? focusTaskBlockAfterDelete,
  }) async {
    final topic = selectedTopic;
    if (topic == null) return;
    await _taskService.deleteTask(task.id);
    if (taskBlock != null) {
      await _blockService.deleteBlock(taskBlock.id);
    }
    await selectTopic(topic);
    if (focusTaskBlockAfterDelete != null) {
      requestBlockFocus(focusTaskBlockAfterDelete.id);
    }
  }

  Future<Block> _createTaskBlock({
    required Block listBlock,
    required int fileId,
    required String title,
    required int orderIndex,
  }) async {
    final detail = selectedDetail;
    if (detail == null) {
      throw StateError('No topic detail loaded');
    }
    final task = await _taskService.createTask(
      blockId: listBlock.id,
      title: title,
    );
    final taskBlock = await _blockService.createBlock(
      fileId: fileId,
      type: 'task',
      content: {'task_id': task.id},
      orderIndex: orderIndex,
    );
    final nextBlocks = <Block>[
      ...(detail.blocksByFileId[fileId] ?? const <Block>[]),
      taskBlock,
    ]..sort((a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0));
    detail.blocksByFileId[fileId] = nextBlocks;
    detail.tasksByBlockId[listBlock.id] = [
      ...(detail.tasksByBlockId[listBlock.id] ?? []),
      task,
    ];
    return taskBlock;
  }

  Future<void> updateTaskTitle(Task task, String title) async {
    await _updateTaskTitleAllowEmpty(task, title);
  }

  List<Task> orderedTasksForFile(AppFile file, Block listBlock) {
    final detail = selectedDetail;
    if (detail == null) return [];
    final blocks = List<Block>.from(detail.blocksByFileId[file.id] ?? [])
      ..sort((a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0));
    final taskById = {
      for (final task in detail.tasksByBlockId[listBlock.id] ?? const <Task>[])
        task.id: task,
    };
    final ordered = <Task>[];
    for (final block in blocks) {
      if (block.type != 'task') continue;
      final taskId = block.content['task_id'] as int?;
      if (taskId == null) continue;
      final task = taskById[taskId];
      if (task != null) ordered.add(task);
    }
    return ordered;
  }

  Future<void> syncTasksFromLines({
    required AppFile file,
    required Block listBlock,
    required List<String> lines,
  }) async {
    if (_syncingTasks) return;
    final topic = selectedTopic;
    final detail = selectedDetail;
    if (topic == null || detail == null) return;

    final normalized = lines.isEmpty ? <String>[''] : List<String>.from(lines);
    final ordered = orderedTasksForFile(file, listBlock);
    final previous = _taskLineSnapshots[listBlock.id] ??
        (ordered.isEmpty ? <String>[''] : ordered.map((task) => task.title).toList());

    final region = diffLineRegion(previous, normalized);
    if (region == null) {
      _taskLineSnapshots[listBlock.id] = normalized;
      return;
    }

    _syncingTasks = true;
    try {
      await _applyLineRegionToTasks(
        file: file,
        listBlock: listBlock,
        region: region,
        lines: normalized,
      );
      _taskLineSnapshots[listBlock.id] = normalized;
      notifyListeners();
    } finally {
      _syncingTasks = false;
    }
  }

  Future<void> _applyLineRegionToTasks({
    required AppFile file,
    required Block listBlock,
    required LineChangeRegion region,
    required List<String> lines,
  }) async {
    if (region.removed.length == 1 &&
        region.added.length == 1 &&
        region.start < orderedTasksForFile(file, listBlock).length) {
      final task = orderedTasksForFile(file, listBlock)[region.start];
      await _updateTaskTitleAllowEmpty(task, region.added.first);
      await _ensureTaskCountMatchesLines(file, listBlock, lines);
      return;
    }

    for (var i = region.removed.length - 1; i >= 0; i--) {
      await _deleteTaskAtLineIndex(file, listBlock, region.start + i);
    }

    for (var i = 0; i < region.added.length; i++) {
      final title = region.added[i];
      final idx = region.start + i;
      final ordered = orderedTasksForFile(file, listBlock);
      if (idx < ordered.length) {
        if (ordered[idx].title != title) {
          await _updateTaskTitleAllowEmpty(ordered[idx], title);
        }
      } else {
        final orderIndex = _orderIndexForTaskInsert(file, listBlock, idx);
        final targetIndex = await _shiftBlocksForInsert(file, orderIndex);
        await _createTaskBlock(
          listBlock: listBlock,
          fileId: file.id,
          title: title,
          orderIndex: targetIndex,
        );
      }
    }

    await _ensureTaskCountMatchesLines(file, listBlock, lines);
  }

  Future<void> _ensureTaskCountMatchesLines(
    AppFile file,
    Block listBlock,
    List<String> lines,
  ) async {
    var ordered = orderedTasksForFile(file, listBlock);
    while (ordered.length < lines.length) {
      final index = ordered.length;
      final orderIndex = _orderIndexForTaskInsert(file, listBlock, index);
      final targetIndex = await _shiftBlocksForInsert(file, orderIndex);
      await _createTaskBlock(
        listBlock: listBlock,
        fileId: file.id,
        title: lines[index],
        orderIndex: targetIndex,
      );
      ordered = orderedTasksForFile(file, listBlock);
    }
  }

  Future<void> _deleteTaskAtLineIndex(
    AppFile file,
    Block listBlock,
    int index,
  ) async {
    final ordered = orderedTasksForFile(file, listBlock);
    if (index < 0 || index >= ordered.length) return;
    final task = ordered[index];
    final detail = selectedDetail;
    if (detail == null) return;

    final blocks = detail.blocksByFileId[file.id] ?? [];
    Block? taskBlock;
    for (final block in blocks) {
      if (block.type == 'task' && block.content['task_id'] == task.id) {
        taskBlock = block;
        break;
      }
    }

    await _taskService.deleteTask(task.id);
    if (taskBlock != null) {
      await _blockService.deleteBlock(taskBlock.id);
    }

    detail.tasksByBlockId[listBlock.id] =
        (detail.tasksByBlockId[listBlock.id] ?? [])
            .where((t) => t.id != task.id)
            .toList();
    if (taskBlock != null) {
      detail.blocksByFileId[file.id] =
          (detail.blocksByFileId[file.id] ?? [])
              .where((b) => b.id != taskBlock!.id)
              .toList();
    }
  }

  int _orderIndexForTaskInsert(AppFile file, Block listBlock, int lineIndex) {
    final blocks = selectedDetail?.blocksByFileId[file.id] ?? [];
    final ordered = orderedTasksForFile(file, listBlock);

    if (lineIndex <= 0) {
      for (final block in blocks) {
        if (block.type == 'task') {
          return block.orderIndex ?? 0;
        }
      }
      return (listBlock.orderIndex ?? 0) + 1;
    }

    if (lineIndex <= ordered.length) {
      final prevTask = ordered[lineIndex - 1];
      for (final block in blocks) {
        if (block.type == 'task' && block.content['task_id'] == prevTask.id) {
          return (block.orderIndex ?? 0) + 1;
        }
      }
    }

    Block? lastTaskBlock;
    for (final block in blocks) {
      if (block.type == 'task') lastTaskBlock = block;
    }
    if (lastTaskBlock != null) {
      return (lastTaskBlock.orderIndex ?? 0) + 1;
    }
    return blocks.length;
  }

  Future<void> _updateTaskTitleAllowEmpty(Task task, String title) async {
    final updated = await _taskService.updateTask(task.id, {'title': title});
    _applyTaskUpdate(updated);
  }

  Future<void> removeChecklistItem(Block block, int index) async {
    final items = List<Map<String, dynamic>>.from(
      block.content['items'] as List<dynamic>? ?? [],
    );
    if (index < 0 || index >= items.length) return;
    items.removeAt(index);
    if (items.isEmpty) {
      items.add({'text': '', 'done': false});
    }
    await updateBlockContent(block, {
      ...block.content,
      'items': items,
    }, notify: true);
  }

  Future<void> toggleTaskStatus(Task task) async {
    final updated = await _taskService.updateTask(task.id, {
      'status': task.isDone ? 'active' : 'done',
    });
    _applyTaskUpdate(updated);
  }

  void _applyTaskUpdate(Task updated) {
    if (selectedViewType != null) {
      viewTasks = viewTasks
          .map((t) => t.id == updated.id ? updated : t)
          .toList();
    }
    final detail = selectedDetail;
    if (detail != null) {
      for (final entry in detail.tasksByBlockId.entries) {
        detail.tasksByBlockId[entry.key] = entry.value
            .map((t) => t.id == updated.id ? updated : t)
            .toList();
      }
    }
    notifyListeners();
  }

  Future<void> addTaskToView(
    Task task,
    String viewType, {
    String? sectionName,
  }) async {
    final existing = membershipForTaskInView(task.id, viewType);
    if (existing != null) {
      await updateTaskViewSection(
        existing,
        sectionName: sectionName,
        task: task,
        clearSection: sectionName == null,
      );
      return;
    }

    final membership = await _taskViewService.createMembership(
      taskId: task.id,
      viewType: viewType,
      sectionName: sectionName,
    );
    _taskViewMemberships = [..._taskViewMemberships, membership];

    if (selectedViewType == viewType) {
      final alreadyListed = viewTasks.any((t) => t.id == task.id);
      if (!alreadyListed) {
        viewTasks = [
          ...viewTasks,
          task.copyWith(
            taskViewId: membership.id,
            viewType: viewType,
            sectionName: sectionName,
            sectionFlag: membership.sectionFlag,
          ),
        ];
      }
    }
    notifyListeners();
  }

  Future<void> updateTaskViewSection(
    TaskViewMembership membership, {
    String? sectionName,
    required Task task,
    bool clearSection = false,
  }) async {
    final updated = await _taskViewService.update(
      membership.id,
      sectionName: sectionName,
      clearSection: clearSection,
    );
    _taskViewMemberships = _taskViewMemberships
        .map((m) => m.id == membership.id ? updated : m)
        .toList();

    if (selectedViewType == membership.viewType) {
      viewTasks = viewTasks
          .map(
            (t) => t.id == task.id
                ? t.copyWith(
                    sectionName: clearSection ? null : sectionName,
                    sectionFlag: updated.sectionFlag,
                    clearSection: clearSection,
                    clearSectionFlag: updated.sectionFlag == null,
                  )
                : t,
          )
          .toList();
    }
    notifyListeners();
  }

  Future<void> setViewSectionImportance(
    ViewSection section, {
    required bool important,
  }) async {
    final updated = await _taskViewService.updateSectionImportance(
      section.id,
      important: important,
    );
    viewSections = viewSections
        .map((s) => s.id == section.id ? updated : s)
        .toList();

    if (selectedViewType == section.viewType) {
      final flag = important ? ViewSectionFlags.important : null;
      viewTasks = viewTasks
          .map(
            (t) => t.sectionName == section.name
                ? t.copyWith(
                    sectionFlag: flag,
                    clearSectionFlag: !important,
                  )
                : t,
          )
          .toList();
      _viewCache[section.viewType] = _ViewSnapshot(
        tasks: List<Task>.from(viewTasks),
        sections: sectionsForViewType(section.viewType),
      );
    }
    notifyListeners();
  }

  Future<void> removeTaskFromView(TaskViewMembership membership) async {
    await _taskViewService.delete(membership.id);
    _taskViewMemberships = _taskViewMemberships
        .where((m) => m.id != membership.id)
        .toList();

    if (selectedViewType == membership.viewType) {
      viewTasks = viewTasks.where((t) => t.id != membership.taskId).toList();
    }
    notifyListeners();
  }

  Future<void> createViewSection(String viewType, String name) async {
    final section = await _taskViewService.createSection(
      viewType: viewType,
      name: name.trim(),
    );
    viewSections = [...viewSections, section];
    notifyListeners();
  }

  Future<void> deleteViewSection(ViewSection section) async {
    await _taskViewService.delete(section.id);
    viewSections = viewSections.where((s) => s.id != section.id).toList();
    if (selectedViewType == section.viewType) {
      await selectView(section.viewType);
    } else {
      notifyListeners();
    }
  }

  Future<void> reorderViewSections(
    String viewType,
    int oldIndex,
    int newIndex,
  ) async {
    final sections = sectionsForViewType(viewType);
    if (oldIndex < 0 ||
        oldIndex >= sections.length ||
        newIndex < 0 ||
        newIndex >= sections.length) {
      return;
    }
    if (oldIndex == newIndex) return;

    final reordered = List<ViewSection>.from(sections);
    final item = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, item);

    for (var i = 0; i < reordered.length; i++) {
      await _taskViewService.updateOrderIndex(reordered[i].id, i);
    }

    final others = viewSections.where((s) => s.viewType != viewType);
    viewSections = [
      ...others,
      ...[
        for (var i = 0; i < reordered.length; i++)
          ViewSection(
            id: reordered[i].id,
            viewType: reordered[i].viewType,
            name: reordered[i].name,
            orderIndex: i,
            sectionFlag: reordered[i].sectionFlag,
          ),
      ],
    ];
    notifyListeners();
  }

  Future<void> addChecklistItem(Block block, {int? index}) async {
    final items = List<Map<String, dynamic>>.from(
      block.content['items'] as List<dynamic>? ?? [],
    );
    final insertIndex = (index ?? items.length).clamp(0, items.length).toInt();
    items.insert(insertIndex, {'text': '', 'done': false});
    await updateBlockContent(block, {
      ...block.content,
      'items': items,
    }, notify: true);
  }

  Future<void> updateChecklistItem(
    Block block,
    int index,
    String text,
    bool done,
  ) async {
    final items = List<Map<String, dynamic>>.from(
      block.content['items'] as List<dynamic>? ?? [],
    );
    if (index < 0 || index > items.length) return;
    if (index == items.length) {
      items.add({'text': '', 'done': false});
    }
    items[index] = {'text': text, 'done': done};
    await updateBlockContent(block, {
      ...block.content,
      'items': items,
    }, notify: true);
  }

  Future<void> addBoardImageItem(
    AppFile file,
    Block boardBlock,
    String filename,
    List<int> bytes,
  ) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final uploaded = await _imageService.uploadBytes(filename, bytes);
    final items = boardItemsFromContent(boardBlock.content);
    final (x, y) = staggerBoardPlacement(items);
    final next = BoardItem(
      id: nextBoardItemId(items),
      imagePath: uploaded['image_path'] as String? ?? '',
      filename: uploaded['filename'] as String? ?? filename,
      x: x,
      y: y,
      width: 220,
      height: 165,
      zIndex: nextBoardZIndex(items),
    );
    if (next.imagePath.isEmpty) return;
    await updateBlockContent(
      boardBlock,
      boardContentFromItems([...items, next], base: boardBlock.content),
      notify: true,
    );
    await _blockService.updateBlock(boardBlock.id, {
      'content': boardContentFromItems(
        [...items, next],
        base: boardBlock.content,
      ),
    });
  }

  Future<Map<String, dynamic>> uploadImageBytes(
    String filename,
    List<int> bytes,
  ) async {
    return _imageService.uploadBytes(filename, bytes);
  }

  Future<void> addImageBlock(
    AppFile file,
    String filename,
    List<int> bytes,
  ) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final uploaded = await _imageService.uploadBytes(filename, bytes);
    final blocks = selectedDetail?.blocksByFileId[file.id] ?? [];
    await _blockService.createBlock(
      fileId: file.id,
      type: 'image',
      content: {
        'image_path': uploaded['image_path'],
        'filename': uploaded['filename'],
      },
      orderIndex: blocks.length,
    );
    await selectTopic(topic);
  }

  Future<void> insertImageBlock(
    AppFile file,
    String filename,
    List<int> bytes, {
    required int orderIndex,
  }) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final uploaded = await _imageService.uploadBytes(filename, bytes);
    final targetIndex = await _shiftBlocksForInsert(
      file,
      _effectiveInsertIndex(file, orderIndex, 'image'),
    );
    await _blockService.createBlock(
      fileId: file.id,
      type: 'image',
      content: {
        'image_path': uploaded['image_path'],
        'filename': uploaded['filename'],
      },
      orderIndex: targetIndex,
    );
    await selectTopic(topic);
  }

  Future<Block?> ensureTaskListBlock(AppFile file) async {
    final detail = selectedDetail;
    if (detail == null) return null;
    final blocks = detail.blocksByFileId[file.id] ?? [];
    for (final block in blocks) {
      if (block.type == 'task_list') return block;
    }
    final block = await _blockService.createBlock(
      fileId: file.id,
      type: 'task_list',
      content: {},
      orderIndex: blocks.length,
    );
    detail.blocksByFileId[file.id] = [...blocks, block];
    detail.tasksByBlockId[block.id] = [];
    notifyListeners();
    return block;
  }

  @override
  void dispose() {
    _automationRunPollTimer?.cancel();
    for (final timer in _saveTimers.values) {
      timer?.cancel();
    }
    super.dispose();
  }
}
