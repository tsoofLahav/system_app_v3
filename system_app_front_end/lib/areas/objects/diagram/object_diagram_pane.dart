import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/app_state.dart';
import '../../../core/models/tag.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../../ux/topic/topic_appearance.dart';
import '../data/object_service.dart';

/// Workspace diagram of info objects with related edges and tag OR-filter.
class ObjectDiagramPane extends StatefulWidget {
  const ObjectDiagramPane({super.key, required this.state});

  final AppState state;

  @override
  State<ObjectDiagramPane> createState() => _ObjectDiagramPaneState();
}

class _ObjectDiagramPaneState extends State<ObjectDiagramPane>
    with SingleTickerProviderStateMixin {
  final _positions = <int, Offset>{};
  final _velocities = <int, Offset>{};
  Ticker? _ticker;
  Size _size = Size.zero;
  var _settled = false;
  Set<int> _lastFilter = {};
  int _lastNodeCount = -1;

  AppState get state => widget.state;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.objectGraph == null) {
        state.loadObjectGraph();
      }
    });
  }

  @override
  void dispose() {
    _ticker?.dispose();
    super.dispose();
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

  void _ensurePositions(List<ObjectGraphNode> nodes, Size size) {
    if (size.isEmpty) return;
    final rnd = math.Random(7);
    final center = Offset(size.width / 2, size.height / 2);
    for (final n in nodes) {
      _positions.putIfAbsent(
        n.objectId,
        () => Offset(
          center.dx + (rnd.nextDouble() - 0.5) * size.width * 0.45,
          center.dy + (rnd.nextDouble() - 0.5) * size.height * 0.45,
        ),
      );
      _velocities.putIfAbsent(n.objectId, () => Offset.zero);
    }
    final live = {for (final n in nodes) n.objectId};
    _positions.removeWhere((id, _) => !live.contains(id));
    _velocities.removeWhere((id, _) => !live.contains(id));
  }

  void _startSim() {
    _settled = false;
    if (_ticker?.isActive != true) _ticker?.start();
  }

  void _tick(Duration elapsed) {
    final nodes = _visibleNodes;
    final edges = _visibleEdges;
    if (nodes.isEmpty || _size.isEmpty) {
      _ticker?.stop();
      return;
    }
    _ensurePositions(nodes, _size);

    const repulsion = 4200.0;
    const attraction = 0.012;
    const damping = 0.86;
    const centerPull = 0.004;
    final center = Offset(_size.width / 2, _size.height / 2);
    final forces = <int, Offset>{
      for (final n in nodes) n.objectId: Offset.zero,
    };

    for (var i = 0; i < nodes.length; i++) {
      for (var j = i + 1; j < nodes.length; j++) {
        final a = nodes[i].objectId;
        final b = nodes[j].objectId;
        final pa = _positions[a]!;
        final pb = _positions[b]!;
        var delta = pa - pb;
        var dist = delta.distance;
        if (dist < 1) {
          delta = Offset(1, 0);
          dist = 1;
        }
        final force = delta / dist * (repulsion / (dist * dist));
        forces[a] = forces[a]! + force;
        forces[b] = forces[b]! - force;
      }
    }

    for (final e in edges) {
      final pa = _positions[e.sourceId];
      final pb = _positions[e.targetId];
      if (pa == null || pb == null) continue;
      final delta = pb - pa;
      final pull = delta * attraction;
      forces[e.sourceId] = forces[e.sourceId]! + pull;
      forces[e.targetId] = forces[e.targetId]! - pull;
    }

    var maxSpeed = 0.0;
    for (final n in nodes) {
      final id = n.objectId;
      var f = forces[id]! + (center - _positions[id]!) * centerPull;
      var v = (_velocities[id]! + f) * damping;
      var p = _positions[id]! + v;
      p = Offset(
        p.dx.clamp(40.0, _size.width - 40),
        p.dy.clamp(40.0, _size.height - 80),
      );
      _velocities[id] = v;
      _positions[id] = p;
      maxSpeed = math.max(maxSpeed, v.distance);
    }

    if (mounted) setState(() {});
    if (maxSpeed < 0.15) {
      _settled = true;
      _ticker?.stop();
    }
  }

  Future<void> _openNode(ObjectGraphNode node) async {
    await state.openObjectInFile(objectId: node.objectId, fileId: node.fileId);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: state,
      builder: (context, _) {
        final nodes = _visibleNodes;
        final edges = _visibleEdges;
        final filter = Set<int>.from(state.diagramFilterTagIds);
        if (filter.length != _lastFilter.length ||
            !filter.containsAll(_lastFilter) ||
            nodes.length != _lastNodeCount) {
          _lastFilter = filter;
          _lastNodeCount = nodes.length;
          _settled = false;
        }
        if (nodes.isNotEmpty && !_settled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _startSim();
          });
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 96),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final size = Size(constraints.maxWidth, constraints.maxHeight);
                  if (size != _size) {
                    _size = size;
                    _ensurePositions(nodes, size);
                    if (!_settled) _startSim();
                  }
                  return CustomPaint(
                    painter: _EdgePainter(
                      edges: edges,
                      positions: Map.of(_positions),
                    ),
                    child: Stack(
                      children: [
                        for (final n in nodes)
                          if (_positions[n.objectId] != null)
                            Positioned(
                              left: _positions[n.objectId]!.dx - 70,
                              top: _positions[n.objectId]!.dy - 22,
                              child: _InfoNodeCard(
                                title: n.title,
                                onTap: () => _openNode(n),
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
                    ),
                  );
                },
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: 28,
              child: _DiagramTagFilter(state: state),
            ),
          ],
        );
      },
    );
  }
}

class _InfoNodeCard extends StatelessWidget {
  const _InfoNodeCard({required this.title, required this.onTap});

  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(12),
        blurSigma: 18,
        tintOpacity: 0.78,
        tintColor: AppColors.glassTint,
        elevation: 0,
        border: Border.all(
          color: AppColors.noteBorder.withValues(alpha: 0.55),
          width: AppColors.filePaneBorderWidth,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 88, maxWidth: 140),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Text(
              title.isEmpty ? 'Info' : title,
              style: AppTypography.listItemStyle.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

class _EdgePainter extends CustomPainter {
  _EdgePainter({required this.edges, required this.positions});

  final List<ObjectGraphEdge> edges;
  final Map<int, Offset> positions;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.text.withValues(alpha: 0.28)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    for (final e in edges) {
      final a = positions[e.sourceId];
      final b = positions[e.targetId];
      if (a == null || b == null) continue;
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _EdgePainter oldDelegate) => true;
}

class _DiagramTagFilter extends StatelessWidget {
  const _DiagramTagFilter({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final tags = state.objectTags;
    if (tags.isEmpty) {
      return GlassBarSegment(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            state.strings['noTagsYet'],
            style: AppTypography.metaStyle,
          ),
        ),
      );
    }
    return Align(
      alignment: Alignment.center,
      child: GlassBarSegment(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final tag in tags) ...[
                _TagChip(
                  tag: tag,
                  selected: state.diagramFilterTagIds.contains(tag.id),
                  onTap: () => state.toggleDiagramFilterTag(tag.id),
                ),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  final AppTag tag;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = TopicAppearance.colorFromHex(
      tag.color ?? TopicAppearance.defaultColor,
    );
    return Material(
      color: selected ? color.withValues(alpha: 0.28) : Colors.transparent,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tag.icon?.isNotEmpty == true
                    ? tag.icon!
                    : TopicAppearance.defaultEmoji,
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(width: 4),
              Text(tag.name, style: AppTypography.metaStyle),
            ],
          ),
        ),
      ),
    );
  }
}
