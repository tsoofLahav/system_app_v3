import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../design_system/app_typography.dart';
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
    this.onLineSecondaryTap,
    this.onCopyAll,
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
  final LineTapCallback? onLineSecondaryTap;
  final VoidCallback? onCopyAll;

  @override
  State<ConnectedLinesEditor> createState() => _ConnectedLinesEditorState();
}

class _ConnectedLinesEditorState extends State<ConnectedLinesEditor> {
  late TextEditingController _controller;
  Timer? _debounce;
  List<String> _lastEmitted = const [];
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _lastEmitted = normalizeDocumentLines(widget.lines);
    _controller = TextEditingController(text: documentFromLines(_lastEmitted));
    _controller.addListener(_onTextChanged);
  }

  @override
  void didUpdateWidget(ConnectedLinesEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_editing) return;
    final next = normalizeDocumentLines(widget.lines);
    final nextText = documentFromLines(next);
    if (nextText != _controller.text) {
      _controller.text = nextText;
      _lastEmitted = next;
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
                  childBuilder: (context, index) => widget.lineAccessoryBuilder!(
                    context,
                    index,
                  ),
                  onSecondaryTap: widget.onLineSecondaryTap,
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
  });

  final String text;
  final TextStyle style;
  final double contentWidth;
  final double width;
  final Widget Function(BuildContext context, int index) childBuilder;
  final Alignment align;
  final EdgeInsets padding;
  final LineTapCallback? onSecondaryTap;

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
          for (var i = 0; i < lines.length; i++)
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
