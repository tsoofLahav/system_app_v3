import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ai/ai_context.dart';
import 'l10n/app_language.dart';
import 'l10n/app_strings.dart';
import 'models/app_file.dart';
import 'models/block.dart';
import 'models/task.dart';
import 'models/task_view_membership.dart';
import 'models/topic.dart';
import 'models/view_section.dart';
import 'registry/file_behavior_registry.dart';
import 'registry/file_registry.dart';
import 'registry/task_view_display.dart';
import 'registry/topic_appearance.dart';
import '../design_system/file_layouts.dart';
import 'services/ai_service.dart';
import 'services/api_service.dart';
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

  bool loading = true;
  String? error;
  List<Topic> topics = [];
  Topic? mainTopic;
  Topic? selectedTopic;
  TopicDetail? selectedDetail;
  String? selectedViewType;
  List<Task> viewTasks = [];
  List<ViewSection> viewSections = [];
  TaskViewDisplayMode viewDisplayMode = TaskViewDisplayMode.bySection;
  List<TaskViewMembership> _taskViewMemberships = [];
  bool moreFilesExpanded = false;
  bool paneDragMode = false;
  final Map<int, String> _layoutByTopicId = {};
  AppLanguage language = AppLanguage.en;
  AiFocus? aiFocus;
  int? pendingFocusBlockId;
  bool aiRunning = false;

  final Map<int, Timer?> _saveTimers = {};

  AppStrings get strings => AppStrings.forLanguage(language);
  bool get isRtl => strings.isRtl;
  TextDirection get textDirection => strings.textDirection;

  String viewLabel(String type) => strings.viewLabel(type);
  String fileDisplayName(String name) => strings.fileNameLabel(name);
  String topicDisplayName(Topic topic) =>
      topic.isMain ? strings['main'] : topic.name;
  String taskTopicDisplayName(Task task) =>
      strings.displayTopicName(task.topicName);

  Future<void> setLanguage(AppLanguage value) async {
    if (language == value) return;
    language = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_language', value.name);
    notifyListeners();
  }

  void setAiFocus(AiFocus focus) {
    aiFocus = focus;
    notifyListeners();
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
    String? lastChecklistItem;
    int? lastChecklistBlockId;
    int? lastChecklistFileId;

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

      final blocks = detail.blocksByFileId[file.id] ?? [];
      for (final block in blocks) {
        if (block.type != 'checklist') continue;
        final items = block.content['items'] as List<dynamic>? ?? [];
        if (items.isNotEmpty) {
          final last = items.last as Map<String, dynamic>;
          final text = last['text'] as String? ?? '';
          if (text.trim().isNotEmpty) {
            lastChecklistItem = text;
            lastChecklistBlockId = block.id;
            lastChecklistFileId = file.id;
          }
        }
      }
    }

    return AiContextResolver.resolve(
      topicId: detail.topic.id,
      focus: aiFocus,
      lastTaskTitle: lastTaskTitle,
      lastChecklistItem: lastChecklistItem,
      lastTaskFileId: lastTaskFileId,
      lastChecklistBlockId: lastChecklistBlockId,
      lastChecklistFileId: lastChecklistFileId,
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

  Future<AiRunResult?> runAiTool(String tool) async {
    final topic = selectedTopic;
    if (topic == null) return null;

    var ctx = resolveAiContext();
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

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    language = AppLanguage.fromStorage(prefs.getString('app_language'));
  }

  List<Topic> get projects =>
      topics.where((t) => t.type == 'project' && !t.isMain).toList();

  List<Topic> get processes =>
      topics.where((t) => t.type == 'process' && !t.isMain).toList();

  List<Topic> get areas =>
      topics.where((t) => t.type == 'area' && !t.isMain).toList();

  bool get isViewMode => selectedViewType != null;

  Future<void> initialize() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _loadLanguage();
      mainTopic = await _bootstrap.ensureMainTopic();
      await refreshTopics();
      await _refreshTaskViewMemberships();
      await selectTopic(mainTopic!);
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
    topics = await _topicService.listTopics();
    mainTopic = topics.firstWhere((t) => t.isMain, orElse: () => mainTopic!);
    notifyListeners();
  }

  Future<void> selectTopic(Topic topic) async {
    loading = true;
    error = null;
    selectedViewType = null;
    viewTasks = [];
    selectedTopic = topic;
    notifyListeners();
    try {
      final files = await _fileService.listForTopic(topic.id);
      final blocksByFileId = <int, List<Block>>{};
      final tasksByBlockId = <int, List<Task>>{};

      for (final file in files) {
        final blocks = await _ensureTrailingDefaultBlock(
          file,
          await _blockService.listForFile(file.id),
        );
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
    } catch (e) {
      error = e.toString();
      selectedDetail = null;
    } finally {
      loading = false;
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
    loading = true;
    error = null;
    selectedViewType = viewType;
    selectedTopic = null;
    selectedDetail = null;
    notifyListeners();
    try {
      viewSections = await _taskViewService.listSectionsForView(viewType);
      viewTasks = await _taskService.listByView(viewType);
    } catch (e) {
      error = e.toString();
      viewTasks = [];
    } finally {
      loading = false;
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
      final allMain = topic.isMain;
      for (var i = 0; i < ordered.length; i++) {
        final isMain = allMain || i < mainCount;
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
          ordered[i].copyWith(orderIndex: i, isMain: allMain || i < mainCount),
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

    final mainFiles = mainFilesFor(topic, detail.files);
    final secondaryFiles = secondaryFilesFor(topic, detail.files);
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
          (f) => f.id == file.id
              ? f.copyWith(isMain: isMain, orderIndex: orderIndex)
              : f,
        )
        .toList();
    _applyOptimisticFiles(updated);
  }

  Future<void> promoteFileToMain(Topic topic, AppFile file) async {
    if (topic.isMain) return;
    await setFileMainVisibility(topic, file, isMain: true);
  }

  Future<void> demoteFileToSecondary(Topic topic, AppFile file) async {
    if (topic.isMain) return;
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
        isMain: topic.isMain ? true : def.isMain,
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
    final isMain = topic.isMain
        ? true
        : def?.isMain ??
              FileRegistry.isMainFile(
                topicType: topic.type,
                fileType: type,
                isMainTopic: false,
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

  Future<List<Block>> _ensureTrailingDefaultBlock(
    AppFile file,
    List<Block> blocks,
  ) async {
    final trailingType = FileBehaviorRegistry.inlineInsertForFileType(
      file.type,
    );
    if (trailingType == null || trailingType != 'text') return blocks;
    if (blocks.isNotEmpty && _isEmptyTextBlock(blocks.last)) return blocks;
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
    final files = await _fileService.listForTopic(topic.id);
    for (final file in files) {
      await _fileService.deleteFile(file.id);
    }
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

  Future<void> addTask(Block block, String title) async {
    final detail = selectedDetail;
    if (detail == null || title.trim().isEmpty) return;
    final task = await _taskService.createTask(
      blockId: block.id,
      title: title.trim(),
    );
    final taskBlock = await _blockService.createBlock(
      fileId: block.fileId!,
      type: 'task',
      content: {'task_id': task.id},
      orderIndex: detail.blocksByFileId[block.fileId]?.length ?? 0,
    );
    final fileId = block.fileId!;
    detail.blocksByFileId[fileId] = [
      ...(detail.blocksByFileId[fileId] ?? []),
      taskBlock,
    ];
    detail.tasksByBlockId[block.id] = [
      ...(detail.tasksByBlockId[block.id] ?? []),
      task,
    ];
    notifyListeners();
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
                    clearSection: clearSection,
                  )
                : t,
          )
          .toList();
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
    for (final timer in _saveTimers.values) {
      timer?.cancel();
    }
    super.dispose();
  }
}
