import 'package:flutter/material.dart';

import '../../../../core/app_state.dart';
import '../document_text_flow.dart';
import '../embed_move_mode_scope.dart';
import '../../../objects/data/object_embed.dart';
import '../../../objects/tasks/file_task_list_bridge.dart';
import '../../../objects/tasks/task_list_surface.dart';

/// In-file task list: thin host over [TaskListSurface] + [FileTaskListBridge].
///
/// Owns document segment ids, Move Mode compact layout, and exit-below into
/// the surrounding file. Row interaction lives in objects/tasks.
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

  @override
  State<InlineTaskListWidget> createState() => _InlineTaskListWidgetState();
}

class _InlineTaskListWidgetState extends State<InlineTaskListWidget> {
  late FileTaskListBridge _bridge;

  @override
  void initState() {
    super.initState();
    _bridge = FileTaskListBridge(
      state: widget.state,
      embed: widget.embed,
      onRefresh: widget.onRefresh,
    );
  }

  @override
  void didUpdateWidget(InlineTaskListWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bridge.embed = widget.embed;
  }

  @override
  Widget build(BuildContext context) {
    final moveMode = EmbedMoveModeScope.of(context);
    return TaskListSurface(
      state: widget.state,
      bridge: _bridge,
      onFocus: widget.onFocus,
      onExitBelow: widget.onExitBelow,
      onDeleteObject: widget.onDeleteObject,
      compactMode: moveMode,
      listTitleSegmentId: taskListTitleSegmentId(widget.blockId),
      taskSegmentId: (index) => taskItemSegmentId(widget.blockId, index),
      climbToListTitleOnLastBackspace: true,
    );
  }
}
