/// Super Editor [ComponentBuilder]s for System App object embeds (+ legacy tables).
library;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/app_state.dart';
import '../../objects/data/object_embed.dart';
import '../model/marker_super_editor_bridge.dart';
import '../model/object_embed_node.dart';
import './drag_mode_frame.dart';
import './embeds/graph_embed.dart';
import './embeds/inline_task_list.dart';
import './embeds/object_embed_widgets.dart';
import './embeds/table_embed.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';

typedef ObjectEmbedLookup = ObjectEmbed? Function(int objectId);
typedef ObjectEmbedAction = void Function(int objectId);
typedef ObjectPayloadChanged = void Function(
  int objectId,
  Map<String, dynamic> payload,
);
typedef EmbedMoveRequested = void Function(String nodeId, int targetIndex);
typedef EmbedMoveModeChanged = void Function(String? nodeId);

/// Builds [ObjectEmbedComponent]s for [ObjectEmbedNode]s.
class ObjectEmbedComponentBuilder implements ComponentBuilder {
  const ObjectEmbedComponentBuilder({
    required this.state,
    required this.lookup,
    required this.onRefresh,
    required this.onPayloadChanged,
    required this.onDelete,
    required this.onClaimFile,
    required this.moveModeNodeId,
    required this.onMoveModeChanged,
    required this.onMoveToIndex,
  });

  final AppState state;
  final ObjectEmbedLookup lookup;
  final Future<void> Function() onRefresh;
  final ObjectPayloadChanged onPayloadChanged;
  final ObjectEmbedAction onDelete;
  final VoidCallback onClaimFile;
  final String? moveModeNodeId;
  final EmbedMoveModeChanged onMoveModeChanged;
  final EmbedMoveRequested onMoveToIndex;

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! ObjectEmbedNode) return null;
    return ObjectEmbedComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      objectId: node.objectId,
      objectType: node.objectType,
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! ObjectEmbedComponentViewModel) return null;
    return ObjectEmbedComponent(
      componentKey: componentContext.componentKey,
      viewModel: componentViewModel,
      state: state,
      lookup: lookup,
      onRefresh: onRefresh,
      onPayloadChanged: onPayloadChanged,
      onDelete: onDelete,
      onClaimFile: onClaimFile,
      moveMode: moveModeNodeId == componentViewModel.nodeId,
      onMoveModeChanged: (active) =>
          onMoveModeChanged(active ? componentViewModel.nodeId : null),
      onMoveToIndex: onMoveToIndex,
    );
  }
}

class ObjectEmbedComponentViewModel extends SingleColumnLayoutComponentViewModel
    with SelectionAwareViewModelMixin {
  ObjectEmbedComponentViewModel({
    required super.nodeId,
    super.createdAt,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    super.opacity = 1.0,
    required this.objectId,
    required this.objectType,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
  }) {
    this.selection = selection;
    this.selectionColor = selectionColor;
  }

  final int objectId;
  final String objectType;

  @override
  ObjectEmbedComponentViewModel copy() {
    return ObjectEmbedComponentViewModel(
      nodeId: nodeId,
      createdAt: createdAt,
      maxWidth: maxWidth,
      padding: padding,
      opacity: opacity,
      objectId: objectId,
      objectType: objectType,
      selection: selection,
      selectionColor: selectionColor,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is ObjectEmbedComponentViewModel &&
          objectId == other.objectId &&
          objectType == other.objectType;

  @override
  int get hashCode => Object.hash(super.hashCode, objectId, objectType);
}

class ObjectEmbedComponent extends StatelessWidget {
  const ObjectEmbedComponent({
    super.key,
    required this.componentKey,
    required this.viewModel,
    required this.state,
    required this.lookup,
    required this.onRefresh,
    required this.onPayloadChanged,
    required this.onDelete,
    required this.onClaimFile,
    required this.moveMode,
    required this.onMoveModeChanged,
    required this.onMoveToIndex,
  });

  /// Must land on [BoxComponent] — SE looks up [DocumentComponent] via this key.
  final GlobalKey componentKey;
  final ObjectEmbedComponentViewModel viewModel;
  final AppState state;
  final ObjectEmbedLookup lookup;
  final Future<void> Function() onRefresh;
  final ObjectPayloadChanged onPayloadChanged;
  final ObjectEmbedAction onDelete;
  final VoidCallback onClaimFile;
  final bool moveMode;
  final ValueChanged<bool> onMoveModeChanged;
  final EmbedMoveRequested onMoveToIndex;

  @override
  Widget build(BuildContext context) {
    final embed = lookup(viewModel.objectId);
    final child = embed == null
        ? _MissingEmbed(type: viewModel.objectType, id: viewModel.objectId)
        : _buildEmbed(embed);

    return BoxComponent(
      key: componentKey,
      child: _SeEmbedMoveHost(
        nodeId: viewModel.nodeId,
        moveMode: moveMode,
        onMoveModeChanged: onMoveModeChanged,
        onInteract: onClaimFile,
        child: child,
      ),
    );
  }

  Widget _buildEmbed(ObjectEmbed embed) {
    final blockId = viewModel.nodeId;
    switch (embed.type) {
      case 'info':
        return InfoEmbed(
          embed: embed,
          blockId: blockId,
          state: state,
          onRefresh: () => onRefresh(),
          onFocus: onClaimFile,
          onDeleteObject: () => onDelete(embed.id),
        );
      case 'task_list':
        return InlineTaskListWidget(
          embed: embed,
          blockId: blockId,
          state: state,
          onRefresh: onRefresh,
          onFocus: onClaimFile,
          onDeleteObject: () => onDelete(embed.id),
        );
      case 'graph':
        return GraphEmbed(
          embed: embed,
          blockId: blockId,
          strings: state.strings,
          onPayloadChanged: (p) => onPayloadChanged(embed.id, p),
          onFocus: onClaimFile,
          onDeleteObject: () => onDelete(embed.id),
        );
      case 'image':
        return ImageEmbed(
          embed: embed,
          state: state,
          onPayloadChanged: (p) => onPayloadChanged(embed.id, p),
        );
      case 'table':
        return TableEmbed(
          embed: embed,
          blockId: blockId,
          strings: state.strings,
          onPayloadChanged: (p) => onPayloadChanged(embed.id, p),
          onFocus: onClaimFile,
          onDeleteObject: () => onDelete(embed.id),
        );
      default:
        return _MissingEmbed(type: embed.type, id: embed.id);
    }
  }
}

/// Placeholder builder for unmigrated structure-fence tables.
class LegacyTableFenceComponentBuilder implements ComponentBuilder {
  const LegacyTableFenceComponentBuilder();

  @override
  SingleColumnLayoutComponentViewModel? createViewModel(
    Document document,
    DocumentNode node,
  ) {
    if (node is! LegacyTableFenceNode) return null;
    return LegacyTableFenceComponentViewModel(
      nodeId: node.id,
      createdAt: node.metadata[NodeMetadata.createdAt],
      selectionColor: const Color(0x00000000),
    );
  }

  @override
  Widget? createComponent(
    SingleColumnDocumentComponentContext componentContext,
    SingleColumnLayoutComponentViewModel componentViewModel,
  ) {
    if (componentViewModel is! LegacyTableFenceComponentViewModel) {
      return null;
    }
    return BoxComponent(
      key: componentContext.componentKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'Migrating table…',
          style: AppTypography.metaStyle,
        ),
      ),
    );
  }
}

class LegacyTableFenceComponentViewModel
    extends SingleColumnLayoutComponentViewModel
    with SelectionAwareViewModelMixin {
  LegacyTableFenceComponentViewModel({
    required super.nodeId,
    super.createdAt,
    super.maxWidth,
    super.padding = EdgeInsets.zero,
    DocumentNodeSelection? selection,
    Color selectionColor = Colors.transparent,
  }) {
    this.selection = selection;
    this.selectionColor = selectionColor;
  }

  @override
  LegacyTableFenceComponentViewModel copy() {
    return LegacyTableFenceComponentViewModel(
      nodeId: nodeId,
      createdAt: createdAt,
      maxWidth: maxWidth,
      padding: padding,
      selection: selection,
      selectionColor: selectionColor,
    );
  }
}

class _MissingEmbed extends StatelessWidget {
  const _MissingEmbed({required this.type, required this.id});

  final String type;
  final int id;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.noteBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Missing $type #$id',
        style: AppTypography.metaStyle,
      ),
    );
  }
}

/// Double-click Move Mode chrome for Super Editor embeds (no DocumentTextFlow).
class _SeEmbedMoveHost extends StatefulWidget {
  const _SeEmbedMoveHost({
    required this.nodeId,
    required this.moveMode,
    required this.onMoveModeChanged,
    required this.onInteract,
    required this.child,
  });

  final String nodeId;
  final bool moveMode;
  final ValueChanged<bool> onMoveModeChanged;
  final VoidCallback onInteract;
  final Widget child;

  @override
  State<_SeEmbedMoveHost> createState() => _SeEmbedMoveHostState();
}

class _SeEmbedMoveHostState extends State<_SeEmbedMoveHost> {
  @override
  Widget build(BuildContext context) {
    Widget body = widget.child;
    if (widget.moveMode) {
      body = DragModeFrame(child: body);
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: widget.onInteract,
      onDoubleTap: () {
        widget.onInteract();
        widget.onMoveModeChanged(!widget.moveMode);
      },
      child: body,
    );
  }
}
