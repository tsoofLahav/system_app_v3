import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../core/app_state.dart';
import '../../core/services/api_service.dart';
import '../../core/models/app_file.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/topic.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_icons.dart';
import '../../design_system/app_typography.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/note_widgets.dart';
import '../../features/blocks/block_context_menu.dart';
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
  late final TextEditingController _titleController;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(
      text: widget.state.fileDisplayName(widget.file.name),
    );
  }

  @override
  void didUpdateWidget(FileSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.id != widget.file.id ||
        oldWidget.file.name != widget.file.name) {
      _titleController.text = widget.state.fileDisplayName(widget.file.name);
    }
  }

  @override
  void dispose() {
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
      topicAccent: widget.accent,
      fileType: widget.file.type,
      isMainTopic: topic.isMain,
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
                        onSecondaryTapDown: (details) => _showBlockMenu(
                          details.globalPosition,
                          orderIndex: i + 1,
                          targetBlock: widget.blocks[i],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.blockGap),
                          child: BlockRenderer(
                            topicAccent: widget.accent,
                            isMainTopic: topic.isMain,
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
    Block? targetBlock,
  }) async {
    await BlockContextMenu.show(
      context: context,
      globalPosition: position,
      strings: widget.state.strings,
      fileType: widget.file.type,
      orderIndex: orderIndex,
      targetBlock: targetBlock,
      onAction: (action) => _handleBlockMenuAction(
        action,
        orderIndex: orderIndex,
        targetBlock: targetBlock,
      ),
    );
  }

  Future<void> _handleBlockMenuAction(
    String action, {
    required int orderIndex,
    Block? targetBlock,
  }) async {
    if (action.startsWith('insert:')) {
      await _insertBlock(action.substring(7), orderIndex: orderIndex);
      return;
    }
    final block = targetBlock;
    if (block == null) return;

    switch (action) {
      case 'delete_block':
        await widget.state.deleteBlock(widget.file, block);
      case 'list:bullet':
        await widget.state.updateBlockContent(
          block,
          {...block.content, 'list_style': 'bullet'},
          notify: true,
        );
      case 'list:numbered':
        await widget.state.updateBlockContent(
          block,
          {...block.content, 'list_style': 'numbered'},
          notify: true,
        );
      case 'table:row':
        await _addTableRow(block);
      case 'table:column':
        await _addTableColumn(block);
      case 'graph:bar':
      case 'graph:line':
      case 'graph:pie':
        final type = action.substring(6);
        await widget.state.updateBlockContent(
          block,
          {...block.content, 'chart_type': type},
          notify: true,
        );
      case 'graph:edit':
        await _editGraphData(block);
      case 'image:replace':
        await _replaceImage(block);
      case 'image:reset_width':
        final content = Map<String, dynamic>.from(block.content);
        content.remove('width');
        content.remove('height');
        await widget.state.updateBlockContent(block, content, notify: true);
    }
  }

  Future<void> _addTableRow(Block block) async {
    final rows = _tableRows(block.content['rows']);
    final columnCount = rows.map((r) => r.length).fold<int>(2, (a, b) => a > b ? a : b);
    rows.add([for (var i = 0; i < columnCount; i++) '']);
    await widget.state.updateBlockContent(
      block,
      {...block.content, 'rows': rows},
      notify: true,
    );
  }

  Future<void> _addTableColumn(Block block) async {
    final rows = _tableRows(block.content['rows']);
    final next = [for (final row in rows) [...row, '']];
    await widget.state.updateBlockContent(
      block,
      {...block.content, 'rows': next},
      notify: true,
    );
  }

  List<List<String>> _tableRows(Object? value) {
    if (value is! List || value.isEmpty) {
      return [
        ['', ''],
        ['', ''],
      ];
    }
    return [
      for (final row in value)
        if (row is List)
          [for (final cell in row) cell?.toString() ?? '']
        else
          [row.toString()],
    ];
  }

  Future<void> _editGraphData(Block block) async {
    final s = widget.state.strings;
    final labelsController = TextEditingController(
      text: ((block.content['labels'] as List?) ?? []).join(', '),
    );
    final valuesController = TextEditingController(
      text: ((block.content['values'] as List?) ?? []).join(', '),
    );
    final titleController = TextEditingController(
      text: block.content['title']?.toString() ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AppGlassDialog(
        title: Text(s['editGraph']),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s['cancel']),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(s['save']),
          ),
        ],
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: titleController,
              decoration: AppTypography.noteInputDecoration(hint: s['name']),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: labelsController,
              decoration: AppTypography.noteInputDecoration(hint: 'A, B, C'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: valuesController,
              decoration: AppTypography.noteInputDecoration(hint: '10, 20, 15'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final labels = labelsController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final values = valuesController.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .map((s) => double.tryParse(s) ?? 0)
        .toList();
    await widget.state.updateBlockContent(
      block,
      {
        ...block.content,
        'title': titleController.text.trim(),
        'labels': labels,
        'values': values,
      },
      notify: true,
    );
  }

  Future<void> _replaceImage(Block block) async {
    try {
      final picked = await _pickLocalImageFile();
      if (picked == null) return;
      final uploaded = await widget.state.uploadImageBytes(picked.$1, picked.$2);
      await widget.state.updateBlockContent(
        block,
        {
          ...block.content,
          'image_path': uploaded['image_path'],
          'filename': uploaded['filename'],
        },
        notify: true,
      );
    } on ApiException catch (e) {
      _showUploadError(e.message);
    }
  }

  /// Opens the OS file picker after the context menu closes; returns name + bytes.
  Future<(String, List<int>)?> _pickLocalImageFile() async {
    // Let the popup route finish closing before opening the native picker.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    if (!mounted) return null;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    final file = result != null && result.files.isNotEmpty
        ? result.files.first
        : null;
    if (file == null || file.name.isEmpty) return null;

    final bytes = file.bytes ?? await _readBytesFromPath(file.path);
    if (bytes == null || bytes.isEmpty) return null;
    return (file.name, bytes);
  }

  Future<List<int>?> _readBytesFromPath(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _insertBlock(String type, {required int orderIndex}) async {
    if (type == 'image') {
      try {
        final picked = await _pickLocalImageFile();
        if (picked == null) return;
        await widget.state.insertImageBlock(
          widget.file,
          picked.$1,
          picked.$2,
          orderIndex: orderIndex,
        );
      } on ApiException catch (e) {
        _showUploadError(e.message);
      }
      return;
    }
    await widget.state.insertDefaultBlock(
      widget.file,
      type,
      orderIndex: orderIndex,
    );
  }

  void _showUploadError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
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
      child: const SizedBox(width: double.infinity, height: 4),
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
