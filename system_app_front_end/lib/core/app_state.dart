import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_context.dart';
import 'browse/bring_file_catalog.dart';
import 'platform/app_form_factor.dart';
import '../features/bring_file/bring_file_preview.dart';
import 'l10n/app_language.dart';
import 'l10n/app_strings.dart';
import 'models/ai_proposal.dart';
import 'models/app_file.dart';
import 'models/archive_index.dart';
import 'models/automation_companion_link.dart';
import 'models/automation_definition.dart';
import 'models/automation_rule.dart';
import 'models/automation_run.dart';
import 'models/block.dart';
import 'models/brought_file_snapshot.dart';
import '../features/blocks/board_content.dart';
import '../features/blocks/block_text_focus.dart';
import '../shared/utils/platform_text.dart';
import 'models/part.dart';
import 'models/task.dart';
import 'models/task_reset_acknowledgement.dart';
import 'models/task_view_membership.dart';
import 'models/topic.dart';
import 'models/view_section.dart';
import 'models/view_section_flags.dart';
import 'registry/automation_flow_registry.dart';
import 'registry/file_behavior_registry.dart';
import 'registry/file_registry.dart';
import 'registry/task_view_display.dart';
import 'models/view_pane_sync_context.dart';
import 'registry/topic_appearance.dart';
import '../design_system/file_layouts.dart';
import 'services/ai_service.dart';
import 'services/ai_proposal_service.dart';
import 'services/api_service.dart';
import 'services/automation_companion_service.dart';
import 'services/automation_definition_service.dart';
import 'services/automation_service.dart';
import 'services/block_service.dart';
import 'services/bootstrap_service.dart';
import 'services/file_service.dart';
import 'services/image_service.dart';
import 'services/part_service.dart';
import 'services/process_documentation_input_service.dart';
import 'services/task_service.dart';
import 'services/task_reset_acknowledgement_service.dart';
import 'services/task_view_service.dart';
import 'services/topic_service.dart';
import 'task_file_layout.dart';
import '../features/tasks/task_drag_data.dart';
import 'task_list_order.dart';
import 'shortcuts/main_file_cycle.dart';
import 'shortcuts/shortcut_binding.dart';
import 'shortcuts/shortcut_bindings_store.dart';

class TopicDetail {
  TopicDetail({
    required this.topic,
    required this.files,
    required this.blocksByFileId,
    required this.tasksByBlockId,
    required this.parts,
  });

  final Topic topic;
  final List<AppFile> files;
  final Map<int, List<Block>> blocksByFileId;
  final Map<int, List<Task>> tasksByBlockId;
  final List<Part> parts;
}

class _ViewSnapshot {
  const _ViewSnapshot({required this.tasks, required this.sections});

  final List<Task> tasks;
  final List<ViewSection> sections;
}

class TopicTasksTarget {
  const TopicTasksTarget({
    required this.topic,
    required this.file,
    required this.listBlock,
  });

  final Topic topic;
  final AppFile file;
  final Block listBlock;
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
  late final AutomationDefinitionService _definitionService =
      AutomationDefinitionService(_api);
  late final AiProposalService _aiProposalService = AiProposalService(_api);
  late final AutomationCompanionService _companionService =
      AutomationCompanionService(_api);
  late final TaskResetAcknowledgementService _taskResetAcknowledgementService =
      TaskResetAcknowledgementService(_api);
  late final PartService _partService = PartService(_api);
  late final ProcessDocumentationInputService _processDocumentationInputService =
      ProcessDocumentationInputService(_api);

  bool loading = true;
  bool appReady = false;
  String? error;
  List<Topic> topics = [];
  Topic? mainTopic;
  Topic? selectedTopic;
  TopicDetail? selectedDetail;
  String? selectedViewType;
  List<Task> viewTasks = [];
  List<ViewSection> viewSections = [];
  TaskResetAcknowledgement? pendingTaskResetAcknowledgement;
  final Map<String, _ViewSnapshot> _viewCache = {};
  final Map<int, List<Part>> _partsCache = {};
  bool _showViewPaneDuringLoad = false;
  bool _loadingTopicFromView = false;
  TaskViewDisplayMode viewDisplayMode = TaskViewDisplayMode.bySection;
  List<TaskViewMembership> _taskViewMemberships = [];
  List<AutomationRule> automationRules = [];
  List<AutomationDefinition> automationDefinitions = [];
  List<AiProposal> pendingAiProposals = [];
  Map<int, List<AppFile>> archivedFilesByTopicId = {};
  ArchiveIndex archiveIndex = ArchiveIndex.empty;
  Topic? selectedArchiveTopic;
  List<AppFile> archiveFilesForTopic = [];
  Map<int, List<Block>> archiveBlocksByFileId = {};
  Map<int, List<Task>> archiveTasksByBlockId = {};
  Map<int, List<String>> archiveHeaderTextsByFileId = {};
  AppFile? selectedArchiveFile;
  bool archiveDeleteMode = false;
  final Set<int> archiveDeleteSelection = {};
  int archiveTotalCount = 0;
  bool archiveHasMore = false;
  bool archiveInitialLoading = false;
  bool archiveLoadingMore = false;
  String archiveSearchQuery = '';
  List<AppFile> archiveRemoteSearchResults = [];
  bool archiveSearchHasMore = false;
  bool archiveSearchLoading = false;
  int _archiveBrowseOffset = 0;
  int _archiveSearchOffset = 0;
  Timer? _archiveSearchDebounce;
  static const archivePageSize = 24;
  bool moreFilesExpanded = false;
  final Map<int, String> _layoutByTopicId = {};
  AppLanguage language = AppLanguage.en;
  ShortcutBindingsStore shortcutBindings = ShortcutBindingsStore();
  final shortcutRebuildListenable = ValueNotifier<int>(0);
  AiFocus? aiFocus;
  int? pendingFocusBlockId;
  bool aiRunning = false;
  BroughtFileSnapshot? broughtFile;
  int? phoneFocusFileId;

  final Map<int, Timer?> _saveTimers = {};
  final Map<int, String?> _automationLastRunAtById = {};
  final Map<int, int> _activeAutomationRunsByRuleId = {};
  final Set<int> _notifiedAutomationRunIds = {};
  Timer? _automationRunPollTimer;
  Timer? _automationStatusPollTimer;
  bool _pollingAutomationRuns = false;
  String? _automationNotice;

  AppStrings get strings => AppStrings.forLanguage(language);
  bool get isRtl => strings.isRtl;
  TextDirection get textDirection => strings.textDirection;

  String viewLabel(String type) => strings.viewLabel(type);
  String fileDisplayName(String name) => strings.fileNameLabel(name);
  String topicDisplayName(Topic topic) =>
      topic.isMain ? strings['main'] : topic.name;
  String taskTopicDisplayName(Task task) =>
      strings.displayTopicName(task.topicName);

  bool get hasBroughtFile => broughtFile != null;

  bool isGuestFile(AppFile file) => broughtFile?.file.id == file.id;

  void clearBroughtFile() {
    if (broughtFile == null) return;
    broughtFile = null;
    notifyListeners();
  }

  void clearPhoneFocusFile() {
    if (phoneFocusFileId == null) return;
    phoneFocusFileId = null;
    notifyListeners();
  }

  Future<void> bringFileOnPhone(Topic sourceTopic, AppFile file) async {
    clearBroughtFile();
    phoneFocusFileId = file.id;
    if (selectedTopic?.id != sourceTopic.id) {
      await selectTopic(sourceTopic);
    } else {
      notifyListeners();
    }
  }

  Future<List<BrowseFileEntry>> loadBringFileCatalog() async {
    final files = await _fileService.listAll();
    return buildBringFileCatalog(
      topics: topics,
      files: files,
      mainTopic: mainTopic,
    );
  }

  Future<Map<int, OverlayFilePreviewData>> loadBringFilePreviews(
    List<AppFile> files,
  ) async {
    final previews = <int, OverlayFilePreviewData>{};
    await Future.wait(
      files.map((file) async {
        try {
          final blocks = await _blockService.listForFile(file.id);
          previews[file.id] = await previewDataForFile(
            blocks,
            _taskService.listForBlock,
          );
        } catch (_) {
          previews[file.id] = OverlayFilePreviewData.empty;
        }
      }),
    );
    return previews;
  }

  Future<void> bringFile(Topic sourceTopic, AppFile file) async {
    error = null;
    try {
      broughtFile = await _loadBroughtFileSnapshot(sourceTopic, file);
    } catch (e) {
      error = e.toString();
      broughtFile = null;
    }
    notifyListeners();
  }

  Future<BroughtFileSnapshot> _loadBroughtFileSnapshot(
    Topic sourceTopic,
    AppFile file,
  ) async {
    final loaded = await _blockService.listForFile(file.id);
    final ensured = file.type == 'board'
        ? await _ensureBoardBlock(file, loaded)
        : loaded;
    final normalized = file.type == 'board'
        ? ensured
        : await _removeAdjacentTextBlocks(file, ensured);
    final blocks = await _ensureTrailingDefaultBlock(file, normalized);
    final tasksByBlockId = <int, List<Task>>{};
    for (final block in blocks) {
      if (block.type == 'task' || block.type == 'task_list') {
        tasksByBlockId[block.id] = await _taskService.listForBlock(block.id);
      }
    }
    return BroughtFileSnapshot(
      sourceTopic: sourceTopic,
      file: file,
      blocks: blocks,
      tasksByBlockId: tasksByBlockId,
    );
  }

  Future<void> _reloadBroughtFileBlocks() async {
    final guest = broughtFile;
    if (guest == null) return;
    try {
      broughtFile = await _loadBroughtFileSnapshot(guest.sourceTopic, guest.file);
    } catch (e) {
      error = e.toString();
      broughtFile = null;
    }
    notifyListeners();
  }

  List<Block> _blocksForFile(AppFile file) {
    if (isGuestFile(file)) return broughtFile!.blocks;
    return selectedDetail?.blocksByFileId[file.id] ?? [];
  }

  List<Block> _blocksForFileId(int fileId) {
    if (broughtFile?.file.id == fileId) return broughtFile!.blocks;
    return selectedDetail?.blocksByFileId[fileId] ?? [];
  }

  Map<int, List<Task>> _tasksByBlockIdForFile(AppFile file) {
    if (isGuestFile(file)) return broughtFile!.tasksByBlockId;
    return selectedDetail?.tasksByBlockId ?? {};
  }

  Map<int, List<Task>> tasksByBlockIdForFile(AppFile file) =>
      _tasksByBlockIdForFile(file);

  Future<void> _refreshAfterFileMutation(AppFile file) async {
    final topic = selectedTopic;
    if (topic == null) return;
    await selectTopic(topic);
    if (isGuestFile(file)) await _reloadBroughtFileBlocks();
  }

  Topic? topicById(int id) {
    for (final topic in topics) {
      if (topic.id == id) return topic;
    }
    return null;
  }

  Topic? topicForViewPaneGroup({String? topicKey}) {
    if (topicKey == null || topicKey == ViewPaneKeys.noTopic) return null;
    for (final topic in topics) {
      if (topic.name == topicKey) return topic;
      if (topicKey == 'main' && topic.isMain) return topic;
    }
    return null;
  }

  List<Topic> get activeTopics => topics.where((t) => !t.isArchived).toList();

  List<Topic> get archivedTopics =>
      topics.where((t) => t.isArchived && !t.isMain).toList();

  bool get hasArchive => !archiveIndex.isEmpty;

  bool get isArchiveMode => selectedArchiveTopic != null;

  bool get archiveIsSearching => archiveSearchQuery.isNotEmpty;

  bool get archiveIsFetchingMore => archiveLoadingMore || archiveSearchLoading;

  List<AppFile> get displayArchiveFiles {
    if (!archiveIsSearching) return archiveFilesForTopic;
    final q = archiveSearchQuery.toLowerCase();
    final seen = <int>{};
    final merged = <AppFile>[];
    for (final file in archiveFilesForTopic) {
      if (_archiveFileMatchesQuery(file, q) && seen.add(file.id)) {
        merged.add(file);
      }
    }
    for (final file in archiveRemoteSearchResults) {
      if (seen.add(file.id)) {
        merged.add(file);
      }
    }
    return merged;
  }

  Future<void> setLanguage(AppLanguage value) async {
    if (language == value) return;
    language = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', value.name);
    notifyListeners();
  }

  Future<void> setShortcutBinding(
    String actionId,
    ShortcutBinding binding,
  ) async {
    await shortcutBindings.setBinding(actionId, binding);
    _notifyShortcutRebuild();
    notifyListeners();
  }

  Future<void> resetShortcut(String actionId) async {
    await shortcutBindings.resetBinding(actionId);
    _notifyShortcutRebuild();
    notifyListeners();
  }

  Future<void> resetAllShortcuts() async {
    await shortcutBindings.resetAll();
    _notifyShortcutRebuild();
    notifyListeners();
  }

  void _notifyShortcutRebuild() {
    shortcutRebuildListenable.value++;
  }

  void _setAiRunning(bool value) {
    if (aiRunning == value) return;
    aiRunning = value;
    _notifyShortcutRebuild();
  }

  static bool _aiContextEmpty(AiFocus? focus) {
    return focus == null || focus.fullText.trim().isEmpty;
  }

  bool _aiFocusShortcutContextChanged(AiFocus? prev, AiFocus next) {
    return prev?.fileId != next.fileId ||
        prev?.blockId != next.blockId ||
        _aiContextEmpty(prev) != _aiContextEmpty(next);
  }

  bool _aiFocusNotifyScheduled = false;

  void setAiFocus(AiFocus focus) {
    final prev = aiFocus;
    final shortcutContextChanged = _aiFocusShortcutContextChanged(prev, focus);
    aiFocus = focus;
    if (shortcutContextChanged) {
      _notifyShortcutRebuild();
    }
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

  AppFile? get aiFocusedFile {
    final detail = selectedDetail;
    final focus = aiFocus;
    if (detail == null || focus == null) return null;
    for (final file in detail.files) {
      if (file.id == focus.fileId) return file;
    }
    return null;
  }

  bool get canUseAiTools =>
      !isArchiveMode && !isViewMode && selectedDetail != null;

  bool canRunAiTool(String tool) {
    if (!canUseAiTools) return false;
    if (tool == 'review') return true;
    if (tool == 'move_file_to_topic') {
      final file = aiFocusedFile;
      return file != null && !isGuestFile(file);
    }
    return hasAiContext;
  }

  Future<bool> runSuggestEmoji() async {
    final ctx = resolveAiContext();
    final topic = selectedTopic;
    if (ctx == null || ctx.text.trim().isEmpty || topic == null) {
      return false;
    }

    final fallbackOffset = _insertOffsetFromAiFocus(aiFocus);
    BlockTextFocusRegistry.beginAiInsertSession(
      fallbackInsertOffset: fallbackOffset,
    );
    if (!BlockTextFocusRegistry.hasAiInsertTarget) {
      return false;
    }

    _setAiRunning(true);
    error = null;
    notifyListeners();
    try {
      final result = await _aiService.runTool(
        tool: 'suggest_emoji',
        topicId: topic.id,
        context: ctx,
        locale: language.name,
      );
      final emoji = insertableEmojis(result.result ?? '');
      if (emoji == null) return false;
      BlockTextFocusRegistry.insertAiEmoji(emoji);
      return true;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      BlockTextFocusRegistry.endAiInsertSession();
      _setAiRunning(false);
      notifyListeners();
    }
  }

  static int? _insertOffsetFromAiFocus(AiFocus? focus) {
    final selection = focus?.selection;
    if (selection == null || !selection.isValid) return null;
    final length = focus!.fullText.length;
    if (!selection.isCollapsed) {
      return selection.end.clamp(0, length);
    }
    return selection.baseOffset.clamp(0, length);
  }

  Future<AiRunResult?> runAiTool(
    String tool, {
    ResolvedAiContext? contextOverride,
  }) async {
    final topic = selectedTopic;
    if (topic == null) return null;

    var ctx = contextOverride ?? resolveAiContext();
    if (ctx == null) return null;
    if (ctx.text.trim().isEmpty) return null;

    _setAiRunning(true);
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
      _setAiRunning(false);
      notifyListeners();
    }
  }

  Future<AiRunResult?> runAiMoveFile(Topic topic, AppFile file) async {
    if (!canUseAiTools) return null;

    _setAiRunning(true);
    error = null;
    notifyListeners();
    try {
      final result = await _aiService.runTool(
        tool: 'move_file_to_topic',
        topicId: topic.id,
        context: ResolvedAiContext(
          text: file.name,
          sourceType: AiSourceType.line,
          topicId: topic.id,
          fileId: file.id,
        ),
        locale: language.name,
      );
      await selectTopic(topic);
      return result;
    } catch (e) {
      error = e.toString();
      rethrow;
    } finally {
      _setAiRunning(false);
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
        sourceType: AiSourceType.line,
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

    _setAiRunning(true);
    error = null;
    notifyListeners();
    try {
      final result = await _aiService.runTool(
        tool: 'create_image',
        topicId: topic.id,
        context: ResolvedAiContext(
          text: prompt.trim(),
          sourceType: AiSourceType.line,
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
          final content = boardContentFromItems([
            ...items,
            next,
          ], base: board.content);
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
      _setAiRunning(false);
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

  List<Topic> get others => topics
      .where((t) => t.type == 'others' && !t.isMain && !t.isArchived)
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
      shortcutBindings = await ShortcutBindingsStore.load();
      mainTopic = await _bootstrap.ensureMainTopic();
      await refreshTopics();
      await refreshAutomationRules();
      await loadArchive();
      await _refreshTaskViewMemberships();
      await selectTopic(mainTopic!);
      _rememberAutomationRunState();
      await _hydrateActiveAutomationRuns();
      _startAutomationRunPolling();
    } catch (e) {
      error = e.toString();
    } finally {
      loading = false;
      appReady = true;
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

  TaskViewMembership? primaryMembershipForTask(int taskId) {
    for (final m in _taskViewMemberships) {
      if (m.taskId == taskId) return m;
    }
    return null;
  }

  String? viewTypeForTask(int taskId) => primaryMembershipForTask(taskId)?.viewType;

  int orderIndexForTask(int taskId) =>
      primaryMembershipForTask(taskId)?.orderIndex ?? 0;

  List<ViewSection> sectionsForViewType(String viewType) {
    return viewSections.where((s) => s.viewType == viewType).toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
  }

  Future<List<ViewSection>> fetchSectionsForView(String viewType) =>
      _taskViewService.listSectionsForView(viewType);

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
    ArchiveTopicEntry? daily;
    final projectEntries = <ArchiveTopicEntry>[];
    final processEntries = <ArchiveTopicEntry>[];
    final areaEntries = <ArchiveTopicEntry>[];
    final othersEntries = <ArchiveTopicEntry>[];
    final archive = <int, List<AppFile>>{};

    for (final topic in topics) {
      final summary = await _fileService.listArchiveForTopic(
        topic.id,
        limit: 0,
      );
      if (summary.total == 0) continue;

      archive[topic.id] = const [];
      final entry = ArchiveTopicEntry(
        topic: topic,
        archivedFileCount: summary.total,
      );

      if (topic.isMain) {
        daily = entry;
      } else {
        switch (topic.type) {
          case 'project':
            projectEntries.add(entry);
          case 'process':
            processEntries.add(entry);
          case 'area':
            areaEntries.add(entry);
          case 'others':
            othersEntries.add(entry);
        }
      }
    }

    archiveIndex = ArchiveIndex(
      daily: daily,
      projects: projectEntries,
      processes: processEntries,
      areas: areaEntries,
      others: othersEntries,
    );
    archivedFilesByTopicId = archive;
    notifyListeners();
  }

  void _clearArchiveMode() {
    _archiveSearchDebounce?.cancel();
    selectedArchiveTopic = null;
    archiveFilesForTopic = [];
    archiveBlocksByFileId = {};
    archiveTasksByBlockId = {};
    archiveHeaderTextsByFileId = {};
    selectedArchiveFile = null;
    archiveDeleteMode = false;
    archiveDeleteSelection.clear();
    archiveTotalCount = 0;
    archiveHasMore = false;
    archiveInitialLoading = false;
    archiveLoadingMore = false;
    archiveSearchQuery = '';
    archiveRemoteSearchResults = [];
    archiveSearchHasMore = false;
    archiveSearchLoading = false;
    _archiveBrowseOffset = 0;
    _archiveSearchOffset = 0;
  }

  void _mergeArchiveHeaderTexts(Map<int, List<String>> texts) {
    texts.forEach((fileId, headers) {
      if (headers.isEmpty) return;
      archiveHeaderTextsByFileId[fileId] = headers;
    });
  }

  bool _archiveFileMatchesQuery(AppFile file, String query) {
    if (query.isEmpty) return true;
    return archiveFileSearchLabel(file).toLowerCase().contains(query);
  }

  Future<void> _loadArchiveBrowsePage({required bool append}) async {
    final topic = selectedArchiveTopic;
    if (topic == null) return;

    archiveLoadingMore = append;
    if (!append) {
      archiveInitialLoading = true;
    }
    notifyListeners();

    try {
      final page = await _fileService.listArchiveForTopic(
        topic.id,
        limit: archivePageSize,
        offset: append ? _archiveBrowseOffset : 0,
      );
      _mergeArchiveHeaderTexts(page.headerTextsByFileId);
      if (append) {
        archiveFilesForTopic = [...archiveFilesForTopic, ...page.files];
      } else {
        archiveFilesForTopic = page.files;
      }
      _archiveBrowseOffset = archiveFilesForTopic.length;
      archiveHasMore = page.hasMore;
      archiveTotalCount = page.total;
    } catch (e) {
      error = e.toString();
    } finally {
      archiveInitialLoading = false;
      archiveLoadingMore = false;
      notifyListeners();
    }
  }

  Future<void> _fetchArchiveSearchPage({required bool reset}) async {
    final topic = selectedArchiveTopic;
    if (topic == null || archiveSearchQuery.isEmpty) return;

    archiveSearchLoading = true;
    notifyListeners();

    try {
      final page = await _fileService.listArchiveForTopic(
        topic.id,
        limit: archivePageSize,
        offset: reset ? 0 : _archiveSearchOffset,
        query: archiveSearchQuery,
      );
      _mergeArchiveHeaderTexts(page.headerTextsByFileId);
      if (reset) {
        archiveRemoteSearchResults = page.files;
        _archiveSearchOffset = page.files.length;
      } else {
        archiveRemoteSearchResults = [
          ...archiveRemoteSearchResults,
          ...page.files,
        ];
        _archiveSearchOffset += page.files.length;
      }
      archiveSearchHasMore = page.hasMore;
    } catch (e) {
      error = e.toString();
    } finally {
      archiveSearchLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadArchivePreviewForFile(AppFile file) async {
    if (archiveBlocksByFileId.containsKey(file.id)) return;

    try {
      final blocks = await _blockService.listForFile(
        file.id,
        includeArchived: true,
      );
      archiveBlocksByFileId[file.id] = blocks;
      final headerTexts = [
        for (final block in blocks)
          if (block.type == 'header' && block.text.trim().isNotEmpty)
            block.text.trim(),
      ];
      if (headerTexts.isNotEmpty) {
        archiveHeaderTextsByFileId[file.id] = headerTexts;
      }
      for (final block in blocks) {
        if (block.type == 'task' || block.type == 'task_list') {
          archiveTasksByBlockId[block.id] = await _taskService.listForBlock(
            block.id,
          );
        }
      }
      notifyListeners();
    } catch (e) {
      error = e.toString();
      notifyListeners();
    }
  }

  Future<void> selectArchiveTopic(Topic topic) async {
    if (isPhoneLayout) return;
    error = null;
    selectedViewType = null;
    selectedTopic = null;
    selectedDetail = null;
    pendingAiProposals = [];
    _clearArchiveMode();
    selectedArchiveTopic = topic;
    _notifyShortcutRebuild();
    notifyListeners();

    try {
      await _loadArchiveBrowsePage(append: false);
      if (archiveFilesForTopic.isEmpty) return;
      selectedArchiveFile = archiveFilesForTopic.first;
      notifyListeners();
      await _loadArchivePreviewForFile(archiveFilesForTopic.first);
    } catch (e) {
      error = e.toString();
      _clearArchiveMode();
      notifyListeners();
    }
  }

  Future<void> selectArchiveFile(AppFile file) async {
    if (selectedArchiveFile?.id == file.id) return;
    selectedArchiveFile = file;
    notifyListeners();
    await _loadArchivePreviewForFile(file);
  }

  void onArchiveSearchQueryChanged(String query) {
    final trimmed = query.trim();
    if (trimmed == archiveSearchQuery) return;
    archiveSearchQuery = trimmed;
    archiveRemoteSearchResults = [];
    archiveSearchHasMore = false;
    _archiveSearchOffset = 0;
    _archiveSearchDebounce?.cancel();
    if (trimmed.isEmpty) {
      archiveSearchLoading = false;
      notifyListeners();
      return;
    }
    notifyListeners();
    _archiveSearchDebounce = Timer(const Duration(milliseconds: 350), () {
      _fetchArchiveSearchPage(reset: true);
    });
  }

  Future<void> loadMoreArchiveContent() async {
    if (archiveLoadingMore || archiveSearchLoading) return;
    if (archiveIsSearching) {
      if (!archiveSearchHasMore) return;
      await _fetchArchiveSearchPage(reset: false);
      return;
    }
    if (!archiveHasMore) return;
    await _loadArchiveBrowsePage(append: true);
  }

  List<String> headerTextsForArchiveFile(AppFile file) {
    final cached = archiveHeaderTextsByFileId[file.id];
    if (cached != null && cached.isNotEmpty) return cached;
    final blocks = archiveBlocksByFileId[file.id] ?? const [];
    return [
      for (final block in blocks)
        if (block.type == 'header' && block.text.trim().isNotEmpty)
          block.text.trim(),
    ];
  }

  String archiveFileSearchLabel(AppFile file) {
    final title = fileDisplayName(file.name);
    final headers = headerTextsForArchiveFile(file);
    if (headers.isEmpty) return title;
    return '$title ${headers.join(' ')}';
  }

  void toggleArchiveDeleteMode() {
    archiveDeleteMode = !archiveDeleteMode;
    if (!archiveDeleteMode) {
      archiveDeleteSelection.clear();
    }
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
    final topic = selectedArchiveTopic;
    if (topic == null || archiveDeleteSelection.isEmpty) return;

    final ids = archiveDeleteSelection.toList();

    try {
      for (final id in ids) {
        await _fileService.deleteFile(id);
      }
      archiveDeleteMode = false;
      archiveDeleteSelection.clear();
      await loadArchive();
      await selectArchiveTopic(topic);
    } catch (e) {
      error = e.toString();
      archiveInitialLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshAutomationRules() async {
    automationDefinitions = await _definitionService.list();
    automationRules = await _automationService.listRules();
    if (await _ensureMainAutomationRules()) {
      automationRules = await _automationService.listRules();
    }
    notifyListeners();
  }

  AutomationDefinition? definitionForKey(String key) {
    for (final definition in automationDefinitions) {
      if (definition.key == key) return definition;
    }
    return null;
  }

  Future<void> ensureMainAutomationRules() => refreshAutomationRules();

  Future<bool> updateAutomationRule(
    AutomationRule rule, {
    bool? enabled,
    String? schedule,
    String? triggerType,
    Map<String, dynamic>? params,
  }) async {
    final patch = <String, dynamic>{};
    if (enabled != null) {
      patch['enabled'] = enabled;
    }
    if (schedule != null) {
      patch['schedule'] = schedule;
    }
    if (triggerType != null) {
      patch['trigger_type'] = triggerType;
    }
    if (params != null) {
      patch['params'] = params;
    }
    try {
      await _automationService.updateRule(rule.id, patch);
      await refreshAutomationRules();
      if (selectedViewType != null) {
        await refreshCurrentView();
      }
      return true;
    } on ApiException catch (error) {
      _automationNotice = error.message;
      notifyListeners();
      return false;
    }
  }

  Future<void> runAutomationRule(AutomationRule rule) async {
    final run = await _automationService.runRule(rule.id);
    _trackAutomationRun(rule.id, run);
    _ensureAutomationStatusPolling();
    notifyListeners();
  }

  bool isAutomationRuleActive(int ruleId) =>
      _activeAutomationRunsByRuleId.containsKey(ruleId);

  String? takeAutomationNotice() {
    final notice = _automationNotice;
    _automationNotice = null;
    return notice;
  }

  void _trackAutomationRun(int ruleId, AutomationRun run) {
    if (run.isActive) {
      _activeAutomationRunsByRuleId[ruleId] = run.id;
    }
  }

  void _ensureAutomationStatusPolling() {
    if (_automationStatusPollTimer != null) return;
    _automationStatusPollTimer = Timer.periodic(
      const Duration(seconds: 8),
      (_) => _pollActiveAutomationRuns(),
    );
  }

  Future<void> _pollActiveAutomationRuns() async {
    if (_activeAutomationRunsByRuleId.isEmpty) {
      _automationStatusPollTimer?.cancel();
      _automationStatusPollTimer = null;
      return;
    }
    if (_pollingAutomationRuns) return;
    _pollingAutomationRuns = true;
    try {
      var completed = false;
      for (final entry in _activeAutomationRunsByRuleId.entries.toList()) {
        final run = await _automationService.getRun(entry.value);
        if (run.isActive) continue;

        _activeAutomationRunsByRuleId.remove(entry.key);
        completed = true;
        if (_notifiedAutomationRunIds.contains(run.id)) continue;
        _notifiedAutomationRunIds.add(run.id);
        _automationNotice = run.status == 'success'
            ? strings['automationCompleted']
            : strings['automationRunFailed'];
      }

      if (!completed) return;

      await refreshAutomationRules();
      _rememberAutomationRunState();
      if (_hasOpenContent) {
        await _refreshVisibleContentAfterAutomation();
      }
      notifyListeners();
    } catch (_) {
      // Active run checks should never interrupt editing.
    } finally {
      _pollingAutomationRuns = false;
    }
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

  Future<void> _hydrateActiveAutomationRuns() async {
    try {
      final runs = await _automationService.listActiveRuns();
      for (final run in runs) {
        _activeAutomationRunsByRuleId[run.ruleId] = run.id;
      }
      if (_activeAutomationRunsByRuleId.isNotEmpty) {
        _ensureAutomationStatusPolling();
      }
    } catch (_) {
      // Active run hydration should not block app startup.
    }
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
    Map<String, bool> decisions, {
    int? companionTaskId,
    bool refreshTopicBanner = true,
  }) async {
    await _aiProposalService.finalize(
      proposal.id,
      Map<String, dynamic>.from(decisions),
    );
    pendingAiProposals = pendingAiProposals
        .where((item) => item.id != proposal.id)
        .toList();
    if (companionTaskId != null) {
      await _completeCompanionTaskById(companionTaskId);
      if (refreshTopicBanner) {
        await refreshPendingProposalsForTopics(_topicIdsForProposal(proposal));
      } else {
        notifyListeners();
      }
      return;
    }
    final topic = selectedTopic;
    if (topic != null) {
      await selectTopic(topic, includeArchived: topic.isArchived);
    } else {
      await refreshTopics();
      await loadArchive();
      notifyListeners();
    }
  }

  Future<AiProposal> finalizeProjectUpdate(
    AiProposal proposal,
    Map<String, bool> decisions, {
    int? companionTaskId,
    bool refreshTopicBanner = true,
  }) async {
    final updated = await _aiProposalService.finalize(
      proposal.id,
      Map<String, dynamic>.from(decisions),
    );
    pendingAiProposals = pendingAiProposals
        .where((item) => item.id != proposal.id)
        .toList();
    if (companionTaskId != null) {
      await _completeCompanionTaskById(companionTaskId);
      if (refreshTopicBanner) {
        await refreshPendingProposalsForTopics(_topicIdsForProposal(proposal));
      } else {
        notifyListeners();
      }
      return updated;
    }
    final topic = selectedTopic;
    if (topic != null) {
      await selectTopic(topic, includeArchived: topic.isArchived);
    } else {
      await refreshTopics();
      await loadArchive();
      notifyListeners();
    }
    return updated;
  }

  Future<void> rejectAiProposal(
    AiProposal proposal, {
    int? companionTaskId,
    bool refreshTopicBanner = true,
  }) async {
    await _aiProposalService.reject(proposal.id);
    pendingAiProposals = pendingAiProposals
        .where((item) => item.id != proposal.id)
        .toList();
    if (companionTaskId != null) {
      await _completeCompanionTaskById(companionTaskId);
      if (refreshTopicBanner) {
        await refreshPendingProposalsForTopics(_topicIdsForProposal(proposal));
      } else {
        notifyListeners();
      }
      return;
    }
    notifyListeners();
  }

  Iterable<int> _topicIdsForProposal(AiProposal proposal) {
    if (proposal.topicId != null) return [proposal.topicId!];
    return const [];
  }

  /// Keeps the process-topic pending banner in sync after companion flows finish.
  Future<void> refreshPendingProposalsForTopics(Iterable<int> topicIds) async {
    final ids = topicIds.where((id) => id > 0).toSet();
    if (ids.isEmpty) {
      notifyListeners();
      return;
    }

    final selected = selectedTopic;
    if (selected != null && ids.contains(selected.id)) {
      pendingAiProposals = await _aiProposalService.listPending(
        topicId: selected.id,
      );
      notifyListeners();
      return;
    }

    for (final topicId in ids) {
      final fresh = await _aiProposalService.listPending(topicId: topicId);
      pendingAiProposals = [
        for (final proposal in pendingAiProposals)
          if (proposal.topicId != topicId) proposal,
        ...fresh,
      ];
    }
    notifyListeners();
  }

  Future<AiProposal> fetchAiProposal(int id) => _aiProposalService.getById(id);

  Future<List<AutomationCompanionLink>> fetchPendingCompanionsForTask(
    int taskId,
  ) => _companionService.listPendingForTask(taskId);

  Future<void> completeAutomationCompanion(int companionTaskId) =>
      _completeCompanionTaskById(companionTaskId);

  Future<void> submitProcessDocumentationInput({
    required int topicId,
    required String text,
    required int grade,
    int? companionTaskId,
  }) async {
    String? timezone;
    for (final rule in automationRules) {
      if (rule.key == 'process_documentation_input') {
        timezone = rule.timezone;
        break;
      }
    }
    await _processDocumentationInputService.submit(
      topicId: topicId,
      text: text,
      grade: grade,
      timezone: timezone,
    );
    if (companionTaskId != null) {
      await _completeCompanionTaskById(companionTaskId);
    }
    final topic = selectedTopic;
    if (topic != null && topic.id == topicId) {
      await selectTopic(topic, includeArchived: topic.isArchived);
    }
  }

  Future<bool> runCompanionTaskFlow(BuildContext context, Task task) =>
      AutomationFlowRegistry.run(context: context, state: this, task: task);

  Future<void> _completeCompanionTaskById(int companionTaskId) async {
    final result = await _companionService.complete(companionTaskId);
    final taskId = result['task_id'];
    final taskStatus = result['task_status'] as String?;
    if (taskId is int && taskStatus != null) {
      _applyTaskStatusInView(taskId, taskStatus);
    }
    if (selectedViewType != null) {
      await refreshCurrentView();
      return;
    }
    notifyListeners();
  }

  void _applyTaskStatusInView(int taskId, String status) {
    viewTasks = [
      for (final task in viewTasks)
        if (task.id == taskId) task.copyWith(status: status) else task,
    ];
    final viewType = selectedViewType;
    if (viewType != null) {
      final cached = _viewCache[viewType];
      if (cached != null) {
        _viewCache[viewType] = _ViewSnapshot(
          tasks: viewTasks,
          sections: cached.sections,
        );
      }
    }
  }

  Future<void> ensureAutomationTriggerTaskDone(int taskId) async {
    final pending = await fetchPendingCompanionsForTask(taskId);
    if (pending.isNotEmpty) return;

    Task? task;
    for (final row in viewTasks) {
      if (row.id == taskId) {
        task = row;
        break;
      }
    }
    if (task == null || task.isDone) return;

    final data = await _taskService.updateTaskRaw(taskId, {'status': 'done'});
    _applyTaskUpdate(Task.fromJson(data));
    notifyListeners();
  }

  Future<void> refreshCurrentView() async {
    final viewType = selectedViewType;
    if (viewType == null) return;
    final tasks = await _taskService.listByView(viewType);
    viewTasks = tasks;
    final cached = _viewCache[viewType];
    _viewCache[viewType] = _ViewSnapshot(
      tasks: tasks,
      sections: cached?.sections ?? sectionsForViewType(viewType),
    );
    await _loadPendingTaskResetAcknowledgement(viewType);
    notifyListeners();
  }

  Future<void> _loadPendingTaskResetAcknowledgement(String viewType) async {
    try {
      final pending = await _taskResetAcknowledgementService.listPendingForView(
        viewType,
      );
      if (selectedViewType != viewType) return;
      pendingTaskResetAcknowledgement = pending.isEmpty ? null : pending.first;
    } catch (_) {
      // Acknowledgement lookup should not block opening the task view.
      if (selectedViewType == viewType) {
        pendingTaskResetAcknowledgement = null;
      }
    }
  }

  Future<void> approveTaskResetAcknowledgement(int id) async {
    await _taskResetAcknowledgementService.approve(id);
    if (pendingTaskResetAcknowledgement?.id == id) {
      pendingTaskResetAcknowledgement = null;
      notifyListeners();
    }
  }

  Future<bool> _ensureMainAutomationRules() async {
    if (automationDefinitions.isEmpty) {
      automationDefinitions = await _definitionService.list();
    }
    var changed = false;
    final keys = automationRules.map((rule) => rule.key).toSet();
    for (final definition in automationDefinitions) {
      if (!keys.contains(definition.key)) {
        await _automationService.createRule({
          'key': definition.key,
          'name': definition.name,
          'action_type': definition.actionType,
          'trigger_type': definition.activations.first,
          if (definition.defaultSchedule != null)
            'schedule': definition.defaultSchedule,
          'timezone': definition.timezoneDefault,
          'enabled': definition.defaultEnabled,
          'params': definition.defaultParams,
        });
        changed = true;
      }
    }
    for (final rule in automationRules) {
      final definition = definitionForKey(rule.key);
      if (definition != null && rule.name != definition.name) {
        await _automationService.updateRule(rule.id, {'name': definition.name});
        changed = true;
      }
      if (definition == null) continue;
      if (rule.timezone == definition.timezoneDefault) continue;
      await _automationService.updateRule(rule.id, {
        'timezone': definition.timezoneDefault,
      });
      changed = true;
    }
    return changed;
  }

  Future<void> selectTopic(Topic topic, {bool includeArchived = false}) async {
    final fromView = selectedViewType != null;
    final switchingTopic = selectedTopic?.id != topic.id;
    if (!topic.isMain) {
      broughtFile = null;
    }
    loading = true;
    error = null;
    selectedViewType = null;
    pendingTaskResetAcknowledgement = null;
    _showViewPaneDuringLoad = false;
    _loadingTopicFromView = fromView;
    _clearArchiveMode();
    selectedTopic = topic;
    notifyListeners();
    try {
      final files = await _fileService.listForTopic(
        topic.id,
        includeArchived: includeArchived || topic.isArchived,
      );
      final blocksByFileId = <int, List<Block>>{};
      final tasksByBlockId = <int, List<Task>>{};
      final parts = topic.type == 'project'
          ? await _partService.listForTopic(topic.id)
          : <Part>[];

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
        parts: parts,
      );
      await _ensurePartsCachedForFiles(files, topicParts: parts, topic: topic);
      pendingAiProposals = await _aiProposalService.listPending(
        topicId: topic.id,
      );
    } catch (e) {
      error = e.toString();
      selectedDetail = null;
    } finally {
      loading = false;
      _loadingTopicFromView = false;
      if (switchingTopic) {
        moreFilesExpanded = false;
      }
      _notifyShortcutRebuild();
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
    _clearArchiveMode();
    selectedViewType = viewType;
    pendingTaskResetAcknowledgement = null;
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
      await _loadPendingTaskResetAcknowledgement(viewType);
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
      _notifyShortcutRebuild();
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
    if (isPhoneLayout) return FileLayouts.single;
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

  void _applyOptimisticFiles(List<AppFile> files) {
    final detail = selectedDetail;
    if (detail == null) return;
    selectedDetail = TopicDetail(
      topic: detail.topic,
      files: files,
      blocksByFileId: detail.blocksByFileId,
      tasksByBlockId: detail.tasksByBlockId,
      parts: detail.parts,
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

  Future<void> cycleMainFilesForward() async {
    final detail = selectedDetail;
    final topic = selectedTopic;
    if (detail == null || topic == null) return;
    if (isArchiveMode || isViewMode) return;

    final main = mainFilesFor(topic, detail.files);
    if (main.length < 2) return;

    final rotated = rotateMainFilesLeft(main);
    final secondary = secondaryFilesFor(topic, detail.files);
    final ordered = [...rotated, ...secondary];
    final err = await reorderTopicFiles(topic, ordered, rotated.length);
    if (err != null) {
      error = err;
      notifyListeners();
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

    final updated = detail.files.map((f) {
      if (f.id == file.id) {
        return f.copyWith(isMain: isMain, orderIndex: orderIndex);
      }
      if (evictedId != null && f.id == evictedId) {
        return f.copyWith(isMain: false);
      }
      return f;
    }).toList();
    _applyOptimisticFiles(updated);
  }

  Future<void> promoteFileToMain(Topic topic, AppFile file) async {
    await setFileMainVisibility(topic, file, isMain: true);
  }

  Future<void> demoteFileToSecondary(Topic topic, AppFile file) async {
    await setFileMainVisibility(topic, file, isMain: false);
  }

  Future<void> moveFileToTopic(
    Topic sourceTopic,
    AppFile file,
    Topic targetTopic,
  ) async {
    final targetFiles = await _fileService.listForTopic(targetTopic.id);
    final secondary = secondaryFilesFor(targetTopic, targetFiles);
    final orderIndex = secondary.isEmpty
        ? 0
        : (secondary.last.orderIndex ?? secondary.length - 1) + 1;

    await _fileService.updateFile(file.id, {
      'topic_id': targetTopic.id,
      'is_main': false,
      'order_index': orderIndex,
    });

    if (selectedTopic?.id == sourceTopic.id) {
      await selectTopic(sourceTopic);
    } else {
      await refreshTopics();
    }
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
    final isMain =
        def?.isMain ??
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

  Future<void> createLogForProject({
    required Topic mainTopic,
    required Topic project,
    String? name,
  }) async {
    if (!mainTopic.isMain) return;
    final file = await _fileService.createFile(
      topicId: mainTopic.id,
      name: name ?? FileRegistry.defaultNameForType('log'),
      type: 'log',
      anchorTopicId: project.id,
      isMain: false,
    );
    await _createDefaultBlocks(file);
    await _refreshPartsCache(project.id);
    await selectTopic(mainTopic);
  }

  Future<void> attachLogToProject({
    required Topic topic,
    required AppFile file,
    required Topic project,
  }) async {
    if (file.type != 'log') return;
    await _fileService.updateFile(file.id, {'anchor_topic_id': project.id});
    await _refreshPartsCache(project.id);
    await selectTopic(topic);
  }

  Future<void> _refreshPartsCache(int topicId) async {
    _partsCache[topicId] = await _partService.listForTopic(topicId);
    notifyListeners();
  }

  Future<void> _ensurePartsCachedForFiles(
    List<AppFile> files, {
    required List<Part> topicParts,
    required Topic topic,
  }) async {
    if (topic.type == 'project') {
      _partsCache[topic.id] = topicParts;
    }
    final anchorIds = files
        .map((file) => file.anchorTopicId)
        .whereType<int>()
        .toSet();
    for (final anchorId in anchorIds) {
      if (_partsCache.containsKey(anchorId)) continue;
      _partsCache[anchorId] = await _partService.listForTopic(anchorId);
    }
  }

  Future<void> updateFileName(Topic topic, AppFile file, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == file.name) return;
    await _fileService.updateFile(file.id, {'name': trimmed});
    if (isGuestFile(file) && selectedTopic?.isMain == true) {
      broughtFile = broughtFile!.copyWith(
        file: file.copyWith(name: trimmed),
      );
      notifyListeners();
      return;
    }
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
      orderIndex: _appendOrderIndex(blocks),
    );
    return [...blocks, block];
  }

  Future<void> deleteTopic(Topic topic) async {
    if (topic.isMain) return;
    await _topicService.deleteTopic(topic.id);
    await refreshTopics();
    await goHome();
  }

  Future<Topic?> duplicateTopic(Topic topic) async {
    if (topic.isMain) return null;
    final copy = await _topicService.duplicateTopic(topic.id);
    await refreshTopics();
    await selectTopic(copy);
    return copy;
  }

  Future<void> deleteFile(Topic topic, AppFile file) async {
    await _fileService.deleteFile(file.id);
    await selectTopic(topic);
  }

  Future<void> duplicateFile(Topic topic, AppFile file) async {
    await _fileService.duplicateFile(file.id);
    await selectTopic(topic);
  }

  Future<void> addTextBlock(AppFile file) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final blocks = _blocksForFile(file);
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
    await _refreshAfterFileMutation(file);
  }

  Future<void> addBlock(
    AppFile file,
    String type,
    Map<String, dynamic> content,
  ) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final blocks = _blocksForFile(file);
    await _blockService.createBlock(
      fileId: file.id,
      type: type,
      content: content,
      orderIndex: blocks.length,
    );
    await _refreshAfterFileMutation(file);
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
    BlockTextFocusRegistry.abandonStashedFocus();
    await _refreshAfterFileMutation(file);
  }

  Block? _textBlockForInsertion(AppFile file, int orderIndex) {
    final blocks = _blocksForFile(file);
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
    final blocks = _blocksForFile(file);
    final targetIndex = orderIndex.clamp(0, blocks.length).toInt();
    if (type == 'text') return targetIndex;
    return _effectiveNonTextInsertIndex(blocks, targetIndex);
  }

  int _effectiveNonTextInsertIndex(List<Block> blocks, int targetIndex) {
    if (blocks.isEmpty) return targetIndex;

    final trailingIndex = blocks.length - 1;
    final trailing = blocks[trailingIndex];
    if (trailing.type != 'text') return targetIndex;

    if (_isEmptyTextBlock(trailing)) {
      if (targetIndex >= trailingIndex) return trailingIndex;
      return targetIndex;
    }

    if (targetIndex > trailingIndex) return blocks.length;
    return targetIndex;
  }

  int _appendOrderIndex(List<Block> blocks) {
    if (blocks.isEmpty) return 0;
    var maxOrder = 0;
    for (final block in blocks) {
      final order = block.orderIndex ?? 0;
      if (order > maxOrder) maxOrder = order;
    }
    return maxOrder + 1;
  }

  int _orderIndexForListInsert(List<Block> blocks, int listInsertIndex) {
    final insertAt = listInsertIndex.clamp(0, blocks.length).toInt();
    if (insertAt >= blocks.length) return _appendOrderIndex(blocks);
    return blocks[insertAt].orderIndex ?? insertAt;
  }

  bool _isEmptyTextBlock(Block block) {
    if (block.type != 'text') return false;
    if (block.text.trim().isNotEmpty) return false;
    final controller = BlockTextFocusRegistry.activeController;
    if (BlockTextFocusRegistry.activeBlockId == block.id &&
        controller != null &&
        controller.text.trim().isNotEmpty) {
      return false;
    }
    return true;
  }

  int _listInsertIndexAfterBlock(List<Block> blocks, Block afterBlock) {
    return listInsertIndexAfterTaskBlock(blocks, afterBlock);
  }

  int _listInsertIndexForNewTask(AppFile file, Block listBlock) {
    return listInsertIndexForNewTask(_blocksForFile(file), listBlock);
  }

  Future<int> _shiftBlocksForInsert(AppFile file, int listInsertIndex) async {
    final blocks = _blocksForFile(file);
    final insertAt = listInsertIndex.clamp(0, blocks.length).toInt();
    final newOrderIndex = _orderIndexForListInsert(blocks, insertAt);

    for (var i = insertAt; i < blocks.length; i++) {
      final block = blocks[i];
      await _blockService.updateBlock(block.id, {
        'order_index': (block.orderIndex ?? i) + 1,
      });
    }
    return newOrderIndex;
  }

  Future<void> addHeaderBlock(AppFile file) async {
    final topic = selectedTopic;
    if (topic == null) return;
    final blocks = _blocksForFile(file);
    await _blockService.createBlock(
      fileId: file.id,
      type: 'header',
      content: {'text': 'Section', 'level': 2},
      orderIndex: blocks.length,
    );
    await _refreshAfterFileMutation(file);
  }

  bool supportsPartPlacement(Topic? topic, AppFile file) {
    if (!FileBehaviorRegistry.supportsPartPlacement(file.type)) return false;
    if (topic?.type == 'project') return true;
    if (topic?.isMain == true && file.anchorTopicId != null) return true;
    return false;
  }

  int? partsTopicIdForFile(AppFile file) =>
      file.anchorTopicId ?? selectedTopic?.id;

  List<Part> partsForFile(AppFile file) {
    final topicId = partsTopicIdForFile(file);
    if (topicId == null) return const [];
    if (selectedTopic?.type == 'project' && selectedTopic?.id == topicId) {
      return topicParts;
    }
    return _partsCache[topicId] ?? const [];
  }

  List<Part> get topicParts => selectedDetail?.parts ?? const [];

  Set<int> partIdsPlacedInFile(AppFile file) {
    final ids = <int>{};
    for (final block in _blocksForFile(file)) {
      if (block.type != 'header') continue;
      final partId = block.partId ?? block.content['part_id'] as int?;
      if (partId != null) ids.add(partId);
    }
    return ids;
  }

  List<Part> partsAvailableForFile(AppFile file) {
    final placed = partIdsPlacedInFile(file);
    return partsForFile(file).where((part) => !placed.contains(part.id)).toList();
  }

  ({int? insertAfterBlockId, int? insertIndex}) _partPlacementArgs(
    AppFile file,
    int orderIndex,
  ) {
    final blocks = _blocksForFile(file);
    final target = orderIndex.clamp(0, blocks.length).toInt();
    if (target <= 0) return (insertAfterBlockId: null, insertIndex: 0);
    if (target >= blocks.length) {
      return (insertAfterBlockId: blocks.last.id, insertIndex: null);
    }
    return (insertAfterBlockId: blocks[target - 1].id, insertIndex: null);
  }

  Future<void> addNewPartToFile(
    AppFile file, {
    required String name,
    required int orderIndex,
  }) async {
    final topic = selectedTopic;
    if (topic == null || !supportsPartPlacement(topic, file)) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final placement = _partPlacementArgs(file, orderIndex);
    await _partService.placePartInFile(
      fileId: file.id,
      name: trimmed,
      insertAfterBlockId: placement.insertAfterBlockId,
      insertIndex: placement.insertIndex,
    );
    final anchorId = file.anchorTopicId;
    if (anchorId != null) {
      await _refreshPartsCache(anchorId);
    }
    await _refreshAfterFileMutation(file);
  }

  Future<void> addExistingPartToFile(
    AppFile file, {
    required int partId,
    required int orderIndex,
  }) async {
    final topic = selectedTopic;
    if (topic == null || !supportsPartPlacement(topic, file)) return;
    final placement = _partPlacementArgs(file, orderIndex);
    await _partService.placePartInFile(
      fileId: file.id,
      partId: partId,
      insertAfterBlockId: placement.insertAfterBlockId,
      insertIndex: placement.insertIndex,
    );
    final anchorId = file.anchorTopicId;
    if (anchorId != null) {
      await _refreshPartsCache(anchorId);
    }
    await _refreshAfterFileMutation(file);
  }

  Future<void> renamePart(int partId, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    await _partService.updatePart(partId, {'name': trimmed});
    final topic = selectedTopic;
    if (topic != null) await selectTopic(topic);
  }

  Future<void> archivePart(int partId) async {
    await _partService.archivePart(partId);
    final topic = selectedTopic;
    if (topic != null) await selectTopic(topic);
  }

  void scheduleBlockSave(Block block, Map<String, dynamic> content) {
    _saveTimers[block.id]?.cancel();
    _saveTimers[block.id] = Timer(const Duration(milliseconds: 500), () async {
      try {
        await _blockService.updateBlock(block.id, {'content': content});
      } catch (e) {
        error = e.toString();
        if (broughtFile != null &&
            broughtFile!.blocks.any((b) => b.id == block.id)) {
          broughtFile = null;
        }
        notifyListeners();
      }
    });
  }

  Future<void> updateBlockContent(
    Block block,
    Map<String, dynamic> content, {
    bool notify = false,
  }) async {
    final updated = block.copyWith(content: content);
    if (broughtFile?.file.id == block.fileId) {
      broughtFile = broughtFile!.copyWith(
        blocks: broughtFile!.blocks
            .map((b) => b.id == block.id ? updated : b)
            .toList(),
      );
      if (notify) notifyListeners();
      scheduleBlockSave(block, content);
      return;
    }
    final detail = selectedDetail;
    if (detail == null) return;
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
        await _refreshAfterFileMutation(file);
        return;
      }
    }
    await _blockService.deleteBlock(block.id);
    await _refreshAfterFileMutation(file);
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
      orderIndex: _blocksForFileId(block.fileId!).length,
    );
    notifyListeners();
  }

  Future<void> insertTaskAfter({
    required AppFile file,
    required Block listBlock,
    required Block afterTaskBlock,
    String status = 'active',
  }) async {
    final topic = selectedTopic;
    final detail = selectedDetail;
    if (topic == null || detail == null) return;

    final blocks = _blocksForFile(file);
    final listInsertIndex = _listInsertIndexAfterBlock(blocks, afterTaskBlock);
    final targetIndex = await _shiftBlocksForInsert(file, listInsertIndex);
    final taskBlock = await _createTaskBlock(
      listBlock: listBlock,
      fileId: file.id,
      title: '',
      orderIndex: targetIndex,
      status: status,
    );
    await _refreshAfterFileMutation(file);
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
    final guest = broughtFile?.file;
    if (guest != null && taskBlock?.fileId == guest.id) {
      await _refreshAfterFileMutation(guest);
    } else {
      await selectTopic(topic);
    }
    if (focusTaskBlockAfterDelete != null) {
      requestBlockFocus(focusTaskBlockAfterDelete.id);
    }
  }

  Future<Block> _createTaskBlock({
    required Block listBlock,
    required int fileId,
    required String title,
    required int orderIndex,
    String status = 'active',
  }) async {
    final detail = selectedDetail;
    if (detail == null) {
      throw StateError('No topic detail loaded');
    }
    final task = await _taskService.createTask(
      blockId: listBlock.id,
      title: title,
      status: status,
    );
    final taskBlock = await _blockService.createBlock(
      fileId: fileId,
      type: 'task',
      content: {'task_id': task.id},
      orderIndex: orderIndex,
    );
    if (broughtFile?.file.id == fileId) {
      final guest = broughtFile!;
      final nextBlocks = <Block>[...guest.blocks, taskBlock]
        ..sort((a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0));
      broughtFile = guest.copyWith(
        blocks: nextBlocks,
        tasksByBlockId: {
          ...guest.tasksByBlockId,
          listBlock.id: [...(guest.tasksByBlockId[listBlock.id] ?? []), task],
        },
      );
      return taskBlock;
    }
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
    return orderedTasksForListBlock(
      _blocksForFile(file),
      listBlock,
      _tasksByBlockIdForFile(file),
    );
  }

  Block? taskRowBlockInFile(AppFile file, Task task) {
    for (final block in _blocksForFile(file)) {
      if (block.type == 'task' && block.content['task_id'] == task.id) {
        return block;
      }
    }
    return null;
  }

  Task? _taskForCreatedBlock(Block taskBlock, Block listBlock) {
    final taskId = taskBlock.content['task_id'] as int?;
    if (taskId == null) return null;
    final tasks = broughtFile?.tasksByBlockId[listBlock.id] ??
        selectedDetail?.tasksByBlockId[listBlock.id] ??
        [];
    for (final task in tasks) {
      if (task.id == taskId) return task;
    }
    return null;
  }

  Future<Task?> createTaskInFileAfter({
    required AppFile file,
    required Block listBlock,
    Task? afterTask,
    String title = '',
    String status = 'active',
  }) async {
    final topic = selectedTopic;
    if (topic == null) return null;

    final afterRow = afterTask != null
        ? taskRowBlockInFile(file, afterTask)
        : null;
    final blocks = _blocksForFile(file);
    final listInsertIndex = afterRow != null
        ? _listInsertIndexAfterBlock(blocks, afterRow)
        : _listInsertIndexForNewTask(file, listBlock);
    final targetIndex = await _shiftBlocksForInsert(file, listInsertIndex);
    final taskBlock = await _createTaskBlock(
      listBlock: listBlock,
      fileId: file.id,
      title: title,
      orderIndex: targetIndex,
      status: status,
    );
    final task = _taskForCreatedBlock(taskBlock, listBlock);
    requestBlockFocus(taskBlock.id);
    notifyListeners();
    return task;
  }

  Future<void> deleteTaskInFile(AppFile file, Task task) async {
    final row = taskRowBlockInFile(file, task);
    await deleteTaskWithBlock(task, row);
  }

  Future<void> pasteTasksInFileAfter({
    required AppFile file,
    required Block listBlock,
    required Task afterTask,
    required List<String> lines,
    required String status,
  }) async {
    Task? cursor = afterTask;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      cursor = await createTaskInFileAfter(
        file: file,
        listBlock: listBlock,
        afterTask: cursor,
        title: trimmed,
        status: status,
      );
    }
  }

  void _patchFileInCaches(AppFile file) {
    final detail = selectedDetail;
    if (detail != null) {
      _applyOptimisticFiles(
        detail.files.map((f) => f.id == file.id ? file : f).toList(),
      );
    } else if (broughtFile?.file.id == file.id) {
      broughtFile = broughtFile!.copyWith(file: file);
      notifyListeners();
    }
  }

  Future<void> setFileTasksFlipByView(AppFile file, bool enabled) async {
    final nextSettings = Map<String, dynamic>.from(file.settings);
    if (enabled) {
      nextSettings['tasks_flip_by_view'] = true;
    } else {
      nextSettings.remove('tasks_flip_by_view');
    }
    final updated = await _fileService.updateFile(file.id, {
      'settings': nextSettings,
    });
    _patchFileInCaches(updated);
  }

  void _applyBlockOrderUpdates(AppFile file, List<Map<String, int>> updates) {
    final byId = {for (final item in updates) item['id']!: item['order_index']!};
    void patchBlocks(List<Block> blocks) {
      for (var i = 0; i < blocks.length; i++) {
        final nextOrder = byId[blocks[i].id];
        if (nextOrder != null) {
          blocks[i] = blocks[i].copyWith(orderIndex: nextOrder);
        }
      }
      blocks.sort(
        (a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0),
      );
    }

    if (broughtFile?.file.id == file.id) {
      final guest = broughtFile!;
      final nextBlocks = List<Block>.from(guest.blocks);
      patchBlocks(nextBlocks);
      broughtFile = guest.copyWith(blocks: nextBlocks);
      return;
    }

    final detail = selectedDetail;
    if (detail == null) return;
    final blocks = List<Block>.from(detail.blocksByFileId[file.id] ?? []);
    patchBlocks(blocks);
    detail.blocksByFileId[file.id] = blocks;
  }

  Future<void> reorderTasksInListBlock(
    AppFile file,
    Block listBlock,
    List<int> orderedTaskIds,
  ) async {
    final blocks = sortedBlocksForFile(_blocksForFile(file));
    final region = taskListRegion(blocks, listBlock);
    final tasks = _tasksByBlockIdForFile(file)[listBlock.id] ?? const <Task>[];
    final taskIdsInBlock = tasks.map((t) => t.id).toSet();
    if (orderedTaskIds.length != taskIdsInBlock.length ||
        !orderedTaskIds.every(taskIdsInBlock.contains)) {
      return;
    }

    final rowByTaskId = <int, Block>{};
    for (var i = region.startIndex + 1; i < region.endIndex; i++) {
      final block = blocks[i];
      if (block.type != 'task') continue;
      final taskId = block.content['task_id'] as int?;
      if (taskId != null) rowByTaskId[taskId] = block;
    }

    final anchorOrder =
        blocks[region.startIndex].orderIndex ?? region.startIndex;
    final updates = <Map<String, int>>[];
    for (var i = 0; i < orderedTaskIds.length; i++) {
      final row = rowByTaskId[orderedTaskIds[i]];
      if (row == null) continue;
      updates.add({'id': row.id, 'order_index': anchorOrder + i + 1});
    }
    if (updates.isEmpty) return;

    _applyBlockOrderUpdates(file, updates);
    notifyListeners();
    try {
      await _blockService.reorderBlocks(file.id, updates);
    } catch (_) {
      await _refreshAfterFileMutation(file);
      rethrow;
    }
  }

  Future<void> reorderTasksInListZone(
    AppFile file,
    Block listBlock, {
    required bool done,
    required int oldIndex,
    required int newIndex,
  }) async {
    final all = orderedTasksForFile(file, listBlock);
    final parts = partitionTasks(all);
    final zone = done
        ? List<Task>.from(parts.done)
        : List<Task>.from(parts.active);
    if (oldIndex < 0 ||
        oldIndex >= zone.length ||
        newIndex < 0 ||
        newIndex > zone.length) {
      return;
    }
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= zone.length) return;
    final moved = zone.removeAt(oldIndex);
    zone.insert(target, moved);
    final mergedIds = done
        ? [...parts.active.map((t) => t.id), ...zone.map((t) => t.id)]
        : [...zone.map((t) => t.id), ...parts.done.map((t) => t.id)];
    await reorderTasksInListBlock(file, listBlock, mergedIds);
  }

  Future<void> reorderTasksInFlipGroup(
    AppFile file,
    String? viewType,
    Map<int, Block> listBlockByTaskId, {
    required List<Task> groupTasks,
    required bool done,
    required int oldIndex,
    required int newIndex,
  }) async {
    final parts = partitionTasks(groupTasks);
    final zone = done
        ? List<Task>.from(parts.done)
        : List<Task>.from(parts.active);
    if (oldIndex < 0 ||
        oldIndex >= zone.length ||
        newIndex < 0 ||
        newIndex > zone.length) {
      return;
    }
    var target = newIndex;
    if (target > oldIndex) target -= 1;
    if (target < 0 || target >= zone.length) return;
    final moved = zone.removeAt(oldIndex);
    zone.insert(target, moved);
    final merged = done
        ? [...parts.active, ...zone]
        : [...zone, ...parts.done];

    if (viewType != null) {
      for (var i = 0; i < merged.length; i++) {
        final membership = primaryMembershipForTask(merged[i].id);
        if (membership == null) continue;
        await _taskViewService.updateOrderIndex(membership.id, i);
        _taskViewMemberships = _taskViewMemberships
            .map(
              (m) => m.id == membership.id ? m.copyWith(orderIndex: i) : m,
            )
            .toList();
      }
      notifyListeners();
      return;
    }

    final byListBlock = <int, List<int>>{};
    for (final task in merged) {
      final listBlock = listBlockByTaskId[task.id];
      if (listBlock == null) continue;
      byListBlock.putIfAbsent(listBlock.id, () => []).add(task.id);
    }
    for (final entry in byListBlock.entries) {
      final listBlock = listBlockByTaskId[entry.value.first];
      if (listBlock == null) continue;
      await reorderTasksInListBlock(file, listBlock, entry.value);
    }
  }

  Future<void> moveTaskToListBlock(
    AppFile file,
    Task task,
    Block targetListBlock, {
    Task? afterTask,
  }) async {
    final all = orderedTasksForFile(file, targetListBlock);
    final parts = partitionTasks(all);
    final targetDone = afterTask != null ? afterTask.isDone : false;
    final zone = targetDone ? parts.done : parts.active;
    final insertIndex = afterTask != null
        ? zone.indexWhere((t) => t.id == afterTask.id) + 1
        : zone.length;
    await moveTaskToListBlockAtIndex(
      file,
      task,
      targetListBlock,
      targetDone: targetDone,
      insertIndexInZone: insertIndex.clamp(0, zone.length),
    );
  }

  Future<void> moveTaskToListBlockAtIndex(
    AppFile file,
    Task task,
    Block targetListBlock, {
    required bool targetDone,
    required int insertIndexInZone,
  }) async {
    final sourceListId = task.blockId;
    final rowBlock = taskRowBlockInFile(file, task);
    if (rowBlock == null) return;

    Task currentTask = task;
    if (task.blockId != targetListBlock.id) {
      currentTask = await _taskService.updateTask(task.id, {
        'block_id': targetListBlock.id,
      });
      _moveTaskBetweenListCaches(
        file: file,
        task: currentTask,
        sourceListId: sourceListId,
        targetListBlock: targetListBlock,
      );
    }

    final listTasks = orderedTasksForFile(file, targetListBlock);
    final tasksForMerge = listTasks.any((t) => t.id == currentTask.id)
        ? listTasks
        : [...listTasks, currentTask];
    final mergedIds = mergedTaskIdsAfterZoneInsert(
      listTasks: tasksForMerge,
      task: currentTask,
      targetDone: targetDone,
      insertIndexInZone: insertIndexInZone,
    );

    var blocks = List<Block>.from(sortedBlocksForFile(_blocksForFile(file)));
    final fromIndex = blocks.indexWhere((b) => b.id == rowBlock.id);
    if (fromIndex >= 0) blocks.removeAt(fromIndex);

    final region = taskListRegion(blocks, targetListBlock);
    final rowByTaskId = <int, Block>{};
    for (var i = region.startIndex + 1; i < region.endIndex; i++) {
      final block = blocks[i];
      if (block.type != 'task') continue;
      final taskId = block.content['task_id'] as int?;
      if (taskId != null) rowByTaskId[taskId] = block;
    }

    final insertAt = blockInsertIndexForTaskInList(
      fileBlocks: blocks,
      listBlock: targetListBlock,
      mergedTaskIds: mergedIds,
      taskId: currentTask.id,
      rowBlockByTaskId: rowByTaskId,
    ).clamp(region.startIndex + 1, region.endIndex);

    blocks.insert(insertAt, rowBlock);
    _replaceBlocksForFile(file, blocks);

    await reorderTasksInListBlock(file, targetListBlock, mergedIds);
    await _ensureTaskStatusForDrop(currentTask, targetDone);
  }

  Future<void> reorderTaskAcrossZonesInListBlock(
    AppFile file,
    Block listBlock,
    Task task, {
    required bool targetDone,
    required int insertIndexInZone,
  }) async {
    final listTasks = orderedTasksForFile(file, listBlock);
    final mergedIds = mergedTaskIdsAfterZoneInsert(
      listTasks: listTasks,
      task: task,
      targetDone: targetDone,
      insertIndexInZone: insertIndexInZone,
    );
    await reorderTasksInListBlock(file, listBlock, mergedIds);
    await _ensureTaskStatusForDrop(task, targetDone);
  }

  Future<void> insertTaskInFlipGroupAt(
    AppFile file,
    Task task,
    String? targetViewType,
    Map<int, Block> listBlockByTaskId, {
    required List<Task> groupTasks,
    required bool targetDone,
    required int insertIndexInZone,
  }) async {
    final parts = partitionTasks(groupTasks);
    final active = List<Task>.from(parts.active)
      ..removeWhere((t) => t.id == task.id);
    final done = List<Task>.from(parts.done)..removeWhere((t) => t.id == task.id);
    final zone = targetDone ? done : active;
    zone.insert(insertIndexInZone.clamp(0, zone.length), task);
    final merged = [...active, ...done];
    final globalIndex = merged.indexWhere((t) => t.id == task.id);

    final currentView = viewTypeForTask(task.id);
    if (currentView != targetViewType) {
      await assignTaskView(
        task,
        targetViewType,
        orderIndex: targetViewType != null ? globalIndex : null,
      );
    }

    if (targetViewType != null) {
      for (var i = 0; i < merged.length; i++) {
        final membership = primaryMembershipForTask(merged[i].id);
        if (membership == null) continue;
        if (membership.orderIndex == i) continue;
        await _taskViewService.updateOrderIndex(membership.id, i);
        _taskViewMemberships = _taskViewMemberships
            .map((m) => m.id == membership.id ? m.copyWith(orderIndex: i) : m)
            .toList();
      }
      notifyListeners();
    } else {
      final byListBlock = <int, List<int>>{};
      for (final entry in merged) {
        final listBlock = listBlockByTaskId[entry.id];
        if (listBlock == null) continue;
        byListBlock.putIfAbsent(listBlock.id, () => []).add(entry.id);
      }
      for (final entry in byListBlock.entries) {
        final listBlock = listBlockByTaskId[entry.value.first];
        if (listBlock == null) continue;
        await reorderTasksInListBlock(file, listBlock, entry.value);
      }
    }

    await _ensureTaskStatusForDrop(task, targetDone);
  }

  Future<void> applyTaskDrop({
    required AppFile file,
    required TaskDragPayload payload,
    required Block targetListBlock,
    required String? targetViewType,
    required bool targetDone,
    required int insertIndex,
    required int sourceIndexInZone,
    required int targetZoneLength,
    required bool isFlipMode,
    required bool allowCrossBoundary,
    Map<int, Block>? listBlockByTaskId,
    List<Task>? flipGroupTasks,
  }) async {
    final action = resolveTaskDrop(
      payload: payload,
      sourceIndexInZone: sourceIndexInZone,
      target: TaskDropTarget(
        listBlockId: targetListBlock.id,
        viewType: targetViewType,
        done: targetDone,
        insertIndex: insertIndex,
      ),
      isFlipMode: isFlipMode,
      allowCrossBoundary: allowCrossBoundary,
      zoneLength: targetZoneLength,
    );

    switch (action.kind) {
      case TaskDropKind.noop:
        return;
      case TaskDropKind.reorder:
        if (isFlipMode &&
            flipGroupTasks != null &&
            listBlockByTaskId != null) {
          await reorderTasksInFlipGroup(
            file,
            targetViewType,
            listBlockByTaskId,
            groupTasks: flipGroupTasks,
            done: payload.sourceDone,
            oldIndex: action.oldIndex!,
            newIndex: action.newIndex!,
          );
        } else {
          await reorderTasksInListZone(
            file,
            targetListBlock,
            done: payload.sourceDone,
            oldIndex: action.oldIndex!,
            newIndex: action.newIndex!,
          );
        }
        return;
      case TaskDropKind.moveAcrossZones:
        if (isFlipMode && flipGroupTasks != null && listBlockByTaskId != null) {
          await insertTaskInFlipGroupAt(
            file,
            payload.task,
            targetViewType,
            listBlockByTaskId,
            groupTasks: flipGroupTasks,
            targetDone: targetDone,
            insertIndexInZone: insertIndex,
          );
        } else {
          await reorderTaskAcrossZonesInListBlock(
            file,
            targetListBlock,
            payload.task,
            targetDone: targetDone,
            insertIndexInZone: insertIndex,
          );
        }
        return;
      case TaskDropKind.moveToListBlock:
        await moveTaskToListBlockAtIndex(
          file,
          payload.task,
          targetListBlock,
          targetDone: targetDone,
          insertIndexInZone: insertIndex,
        );
        return;
      case TaskDropKind.assignView:
        if (listBlockByTaskId == null || flipGroupTasks == null) return;
        await insertTaskInFlipGroupAt(
          file,
          payload.task,
          targetViewType,
          listBlockByTaskId,
          groupTasks: flipGroupTasks,
          targetDone: targetDone,
          insertIndexInZone: insertIndex,
        );
        return;
    }
  }

  Future<void> _ensureTaskStatusForDrop(Task task, bool targetDone) async {
    if (task.isDone == targetDone) return;
    final data = await _taskService.updateTaskRaw(task.id, {
      'status': targetDone ? 'done' : 'active',
    });
    final updated = Task.fromJson(data);
    _applyTaskUpdate(updated);
    notifyListeners();
  }

  void _replaceBlocksForFile(AppFile file, List<Block> blocks) {
    if (broughtFile?.file.id == file.id) {
      broughtFile = broughtFile!.copyWith(blocks: blocks);
      return;
    }
    final detail = selectedDetail;
    if (detail == null) return;
    detail.blocksByFileId[file.id] = blocks;
  }

  void _moveTaskBetweenListCaches({
    required AppFile file,
    required Task task,
    required int? sourceListId,
    required Block targetListBlock,
  }) {
    void patchMap(Map<int, List<Task>> tasksByBlockId) {
      if (sourceListId != null) {
        tasksByBlockId[sourceListId] = (tasksByBlockId[sourceListId] ?? [])
            .where((t) => t.id != task.id)
            .toList();
      }
      tasksByBlockId[targetListBlock.id] = [
        ...(tasksByBlockId[targetListBlock.id] ?? [])
            .where((t) => t.id != task.id),
        task,
      ];
    }

    if (broughtFile?.file.id == file.id) {
      final guest = broughtFile!;
      final nextMap = Map<int, List<Task>>.from(guest.tasksByBlockId);
      patchMap(nextMap);
      broughtFile = guest.copyWith(tasksByBlockId: nextMap);
      return;
    }

    final detail = selectedDetail;
    if (detail == null) return;
    patchMap(detail.tasksByBlockId);
  }

  Future<Task?> createTaskInViewZoneAfter({
    required ViewPaneSyncContext pane,
    Task? afterTask,
    String title = '',
    required bool done,
    required Future<int?> Function(Offset position) pickTopic,
    Offset menuPosition = Offset.zero,
  }) async {
    Topic? topic;
    if (afterTask != null) {
      topic = topicForTask(afterTask);
    }
    if (topic == null && pane.displayMode == TaskViewDisplayMode.byTopic) {
      topic = topicForViewPaneGroup(topicKey: pane.topicKey);
    }
    if (topic == null) {
      final topicId = await pickTopic(menuPosition);
      if (topicId == null) return null;
      topic = topicById(topicId);
    }
    if (topic == null) return null;

    return createTaskInView(
      viewType: pane.viewType,
      topic: topic,
      title: title,
      sectionName: pane.sectionName,
      afterTask: afterTask,
      status: done ? 'done' : 'active',
    );
  }

  Future<void> pasteTasksInViewAfter({
    required ViewPaneSyncContext pane,
    required Task afterTask,
    required List<String> lines,
    required bool done,
    required Future<int?> Function(Offset position) pickTopic,
    Offset menuPosition = Offset.zero,
  }) async {
    Task? cursor = afterTask;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      cursor = await createTaskInViewZoneAfter(
        pane: pane,
        afterTask: cursor,
        title: trimmed,
        done: done,
        pickTopic: pickTopic,
        menuPosition: menuPosition,
      );
    }
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

  Future<void> abandonAutomationCompanionFlow(Task task) async {
    final companions = await fetchPendingCompanionsForTask(task.id);
    final topicIds = <int>{
      for (final companion in companions)
        if (companion.topicId != null) companion.topicId!,
    };
    for (final companion in companions) {
      final proposalId = companion.proposalId;
      if (proposalId != null) {
        try {
          final proposal = await fetchAiProposal(proposalId);
          await rejectAiProposal(
            proposal,
            companionTaskId: companion.id,
            refreshTopicBanner: false,
          );
        } catch (_) {
          await _completeCompanionTaskById(companion.id);
        }
      } else {
        await _completeCompanionTaskById(companion.id);
      }
    }

    await refreshPendingProposalsForTopics(topicIds);

    Task? current;
    for (final row in viewTasks) {
      if (row.id == task.id) {
        current = row;
        break;
      }
    }
    current ??= task;
    if (!current.isDone) {
      final data = await _taskService.updateTaskRaw(task.id, {
        'status': 'done',
        '_skip_automation_trigger': true,
      });
      _applyTaskUpdate(Task.fromJson(data));
    }

    if (selectedViewType != null) {
      await refreshCurrentView();
    } else {
      notifyListeners();
    }
  }

  Future<void> toggleTaskStatus(
    Task task, {
    Future<bool> Function()? confirmAbandonCompanionFlow,
  }) async {
    if (!task.isDone && task.isAutomationTrigger && task.hasAutomationFlow) {
      if (confirmAbandonCompanionFlow == null) return;
      final confirmed = await confirmAbandonCompanionFlow();
      if (!confirmed) return;
      await abandonAutomationCompanionFlow(task);
      return;
    }

    final data = await _taskService.updateTaskRaw(task.id, {
      'status': task.isDone ? 'active' : 'done',
    });
    final updated = Task.fromJson(data);
    _applyTaskUpdate(updated);
    final runIds = data['automation_run_ids'];
    if (runIds is List && runIds.isNotEmpty) {
      var anyActive = false;
      var anyFailed = false;
      String? failureError;
      for (final rawId in runIds) {
        final runId = rawId is int ? rawId : (rawId as num).toInt();
        final run = await _automationService.getRun(runId);
        _trackAutomationRun(run.ruleId, run);
        if (run.isActive) {
          anyActive = true;
        } else if (run.status == 'failed') {
          anyFailed = true;
          failureError ??= run.error;
        }
      }
      if (anyFailed) {
        _automationNotice = failureError ?? strings['automationRunFailed'];
      } else if (anyActive) {
        _automationNotice = strings['automationRan'];
        _ensureAutomationStatusPolling();
      } else {
        _automationNotice = strings['automationCompleted'];
        await refreshAutomationRules();
        if (_hasOpenContent) {
          await _refreshVisibleContentAfterAutomation();
        }
      }
    } else {
      final skip = data['automation_trigger_skipped'] as String?;
      if (task.isAutomationTrigger) {
        if (skip == 'uncheck_to_run') {
          _automationNotice = strings['automationUncheckToRun'];
        } else if (skip == 'not_trigger_task') {
          _automationNotice = strings['automationNotTriggerTask'];
        }
      }
    }
    notifyListeners();
  }

  Topic? topicForTask(Task task) {
    if (task.topicId != null) return topicById(task.topicId!);
    if (task.topicName != null && task.topicName != ViewPaneKeys.noTopic) {
      return topicForViewPaneGroup(topicKey: task.topicName);
    }
    return null;
  }

  Future<AppFile> _ensureTasksFileForTopic(Topic topic) async {
    final def = FileRegistry.definitionFor(
      topicType: topic.type,
      fileType: 'tasks',
      isMainTopic: topic.isMain,
    );
    final file = await _fileService.createFile(
      topicId: topic.id,
      name: def?.name ?? FileRegistry.defaultNameForType('tasks'),
      type: 'tasks',
      orderIndex: def?.orderIndex,
      isMain:
          def?.isMain ??
          FileRegistry.isMainFile(
            topicType: topic.type,
            fileType: 'tasks',
            isMainTopic: topic.isMain,
          ),
    );
    await _createDefaultBlocks(file);

    final detail = selectedDetail;
    if (detail != null && detail.topic.id == topic.id) {
      detail.files.add(file);
      final blocks = await _blockService.listForFile(file.id);
      detail.blocksByFileId[file.id] = blocks;
      for (final block in blocks) {
        if (block.type == 'task_list') {
          detail.tasksByBlockId[block.id] = const [];
        }
      }
    }
    return file;
  }

  Future<TopicTasksTarget> ensureTopicTasksTarget(Topic topic) async {
    final files = await _fileService.listForTopic(topic.id);
    AppFile? tasksFile;
    for (final file in files) {
      if (file.type == 'tasks' && !file.isArchived) {
        tasksFile = file;
        break;
      }
    }
    tasksFile ??= await _ensureTasksFileForTopic(topic);

    final blocks = await _blockService.listForFile(tasksFile.id);
    Block? listBlock;
    for (final block in blocks) {
      if (block.type == 'task_list') {
        listBlock = block;
        break;
      }
    }
    listBlock ??= await _blockService.createBlock(
      fileId: tasksFile.id,
      type: 'task_list',
      content: const {},
      orderIndex: 0,
    );
    return TopicTasksTarget(
      topic: topic,
      file: tasksFile,
      listBlock: listBlock,
    );
  }

  Future<Block?> findTaskRowBlock(Task task) async {
    if (task.blockId == null) return null;
    final listBlock = await _blockService.getBlock(task.blockId!);
    final fileId = listBlock.fileId;
    if (fileId == null) return null;
    final blocks = await _blockService.listForFile(fileId);
    for (final block in blocks) {
      if (block.type == 'task' && block.content['task_id'] == task.id) {
        return block;
      }
    }
    return null;
  }

  Future<int> _remoteOrderIndexAfterTask(
    TopicTasksTarget target,
    Task? afterTask,
  ) async {
    final blocks = await _blockService.listForFile(target.file.id);
    if (afterTask == null) {
      var maxOrder = target.listBlock.orderIndex ?? 0;
      for (final block in blocks) {
        if (block.type == 'task' && (block.orderIndex ?? 0) >= maxOrder) {
          maxOrder = (block.orderIndex ?? 0) + 1;
        }
      }
      return maxOrder;
    }

    final afterRow = await findTaskRowBlock(afterTask);
    if (afterRow == null) {
      return _remoteOrderIndexAfterTask(target, null);
    }
    final orderIndex = (afterRow.orderIndex ?? 0) + 1;
    for (final block in blocks) {
      if ((block.orderIndex ?? 0) >= orderIndex) {
        await _blockService.updateBlock(block.id, {
          'order_index': (block.orderIndex ?? 0) + 1,
        });
      }
    }
    return orderIndex;
  }

  Future<Task> createTaskInView({
    required String viewType,
    required Topic topic,
    String title = '',
    String? sectionName,
    Task? afterTask,
    String status = 'active',
  }) async {
    final target = await ensureTopicTasksTarget(topic);
    final orderIndex = await _remoteOrderIndexAfterTask(target, afterTask);
    final task = await _taskService.createTask(
      blockId: target.listBlock.id,
      title: title,
      status: status,
    );
    await _blockService.createBlock(
      fileId: target.file.id,
      type: 'task',
      content: {'task_id': task.id},
      orderIndex: orderIndex,
    );

    TaskViewMembership membership;
    final existing = membershipForTaskInView(task.id, viewType);
    if (existing == null) {
      membership = await _taskViewService.createMembership(
        taskId: task.id,
        viewType: viewType,
        sectionName: sectionName,
      );
      _taskViewMemberships = [..._taskViewMemberships, membership];
    } else if (sectionName != existing.sectionName) {
      membership = await _taskViewService.update(
        existing.id,
        sectionName: sectionName,
      );
      _taskViewMemberships = _taskViewMemberships
          .map((m) => m.id == existing.id ? membership : m)
          .toList();
    } else {
      membership = existing;
    }

    final enriched = task.copyWith(
      taskViewId: membership.id,
      viewType: viewType,
      sectionName: sectionName,
      sectionFlag: membership.sectionFlag,
      topicId: topic.id,
      topicName: topic.name,
    );

    if (selectedViewType == viewType) {
      viewTasks = [...viewTasks, enriched];
      _cacheCurrentView();
    }
    _syncSelectedDetailTask(enriched, target);
    notifyListeners();
    return enriched;
  }

  Future<void> deleteTaskInView(Task task) async {
    final rowBlock = await findTaskRowBlock(task);
    await _taskService.deleteTask(task.id);
    if (rowBlock != null) {
      await _blockService.deleteBlock(rowBlock.id);
    }
    _taskViewMemberships = _taskViewMemberships
        .where((m) => m.taskId != task.id)
        .toList();
    if (selectedViewType != null) {
      viewTasks = viewTasks.where((t) => t.id != task.id).toList();
      _cacheCurrentView();
    }
    _removeSelectedDetailTask(task);
    notifyListeners();
  }

  Future<void> assignTaskToTopicInView(
    Task task,
    Topic topic, {
    required String viewType,
    String? sectionName,
  }) async {
    final target = await ensureTopicTasksTarget(topic);
    final oldRow = await findTaskRowBlock(task);

    if (task.blockId != target.listBlock.id) {
      await _taskService.updateTask(task.id, {'block_id': target.listBlock.id});
    }
    if (oldRow != null && oldRow.fileId != target.file.id) {
      await _blockService.deleteBlock(oldRow.id);
    }

    Block? rowBlock = oldRow;
    if (rowBlock == null || rowBlock.fileId != target.file.id) {
      final orderIndex = await _remoteOrderIndexAfterTask(target, null);
      rowBlock = await _blockService.createBlock(
        fileId: target.file.id,
        type: 'task',
        content: {'task_id': task.id},
        orderIndex: orderIndex,
      );
    }

    final existing = membershipForTaskInView(task.id, viewType);
    TaskViewMembership membership;
    if (existing == null) {
      membership = await _taskViewService.createMembership(
        taskId: task.id,
        viewType: viewType,
        sectionName: sectionName ?? task.sectionName,
      );
      _taskViewMemberships = [..._taskViewMemberships, membership];
    } else {
      final nextSection = sectionName ?? task.sectionName;
      if (nextSection != existing.sectionName) {
        membership = await _taskViewService.update(
          existing.id,
          sectionName: nextSection,
        );
        _taskViewMemberships = _taskViewMemberships
            .map((m) => m.id == existing.id ? membership : m)
            .toList();
      } else {
        membership = existing;
      }
    }

    final enriched = task.copyWith(
      blockId: target.listBlock.id,
      taskViewId: membership.id,
      viewType: viewType,
      sectionName: membership.sectionName,
      sectionFlag: membership.sectionFlag,
      topicId: topic.id,
      topicName: topic.name,
    );

    if (selectedViewType == viewType) {
      viewTasks = viewTasks.map((t) => t.id == task.id ? enriched : t).toList();
      _cacheCurrentView();
    }
    _syncSelectedDetailTask(enriched, target, rowBlock: rowBlock);
    notifyListeners();
  }

  Future<void> updateTaskViewSectionInView(
    Task task,
    String viewType, {
    required String? sectionName,
    bool clearSection = false,
  }) async {
    final existing = membershipForTaskInView(task.id, viewType);
    if (existing == null) {
      await addTaskToView(
        task,
        viewType,
        sectionName: clearSection ? null : sectionName,
      );
      return;
    }
    if (!clearSection &&
        sectionName != null &&
        existing.sectionName == sectionName) {
      await removeTaskFromView(existing);
      return;
    }
    await updateTaskViewSection(
      existing,
      sectionName: sectionName,
      task: task,
      clearSection: clearSection,
    );
  }

  void _syncSelectedDetailTask(
    Task task,
    TopicTasksTarget target, {
    Block? rowBlock,
  }) {
    final detail = selectedDetail;
    if (detail == null || detail.topic.id != target.topic.id) return;

    final listId = target.listBlock.id;
    final tasks = List<Task>.from(detail.tasksByBlockId[listId] ?? []);
    final index = tasks.indexWhere((t) => t.id == task.id);
    if (index >= 0) {
      tasks[index] = task;
    } else {
      tasks.add(task);
    }
    detail.tasksByBlockId[listId] = tasks;

    if (rowBlock != null) {
      final block = rowBlock;
      final blocks = List<Block>.from(
        detail.blocksByFileId[target.file.id] ?? [],
      );
      if (!blocks.any((b) => b.id == block.id)) {
        blocks.add(block);
        blocks.sort((a, b) => (a.orderIndex ?? 0).compareTo(b.orderIndex ?? 0));
        detail.blocksByFileId[target.file.id] = blocks;
      }
    }
  }

  void _removeSelectedDetailTask(Task task) {
    final detail = selectedDetail;
    if (detail == null) return;
    for (final entry in detail.tasksByBlockId.entries.toList()) {
      detail.tasksByBlockId[entry.key] = entry.value
          .where((t) => t.id != task.id)
          .toList();
    }
    if (task.blockId != null) {
      for (final entry in detail.blocksByFileId.entries.toList()) {
        detail.blocksByFileId[entry.key] = entry.value
            .where((b) => b.type != 'task' || b.content['task_id'] != task.id)
            .toList();
      }
    }
  }

  void _applyTaskUpdate(Task updated) {
    Task merge(Task existing) => existing.copyWith(
      title: updated.title,
      status: updated.status,
      blockId: updated.blockId,
    );

    if (selectedViewType != null) {
      viewTasks = viewTasks
          .map((t) => t.id == updated.id ? merge(t) : t)
          .toList();
      _cacheCurrentView();
    }
    final detail = selectedDetail;
    if (detail != null) {
      for (final entry in detail.tasksByBlockId.entries) {
        detail.tasksByBlockId[entry.key] = entry.value
            .map((t) => t.id == updated.id ? merge(t) : t)
            .toList();
      }
    }
    notifyListeners();
  }

  Future<void> assignTaskView(
    Task task,
    String? viewType, {
    String? sectionName,
    bool clearSection = false,
    int? orderIndex,
  }) async {
    final previous = primaryMembershipForTask(task.id);
    final membership = await _taskViewService.assignView(
      taskId: task.id,
      viewType: viewType,
      sectionName: sectionName,
      clearSection: clearSection,
      orderIndex: orderIndex,
    );

    _taskViewMemberships = [
      ..._taskViewMemberships.where((m) => m.taskId != task.id),
      if (membership != null) membership,
    ];

    if (previous != null && selectedViewType == previous.viewType) {
      viewTasks = viewTasks.where((t) => t.id != task.id).toList();
    }
    if (membership != null && selectedViewType == membership.viewType) {
      final alreadyListed = viewTasks.any((t) => t.id == task.id);
      if (!alreadyListed) {
        viewTasks = [
          ...viewTasks,
          task.copyWith(
            taskViewId: membership.id,
            viewType: membership.viewType,
            sectionName: membership.sectionName,
            sectionFlag: membership.sectionFlag,
          ),
        ];
      } else {
        viewTasks = viewTasks
            .map(
              (t) => t.id == task.id
                  ? t.copyWith(
                      taskViewId: membership.id,
                      viewType: membership.viewType,
                      sectionName: membership.sectionName,
                      sectionFlag: membership.sectionFlag,
                    )
                  : t,
            )
            .toList();
      }
      _cacheCurrentView();
    }

    final detail = selectedDetail;
    if (detail != null) {
      for (final entry in detail.tasksByBlockId.entries) {
        detail.tasksByBlockId[entry.key] = entry.value
            .map(
              (t) => t.id == task.id
                  ? t.copyWith(
                      taskViewId: membership?.id,
                      viewType: membership?.viewType,
                      sectionName: membership?.sectionName,
                      sectionFlag: membership?.sectionFlag,
                      clearSection: membership?.sectionName == null,
                      clearSectionFlag: membership?.sectionFlag == null,
                    )
                  : t,
            )
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
    await assignTaskView(task, viewType, sectionName: sectionName);
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
                ? t.copyWith(sectionFlag: flag, clearSectionFlag: !important)
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
    Task? task;
    final detail = selectedDetail;
    if (detail != null) {
      for (final tasks in detail.tasksByBlockId.values) {
        for (final candidate in tasks) {
          if (candidate.id == membership.taskId) {
            task = candidate;
            break;
          }
        }
        if (task != null) break;
      }
    }
    if (task != null) {
      await assignTaskView(task, null);
      return;
    }

    await _taskViewService.assignView(
      taskId: membership.taskId,
      viewType: null,
    );
    _taskViewMemberships = _taskViewMemberships
        .where((m) => m.taskId != membership.taskId)
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
      'content': boardContentFromItems([
        ...items,
        next,
      ], base: boardBlock.content),
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
    final blocks = _blocksForFile(file);
    await _blockService.createBlock(
      fileId: file.id,
      type: 'image',
      content: {
        'image_path': uploaded['image_path'],
        'filename': uploaded['filename'],
      },
      orderIndex: blocks.length,
    );
    await _refreshAfterFileMutation(file);
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
    BlockTextFocusRegistry.abandonStashedFocus();
    await _refreshAfterFileMutation(file);
  }

  Future<Block?> ensureTaskListBlock(AppFile file) async {
    if (selectedDetail == null && !isGuestFile(file)) return null;
    final blocks = _blocksForFile(file);
    for (final block in blocks) {
      if (block.type == 'task_list') return block;
    }
    final block = await _blockService.createBlock(
      fileId: file.id,
      type: 'task_list',
      content: {},
      orderIndex: blocks.length,
    );
    if (isGuestFile(file)) {
      await _reloadBroughtFileBlocks();
      return broughtFile?.blocks.firstWhere(
        (b) => b.type == 'task_list',
        orElse: () => block,
      );
    }
    final detail = selectedDetail!;
    detail.blocksByFileId[file.id] = [...blocks, block];
    detail.tasksByBlockId[block.id] = [];
    notifyListeners();
    return block;
  }

  @override
  void dispose() {
    _automationRunPollTimer?.cancel();
    _automationStatusPollTimer?.cancel();
    for (final timer in _saveTimers.values) {
      timer?.cancel();
    }
    super.dispose();
  }
}
