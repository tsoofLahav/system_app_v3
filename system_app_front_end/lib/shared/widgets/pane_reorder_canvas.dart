import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/models/app_file.dart';
import '../../core/models/task.dart';
import '../../core/models/topic.dart';
import 'file_reorder_tile.dart';
import 'files_section_divider.dart';
import 'pane_reorder_logic.dart';

const _tileSpacing = 8.0;

class PaneReorderCanvas extends StatefulWidget {
  const PaneReorderCanvas({
    super.key,
    required this.topic,
    required this.mainFiles,
    required this.secondaryFiles,
    required this.state,
    required this.accent,
    required this.onDeleteFile,
    required this.onReorderError,
  });

  final Topic topic;
  final List<AppFile> mainFiles;
  final List<AppFile> secondaryFiles;
  final AppState state;
  final Color accent;
  final void Function(AppFile file) onDeleteFile;
  final void Function(String message) onReorderError;

  @override
  State<PaneReorderCanvas> createState() => _PaneReorderCanvasState();
}

class _PaneReorderCanvasState extends State<PaneReorderCanvas> {
  late PaneReorderState _sections;
  late List<AppFile> _mainOnly;
  bool _persisting = false;
  int? _draggingFileId;
  PaneReorderSection? _hoverSection;
  int? _hoverIndex;

  double get _rowHeight => fileReorderTileHeight + _tileSpacing;

  double get _mainZoneHeight => paneReorderMaxMainFiles * _rowHeight;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(PaneReorderCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_persisting) return;
    _syncFromWidget();
  }

  void _syncFromWidget() {
    if (widget.topic.isMain) {
      _mainOnly = List<AppFile>.from(widget.mainFiles);
    } else {
      _sections = PaneReorderState.fromFiles(
        mainFiles: widget.mainFiles,
        secondaryFiles: widget.secondaryFiles,
      );
    }
  }

  List<Task> _tasksForFile(int fileId) {
    final detail = widget.state.selectedDetail!;
    final tasks = <Task>[];
    for (final block in detail.blocksByFileId[fileId] ?? const []) {
      tasks.addAll(detail.tasksByBlockId[block.id] ?? const []);
    }
    return tasks;
  }

  Widget _buildTile(AppFile file, {required bool dimmed}) {
    final detail = widget.state.selectedDetail!;
    return _tileChrome(
      FileReorderTile(
        file: file,
        blocks: detail.blocksByFileId[file.id] ?? [],
        tasks: _tasksForFile(file.id),
        state: widget.state,
        accent: widget.accent,
        isMainTopic: widget.topic.isMain,
        dimmed: dimmed,
      ),
    );
  }

  Widget _tileChrome(Widget child) {
    return Padding(
      padding: const EdgeInsets.only(bottom: _tileSpacing),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: fileReorderTileMaxWidth),
          child: SizedBox(
            height: fileReorderTileHeight,
            width: double.infinity,
            child: child,
          ),
        ),
      ),
    );
  }

  void _onDragStarted(AppFile file) {
    setState(() {
      _draggingFileId = file.id;
      _hoverSection = null;
      _hoverIndex = null;
    });
  }

  void _onDragEnded() {
    setState(() {
      _draggingFileId = null;
      _hoverSection = null;
      _hoverIndex = null;
    });
  }

  void _onHover(PaneReorderSection section, int index) {
    if (_hoverSection == section && _hoverIndex == index) return;
    setState(() {
      _hoverSection = section;
      _hoverIndex = index;
    });
  }

  void _onHoverLeave() {
    if (_hoverSection == null && _hoverIndex == null) return;
    setState(() {
      _hoverSection = null;
      _hoverIndex = null;
    });
  }

  Future<void> _onDrop(
    AppFile file,
    PaneReorderSection toSection,
    int toIndex,
  ) async {
    _onDragEnded();

    if (widget.topic.isMain) {
      final fromIndex = _mainOnly.indexWhere((f) => f.id == file.id);
      if (fromIndex < 0) return;

      final previous = List<AppFile>.from(_mainOnly);
      setState(() {
        final moved = _mainOnly.removeAt(fromIndex);
        var insertAt = toIndex;
        if (fromIndex < toIndex) insertAt--;
        _mainOnly.insert(insertAt.clamp(0, _mainOnly.length), moved);
      });

      await _persist(
        ordered: _mainOnly,
        mainCount: _mainOnly.length,
        onError: () => setState(() => _mainOnly = previous),
      );
      return;
    }

    final fromSection = _sections.sectionOf(file);
    if (fromSection == null) return;
    final fromIndex = _sections.indexInSection(file, fromSection);

    final previous = PaneReorderState(
      main: List<AppFile>.from(_sections.main),
      additional: List<AppFile>.from(_sections.additional),
    );

    setState(() {
      _sections = applyPaneReorderDrop(
        state: _sections,
        file: file,
        from: fromSection,
        fromIndex: fromIndex,
        to: toSection,
        toIndex: toIndex,
      );
    });

    await _persist(
      ordered: orderedFiles(_sections),
      mainCount: _sections.main.length,
      onError: () => setState(() => _sections = previous),
    );
  }

  Future<void> _persist({
    required List<AppFile> ordered,
    required int mainCount,
    required VoidCallback onError,
  }) async {
    _persisting = true;
    final error = await widget.state.reorderTopicFiles(
      widget.topic,
      ordered,
      mainCount,
    );
    _persisting = false;

    if (!mounted) return;
    if (error != null) {
      onError();
      widget.onReorderError(error);
    } else {
      setState(_syncFromWidget);
    }
  }

  Widget _dropSlot({
    required PaneReorderSection section,
    required int index,
    required double emptyMinHeight,
  }) {
    final isHover =
        _hoverSection == section && _hoverIndex == index && _draggingFileId != null;

    final dragging = _draggingFileId != null;

    return DragTarget<AppFile>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (_) => _onHover(section, index),
      onLeave: (_) => _onHoverLeave(),
      onAcceptWithDetails: (details) =>
          _onDrop(details.data, section, index),
      builder: (context, candidateData, rejectedData) {
        final active = candidateData.isNotEmpty || isHover;
        final height = active
            ? _rowHeight
            : (dragging ? 6.0 : emptyMinHeight);
        return AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          height: height,
          width: double.infinity,
          alignment: AlignmentDirectional.centerStart,
          child: active
              ? Padding(
                  padding: const EdgeInsets.only(bottom: _tileSpacing),
                  child: SizedBox(height: fileReorderTileHeight),
                )
              : null,
        );
      },
    );
  }

  Widget _draggableFile(AppFile file, {required bool dimmed}) {
    final tile = _buildTile(file, dimmed: dimmed);

    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: SizedBox(
        width: fileReorderTileMaxWidth,
        child: Draggable<AppFile>(
          data: file,
          axis: Axis.vertical,
          onDragStarted: () => _onDragStarted(file),
          onDragEnd: (_) => _onDragEnded(),
          onDraggableCanceled: (velocity, offset) => _onDragEnded(),
          feedback: Material(
            color: Colors.transparent,
            child: SizedBox(
              width: fileReorderTileMaxWidth,
              child: _buildTile(file, dimmed: false),
            ),
          ),
          childWhenDragging: const SizedBox.shrink(),
          child: tile,
        ),
      ),
    );
  }

  Widget _fileList({
    required List<AppFile> files,
    required PaneReorderSection section,
    required double emptySlotMinHeight,
  }) {
    if (files.isEmpty) {
      return _dropSlot(
        section: section,
        index: 0,
        emptyMinHeight: emptySlotMinHeight,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i <= files.length; i++) ...[
          _dropSlot(
            section: section,
            index: i,
            emptyMinHeight: 0,
          ),
          if (i < files.length)
            _draggableFile(
              files[i],
              dimmed: _draggingFileId != null && _draggingFileId != files[i].id,
            ),
        ],
      ],
    );
  }

  Widget _scrollableListFrame({
    required double? height,
    required Widget child,
  }) {
    final list = SingleChildScrollView(child: child);
    if (height == null) return Expanded(child: list);
    return SizedBox(height: height, child: ClipRect(child: list));
  }

  Widget _buildDualSectionLayout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _scrollableListFrame(
          height: _mainZoneHeight,
          child: _fileList(
            files: _sections.main,
            section: PaneReorderSection.main,
            emptySlotMinHeight: _mainZoneHeight,
          ),
        ),
        const FilesSectionDivider(compact: true),
        _scrollableListFrame(
          height: null,
          child: _fileList(
            files: _sections.additional,
            section: PaneReorderSection.additional,
            emptySlotMinHeight: _rowHeight,
          ),
        ),
      ],
    );
  }

  Widget _buildMainTopicLayout() {
    return SingleChildScrollView(
      child: _fileList(
        files: _mainOnly,
        section: PaneReorderSection.main,
        emptySlotMinHeight: _rowHeight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: widget.topic.isMain
          ? _buildMainTopicLayout()
          : _buildDualSectionLayout(),
    );
  }
}
