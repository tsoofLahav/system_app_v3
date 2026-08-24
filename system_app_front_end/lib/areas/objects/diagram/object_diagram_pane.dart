import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:interactive_graph_view/interactive_graph_view.dart';

import '../../../core/app_state.dart';
import '../../../core/platform/app_form_factor.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../../ux/shell/app_bottom_bar.dart';
import '../../ux/topic/topic_appearance.dart';
import '../../ux/widgets/app_context_menu.dart';
import '../data/object_embed.dart';
import '../data/object_service.dart';
import '../links/add_connection_dialog.dart';
import 'diagram_layout.dart';

/// Workspace objects map: info nodes + related edges via [interactive_graph_view].
///
/// Positions persist on the object (`diagram_x` / `diagram_y`). Double-click
/// opens a card in place (several may be open). Each open card keeps its
/// circle-center; closed nodes move out along rays by `R_open − R_closed`.
/// Pan, zoom, and drag work the same while cards are open. Close with ×
/// (one card) or **Close all**. **Arrange by links** throws away saved spots
/// and writes the connected layout; a later drag is saved until Arrange
/// again. Isolated objects stay off the map unless Graph configuration
/// shows them.
class ObjectDiagramPane extends StatefulWidget {
  const ObjectDiagramPane({super.key, required this.state});

  final AppState state;

  @override
  State<ObjectDiagramPane> createState() => _ObjectDiagramPaneState();
}

class _ObjectDiagramPaneState extends State<ObjectDiagramPane> {
  final _positions = <int, Offset>{};
  final _graphKey = GlobalKey<GraphViewState<int, int>>();
  /// Created only after the first layout, with those IDs — mounting
  /// [GraphView] on an empty controller left chips at the origin while
  /// edges later used the real coordinates.
  GraphViewportController<int, int>? _controller;
  GraphViewportTransform? _camera;
  var _rebuildScheduled = false;
  final _nodesById = <int, ObjectGraphNode>{};
  final _edgesById = <int, ObjectGraphEdge>{};

  /// Rest layout (what we persist). [_positions] is the displayed map, which
  /// includes temporary open-card push.
  final _basePositions = <int, Offset>{};
  final _open = <_OpenDiagramCard>[];
  Set<int> _lastNodeIds = {};
  Set<int> _lastEdgeIds = {};
  DiagramColorMode? _lastColorMode;
  var _didInitialFit = false;
  var _appliedLayoutEpoch = 0;
  var _arrangeScheduled = false;

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.objectGraph == null) {
        state.loadObjectGraph();
      }
    });
  }

  @override
  void dispose() {
    _camera?.removeListener(_onCamera);
    super.dispose();
  }

  GraphViewportController<int, int> _createController(
    Set<int> nodeIds,
    Set<int> edgeIds,
  ) {
    return GraphViewportController<int, int>(
      initialNodeIds: nodeIds,
      initialEdgeIds: edgeIds,
      onNodesMoved: (ids, offset) =>
          _onNodesMoved(Set<int>.from(ids), offset),
    );
  }

  List<ObjectGraphNode> get _visibleNodes {
    final graph = state.objectGraph;
    if (graph == null) return const [];
    var nodes = graph.nodes;
    if (!state.diagramShowUnconnected) {
      final connected = DiagramLayout.connectedObjectIds(
        nodes: nodes,
        edges: graph.edges,
      );
      nodes = [for (final n in nodes) if (connected.contains(n.objectId)) n];
    }
    final filter = state.diagramFilterTagIds;
    if (filter.isEmpty) return nodes;
    return [
      for (final n in nodes)
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

  Future<void> _loadCardDescriptionLinks(int objectId) async {
    try {
      final links = await state.listObjectLinks(objectId);
      final card = _open.where((c) => c.objectId == objectId).firstOrNull;
      if (card == null || !mounted) return;
      card.descriptionLinks = [
        for (final l in links)
          if ('${l['kind'] ?? ''}' == 'description' && l['source_id'] == objectId)
            Map<String, dynamic>.from(l),
      ];
      setState(() {});
    } catch (_) {}
  }

  void _jumpToCard(int objectId) {
    if (!_open.any((c) => c.objectId == objectId)) {
      _expand(objectId);
    }
    final controller = _controller;
    if (controller != null && controller.isAttached) {
      unawaited(
        controller.showNodesOnScreen(
          {objectId},
          padding: const EdgeInsets.all(48),
        ),
      );
    }
  }

  Future<void> _showNodeContextMenu(
    ObjectGraphNode node,
    Offset global,
  ) async {
    final value = await AppContextMenu.show(
      context: context,
      globalPosition: global,
      isRtl: state.strings.isRtl,
      entries: [
        AppContextMenuItem(
          value: 'add_connection',
          label: state.strings['addConnection'],
        ),
        AppContextMenuItem(
          value: 'go_to_source',
          label: state.strings['goToSource'],
        ),
      ],
    );
    if (!mounted || value == null) return;
    if (value == 'go_to_source') {
      await state.openObjectInFile(
        objectId: node.objectId,
        fileId: node.fileId,
      );
      return;
    }
    if (value != 'add_connection') return;
    final source = ObjectEmbed(
      id: node.objectId,
      fileId: node.fileId,
      type: node.type,
    );
    final pick = await showAddConnectionDialog(
      context: context,
      state: state,
      source: source,
    );
    if (pick == null || !mounted) return;
    await state.addRelatedObjectLink(source, targetObjectId: pick.objectId);
  }

  bool _isSecondaryPointer(PointerDownEvent event) =>
      (event.buttons & kSecondaryMouseButton) != 0;

  void _onNodesMoved(Set<int> nodeIds, Offset offset) {
    final moved = <int, Offset>{};
    for (final id in nodeIds) {
      final current = _positions[id];
      if (current == null) continue;
      final next = current + offset;
      _positions[id] = next;
      _basePositions[id] = (_basePositions[id] ?? current) + offset;
      for (final card in _open) {
        if (card.objectId == id) card.origin += offset;
      }
      moved[id] = _basePositions[id]!;
      final controller = _controller;
      if (controller != null && controller.isAttached) {
        controller.rebuildNode(id);
      }
    }
    if (moved.isNotEmpty) {
      unawaited(state.saveDiagramPositions(moved));
    }
  }

  void _ensurePositions() {
    final graph = state.objectGraph;
    if (graph == null) return;
    final rest = _open.isEmpty ? _positions : _basePositions;
    final newly = DiagramLayout.placeUnplaced(
      nodes: graph.nodes,
      edges: graph.edges,
      positions: rest,
    );
    final allGraphIds = {for (final n in graph.nodes) n.objectId};
    _positions.removeWhere((id, _) => !allGraphIds.contains(id));
    _basePositions.removeWhere((id, _) => !allGraphIds.contains(id));
    if (_open.isEmpty) {
      _basePositions
        ..clear()
        ..addAll(_positions);
    } else if (newly.isNotEmpty) {
      _relayoutForOpens();
    }
    if (newly.isNotEmpty) {
      unawaited(
        state.saveDiagramPositions({
          for (final id in newly)
            if (_basePositions[id] != null) id: _basePositions[id]!,
        }),
      );
      if (newly.length > 1 && _open.isEmpty) {
        _didInitialFit = false;
      }
      _scheduleRebuildGraph();
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
      final controller = _controller;
      if (controller == null || !controller.isAttached) {
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
      controller.setNodes(nodeIds);
      controller.setEdges(edgeIds);
      _applyGraphWidgets(controller);
      // Only the first non-empty load — later fits fight pan/drag and feel stuck.
      if (fitView && !_didInitialFit && nodeIds.isNotEmpty) {
        _didInitialFit = true;
        unawaited(
          controller.showNodesOnScreen(
            nodeIds,
            padding: const EdgeInsets.all(48),
          ),
        );
      }
    });
  }

  void _applyGraphWidgets(GraphViewportController<int, int> controller) {
    for (final id in controller.allNodeIds) {
      controller.rebuildNode(id);
    }
    for (final id in controller.allEdgeIds) {
      controller.rebuildEdge(id);
    }
  }

  void _scheduleRebuildGraph() {
    if (_rebuildScheduled) return;
    _rebuildScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _rebuildScheduled = false;
      if (!mounted) return;
      final controller = _controller;
      if (controller == null || !controller.isAttached) return;
      _applyGraphWidgets(controller);
    });
  }

  void _syncController(List<ObjectGraphNode> nodes, List<ObjectGraphEdge> edges) {
    _ensurePositions();
    _refreshLookups(nodes, edges);
    final nodeIds = {for (final n in nodes) n.objectId};
    final edgeIds = {for (final e in edges) e.id};
    final colorChanged = _lastColorMode != state.diagramColorMode;
    _lastColorMode = state.diagramColorMode;

    if (_controller == null) {
      if (nodeIds.isEmpty) return;
      _controller = _createController(nodeIds, edgeIds);
      _lastNodeIds = nodeIds;
      _lastEdgeIds = edgeIds;
      _scheduleControllerSync(nodeIds, edgeIds, fitView: true);
      return;
    }

    final changed =
        nodeIds.length != _lastNodeIds.length ||
        edgeIds.length != _lastEdgeIds.length ||
        !nodeIds.containsAll(_lastNodeIds) ||
        !_lastNodeIds.containsAll(nodeIds) ||
        !edgeIds.containsAll(_lastEdgeIds) ||
        !_lastEdgeIds.containsAll(edgeIds);

    if (changed) {
      final fitView = !_didInitialFit && nodeIds.isNotEmpty;
      _lastNodeIds = nodeIds;
      _lastEdgeIds = edgeIds;
      _scheduleControllerSync(nodeIds, edgeIds, fitView: fitView);
    } else if (!_didInitialFit && nodeIds.isNotEmpty) {
      _scheduleControllerSync(nodeIds, edgeIds, fitView: true);
    } else if (colorChanged) {
      _scheduleRebuildGraph();
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

  TextDirection get _textDirection => state.strings.textDirection;

  GraphViewportTransform? get _transform =>
      _graphKey.currentState?.viewportTransform;

  void _syncCameraListener() {
    final next = _graphKey.currentState?.viewportTransform;
    if (identical(next, _camera)) return;
    _camera?.removeListener(_onCamera);
    _camera = next;
    _camera?.addListener(_onCamera);
  }

  void _onCamera() {
    if (!mounted || _open.isEmpty) return;
    setState(() {});
  }

  void _rebuildGraph() => _scheduleRebuildGraph();

  void _relayoutForOpens() {
    if (_open.isEmpty) {
      _positions
        ..clear()
        ..addAll(_basePositions);
    } else {
      DiagramLayout.applyOpenPushes(
        base: _basePositions,
        positions: _positions,
        opens: [
          for (final card in _open)
            (
              originId: card.objectId,
              origin: card.origin,
              deltaRadius: card.deltaRadius(_textDirection),
            ),
        ],
      );
    }
    _rebuildGraph();
  }

  void _expand(int objectId) {
    if (_open.any((c) => c.objectId == objectId)) return;
    final origin = _positions[objectId];
    if (origin == null) return;
    if (_open.isEmpty) {
      _basePositions
        ..clear()
        ..addAll(_positions);
    }
    final node = _nodesById[objectId];
    _open.add(
      _OpenDiagramCard(
        objectId: objectId,
        origin: origin,
        title: node?.title ?? '',
        body: node?.body ?? '',
      ),
    );
    _relayoutForOpens();
    setState(() {});
    unawaited(_loadCardDescriptionLinks(objectId));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _open.isEmpty) return;
      _syncCameraListener();
      setState(() {});
    });
  }

  void _closeOne(int objectId) {
    final before = _open.length;
    _open.removeWhere((c) => c.objectId == objectId);
    if (_open.length == before) return;
    _finishClose();
  }

  void _closeAll() {
    if (_open.isEmpty) return;
    _open.clear();
    _finishClose();
  }

  void _finishClose() {
    _relayoutForOpens();
    if (_open.isEmpty && DiagramLayout.isCollapsed(_positions.values)) {
      _positions.clear();
      _basePositions.clear();
      _ensurePositions();
    }
    setState(() {});
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _rebuildGraph();
    });
  }

  void _consumeArrangeRequest() {
    if (state.diagramLayoutEpoch <= _appliedLayoutEpoch) return;
    if (_arrangeScheduled) return;
    _arrangeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _arrangeScheduled = false;
      if (!mounted) return;
      if (state.diagramLayoutEpoch <= _appliedLayoutEpoch) return;
      _appliedLayoutEpoch = state.diagramLayoutEpoch;
      _arrangeByConnections();
    });
  }

  /// Throw away saved spots and lay every node out from the links.
  void _arrangeByConnections() {
    final graph = state.objectGraph;
    if (graph == null || graph.nodes.isEmpty) return;
    _appliedLayoutEpoch = math.max(
      _appliedLayoutEpoch,
      state.diagramLayoutEpoch,
    );
    _open.clear();
    _positions.clear();
    _basePositions.clear();
    DiagramLayout.layoutAll(
      nodes: graph.nodes,
      edges: graph.edges,
      positions: _positions,
    );
    _basePositions.addAll(_positions);
    unawaited(state.saveDiagramPositions(Map<int, Offset>.from(_positions)));
    _didInitialFit = false;
    setState(() {});
    _scheduleRebuildGraph();
    final nodeIds = {for (final n in _visibleNodes) n.objectId};
    if (nodeIds.isEmpty) return;
    _scheduleControllerSync(
      nodeIds,
      {for (final e in _visibleEdges) e.id},
      fitView: true,
    );
  }

  void _onOpenCardChanged(int objectId, String title, String body) {
    final card = _open.where((c) => c.objectId == objectId).firstOrNull;
    if (card == null) return;
    card.title = title;
    card.body = body;
    _relayoutForOpens();
    setState(() {});
  }

  List<Widget> _buildOpenOverlays() {
    final transform = _transform;
    if (transform == null || !transform.hasViewportSize) {
      return const [];
    }
    return [
      for (final card in _open)
        _buildOpenOverlay(card, transform.toScreenSpacePosition(card.origin)),
    ];
  }

  Widget _buildOpenOverlay(_OpenDiagramCard card, Offset center) {
    final node = _nodesById[card.objectId];
    if (node == null) return const SizedBox.shrink();
    final size = card.openSize(_textDirection);
    final accent = _accentFor(node);
    return Positioned(
      left: center.dx - size.width / 2,
      top: center.dy - size.height / 2,
      width: size.width,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (event) {
          if (_isSecondaryPointer(event)) {
            unawaited(_showNodeContextMenu(node, event.position));
          }
        },
        child: GestureDetector(
          onLongPressStart: isPhoneLayout
              ? (d) => unawaited(
                    _showNodeContextMenu(node, d.globalPosition),
                  )
              : null,
          child: Material(
            color: Colors.transparent,
            child: Stack(
              children: [
                Positioned.fill(
                  child: _NodeChrome(accent: accent, expanded: true),
                ),
                _ExpandedInfoCard(
                  key: ValueKey('diagram-expand-${node.objectId}'),
                  node: node,
                  width: size.width,
                  accent: accent,
                  descriptionLinks: card.descriptionLinks,
                  onJumpTo: _jumpToCard,
                  onChanged: (title, body) =>
                      _onOpenCardChanged(card.objectId, title, body),
                  onSave: node.informationId == null
                      ? null
                      : (title, body) => state.updateInfoFromDiagram(
                            informationId: node.informationId!,
                            objectId: node.objectId,
                            title: title,
                            body: body,
                          ),
                ),
                Positioned(
                  top: 2,
                  right: 2,
                  child: _DiagramCloseHit(
                    onClose: () => _closeOne(card.objectId),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final nodes = _visibleNodes;
        final edges = _visibleEdges;
        final visibleIds = {for (final n in nodes) n.objectId};
        if (_open.any((c) => !visibleIds.contains(c.objectId))) {
          _open.removeWhere((c) => !visibleIds.contains(c.objectId));
          _relayoutForOpens();
        }
        _consumeArrangeRequest();
        _syncController(nodes, edges);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _syncCameraListener();
        });

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
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (_controller != null)
                    GraphView<int, int>(
                  key: _graphKey,
                  viewportController: _controller!,
                  // false = parent rebuilds (filter chrome, etc.) do not tear
                  // down every node mid-drag / mid-pan.
                  rebuildAllChildrenOnWidgetUpdate: false,
                  interactionConfig: _interaction,
                  style: const GraphStyle(backgroundColor: _graphBackground),
                  nodeBuilder: (context, nodeId) {
                    final node = _nodesById[nodeId];
                    final position = _positions[nodeId];
                    if (node == null || position == null) {
                      // Keep a real slot so edges can anchor. Never collapse
                      // missing coords onto Offset.zero — that stacked every
                      // chip on the first object while edges kept real ends.
                      return NodeWidget.basic(
                        position: position ?? Offset(
                          (nodeId % 8) * DiagramLayout.spacingX,
                          (nodeId % 5) * DiagramLayout.spacingY,
                        ),
                        text: '…',
                        isDragEnabled: false,
                      );
                    }
                    final expanded = _open.any((c) => c.objectId == nodeId);
                    final accent = _accentFor(node);
                    return NodeWidget.custom(
                      key: ValueKey('info-node-$nodeId'),
                      position: position,
                      isDragEnabled: true,
                      onDoubleTap: expanded ? null : () => _expand(nodeId),
                      style: const NodeStyle(
                        borderRadius: Radius.circular(8),
                        clipBehavior: Clip.antiAlias,
                        contentConstraints: BoxConstraints(
                          maxWidth: DiagramLayout.closedMaxWidth,
                          minWidth: 40,
                        ),
                      ),
                      background: _NodeChrome(
                        accent: accent,
                        expanded: false,
                      ),
                      content: Listener(
                        onPointerDown: (event) {
                          if (_isSecondaryPointer(event)) {
                            unawaited(
                              _showNodeContextMenu(node, event.position),
                            );
                          }
                        },
                        child: GestureDetector(
                          onLongPressStart: isPhoneLayout
                              ? (d) => unawaited(
                                    _showNodeContextMenu(
                                      node,
                                      d.globalPosition,
                                    ),
                                  )
                              : null,
                          child: _InfoNodeCard(title: node.title),
                        ),
                      ),
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
                    ..._buildOpenOverlays(),
                    if (state.objectGraph != null &&
                        state.objectGraph!.nodes.isNotEmpty)
                      PositionedDirectional(
                        top: 4,
                        start: 4,
                        child: _ArrangeHit(
                          onArrange: _arrangeByConnections,
                          label: state.strings['diagramArrange'],
                          hint: state.strings['diagramArrangeHint'],
                        ),
                      ),
                    if (_open.isNotEmpty)
                      PositionedDirectional(
                        top: 4,
                        end: 4,
                        child: _CloseAllHit(onCloseAll: _closeAll, label: state.strings['diagramCloseAll']),
                      ),
                  ],
                ),
              ),
            ),
            if (nodes.isEmpty)
              Center(
                child: Text(
                  state.objectGraph != null &&
                          state.objectGraph!.nodes.isNotEmpty &&
                          !state.diagramShowUnconnected
                      ? state.strings['diagramEmptyUnconnected']
                      : state.strings['diagramEmpty'],
                  textAlign: TextAlign.center,
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

class _OpenDiagramCard {
  _OpenDiagramCard({
    required this.objectId,
    required this.origin,
    required this.title,
    required this.body,
  });

  final int objectId;
  Offset origin;
  String title;
  String body;
  List<Map<String, dynamic>> descriptionLinks = const [];

  double deltaRadius(TextDirection textDirection) {
    final closed = DiagramLayout.measureClosedChip(
      title,
      textDirection: textDirection,
    );
    final open = DiagramLayout.measureOpenCard(
      title,
      body,
      textDirection: textDirection,
    );
    return math.max(
      0.0,
      DiagramLayout.circumradius(open) - DiagramLayout.circumradius(closed),
    );
  }

  Size openSize(TextDirection textDirection) {
    return DiagramLayout.measureOpenCard(
      title,
      body,
      textDirection: textDirection,
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

/// Overlay close — [Listener] beats the graph gesture arena that ate IconButton.
class _DiagramCloseHit extends StatelessWidget {
  const _DiagramCloseHit({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onClose(),
      child: Tooltip(
        message: MaterialLocalizations.of(context).closeButtonTooltip,
        child: const SizedBox(
          width: 28,
          height: 28,
          child: Center(child: AppIcon(AppIcons.close, size: 16)),
        ),
      ),
    );
  }
}

class _CloseAllHit extends StatelessWidget {
  const _CloseAllHit({required this.onCloseAll, required this.label});

  final VoidCallback onCloseAll;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onCloseAll(),
      child: GlassBarSegment(
        height: 32,
        tightShadow: true,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIcon(AppIcons.close, size: 14),
            const SizedBox(width: 6),
            Text(label, style: AppTypography.metaStyle.copyWith(fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ArrangeHit extends StatelessWidget {
  const _ArrangeHit({
    required this.onArrange,
    required this.label,
    required this.hint,
  });

  final VoidCallback onArrange;
  final String label;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => onArrange(),
      child: Tooltip(
        message: hint,
        child: GlassBarSegment(
          height: 32,
          tightShadow: true,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(AppIcons.arrange, size: 14),
              const SizedBox(width: 6),
              Text(label, style: AppTypography.metaStyle.copyWith(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpandedInfoCard extends StatefulWidget {
  const _ExpandedInfoCard({
    super.key,
    required this.node,
    required this.width,
    required this.onChanged,
    required this.onSave,
    this.accent,
    this.descriptionLinks = const [],
    this.onJumpTo,
  });

  final ObjectGraphNode node;
  final double width;
  final void Function(String title, String body) onChanged;
  final Future<void> Function(String title, String body)? onSave;
  final Color? accent;
  final List<Map<String, dynamic>> descriptionLinks;
  final ValueChanged<int>? onJumpTo;

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
    if (oldWidget.descriptionLinks != widget.descriptionLinks) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _onChanged() {
    widget.onChanged(_title.text, _body.text);
    final save = widget.onSave;
    if (save == null) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(save(_title.text, _body.text));
    });
  }

  @override
  Widget build(BuildContext context) {
    final titleStyle = AppTypography.noteTitleStyle.copyWith(fontSize: 13);
    final bodyStyle = AppTypography.noteBodyStyle.copyWith(fontSize: 12);
    final titleSpans = _descriptionSpansForField(
      links: widget.descriptionLinks,
      title: _title.text,
      body: _body.text,
      titleField: true,
    );
    final bodySpans = _descriptionSpansForField(
      links: widget.descriptionLinks,
      title: _title.text,
      body: _body.text,
      titleField: false,
    );
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: widget.width,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 22),
                child: _linkedMapField(
                  controller: _title,
                  style: titleStyle,
                  spans: titleSpans,
                  maxLines: 1,
                ),
              ),
              _linkedMapField(
                controller: _body,
                style: bodyStyle,
                spans: bodySpans,
                maxLines: null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _linkedMapField({
    required TextEditingController controller,
    required TextStyle style,
    required List<_MapDescriptionSpan> spans,
    required int? maxLines,
  }) {
    final field = TextField(
      controller: controller,
      autofocus: false,
      style: style,
      maxLines: maxLines,
      minLines: 1,
      decoration: const InputDecoration(
        isDense: true,
        border: InputBorder.none,
        contentPadding: EdgeInsets.zero,
      ),
      onChanged: (_) => _onChanged(),
    );
    if (spans.isEmpty || widget.onJumpTo == null) return field;
    return Stack(
      children: [
        field,
        Positioned.fill(
          child: _LinkedSpanLayer(
            text: controller.text,
            style: style,
            spans: spans,
            onJump: widget.onJumpTo!,
          ),
        ),
      ],
    );
  }
}

class _MapDescriptionSpan {
  const _MapDescriptionSpan({
    required this.start,
    required this.end,
    required this.targetId,
  });

  final int start;
  final int end;
  final int targetId;
}

int? _readInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

List<_MapDescriptionSpan> _descriptionSpansForField({
  required List<Map<String, dynamic>> links,
  required String title,
  required String body,
  required bool titleField,
}) {
  final combined = body.isEmpty ? title : '$title\n$body';
  final nl = combined.indexOf('\n');
  final out = <_MapDescriptionSpan>[];
  for (final link in links) {
    final anchor = link['anchor'];
    if (anchor is! Map) continue;
    final start = _readInt(anchor['start']) ?? 0;
    final end = _readInt(anchor['end']) ?? 0;
    final targetId = _readInt(link['target_id']) ??
        _readInt(link['peer'] is Map ? (link['peer'] as Map)['id'] : null);
    if (targetId == null || end <= start) continue;
    if (nl < 0) {
      if (titleField) {
        out.add(_MapDescriptionSpan(start: start, end: end, targetId: targetId));
      }
      continue;
    }
    if (titleField) {
      if (start >= nl) continue;
      final from = start.clamp(0, nl);
      final to = end.clamp(0, nl);
      if (from < to) {
        out.add(_MapDescriptionSpan(start: from, end: to, targetId: targetId));
      }
    } else {
      final from = (start - (nl + 1)).clamp(0, body.length);
      final to = (end - (nl + 1)).clamp(0, body.length);
      if (from < to) {
        out.add(_MapDescriptionSpan(start: from, end: to, targetId: targetId));
      }
    }
  }
  return out;
}

class _LinkedSpanLayer extends StatelessWidget {
  const _LinkedSpanLayer({
    required this.text,
    required this.style,
    required this.spans,
    required this.onJump,
  });

  final String text;
  final TextStyle style;
  final List<_MapDescriptionSpan> spans;
  final ValueChanged<int> onJump;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: Directionality.of(context),
          maxLines: null,
        )..layout(maxWidth: constraints.maxWidth);
        final boxes = <(Rect, int)>[];
        for (final span in spans) {
          final start = span.start.clamp(0, text.length);
          final end = span.end.clamp(0, text.length);
          if (end <= start) continue;
          for (final box in painter.getBoxesForSelection(
            TextSelection(baseOffset: start, extentOffset: end),
          )) {
            boxes.add((box.toRect(), span.targetId));
          }
        }
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) {
            if ((event.buttons & kPrimaryButton) == 0) return;
            for (final (rect, targetId) in boxes) {
              if (rect.inflate(2).contains(event.localPosition)) {
                onJump(targetId);
                return;
              }
            }
          },
          child: IgnorePointer(
            child: CustomPaint(
              painter: _LinkedSpanPainter(
                boxes: [for (final b in boxes) b.$1],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _LinkedSpanPainter extends CustomPainter {
  const _LinkedSpanPainter({required this.boxes});

  final List<Rect> boxes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.text.withValues(alpha: 0.55)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final box in boxes) {
      final y = box.bottom - 1;
      canvas.drawLine(Offset(box.left, y), Offset(box.right, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LinkedSpanPainter oldDelegate) =>
      oldDelegate.boxes != boxes;
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
