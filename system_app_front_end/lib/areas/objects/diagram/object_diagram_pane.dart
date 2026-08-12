import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/app_state.dart';
import '../../../core/models/tag.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_icons.dart';
import '../../ui/app_segmented_toggle.dart';
import '../../ui/app_typography.dart';
import '../../ui/glass_surface.dart';
import '../../ux/shell/app_bottom_bar.dart';
import '../../ux/topic/topic_appearance.dart';
import '../data/object_service.dart';

/// Workspace objects map: info nodes, related edges, tag filter, color modes.
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
  int? _expandedObjectId;

  static const _cardHalfW = 52.0;
  static const _cardHalfH = 18.0;
  static const _expandedHalfW = 140.0;
  static const _expandedHalfH = 90.0;
  static const _filterFloor = AppBottomBarMetrics.scrollInset + 8;

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
    if (_expandedObjectId != null) return;
    _settled = false;
    if (_ticker?.isActive != true) _ticker?.start();
  }

  void _tick(Duration elapsed) {
    // Freeze the whole sim while editing so setState doesn't rebuild TextFields
    // under a held key (HardwareKeyboard "already pressed" assertion).
    if (_expandedObjectId != null) {
      _ticker?.stop();
      return;
    }
    final nodes = _visibleNodes;
    final edges = _visibleEdges;
    if (nodes.isEmpty || _size.isEmpty) {
      _ticker?.stop();
      return;
    }
    _ensurePositions(nodes, _size);

    // Tighter packing so related edges stay visible between cards.
    const repulsion = 2200.0;
    const attraction = 0.018;
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
          delta = const Offset(1, 0);
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
        p.dy.clamp(40.0, _size.height - 40),
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

  void _toggleExpand(ObjectGraphNode node) {
    setState(() {
      if (_expandedObjectId == node.objectId) {
        _expandedObjectId = null;
      } else {
        _expandedObjectId = node.objectId;
        _ticker?.stop();
      }
    });
    if (_expandedObjectId == null) _startSim();
  }

  void _closeExpand() {
    setState(() => _expandedObjectId = null);
    _startSim();
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
        if (_expandedObjectId != null &&
            !nodes.any((n) => n.objectId == _expandedObjectId)) {
          _expandedObjectId = null;
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
              padding: EdgeInsets.fromLTRB(24, 48, 24, _filterFloor + 100),
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
                            Builder(
                              builder: (context) {
                                final expanded =
                                    n.objectId == _expandedObjectId;
                                final halfW =
                                    expanded ? _expandedHalfW : _cardHalfW;
                                final halfH =
                                    expanded ? _expandedHalfH : _cardHalfH;
                                return Positioned(
                                  left: _positions[n.objectId]!.dx - halfW,
                                  top: _positions[n.objectId]!.dy - halfH,
                                  child: expanded
                                      ? _ExpandedInfoCard(
                                          key: ValueKey(
                                            'diagram-expand-${n.objectId}',
                                          ),
                                          node: n,
                                          accent: _accentFor(n),
                                          onClose: _closeExpand,
                                          onSave: n.informationId == null
                                              ? null
                                              : (title, body) =>
                                                  state.updateInfoFromDiagram(
                                                    informationId:
                                                        n.informationId!,
                                                    objectId: n.objectId,
                                                    title: title,
                                                    body: body,
                                                  ),
                                        )
                                      : _InfoNodeCard(
                                          title: n.title,
                                          accent: _accentFor(n),
                                          onTap: () => _toggleExpand(n),
                                        ),
                                );
                              },
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
              bottom: _filterFloor,
              child: _DiagramChrome(state: state),
            ),
          ],
        );
      },
    );
  }
}

class _InfoNodeCard extends StatelessWidget {
  const _InfoNodeCard({
    required this.title,
    required this.onTap,
    this.accent,
  });

  final String title;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final tint = accent ?? AppColors.glassTint;
    final border = accent ?? AppColors.noteBorder;
    return GestureDetector(
      onTap: onTap,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(10),
        blurSigma: 18,
        tintOpacity: accent == null ? 0.78 : 0.55,
        tintColor: tint,
        elevation: 0,
        border: Border.all(
          color: border.withValues(alpha: accent == null ? 0.55 : 0.75),
          width: AppColors.filePaneBorderWidth,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 72, maxWidth: 110),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Text(
              title.isEmpty ? 'Info' : title,
              style: AppTypography.listItemStyle.copyWith(
                fontWeight: FontWeight.w600,
                fontSize: 12,
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
    final tint = widget.accent ?? AppColors.glassTint;
    final border = widget.accent ?? AppColors.noteBorder;
    return Material(
      color: Colors.transparent,
      child: GlassSurface(
        borderRadius: BorderRadius.circular(12),
        blurSigma: 20,
        tintOpacity: widget.accent == null ? 0.9 : 0.72,
        tintColor: tint,
        elevation: 0,
        border: Border.all(
          color: border.withValues(alpha: 0.8),
          width: AppColors.filePaneBorderWidth,
        ),
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
                      tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
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
      ..color = AppColors.text.withValues(alpha: 0.34)
      ..strokeWidth = 1.15
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

class _DiagramChrome extends StatelessWidget {
  const _DiagramChrome({required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    final s = state.strings;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.center,
          child: GlassBarSegment(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: AppSegmentedToggle<DiagramColorMode>(
              options: [
                AppSegmentedOption(
                  value: DiagramColorMode.byTopic,
                  label: s['diagramColorByTopic'],
                ),
                AppSegmentedOption(
                  value: DiagramColorMode.byTag,
                  label: s['diagramColorByTag'],
                ),
              ],
              selected: state.diagramColorMode,
              onSelected: state.setDiagramColorMode,
            ),
          ),
        ),
        const SizedBox(height: 8),
        _DiagramTagFilter(state: state),
      ],
    );
  }
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

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    if (!it.moveNext()) return null;
    return it.current;
  }
}
