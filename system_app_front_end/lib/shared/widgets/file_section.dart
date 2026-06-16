import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/topic.dart';
import '../../core/registry/file_behavior_registry.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/note_widgets.dart';
import '../../features/blocks/block_renderer.dart';

class FileSection extends StatefulWidget {
  const FileSection({
    super.key,
    required this.topic,
    required this.file,
    required this.blocks,
    required this.state,
    required this.onDelete,
    this.accent,
  });

  final Topic topic;
  final AppFile file;
  final List<Block> blocks;
  final AppState state;
  final VoidCallback onDelete;
  final Color? accent;

  @override
  State<FileSection> createState() => _FileSectionState();
}

class _FileSectionState extends State<FileSection> {
  final _taskController = TextEditingController();
  final _taskFocusNode = FocusNode();
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.state.fileDisplayName(widget.file.name),
    );
    _taskController.addListener(_reportTaskAiFocus);
  }

  @override
  void didUpdateWidget(FileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id ||
        oldWidget.file.name != widget.file.name) {
      _titleController.text = widget.state.fileDisplayName(widget.file.name);
    }
  }

  void _reportTaskAiFocus() {
    widget.state.setAiFocus(
      AiFocus(
        fileId: widget.file.id,
        fullText: _taskController.text,
        selection: _taskController.selection,
        isTaskInput: true,
      ),
    );
  }

  @override
  void dispose() {
    _taskController.removeListener(_reportTaskAiFocus);
    _taskController.dispose();
    _taskFocusNode.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state.strings;
    final topic = widget.topic;
    final isMainPane = widget.state.fileIsMain(topic, widget.file);
    final canToggleVisibility = !topic.isMain;
    final tasks = <Task>[];
    for (final b in widget.blocks) {
      tasks.addAll(
        widget.state.selectedDetail?.tasksByBlockId[b.id] ?? const [],
      );
    }

    final note = NoteCard(
      accent: widget.accent,
      child: Padding(
        padding: AppSpacing.notePadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _titleController,
                    style: AppTypography.noteTitleStyle,
                    decoration: AppTypography.noteInputDecoration(),
                    textInputAction: TextInputAction.done,
                    onSubmitted: _saveTitle,
                    onEditingComplete: () => _saveTitle(_titleController.text),
                  ),
                ),
                PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  icon: AppIcon(
                    AppIcons.more,
                    size: 18,
                    color: AppColors.noteMeta.withValues(alpha: 0.72),
                  ),
                  onSelected: (value) => _onMenu(value),
                  itemBuilder: (context) => [
                    if (canToggleVisibility && !isMainPane)
                      PopupMenuItem(
                        value: 'showOnMain',
                        child: Text(s['showOnMain']),
                      ),
                    if (canToggleVisibility && isMainPane)
                      PopupMenuItem(
                        value: 'moveToMoreFiles',
                        child: Text(s['moveToMoreFiles']),
                      ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(s['deleteFile']),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 4),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _InlineInsertGap(
                      onSecondaryTapDown: (details) =>
                          _showBlockMenu(details.globalPosition, orderIndex: 0),
                    ),
                    for (var i = 0; i < widget.blocks.length; i++) ...[
                      GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onSecondaryTapDown: widget.blocks[i].type == 'table'
                            ? null
                            : (details) => _showBlockMenu(
                                details.globalPosition,
                                orderIndex: i + 1,
                              ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: BlockRenderer(
                            file: widget.file,
                            block: widget.blocks[i],
                            tasks: tasks,
                            state: widget.state,
                          ),
                        ),
                      ),
                      _InlineInsertGap(
                        onSecondaryTapDown: (details) => _showBlockMenu(
                          details.globalPosition,
                          orderIndex: i + 1,
                        ),
                      ),
                    ],
                    if (FileBehaviorRegistry.showsTaskInputForFileType(
                      widget.file.type,
                    )) ...[
                      TextField(
                        controller: _taskController,
                        focusNode: _taskFocusNode,
                        style: AppTypography.noteBodyStyle,
                        decoration: AppTypography.noteInputDecoration(
                          hint: s['newTaskHint'],
                        ),
                        onTap: _reportTaskAiFocus,
                        onSubmitted: (value) async {
                          final listBlock = await widget.state
                              .ensureTaskListBlock(widget.file);
                          if (listBlock != null && value.trim().isNotEmpty) {
                            await widget.state.addTask(listBlock, value);
                            _taskController.clear();
                            _taskFocusNode.requestFocus();
                          }
                        },
                      ),
                    ],
                    _FileContextArea(
                      onSecondaryTapDown: (details) => _showBlockMenu(
                        details.globalPosition,
                        orderIndex: widget.blocks.length,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return note;
  }

  Future<void> _onMenu(String value) async {
    final s = widget.state.strings;
    if (value == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AppGlassDialog(
          title: Text(s['deleteFileTitle']),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(s['cancel']),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(s['delete']),
            ),
          ],
          child: Text(s.deleteFileMessage(widget.file.name)),
        ),
      );
      if (ok == true) widget.onDelete();
    } else if (value == 'showOnMain') {
      await widget.state.promoteFileToMain(widget.topic, widget.file);
    } else if (value == 'moveToMoreFiles') {
      await widget.state.demoteFileToSecondary(widget.topic, widget.file);
    }
  }

  Future<void> _saveTitle(String value) async {
    final trimmed = value.trim();
    final displayName = widget.state.fileDisplayName(widget.file.name);
    if (trimmed.isEmpty || trimmed == displayName) return;
    await widget.state.updateFileName(widget.topic, widget.file, trimmed);
  }

  Future<void> _showBlockMenu(
    Offset position, {
    required int orderIndex,
  }) async {
    final s = widget.state.strings;
    final options = FileBehaviorRegistry.contextMenuForFileType(
      widget.file.type,
    );
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final localPosition = overlay.globalToLocal(position);
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        localPosition.dx,
        localPosition.dy,
        overlay.size.width - localPosition.dx,
        overlay.size.height - localPosition.dy,
      ),
      items: [
        for (final type in options)
          PopupMenuItem(value: type, child: Text(_blockLabel(type, s))),
      ],
    );
    if (selected == null) return;
    await _insertBlock(selected, orderIndex: orderIndex);
  }

  Future<void> _insertBlock(String type, {required int orderIndex}) async {
    if (type == 'image') {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final file = result?.files.first;
      if (file?.bytes != null && file!.name.isNotEmpty) {
        await widget.state.insertImageBlock(
          widget.file,
          file.name,
          file.bytes!,
          orderIndex: orderIndex,
        );
      }
      return;
    }
    await widget.state.insertDefaultBlock(
      widget.file,
      type,
      orderIndex: orderIndex,
    );
  }

  String _blockLabel(String type, AppStrings s) {
    switch (type) {
      case 'text':
        return s['addText'];
      case 'header':
        return s['addHeader'];
      case 'summary':
        return s['addSummary'];
      case 'checklist':
        return s['addChecklist'];
      case 'image':
        return s['addImage'];
      case 'table':
        return s['addTable'];
      case 'list':
        return s['addList'];
      case 'graph':
        return s['addGraph'];
      case 'task_list':
        return s['addTaskList'];
      default:
        return type;
    }
  }
}

class _InlineInsertGap extends StatelessWidget {
  const _InlineInsertGap({required this.onSecondaryTapDown});

  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: onSecondaryTapDown,
      child: const SizedBox(width: double.infinity, height: 6),
    );
  }
}

class _FileContextArea extends StatelessWidget {
  const _FileContextArea({required this.onSecondaryTapDown});

  final GestureTapDownCallback onSecondaryTapDown;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onSecondaryTapDown: onSecondaryTapDown,
      child: const SizedBox(width: double.infinity, height: 34),
    );
  }
}
