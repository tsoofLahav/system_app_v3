import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/ai/ai_context.dart';
import '../../core/models/block.dart';
import '../../shared/utils/platform_text.dart';
import '../../core/models/task.dart';
import '../../design_system/app_colors.dart';
import '../../design_system/app_typography.dart';
import '../../features/blocks/list_text_parse.dart';
import '../../features/blocks/block_context_menu.dart';
import '../../core/models/task_view_menu_context.dart';
import '../../shared/widgets/task_context_menu.dart';
import '../../features/blocks/formatted_text_field.dart';
import 'details_hover_bubble.dart';
import 'task_mark.dart';

class TaskRow extends StatefulWidget {
  const TaskRow({
    super.key,
    required this.task,
    required this.state,
    required this.onToggle,
    this.taskBlock,
    this.onDelete,
    this.onTitleChanged,
    this.onAddTaskAfter,
    this.allTaskTitles,
    this.onPasteLines,
    this.autofocus = false,
    this.onAutofocused,
    this.contextMenuFileType,
    this.contextMenuTargetBlock,
    this.onBlockMenuAction,
    this.onReadOnlyAction,
    this.viewMenuContext,
    this.readOnly = false,
    this.toggleEnabled = true,
    this.onRowTap,
    this.aiFileId,
  });

  final Task task;
  final AppState state;
  final VoidCallback onToggle;
  final Block? taskBlock;
  final Future<void> Function()? onDelete;
  final ValueChanged<String>? onTitleChanged;
  final void Function(Offset globalPosition)? onAddTaskAfter;
  final List<String>? allTaskTitles;
  final Future<void> Function(List<String> lines, Offset globalPosition)?
  onPasteLines;
  final bool autofocus;
  final VoidCallback? onAutofocused;
  final String? contextMenuFileType;
  final Block? contextMenuTargetBlock;
  final BlockMenuHandler? onBlockMenuAction;
  final VoidCallback? onReadOnlyAction;
  final TaskViewMenuContext? viewMenuContext;
  final bool readOnly;
  final bool toggleEnabled;
  final VoidCallback? onRowTap;
  final int? aiFileId;

  @override
  State<TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<TaskRow> {
  late final TextEditingController _controller;
  final _focusNode = FocusNode();
  bool _normalizingSelection = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.task.title);
    _controller.addListener(_reportAiFocus);
    _controller.addListener(_normalizeSelectionIfNeeded);
    _focusNode.addListener(_reportAiFocus);
    _requestAutofocus();
  }

  @override
  void didUpdateWidget(TaskRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.task.id != widget.task.id &&
        _controller.text != widget.task.title) {
      _controller.text = widget.task.title;
    }
    _requestAutofocus();
  }

  void _requestAutofocus() {
    if (!widget.autofocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
      _controller.selection = const TextSelection.collapsed(offset: 0);
      widget.onAutofocused?.call();
    });
  }

  @override
  void dispose() {
    _controller.removeListener(_reportAiFocus);
    _controller.removeListener(_normalizeSelectionIfNeeded);
    _focusNode.removeListener(_reportAiFocus);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _normalizeSelectionIfNeeded() {
    if (_normalizingSelection) return;
    final normalized = normalizeTextSelection(_controller.text, _controller.selection);
    if (normalized == _controller.selection) return;
    _normalizingSelection = true;
    _controller.selection = normalized;
    _normalizingSelection = false;
  }

  void _reportAiFocus() {
    if (!_focusNode.hasFocus) return;
    final fileId = widget.aiFileId;
    if (fileId == null) return;
    widget.state.setAiFocus(
      AiFocus(
        fileId: fileId,
        blockId: widget.taskBlock?.id,
        fullText: _controller.text,
        selection: _controller.selection,
        isTaskInput: true,
      ),
    );
  }

  Future<void> _handlePaste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty || widget.onPasteLines == null) return;
    final lines = parsePastedListText(raw);
    if (lines.isEmpty) return;
    if (lines.length == 1) {
      _controller.text = lines.first;
      widget.onTitleChanged?.call(lines.first);
      return;
    }
    _controller.text = lines.first;
    widget.onTitleChanged?.call(lines.first);
    final box = _focusNode.context?.findRenderObject() as RenderBox?;
    final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
    await widget.onPasteLines!(lines.sublist(1), position);
  }

  void _copySelectionOrTitle() {
    final selection = _controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      setClipboardText(
        safeSubstring(_controller.text, selection.start, selection.end),
      );
      return;
    }
    setClipboardText(_controller.text);
  }

  void _cutSelectionOrTitle() {
    final selection = _controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      setClipboardText(
        safeSubstring(_controller.text, selection.start, selection.end),
      );
      final (start, end) = normalizeUtf16Range(
        _controller.text,
        selection.start,
        selection.end,
      );
      final next = _controller.text.replaceRange(start, end, '');
      _controller.text = sanitizePlatformText(next);
      widget.onTitleChanged?.call(_controller.text);
      return;
    }
    setClipboardText(_controller.text);
    _controller.clear();
    widget.onTitleChanged?.call('');
  }

  void _copyAllTitles() {
    final titles = widget.allTaskTitles;
    if (titles == null || titles.isEmpty) return;
    setClipboardText(titles.join('\n'));
  }

  Future<void> _showContextMenu(Offset globalPosition) async {
    if (widget.readOnly && widget.onReadOnlyAction != null) {
      widget.onReadOnlyAction?.call();
      return;
    }
    await showTaskContextMenu(
      context: context,
      globalPosition: globalPosition,
      task: widget.task,
      state: widget.state,
      onCut: _cutSelectionOrTitle,
      onCopy: _copySelectionOrTitle,
      onPaste: _handlePaste,
      onCopyAll: widget.allTaskTitles != null ? _copyAllTitles : null,
      onDelete: widget.onDelete,
      fileType: widget.contextMenuFileType,
      targetBlock: widget.contextMenuTargetBlock,
      onBlockAction: widget.onBlockMenuAction,
      viewMenuContext: widget.viewMenuContext,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lineHeight = AppTypography.taskRowLineHeight;
    final isAutomationReview =
        widget.task.hasAutomationFlow && widget.onRowTap != null;
    final titleStyle = AppTypography.taskRowStyle.copyWith(
      decoration: widget.task.isDone ? TextDecoration.lineThrough : null,
      color: widget.task.isDone
          ? AppColors.text.withValues(alpha: 0.45)
          : isAutomationReview
          ? AppColors.aiCyan.withValues(alpha: 0.92)
          : null,
    );

    Widget titleField;
    if (widget.readOnly) {
      final readOnlyContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.task.title, style: titleStyle),
            if (!widget.task.isAutomationTrigger &&
                widget.task.displaySubjectTopicName != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  widget.task.displaySubjectTopicName!,
                  style: AppTypography.metaStyle.copyWith(
                    color: AppColors.noteMeta.withValues(alpha: 0.75),
                  ),
                ),
              ),
          ],
        ),
      );
      if (!isAutomationReview && widget.onReadOnlyAction != null) {
        titleField = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onRowTap ?? widget.onReadOnlyAction,
          onSecondaryTapDown: (details) =>
              _showContextMenu(details.globalPosition),
          child: readOnlyContent,
        );
      } else {
        titleField = MouseRegion(
          cursor: isAutomationReview
              ? SystemMouseCursors.click
              : SystemMouseCursors.basic,
          child: InkWell(
            onTap: widget.onRowTap ?? widget.onReadOnlyAction,
            onSecondaryTapDown: (details) =>
                _showContextMenu(details.globalPosition),
            child: readOnlyContent,
          ),
        );
      }
    } else {
      titleField = FormattedTextField(
        controller: _controller,
        focusNode: _focusNode,
        textAlignVertical: TextAlignVertical.top,
        onSecondaryTapDown: (details) =>
            _showContextMenu(details.globalPosition),
        style: titleStyle,
        maxLines: null,
        minLines: 1,
        stripNewlines: true,
        emojiSearchHint: widget.state.strings['searchEmoji'],
        emojiPickerTitle: widget.state.strings['insertEmoji'],
        onChanged: (v) {
          _reportAiFocus();
          widget.onTitleChanged?.call(v);
        },
        onEnter: () {
          final box = _focusNode.context?.findRenderObject() as RenderBox?;
          final position = box?.localToGlobal(Offset.zero) ?? Offset.zero;
          widget.onAddTaskAfter?.call(position);
        },
        onBackspaceAtStart: () async {
          if (_controller.text.isEmpty) {
            await widget.onDelete?.call();
          }
        },
      );
    }

    final row = Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Focus(
          onKeyEvent: (_, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            final isMeta = HardwareKeyboard.instance.isMetaPressed;
            if (isMeta && event.logicalKey == LogicalKeyboardKey.keyA) {
              _copyAllTitles();
              return KeyEventResult.handled;
            }
            if (isMeta && event.logicalKey == LogicalKeyboardKey.keyV) {
              _handlePaste();
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: (details) =>
                    _showContextMenu(details.globalPosition),
                child: SizedBox(
                  width: 32,
                  height: lineHeight,
                  child: Center(
                    child: IgnorePointer(
                      ignoring: !widget.toggleEnabled,
                      child: Opacity(
                        opacity: widget.toggleEnabled ? 1 : 0.35,
                        child: TaskMark(
                          done: widget.task.isDone,
                          onToggle: widget.onToggle,
                          compact: true,
                          accent: isAutomationReview,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(child: titleField),
            ],
          ),
        ),
      ),
    );

    if (!isAutomationReview) {
      if (widget.task.detailsBlockId != null) {
        return DetailsHoverTarget(
          detailsBlockId: widget.task.detailsBlockId,
          loadBlock: widget.state.detailsBlockForId,
          child: row,
        );
      }
      return row;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: AppColors.aiCyan.withValues(alpha: 0.05),
          border: Border.all(
            color: AppColors.aiCyan.withValues(alpha: 0.32),
            width: 1,
          ),
        ),
        child: row,
      ),
    );
  }
}
