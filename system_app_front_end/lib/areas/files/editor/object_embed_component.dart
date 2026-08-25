/// Super Editor [ComponentBuilder]s for System App object embeds (+ legacy tables).
library;

import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';

import '../../../core/app_state.dart';
import '../../objects/data/object_embed.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../model/marker_super_editor_bridge.dart';
import '../model/object_embed_node.dart';
import './drag_mode_frame.dart';
import './embed_caret_bridge.dart';
import './embeds/inline_task_list.dart';
import './embeds/object_embed_widgets.dart';
import './embeds/table_embed.dart';

typedef ObjectEmbedLookup = ObjectEmbed? Function(int objectId);
typedef ObjectEmbedAction = void Function(int objectId);
typedef ObjectPayloadChanged = void Function(
  int objectId,
  Map<String, dynamic> payload,
);
typedef EmbedMoveRequested = void Function(String nodeId, int targetIndex);

/// Builds [ObjectEmbedComponent]s for [ObjectEmbedNode]s.
class ObjectEmbedComponentBuilder implements ComponentBuilder {
  const ObjectEmbedComponentBuilder({
    required this.state,
    required this.lookup,
    required this.onRefresh,
    required this.onPayloadChanged,
    required this.onDelete,
    required this.onClaimFile,
    required this.onInnerFocusChanged,
    required this.moveModeNodeId,
    required this.onMoveToIndex,
  });

  final AppState state;
  final ObjectEmbedLookup lookup;
  final Future<void> Function() onRefresh;
  final ObjectPayloadChanged onPayloadChanged;
  final ObjectEmbedAction onDelete;
  final VoidCallback onClaimFile;

  /// Embed node id when an inner field is focused; `null` when it leaves.
  final ValueChanged<String?> onInnerFocusChanged;
  final String? moveModeNodeId;
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
      // Washed by ObjectEmbedComponent when selected (atomic block caret).
      selectionColor: AppColors.primary.withValues(alpha: 0.35),
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
      onInnerFocusChanged: onInnerFocusChanged,
      moveMode: moveModeNodeId == componentViewModel.nodeId,
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
          objectType == other.objectType &&
          selection == other.selection &&
          selectionColor == other.selectionColor;

  @override
  int get hashCode => Object.hash(
        super.hashCode,
        objectId,
        objectType,
        selection,
        selectionColor,
      );
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
    required this.onInnerFocusChanged,
    required this.moveMode,
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
  final ValueChanged<String?> onInnerFocusChanged;
  final bool moveMode;
  final EmbedMoveRequested onMoveToIndex;

  @override
  Widget build(BuildContext context) {
    final embed = lookup(viewModel.objectId);
    final child = embed == null
        ? _MissingEmbed(type: viewModel.objectType, id: viewModel.objectId)
        : _buildEmbed(embed);

    final nodeSel = viewModel.selection?.nodeSelection;
    final blockSel =
        nodeSel is UpstreamDownstreamNodeSelection ? nodeSel : null;
    // SE treats the object as one atomic block — show wash whenever selected
    // (collapsed = "on this object"; expanded = shift-select through it).
    final showBlockWash = blockSel != null;

    return BoxComponent(
      key: componentKey,
      child: Stack(
        children: [
          _SeEmbedMoveHost(
            nodeId: viewModel.nodeId,
            moveMode: moveMode,
            onInteract: onClaimFile,
            onInnerFocusChanged: onInnerFocusChanged,
            child: EmbedEditScope(nodeId: viewModel.nodeId, child: child),
          ),
          if (showBlockWash)
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: viewModel.selectionColor.withValues(
                      alpha: blockSel.isCollapsed ? 0.28 : 0.45,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
        ],
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
          onFocus: () => onInnerFocusChanged(blockId),
          onDeleteObject: () => onDelete(embed.id),
        );
      case 'task_list':
        return InlineTaskListWidget(
          embed: embed,
          blockId: blockId,
          state: state,
          onRefresh: onRefresh,
          onFocus: () => onInnerFocusChanged(blockId),
          onDeleteObject: () => onDelete(embed.id),
        );
      case 'image':
        return ImageEmbed(
          embed: embed,
          state: state,
          onPayloadChanged: (p) => onPayloadChanged(embed.id, p),
        );
      case 'table':
      case 'graph': // legacy unmigrated cache — same host as table + chart
        return TableEmbed(
          embed: embed,
          blockId: blockId,
          state: state,
          onPayloadChanged: (p) => onPayloadChanged(embed.id, p),
          onFocus: () => onInnerFocusChanged(blockId),
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      super == other &&
          other is LegacyTableFenceComponentViewModel &&
          selection == other.selection &&
          selectionColor == other.selectionColor;

  @override
  int get hashCode => Object.hash(super.hashCode, selection, selectionColor);
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

/// Chrome for Super Editor embeds. Inner fields own double-click (word
/// select). Move Mode is the object menu and the Move-object shortcut.
///
/// Watches descendant focus so any inner [TextField] clears the document caret
/// (avoids the double-caret: SE block caret + field caret).
class _SeEmbedMoveHost extends StatefulWidget {
  const _SeEmbedMoveHost({
    required this.nodeId,
    required this.moveMode,
    required this.onInteract,
    required this.onInnerFocusChanged,
    required this.child,
  });

  final String nodeId;
  final bool moveMode;
  final VoidCallback onInteract;
  final ValueChanged<String?> onInnerFocusChanged;
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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => widget.onInteract(),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          widget.onInnerFocusChanged(focused ? widget.nodeId : null);
        },
        child: body,
      ),
    );
  }
}
