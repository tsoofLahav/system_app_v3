import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_state.dart';
import '../../core/models/block.dart';
import '../../core/models/task.dart';
import '../../core/models/task_view_menu_context.dart';
import '../../design_system/app_typography.dart';
import '../../shared/widgets/task_context_menu.dart';
import 'block_context_menu.dart';
import 'list_text_parse.dart';

typedef LineAccessoryBuilder = Widget Function(
  BuildContext context,
  int lineIndex,
);

typedef LineTapCallback = void Function(TapDownDetails details, int lineIndex);

typedef ConnectedLinesChanged = FutureOr<void> Function(List<String> lines);

/// One multiline field where each newline-delimited row is a logical item.
/// Keyboard navigation (arrows, enter, backspace) behaves like plain text.
class ConnectedLinesEditor extends StatefulWidget {
  const ConnectedLinesEditor({
    super.key,
    required this.lines,
    required this.onLinesChanged,
    required this.style,
    this.gutterWidth = 22,
    this.gutterLabelBuilder,
    this.lineAccessoryBuilder,
    this.accessoryWidth = 32,
    this.hint,
    this.debounceMs = 280,
    this.contextMenuTasks,
    this.contextMenuState,
    this.onCopyAll,
    this.contextMenuFileType,
    this.contextMenuTargetBlock,
    this.onBlockMenuAction,
    this.viewMenuContext,
    this.dividerAfterLineIndex,
    this.lineTaskIds,
  });

  final List<String> lines;
  final ConnectedLinesChanged onLinesChanged;
  final TextStyle style;
  final double gutterWidth;
  final String Function(int index)? gutterLabelBuilder;
  final LineAccessoryBuilder? lineAccessoryBuilder;
  final double accessoryWidth;
  final String? hint;
  final int debounceMs;
  final List<Task>? contextMenuTasks;
  final AppState? contextMenuState;
  final VoidCallback? onCopyAll;
  final String? contextMenuFileType;
  final Block? contextMenuTargetBlock;
  final BlockMenuHandler? onBlockMenuAction;
  final TaskViewMenuContext? viewMenuContext;
  final int? dividerAfterLineIndex;
  final List<int>? lineTaskIds;

  @override
  State<ConnectedLinesEditor> createState() => _ConnectedLinesEditorState();
}

class _ConnectedLinesEditorState extends State<ConnectedLinesEditor> {
  late TextEditingController _controller;
  Timer? _debounce;
  List<String> _lastEmitted = const [];
  List<int> _lastTaskIds = const [];
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _lastEmitted = normalizeDocumentLines(widget.lines);
    _lastTaskIds = List<int>.from(widget.lineTaskIds ?? const []);
    _controller = TextEditingController(text: documentFromLines(_lastEmitted));
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(ConnectedLinesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = normalizeDocumentLines(widget.lines);
    final nextText = documentFromLines(next);
    final nextTaskIds = widget.lineTaskIds ?? const <int>[];
    final orderChanged = nextTaskIds.isNotEmpty &&
        (_lastTaskIds.length != nextTaskIds.length ||
            !_taskIdsEqual(_lastTaskIds, nextTaskIds));

    if (orderChanged || (!_editing && nextText != _controller.text)) {
      _controller.text = nextText;
      _lastEmitted = next;
      _lastTaskIds = List<int>.from(nextTaskIds);
      _editing = false;
      return;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _flush();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    _editing = true;
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(Duration(milliseconds: widget.debounceMs), _flush);
  }

  void _flush() {
    _debounce?.cancel();
    if (!mounted) return;
    final lines = linesFromDocument(_controller.text);
    if (_listsEqual(lines, _lastEmitted)) {
      _editing = false;
      return;
    }
    _lastEmitted = lines;
    final result = widget.onLinesChanged(lines);
    if (result is Future<void>) {
      result.whenComplete(() {
        if (!mounted) return;
        setState(() => _editing = false);
      });
    } else {
      _editing = false;
    }
  }

  bool get _hasTaskContextMenu =>
      widget.contextMenuTasks != null && widget.contextMenuState != null;

  Future<void> _showContextMenuForLine(
    int lineIndex,
    Offset globalPosition,
  ) async {
    final tasks = widget.contextMenuTasks;
    final menuState = widget.contextMenuState;
    if (tasks == null || menuState == null || lineIndex >= tasks.length) {
      return;
    }
    await showTaskContextMenu(
      context: context,
      globalPosition: globalPosition,
      task: tasks[lineIndex],
      state: menuState,
      onCut: () => _cutAtLine(lineIndex),
      onCopy: () => _copyAtLine(lineIndex),
      onPaste: () => _pasteAtLine(lineIndex),
      onCopyAll: widget.onCopyAll,
      fileType: widget.contextMenuFileType,
      targetBlock: widget.contextMenuTargetBlock,
      onBlockAction: widget.onBlockMenuAction,
      viewMenuContext: widget.viewMenuContext,
    );
  }

  void _copyAtLine(int lineIndex) {
    final selection = _controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      Clipboard.setData(
        ClipboardData(
          text: _controller.text.substring(selection.start, selection.end),
        ),
      );
      return;
    }
    final lines = linesFromDocument(_controller.text);
    if (lineIndex < lines.length) {
      Clipboard.setData(ClipboardData(text: lines[lineIndex]));
    }
  }

  void _cutAtLine(int lineIndex) {
    final selection = _controller.selection;
    if (selection.isValid && !selection.isCollapsed) {
      Clipboard.setData(
        ClipboardData(
          text: _controller.text.substring(selection.start, selection.end),
        ),
      );
      _controller.text = _controller.text.replaceRange(
        selection.start,
        selection.end,
        '',
      );
      _flush();
      return;
    }
    final lines = linesFromDocument(_controller.text);
    if (lineIndex >= lines.length) return;
    Clipboard.setData(ClipboardData(text: lines[lineIndex]));
    lines[lineIndex] = '';
    _controller.text = documentFromLines(lines);
    _flush();
  }

  Future<void> _pasteAtLine(int lineIndex) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty) return;
    final pasted = parsePastedListText(raw);
    if (pasted.isEmpty) return;

    final lines = linesFromDocument(_controller.text);
    while (lines.length <= lineIndex) {
      lines.add('');
    }

    if (pasted.length == 1) {
      lines[lineIndex] = pasted.first;
    } else {
      lines.removeAt(lineIndex);
      lines.insertAll(lineIndex, pasted);
    }
    _controller.text = documentFromLines(lines);
    _flush();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (_, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        final isMeta = HardwareKeyboard.instance.isMetaPressed;
        if (isMeta && event.logicalKey == LogicalKeyboardKey.keyA) {
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
          return KeyEventResult.handled;
        }
        if (isMeta &&
            event.logicalKey == LogicalKeyboardKey.keyC &&
            _controller.selection.isCollapsed == false) {
          return KeyEventResult.ignored;
        }
        if (isMeta && event.logicalKey == LogicalKeyboardKey.keyC) {
          widget.onCopyAll?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final accessoryWidth =
              widget.lineAccessoryBuilder != null ? widget.accessoryWidth : 0.0;
          final gutterWidth =
              widget.gutterLabelBuilder != null ? widget.gutterWidth : 0.0;
          final fieldWidth = (constraints.maxWidth - accessoryWidth - gutterWidth)
              .clamp(1.0, double.infinity);

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (widget.lineAccessoryBuilder != null)
                _AlignedLineColumn(
                  text: _controller.text,
                  style: widget.style,
                  contentWidth: fieldWidth,
                  width: accessoryWidth,
                  dividerAfterLineIndex: widget.dividerAfterLineIndex,
                  childBuilder: (context, index) => widget.lineAccessoryBuilder!(
                    context,
                    index,
                  ),
                  onSecondaryTap: _hasTaskContextMenu
                      ? (details, index) =>
                          _showContextMenuForLine(index, details.globalPosition)
                      : null,
                ),
              if (widget.gutterLabelBuilder != null)
                _AlignedLineColumn(
                  text: _controller.text,
                  style: widget.style,
                  contentWidth: fieldWidth,
                  width: gutterWidth,
                  align: Alignment.topRight,
                  padding: const EdgeInsets.only(top: 2, right: 4),
                  childBuilder: (context, index) => Text(
                    widget.gutterLabelBuilder!(index),
                    style: widget.style,
                    textAlign: TextAlign.right,
                  ),
                ),
              SizedBox(
                width: fieldWidth,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onSecondaryTapDown: _hasTaskContextMenu
                      ? (details) {
                          final box = context.findRenderObject() as RenderBox?;
                          if (box == null) return;
                          final local = box.globalToLocal(details.globalPosition);
                          final lineIndex = lineIndexAtLocalY(
                            text: _controller.text,
                            style: widget.style,
                            maxWidth: fieldWidth,
                            localY: local.dy,
                            textDirection: Directionality.of(context),
                          );
                          _showContextMenuForLine(lineIndex, details.globalPosition);
                        }
                      : null,
                  child: TextField(
                    controller: _controller,
                    style: widget.style,
                    maxLines: null,
                    minLines: 1,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                    decoration: AppTypography.noteInputDecoration(
                      hint: widget.hint,
                      fontSize: widget.style.fontSize,
                    ),
                    contextMenuBuilder: _hasTaskContextMenu
                        ? (context, editableTextState) => const SizedBox.shrink()
                        : null,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  bool _listsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _taskIdsEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _AlignedLineColumn extends StatelessWidget {
  const _AlignedLineColumn({
    required this.text,
    required this.style,
    required this.contentWidth,
    required this.width,
    required this.childBuilder,
    this.align = Alignment.topCenter,
    this.padding = EdgeInsets.zero,
    this.onSecondaryTap,
    this.dividerAfterLineIndex,
  });

  final String text;
  final TextStyle style;
  final double contentWidth;
  final double width;
  final Widget Function(BuildContext context, int index) childBuilder;
  final Alignment align;
  final EdgeInsets padding;
  final LineTapCallback? onSecondaryTap;
  final int? dividerAfterLineIndex;

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    if (lines.isEmpty) {
      lines.add('');
    }

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            _LineHeightSlot(
              lineText: lines[i],
              style: style,
              maxWidth: contentWidth,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onSecondaryTapDown: onSecondaryTap == null
                    ? null
                    : (details) => onSecondaryTap!(details, i),
                child: Padding(
                  padding: padding,
                  child: Align(
                    alignment: align,
                    child: childBuilder(context, i),
                  ),
                ),
              ),
            ),
            if (dividerAfterLineIndex != null && i == dividerAfterLineIndex)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: Theme.of(context).dividerColor.withValues(alpha: 0.35),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _LineHeightSlot extends StatelessWidget {
  const _LineHeightSlot({
    required this.lineText,
    required this.style,
    required this.maxWidth,
    required this.child,
  });

  final String lineText;
  final TextStyle style;
  final double maxWidth;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(
        text: lineText.isEmpty ? ' ' : lineText,
        style: style,
      ),
      textDirection: Directionality.of(context),
      maxLines: null,
    )..layout(maxWidth: maxWidth);

    return SizedBox(
      height: painter.height,
      child: child,
    );
  }
}

int lineIndexAtLocalY({
  required String text,
  required TextStyle style,
  required double maxWidth,
  required double localY,
  required TextDirection textDirection,
}) {
  final lines = text.split('\n');
  if (lines.isEmpty) return 0;

  var y = 0.0;
  for (var i = 0; i < lines.length; i++) {
    final painter = TextPainter(
      text: TextSpan(text: lines[i].isEmpty ? ' ' : lines[i], style: style),
      textDirection: textDirection,
      maxLines: null,
    )..layout(maxWidth: maxWidth);
    final nextY = y + painter.height;
    if (localY < nextY) return i;
    y = nextY;
  }
  return lines.length - 1;
}
