import 'dart:async';

import 'package:flutter/material.dart';
import 'package:interactive_graph_view/interactive_graph_view.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ux/shell/app_bottom_bar.dart';
import '../../ux/topic/topic_appearance.dart';
import '../data/object_service.dart';
import 'diagram_layout.dart';

/// Workspace objects map: info nodes + related edges via [interactive_graph_view].
///
/// Positions persist on the object (`diagram_x` / `diagram_y`). Double-click
/// expands in place and temporarily pushes neighbors so the card does not cover
/// them; close restores the saved layout.
class ObjectDiagramPane extends StatefulWidget {
  const ObjectDiagramPane({super.key, required this.state});

  final AppState state;

  @override
  State<ObjectDiagramPane> createState() => _ObjectDiagramPaneState();
}

class _ObjectDiagramPaneState extends State<ObjectDiagramPane> {
  final _positions = <int, Offset>{};
  late final GraphViewportController<int, int> _controller;
  final _nodesById = <int, ObjectGraphNode>{};
  final _edgesById = <int, ObjectGraphEdge>{};

  int? _expandedObjectId;
  Map<int, Offset>? _positionsBeforeExpand;
  Set<int> _lastNodeIds = {};
  Set<int> _lastEdgeIds = {};
  DiagramColorMode? _lastColorMode;
  var _didInitialFit = false;

  static const _filterFloor = AppBottomBarMetrics.scrollInset + 8;

  /// Match the app’s neutral canvas (solid stand-in for the canvas gradient).
  static const _graphBackground = AppColors.canvasNeutralTop;

  /// Visual weight for edges — hit-testing stays thin so pan/drag still work.
  static final _edgeStyle = EdgeStyle(
    lineColor: AppColors.text.withValues(alpha: 0.62),
    lineStyle: const SolidLineStyle(thickness: 1.5),
    arrowStyle: const ArrowStyle(length: 0, width: 0),
    textBackgroundColor: Colors.transparent,
    shadow: [
      LineShadow(
        color: AppColors.text.withValues(alpha: 0.12),
        blurRadius: 2,
        spreadRadius: 0.4,
      ),
    ],
  );

  static const _interaction = InteractionConfig(
    // Default 40 steals almost every pointer on a dense map.
    edgeHitboxThickness: 8,
  );

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    // Stable controller for the pane lifetime — never recreate (remounting
    // GraphView mid-load was dropping all but one node).
    _controller = GraphViewportController<int, int>(
      initialNodeIds: const [],
      initialEdgeIds: const [],
      onNodesMoved: (ids, offset) =>
          _onNodesMoved(Set<int>.from(ids), offset),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.objectGraph == null) {
        state.loadObjectGraph();
      }
    });
  }

  List<ObjectGraphNode> get _visibleNodes {
    final graph = state.objectGraph;
    if (graph == null) return const [];
    final filter = state.diagramFilterTagIds;
    if (filter.isEmpty) return graph.nodes;
    return [
      for (final n in graph.nodes)
        if (n.tagIds.any(filter.contains)) n,
    ];
  }

  List<ObjectGraphEdge> get _visibleEdges {
    final graph = state.objectGraph;
    if (graph == null) return const [];
    final ids = {for (final n in _visibleNodes) n.objectId};
    return [
      for (final e in graph.edges)
        if (ids.contains(e.sourceId) && ids.contains(e.targetId)) e,
    ];
  }

  void _onNodesMoved(Set<int> nodeIds, Offset offset) {
    if (_expandedObjectId != null) return;
    final moved = <int, Offset>{};
    for (final id in nodeIds) {
      final current = _positions[id];
      if (current == null) continue;
      final next = current + offset;
      _positions[id] = next;
      moved[id] = next;
      if (_controller.isAttached) {
        _controller.rebuildNode(id);
      }
    }
    if (moved.isNotEmpty) {
      unawaited(state.saveDiagramPositions(moved));
    }
  }

  void _ensurePositions() {
    final graph = state.objectGraph;
    if (graph == null) return;
    final newly = DiagramLayout.placeUnplaced(
      nodes: graph.nodes,
      edges: graph.edges,
      positions: _positions,
    );
    final allGraphIds = {for (final n in graph.nodes) n.objectId};
    _positions.removeWhere((id, _) => !allGraphIds.contains(id));
    if (newly.isNotEmpty && _expandedObjectId == null) {
      unawaited(
        state.saveDiagramPositions({
          for (final id in newly)
            if (_positions[id] != null) id: _positions[id]!,
        }),
      );
    }
  }

  void _refreshLookups(
    List<ObjectGraphNode> nodes,
    List<ObjectGraphEdge> edges,
  ) {
    _nodesById
      ..clear()
      ..addEntries(nodes.map((n) => MapEntry(n.objectId, n)));
    _edgesById
      ..clear()
      ..addEntries(edges.map((e) => MapEntry(e.id, e)));
  }

  void _scheduleControllerSync(
    Set<int> nodeIds,
    Set<int> edgeIds, {
    required bool fitView,
    int attempt = 0,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_controller.isAttached) {
        if (attempt < 12) {
          _scheduleControllerSync(
            nodeIds,
            edgeIds,
            fitView: fitView,
            attempt: attempt + 1,
          );
        }
        return;
      }
      _controller.setNodes(nodeIds);
      _controller.setEdges(edgeIds);
      // Only the first non-empty load — later fits fight pan/drag and feel stuck.
      if (fitView && !_didInitialFit && nodeIds.isNotEmpty) {
        _didInitialFit = true;
        unawaited(
          _controller.showNodesOnScreen(
            nodeIds,
            padding: const EdgeInsets.all(48),
          ),
        );
      }
    });
  }

  void _rebuildVisibleNodes() {
    if (!_controller.isAttached) return;
    for (final id in _lastNodeIds) {
      _controller.rebuildNode(id);
    }
  }

  void _syncController(List<ObjectGraphNode> nodes, List<ObjectGraphEdge> edges) {
    _ensurePositions();
    _refreshLookups(nodes, edges);
    final nodeIds = {for (final n in nodes) n.objectId};
    final edgeIds = {for (final e in edges) e.id};
    final changed =
        nodeIds.length != _lastNodeIds.length ||
        edgeIds.length != _lastEdgeIds.length ||
        !nodeIds.containsAll(_lastNodeIds) ||
        !_lastNodeIds.containsAll(nodeIds) ||
        !edgeIds.containsAll(_lastEdgeIds) ||
        !_lastEdgeIds.containsAll(edgeIds);
    final colorChanged = _lastColorMode != state.diagramColorMode;
    _lastColorMode = state.diagramColorMode;

    if (changed) {
      final fitView = !_didInitialFit && nodeIds.isNotEmpty;
      _lastNodeIds = nodeIds;
      _lastEdgeIds = edgeIds;
      _scheduleControllerSync(nodeIds, edgeIds, fitView: fitView);
    } else if (colorChanged) {
      // Accents live in node builders — refresh without remounting the graph.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildVisibleNodes();
      });
    }
  }

  Color? _accentFor(ObjectGraphNode node) {
    if (state.diagramColorMode == DiagramColorMode.byTag) {
      if (node.tagIds.isEmpty) return null;
      final tag = state.objectTags
          .where((t) => t.id == node.tagIds.first)
          .firstOrNull;
      if (tag == null) return null;
      return TopicAppearance.colorFromHex(
        tag.color ?? TopicAppearance.defaultColor,
      );
    }
    final hex = node.topicColor;
    if (hex == null || hex.isEmpty) return null;
    return TopicAppearance.colorFromHex(hex);
  }

  Set<int> _connectedIds(int objectId) {
    return {
      for (final edge in _visibleEdges)
        if (edge.sourceId == objectId)
          edge.targetId
        else if (edge.targetId == objectId)
          edge.sourceId,
    };
  }

  void _rebuildNodes(Iterable<int> ids) {
    if (!_controller.isAttached) return;
    for (final id in ids) {
      if (_lastNodeIds.contains(id) || _controller.allNodeIds.contains(id)) {
        _controller.rebuildNode(id);
      }
    }
  }

  void _expand(int objectId) {
    if (_expandedObjectId == objectId) {
      _closeExpand();
      return;
    }
    if (_expandedObjectId != null) {
      _restoreExpandPositions();
    }
    _positionsBeforeExpand = Map<int, Offset>.of(_positions);
    DiagramLayout.pushNeighbors(
      originId: objectId,
      positions: _positions,
      connectedIds: _connectedIds(objectId),
    );
    final touched = _positions.keys.toSet();
    setState(() => _expandedObjectId = objectId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rebuildNodes(touched);
    });
  }

  void _restoreExpandPositions() {
    final snapshot = _positionsBeforeExpand;
    if (snapshot == null) return;
    _positions
      ..clear()
      ..addAll(snapshot);
    _positionsBeforeExpand = null;
  }

  void _closeExpand() {
    final previous = _expandedObjectId;
    if (previous == null) return;
    _restoreExpandPositions();
    setState(() => _expandedObjectId = null);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _rebuildNodes([previous, ..._positions.keys]);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final nodes = _visibleNodes;
        final edges = _visibleEdges;
        if (_expandedObjectId != null &&
            !_nodesById.containsKey(_expandedObjectId) &&
            !nodes.any((n) => n.objectId == _expandedObjectId)) {
          _restoreExpandPositions();
          _expandedObjectId = null;
        }
        _syncController(nodes, edges);

        final theme = Theme.of(context);
        return Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                8,
                40,
                8,
                (isPhoneLayout ? 8.0 : _filterFloor) + 8,
              ),
              child: Theme(
                data: theme.copyWith(
                  extensions: [
                    ...theme.extensions.values,
                    const GraphStyle(backgroundColor: _graphBackground),
                  ],
                ),
                child: GraphView<int, int>(
                  viewportController: _controller,
                  // false = parent rebuilds (filter chrome, etc.) do not tear
                  // down every node mid-drag / mid-pan.
                  rebuildAllChildrenOnWidgetUpdate: false,
                  interactionConfig: _interaction,
                  style: const GraphStyle(backgroundColor: _graphBackground),
                  nodeBuilder: (context, nodeId) {
                    final node = _nodesById[nodeId];
                    final position = _positions[nodeId];
                    if (node == null || position == null) {
                      // Keep a real slot so edges can anchor; avoid empty
                      // zero-size widgets that vanish from the quad tree.
                      return NodeWidget.basic(
                        position: position ?? Offset.zero,
                        text: '…',
                        isDragEnabled: false,
                      );
                    }
                    final expanded = nodeId == _expandedObjectId;
                    final accent = _accentFor(node);
                    return NodeWidget.custom(
                      position: position,
                      // Drag during expand would persist the temporary push.
                      isDragEnabled: _expandedObjectId == null,
                      onDoubleTap: () => _expand(nodeId),
                      style: NodeStyle(
                        borderRadius:
                            Radius.circular(expanded ? 12 : 8),
                        clipBehavior: Clip.antiAlias,
                        contentConstraints: BoxConstraints(
                          maxWidth: expanded ? 280 : 96,
                          minWidth: expanded ? 200 : 40,
                        ),
                      ),
                      background: _NodeChrome(
                        accent: accent,
                        expanded: expanded,
                      ),
                      content: expanded
                          ? _ExpandedInfoCard(
                              key: ValueKey('diagram-expand-$nodeId'),
                              node: node,
                              accent: accent,
                              onClose: _closeExpand,
                              onSave: node.informationId == null
                                  ? null
                                  : (title, body) =>
                                      state.updateInfoFromDiagram(
                                        informationId: node.informationId!,
                                        objectId: node.objectId,
                                        title: title,
                                        body: body,
                                      ),
                            )
                          : _InfoNodeCard(title: node.title),
                    );
                  },
                  edgeBuilder: (context, edgeId) {
                    final edge = _edgesById[edgeId];
                    if (edge == null) {
                      return const EdgeWidget(
                        startNodeId: -1,
                        endNodeId: -1,
                        text: null,
                      );
                    }
                    return EdgeWidget(
                      startNodeId: edge.sourceId,
                      endNodeId: edge.targetId,
                      text: null,
                      style: _edgeStyle,
                    );
                  },
                ),
              ),
            ),
            if (nodes.isEmpty)
              Center(
                child: Text(
                  state.strings['diagramEmpty'],
                  style: AppTypography.noteBodyStyle.copyWith(
                    color: AppColors.textHint,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Opaque card chrome — BackdropFilter glass was unreliable for many graph nodes.
class _NodeChrome extends StatelessWidget {
  const _NodeChrome({required this.expanded, this.accent});

  final Color? accent;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.glassTint;
    final border = accent ?? AppColors.noteBorder;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(expanded ? 12 : 8),
        color: Color.alphaBlend(
          tint.withValues(alpha: accent == null ? 0.12 : 0.28),
          Colors.white.withValues(alpha: 0.94),
        ),
        border: Border.all(
          color: border.withValues(alpha: accent == null ? 0.55 : 0.75),
          width: AppColors.filePaneBorderWidth,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.noteShadow.withValues(alpha: 0.07),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _InfoNodeCard extends StatelessWidget {
  const _InfoNodeCard({required this.title});

  final String title;

  static double _fontSizeFor(String label) {
    final len = label.length;
    if (len <= 12) return 11;
    if (len <= 18) return 10;
    if (len <= 28) return 9;
    return 8;
  }

  @override
  Widget build(BuildContext context) {
    final label = title.isEmpty ? 'Info' : title;
    final fontSize = _fontSizeFor(label);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 40, maxWidth: 96),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Text(
          label,
          style: AppTypography.listItemStyle.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: fontSize,
            height: 1.15,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _ExpandedInfoCard extends StatefulWidget {
  const _ExpandedInfoCard({
    super.key,
    required this.node,
    required this.onClose,
    required this.onSave,
    this.accent,
  });

  final ObjectGraphNode node;
  final VoidCallback onClose;
  final Future<void> Function(String title, String body)? onSave;
  final Color? accent;

  @override
  State<_ExpandedInfoCard> createState() => _ExpandedInfoCardState();
}

class _ExpandedInfoCardState extends State<_ExpandedInfoCard> {
  late final TextEditingController _title;
  late final TextEditingController _body;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.node.title);
    _body = TextEditingController(text: widget.node.body);
  }

  @override
  void didUpdateWidget(covariant _ExpandedInfoCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node.objectId != widget.node.objectId) {
      _title.text = widget.node.title;
      _body.text = widget.node.body;
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _scheduleSave() {
    final save = widget.onSave;
    if (save == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(save(_title.text, _body.text));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: 280,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 6, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _title,
                      style: AppTypography.noteTitleStyle.copyWith(
                        fontSize: 13,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (_) => _scheduleSave(),
                    ),
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(context)
                        .closeButtonTooltip,
                    onPressed: widget.onClose,
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    padding: const EdgeInsets.all(4),
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    icon: const AppIcon(AppIcons.close, size: 16),
                  ),
                ],
              ),
              TextField(
                controller: _body,
                style: AppTypography.noteBodyStyle.copyWith(fontSize: 12),
                maxLines: 6,
                minLines: 3,
                decoration: const InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
                onChanged: (_) => _scheduleSave(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
