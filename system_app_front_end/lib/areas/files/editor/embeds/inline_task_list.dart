import 'package:flutter/material.dart';

import '../../../../core/app_state.dart';
import '../../../objects/data/object_embed.dart';
import '../../../objects/tasks/file_task_list_bridge.dart';
import '../../../objects/tasks/task_list_surface.dart';
import '../document_text_flow.dart';
import '../embed_caret_bridge.dart';
import '../embed_move_mode_scope.dart';

/// In-file task list: thin host over [TaskListSurface] + [FileTaskListBridge].
///
/// Owns document segment ids, Move Mode compact layout, and exit into the
/// surrounding file. Row ↑/↓ is an ordered line chain on the surface.
class InlineTaskListWidget extends StatefulWidget {
  const InlineTaskListWidget({
    super.key,
    required this.embed,
    required this.blockId,
    required this.state,
    required this.onRefresh,
    this.onFocus,
    this.onExitBelow,
    this.onDeleteObject,
    this.documentBaseOffset = 0,
  });

  final ObjectEmbed embed;
  final String blockId;
  final AppState state;
  final Future<void> Function() onRefresh;
  final VoidCallback? onFocus;
  /// Called with the empty task's id (null for an unsaved seed row).
  final ValueChanged<int?>? onExitBelow;

  /// Last empty task + Backspace — remove the object from the file.
  final VoidCallback? onDeleteObject;

  /// Start of this pointer slice in the marker-text buffer.
  final int documentBaseOffset;

  @override
  State<InlineTaskListWidget> createState() => _InlineTaskListWidgetState();
}

class _InlineTaskListWidgetState extends State<InlineTaskListWidget>
    with EmbedLineGatewayMixin
    implements EmbedCaretGateway {
  late FileTaskListBridge _bridge;
  final _surfaceKey = GlobalKey<TaskListSurfaceState>();
  EmbedCaretRegistry? _registry;

  @override
  String get nodeId => widget.blockId;

  @override
  int get lineCount => _surfaceKey.currentState?.lineCount ?? 0;

  @override
  void focusLine(int index, {required bool fromAbove}) {
    _surfaceKey.currentState?.focusLine(index, fromAbove: fromAbove);
  }

  @override
  void nudgeInner(AxisDirection direction) {
    _surfaceKey.currentState?.nudge(direction);
  }

  @override
  void beginTaskReorderMode() {
    _surfaceKey.currentState?.setReorderMode(true);
  }

  @override
  void initState() {
    super.initState();
    _bridge = FileTaskListBridge(
      state: widget.state,
      embed: widget.embed,
      onRefresh: widget.onRefresh,
    );
    widget.state.addListener(_onAppState);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = EmbedCaretScope.maybeOf(context)?.registry;
    if (!identical(next, _registry)) {
      _registry?.unregister(nodeId);
      _registry = next;
      _registry?.register(this);
    }
  }

  @override
  void didUpdateWidget(InlineTaskListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bridge.embed = widget.embed;
  }

  void _onAppState() {
    if (!mounted) return;
    final list = widget.state.embedsByFileId[widget.embed.fileId];
    if (list == null) return;
    ObjectEmbed? live;
    for (final embed in list) {
      if (embed.id == widget.embed.id) {
        live = embed;
        break;
      }
    }
    if (live == null || identical(live, _bridge.embed)) return;
    _bridge.embed = live;
    // Payload-only cache updates do not remount Super Editor (keyboard safety).
    _surfaceKey.currentState?.syncFromRemote();
  }

  @override
  void dispose() {
    widget.state.removeListener(_onAppState);
    _registry?.unregister(nodeId);
    _registry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final moveMode = EmbedMoveModeScope.of(context);
    return TaskListSurface(
      key: _surfaceKey,
      state: widget.state,
      bridge: _bridge,
      onFocus: widget.onFocus,
      onDeleteObject: widget.onDeleteObject,
      compactMode: moveMode,
      listTitleSegmentId: taskListTitleSegmentId(widget.blockId),
      documentBaseOffset: widget.documentBaseOffset,
      hostEmbed: widget.embed,
      climbToListTitleOnLastBackspace: true,
      // Arrows stay inside the list; Escape (EmbedEditScope) leaves to SE.
      onArrowExitAbove: () {},
      onArrowExitBelow: () {},
    );
  }
}
