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
/// When [registerAsUnit] is true (e.g. image), the whole object is one atomic
/// segment. Info, task lists, and graphs register their own parts instead and
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
  /// Double-click armed on pointer-down; applied on pointer-up so the Move Mode
  /// tree is never swapped under an in-flight hit-test.
  var _pendingMoveMode = false;
  var _dragging = false;
  DateTime? _lastPointerDown;
  Size? _moveModeSize;

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
    // Rebuilds mid-gesture while swapping into Move Mode leave RenderBoxes
    // without size in the hit-test path.
    if (!mounted || _moveMode || _pendingMoveMode) return;
    setState(() {});
  }

  void _onFocusChanged() {
    if (!mounted) return;
    if (_focusNode.hasFocus) {
      widget.onInteract?.call();
      // Honor edge landing from DocumentTextFlow (↑ into object → end).
      // Only full-select when the flow has not already placed a caret here.
      final flowSel = _flow?.selection;
      final flowAlreadyHere = flowSel != null &&
          flowSel.isWithinOneSegment &&
          flowSel.focus.segmentId == _segmentId;
      if (!flowAlreadyHere) {
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
        _flow?.collapseTo(DocumentTextPosition(_segmentId, 0));
        _flow?.extendTo(
          DocumentTextPosition(_segmentId, _controller.text.length),
        );
      } else {
        final offset = flowSel.focus.offset.clamp(0, _controller.text.length);
        _controller.selection = TextSelection.collapsed(offset: offset);
      }
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
    if (!_moveMode && !_pendingMoveMode) setState(() {});
  }

  Size? _measureHostSize() {
    final box = context.findRenderObject();
    if (box is RenderBox && box.hasSize) return box.size;
    return null;
  }

  void _setMoveMode(bool value) {
    if (_moveMode == value) return;
    if (value) {
      _moveModeSize = _measureHostSize() ?? _moveModeSize;
      FocusManager.instance.primaryFocus?.unfocus();
      // Pointer-up already ended the double-click gesture; wait one frame so
      // the framed shell is laid out before the next mouse hit-test.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _moveMode) return;
        setState(() => _moveMode = true);
        widget.onMoveModeChanged?.call(true);
      });
      return;
    }
    _pendingMoveMode = false;
    _moveModeSize = null;
    setState(() => _moveMode = false);
    widget.onMoveModeChanged?.call(false);
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
      // Arm only — swap the tree on pointer-up (see [_onPointerUp]).
      _pendingMoveMode = true;
      _moveModeSize = _measureHostSize();
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (!_pendingMoveMode || _moveMode) return;
    _pendingMoveMode = false;
    _setMoveMode(true);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pendingMoveMode = false;
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

  /// Move Mode shell: min size for hit-testing, natural height for content.
  ///
  /// Never impose a *max* height from the pre-measure — the glass padding sits
  /// outside the child, so a tight [SizedBox] was squeezing InfoEmbed/etc.
  /// into ~20px and overflowing.
  Widget _moveModeShell({required Widget child, double opacity = 1}) {
    final size = _moveModeSize;
    Widget framed = Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: size?.width ?? 48,
          minHeight: size?.height ?? 48,
        ),
        child: DragModeFrame.chip(
          child: MouseRegion(
            cursor: SystemMouseCursors.grab,
            child: child,
          ),
        ),
      ),
    );
    if (opacity < 1) {
      framed = Opacity(opacity: opacity, child: framed);
    }
    return framed;
  }

  @override
  Widget build(BuildContext context) {
    final flow = widget.registerAsUnit ? _flow : null;
    final crossPartMark = flow != null &&
        flow.spansSegments &&
        flow.selectionWithin(_segmentId) != null;

    // Object editors must stay in ONE slot for the whole Move Mode session.
    // Putting them in Draggable.child / childWhenDragging disposes State on
    // drag start (Flutter swaps those slots) and wipes info content.
    final editingChild = EmbedMoveModeScope(
      active: false,
      child: widget.child,
    );

    Widget body;
    if (_moveMode) {
      final ghostWidth = (_moveModeSize?.width ?? 168).clamp(96.0, 280.0);
      final dragChrome = Draggable<String>(
        data: widget.blockId,
        maxSimultaneousDrags: 1,
        onDragStarted: () {
          if (!mounted) return;
          setState(() => _dragging = true);
        },
        onDragEnd: (_) {
          if (!mounted) return;
          _dragging = false;
          _setMoveMode(false);
        },
        onDraggableCanceled: (_, _) {
          if (!mounted) return;
          _dragging = false;
          _setMoveMode(false);
        },
        feedback: Material(
          color: Colors.transparent,
          child: DragModeFrame.chip(
            child: SizedBox(
              width: ghostWidth,
              height: 40,
              child: Icon(
                Icons.drag_handle_rounded,
                color: AppColors.text.withValues(alpha: 0.45),
              ),
            ),
          ),
        ),
        // Hit target only — never host the live object editors here.
        childWhenDragging: const SizedBox.expand(),
        child: const SizedBox.expand(),
      );
      body = TapRegion(
        onTapOutside: (_) {
          if (_dragging) return;
          _setMoveMode(false);
        },
        child: _moveModeShell(
          opacity: _dragging ? 0.28 : 1,
          child: Stack(
            children: [
              IgnorePointer(child: editingChild),
              Positioned.fill(child: dragChrome),
            ],
          ),
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
        child: editingChild,
      );
    }

    final gestured = Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
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
