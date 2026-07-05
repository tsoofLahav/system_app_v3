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
import '../../features/blocks/graph_content.dart';
import '../../design_system/glass_surface.dart';
import '../../design_system/note_widgets.dart';
import '../../features/blocks/board_block_widget.dart';
import '../../features/blocks/block_context_menu.dart';
import '../../features/blocks/block_renderer.dart';
import '../../shared/utils/local_image_picker.dart';

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
    if (widget.file.type == 'board') {
      return _buildBoardFile(context);
    }
    return _buildBlockFile(context);
  }

  Block? _boardBlock() {
    for (final block in widget.blocks) {
      if (block.type == 'board') return block;
    }
    return null;
  }

  Widget _buildBoardFile(BuildContext context) {
    final s = widget.state.strings;
    final topic = widget.topic;
    final isMainPane = widget.state.fileIsMain(topic, widget.file);
    final boardBlock = _boardBlock();

    return NoteCard(
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
                  onSelected: (value) => _onMenu(value, isMainPane: isMainPane),
                  itemBuilder: (context) => [
                    if (!isMainPane)
                      PopupMenuItem(
                        value: 'showOnMain',
                        child: Text(s['showOnMain']),
                      ),
                    if (isMainPane)
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
              child: boardBlock == null
                  ? Center(
                      child: Text(
                        s['boardEmptyHint'],
                        style: AppTypography.noteBodyStyle.copyWith(
                          color: AppColors.noteHint,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                  : BoardBlockWidget(
                      block: boardBlock,
                      addImageTooltip: s['boardAddImage'],
                      aiImageTooltip: s['aiImage'],
                      cropTooltip: s['boardCrop'],
                      aiPromptTitle: s['boardAiPromptTitle'],
                      aiPromptHint: s['boardAiPromptHint'],
                      emptyHint: s['boardEmptyHint'],
                      deleteImageLabel: s['boardDeleteImage'],
                      cancelLabel: s['cancel'],
                      submitLabel: s['aiImage'],
                      copyImageLabel: s['boardCopyImage'],
                      pasteImageLabel: s['boardPasteImage'],
                      backgroundLabel: s['boardBackground'],
                      backgroundCustomLabel: s['boardBackgroundCustom'],
                      backgroundWhiteLabel: s['boardBgWhite'],
                      backgroundLightGrayLabel: s['boardBgLightGray'],
                      backgroundSkyLabel: s['boardBgSky'],
                      backgroundCreamLabel: s['boardBgCream'],
                      okLabel: s['ok'],
                      isRtl: s.isRtl,
                      aiRunning: widget.state.aiRunning,
                      uploadImage: (filename, bytes) =>
                          widget.state.uploadImageBytes(filename, bytes),
                      onRunAiImage: (prompt) => _runBoardAiImage(
                        context,
                        boardBlock,
                        prompt,
                      ),
                      onChanged: (content) => widget.state.updateBlockContent(
                        boardBlock,
                        content,
                        notify: true,
                      ),
                      onCommit: (content) =>
                          widget.state.scheduleBlockSave(boardBlock, content),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockFile(BuildContext context) {
    final s = widget.state.strings;
    final topic = widget.topic;
    final isMainPane = widget.state.fileIsMain(topic, widget.file);
    final canToggleVisibility = true;
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
                  onSelected: (value) => _onMenu(value, isMainPane: isMainPane),
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
                      if (widget.blocks[i].type == 'task_list')
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.blockGap),
                          child: BlockRenderer(
                            topicAccent: widget.accent,
                            isMainTopic: topic.isMain,
                            file: widget.file,
                            block: widget.blocks[i],
                            tasks: tasks,
                            state: widget.state,
                            onBlockMenuAction: (action) => _handleBlockMenuAction(
                              action,
                              orderIndex: i + 1,
                              targetBlock: widget.blocks[i],
                            ),
                          ),
                        )
                      else if (widget.blocks[i].type == 'table')
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.blockGap),
                          child: BlockRenderer(
                            topicAccent: widget.accent,
                            isMainTopic: topic.isMain,
                            file: widget.file,
                            block: widget.blocks[i],
                            tasks: tasks,
                            state: widget.state,
                            onTableCellSecondaryTapDown: (position, row, column) =>
                                _showBlockMenu(
                              position,
                              orderIndex: _insertOrderIndexForBlock(
                                widget.blocks,
                                i,
                              ),
                              targetBlock: widget.blocks[i],
                              tableRow: row,
                              tableColumn: column,
                            ),
                          ),
                        )
                      else
                        GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onSecondaryTapDown: (details) => _showBlockMenu(
                            details.globalPosition,
                            orderIndex: _insertOrderIndexForBlock(
                              widget.blocks,
                              i,
                            ),
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

  Future<void> _onMenu(String value, {required bool isMainPane}) async {
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

  Future<void> _runBoardAiImage(
    BuildContext context,
    Block boardBlock,
    String prompt,
  ) async {
    final s = widget.state.strings;
    try {
      final result = await widget.state.runBoardAiImage(
        widget.file,
        boardBlock,
        prompt,
      );
      if (!context.mounted || result == null) return;
      final message = result.result ?? s['aiDone'];
      final target = result.targetFileName;
      showDialog<void>(
        context: context,
        builder: (ctx) => AppGlassDialog(
          title: Text(s['aiDone']),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(s['ok']),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (target != null) ...[
                Text(target, style: AppTypography.metaStyle),
                const SizedBox(height: 8),
              ],
              Text(message, style: AppTypography.noteBodyStyle),
            ],
          ),
        ),
      );
    } on ApiException catch (e) {
      _showUploadError(e.message);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())),
      );
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
    int? tableRow,
    int? tableColumn,
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
        tableRow: tableRow,
        tableColumn: tableColumn,
      ),
    );
  }

  int _insertOrderIndexForBlock(List<Block> blocks, int blockIndex) {
    final block = blocks[blockIndex];
    if (block.type == 'text' && block.text.trim().isEmpty) {
      return blockIndex;
    }
    return blockIndex + 1;
  }

  Future<void> _handleBlockMenuAction(
    String action, {
    required int orderIndex,
    Block? targetBlock,
    int? tableRow,
    int? tableColumn,
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
        await _insertTableRow(block, _tableRows(block.content['rows']).length);
      case 'table:row:before':
        await _insertTableRow(block, tableRow ?? 0);
      case 'table:row:after':
        await _insertTableRow(block, (tableRow ?? 0) + 1);
      case 'table:column':
        await _insertTableColumn(
          block,
          _tableColumnCount(block.content['rows']),
        );
      case 'table:column:before':
        await _insertTableColumn(block, tableColumn ?? 0);
      case 'table:column:after':
        await _insertTableColumn(block, (tableColumn ?? 0) + 1);
      case 'graph:bar':
      case 'graph:line':
      case 'graph:pie':
        final type = action.substring(6);
        await widget.state.updateBlockContent(
          block,
          {...block.content, 'chart_type': type},
          notify: true,
        );
      case 'graph:add_variable':
        await _addGraphVariable(block);
      case 'graph:remove_variable':
        await _removeGraphVariable(block);
      case 'graph:colors':
        await widget.state.updateBlockContent(
          block,
          {
            ...block.content,
            'palette_index': nextGraphPaletteIndex(block.content),
            'colors': null,
          },
          notify: true,
        );
      case 'image:replace':
        await _replaceImage(block);
      case 'image:reset_width':
        final content = Map<String, dynamic>.from(block.content);
        content.remove('width');
        content.remove('height');
        await widget.state.updateBlockContent(block, content, notify: true);
    }
  }

  Future<void> _insertTableRow(Block block, int atIndex) async {
    final rows = _tableRows(block.content['rows']);
    final columnCount = _tableColumnCount(block.content['rows']);
    final index = atIndex.clamp(0, rows.length);
    rows.insert(index, [for (var i = 0; i < columnCount; i++) '']);
    await widget.state.updateBlockContent(
      block,
      {...block.content, 'rows': rows},
      notify: true,
    );
  }

  Future<void> _insertTableColumn(Block block, int atIndex) async {
    final rows = _tableRows(block.content['rows']);
    final next = [
      for (final row in rows)
        [
          ...row.sublist(0, atIndex.clamp(0, row.length)),
          '',
          ...row.sublist(atIndex.clamp(0, row.length)),
        ],
    ];
    await widget.state.updateBlockContent(
      block,
      {...block.content, 'rows': next},
      notify: true,
    );
  }

  int _tableColumnCount(Object? rowsValue) {
    final rows = _tableRows(rowsValue);
    return rows.map((r) => r.length).fold<int>(2, (a, b) => a > b ? a : b);
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

  Future<void> _addGraphVariable(Block block) async {
    final labels = graphLabels(block.content);
    final values = graphValues(block.content, labels.length);
    final nextLabels = [...labels, nextGraphLabel(labels)];
    final nextValues = [...values, 0.0];
    await widget.state.updateBlockContent(
      block,
      graphContentWithColumns(
        base: block.content,
        labels: nextLabels,
        values: nextValues,
      ),
      notify: true,
    );
  }

  Future<void> _removeGraphVariable(Block block) async {
    final labels = graphLabels(block.content);
    if (labels.length <= 1) return;
    final values = graphValues(block.content, labels.length);
    final nextLabels = labels.sublist(0, labels.length - 1);
    final nextValues = values.sublist(0, values.length - 1);
    await widget.state.updateBlockContent(
      block,
      graphContentWithColumns(
        base: block.content,
        labels: nextLabels,
        values: nextValues,
      ),
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
  Future<(String, List<int>)?> _pickLocalImageFile() => pickLocalImageFile();

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
