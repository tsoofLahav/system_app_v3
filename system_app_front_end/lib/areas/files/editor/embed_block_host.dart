import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ui/app_colors.dart';
import '../model/document_codec.dart';
import './document_text_flow.dart';
import './drag_mode_frame.dart';
import './embed_move_mode_scope.dart';

/// Hosts an embedded object in the document.
///
/// When [registerAsUnit] is true (info / image), the whole object is one
/// atomic segment. Task lists and graphs register their own parts instead and
/// pass false — they still get Move Mode chrome, not a permanent frame.
///
/// Double-click enters Move Mode: editing is blocked, the whole object is
/// wrapped in a glass frame and draggable. Dropping or tapping outside ends
/// the mode. No handles, no instructional chrome.
class EmbedBlockHost extends StatefulWidget {
  const EmbedBlockHost({
    super.key,
    required this.blockId,
    required this.child,
    this.onMoveModeChanged,
    this.onInteract,
    this.registerAsUnit = true,
  });

  final String blockId;
  final Widget child;
  final ValueChanged<bool>? onMoveModeChanged;

  /// Fired when the user clicks or focuses inside this object (claims the file).
  final VoidCallback? onInteract;

  /// When false, child widgets own the flow segments (tasks / graph cells).
  final bool registerAsUnit;

  @override
  State<EmbedBlockHost> createState() => _EmbedBlockHostState();
}

class _EmbedBlockHostState extends State<EmbedBlockHost> {
  final _focusNode = FocusNode(debugLabel: 'embed');
  late final TextEditingController _controller;
  DocumentTextFlow? _flow;
  String? _registeredSegmentId;
  var _moveMode = false;
  DateTime? _lastPointerDown;

  String get _segmentId => embedSegmentId(widget.blockId);

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: DocumentCodec.embedChar);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachToFlow(DocumentTextFlowScope.maybeOf(context));
  }

  @override
  void didUpdateWidget(EmbedBlockHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.blockId != widget.blockId ||
        oldWidget.registerAsUnit != widget.registerAsUnit) {
      _detachFromFlow();
      _attachToFlow(DocumentTextFlowScope.maybeOf(context));
    }
  }

  @override
  void dispose() {
    _detachFromFlow();
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _attachToFlow(DocumentTextFlow? flow) {
    if (!widget.registerAsUnit) {
      _detachFromFlow();
      return;
    }
    if (flow == _flow && _registeredSegmentId == _segmentId) return;
    _detachFromFlow();
    _flow = flow;
    _registeredSegmentId = _segmentId;
    if (flow != null) {
      flow.register(_segmentId, _controller, _focusNode);
      flow.addListener(_onFlowChanged);
    }
  }

  void _detachFromFlow() {
    final flow = _flow;
    final segmentId = _registeredSegmentId;
    if (flow != null) {
      flow.removeListener(_onFlowChanged);
      if (segmentId != null) flow.unregister(segmentId, _controller);
    }
    _flow = null;
    _registeredSegmentId = null;
  }

  void _onFlowChanged() {
    if (mounted) setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_focusNode.hasFocus) {
      widget.onInteract?.call();
      _controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _controller.text.length,
      );
      _flow?.collapseTo(DocumentTextPosition(_segmentId, 0));
      _flow?.extendTo(
        DocumentTextPosition(_segmentId, _controller.text.length),
      );
    } else {
      final flow = _flow;
      final sel = flow?.selection;
      if (flow != null &&
          sel != null &&
          sel.isWithinOneSegment &&
          sel.focus.segmentId == _segmentId) {
        flow.clearSelection();
      }
    }
    setState(() {});
  }

  void _setMoveMode(bool value) {
    if (_moveMode == value) return;
    setState(() => _moveMode = value);
    widget.onMoveModeChanged?.call(value);
    if (value) {
      FocusManager.instance.primaryFocus?.unfocus();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton) return;
    widget.onInteract?.call();
    if (_moveMode) return;
    final now = DateTime.now();
    final last = _lastPointerDown;
    _lastPointerDown = now;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 350)) {
      _lastPointerDown = null;
      _setMoveMode(true);
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final flow = _flow;
    if (flow == null) return KeyEventResult.ignored;

    final key = event.logicalKey;
    final isDelete = key == LogicalKeyboardKey.backspace ||
        key == LogicalKeyboardKey.delete;
    if (isDelete) {
      _controller.text = '';
      flow.pruneStructures({_segmentId}, spansParts: false);
      return KeyEventResult.handled;
    }

    DocumentTextPosition? target;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp) {
      target = flow.positionBefore(DocumentTextPosition(_segmentId, 0));
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown) {
      target = flow.positionAfter(
        DocumentTextPosition(_segmentId, _controller.text.length),
      );
    }
    if (target == null) return KeyEventResult.ignored;

    final extend = HardwareKeyboard.instance.isShiftPressed;
    flow.placeCaret(target, extendSelection: extend);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.registerAsUnit ? _flow : null;
    final crossPartMark = flow != null &&
        flow.spansSegments &&
        flow.selectionWithin(_segmentId) != null;

    final scopedChild = EmbedMoveModeScope(
      active: _moveMode,
      child: widget.child,
    );

    final content = IgnorePointer(
      ignoring: _moveMode,
      child: scopedChild,
    );

    Widget body;
    if (_moveMode) {
      // Same rounded-square glass as task Reorder — children compact themselves
      // via [EmbedMoveModeScope] so the frame hugs instead of a full-width bar.
      final framed = Align(
        alignment: AlignmentDirectional.centerStart,
        child: DragModeFrame.chip(
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: content,
          ),
        ),
      );
      body = TapRegion(
        onTapOutside: (_) => _setMoveMode(false),
        child: Draggable<String>(
          data: widget.blockId,
          onDragEnd: (_) => _setMoveMode(false),
          feedback: Material(
            color: Colors.transparent,
            child: DragModeFrame.chip(
              child: Opacity(
                opacity: 0.95,
                child: EmbedMoveModeScope(active: true, child: widget.child),
              ),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.28, child: framed),
          child: framed,
        ),
      );
    } else {
      body = AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: crossPartMark
              ? AppColors.primary.withValues(alpha: 0.08)
              : null,
        ),
        child: content,
      );
    }

    final gestured = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      child: body,
    );

    if (!widget.registerAsUnit) return gestured;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      child: gestured,
    );
  }
}
