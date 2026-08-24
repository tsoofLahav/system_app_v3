import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../data/object_service.dart';

/// Default map placement and temporary expand-push.
///
/// [interactive_graph_view] has no layout or persistence — we own coordinates
/// via [NodeWidget.position]. Saved `diagram_x` / `diagram_y` stay put until
/// the user asks to arrange; only nodes without a stored point (or a full
/// [layoutAll]) get a connected layout (BFS layers, then Fruchterman–Reingold
/// springs) so related objects sit near each other.
class DiagramLayout {
  DiagramLayout._();

  /// Collapsed node is ~96×40; this keeps first-run nodes from lining up.
  static const spacingX = 280.0;
  static const spacingY = 200.0;

  static const closedMaxWidth = 96.0;
  static const openMaxWidth = 260.0;

  /// Circumradius of the rectangle that traps the card (center = node coordinate).
  static double circumradius(Size size) {
    return Offset(size.width / 2, size.height / 2).distance;
  }

  static Size measureClosedChip(String title, {TextDirection textDirection = TextDirection.ltr}) {
    final label = title.isEmpty ? 'Info' : title;
    final fontSize = _closedFontSize(label);
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: fontSize,
          height: 1.15,
          fontWeight: FontWeight.w600,
        ),
      ),
      maxLines: 2,
      ellipsis: '…',
      textDirection: textDirection,
    )..layout(maxWidth: closedMaxWidth - 12);
    return Size(
      (painter.width + 12).clamp(40.0, closedMaxWidth),
      painter.height + 8,
    );
  }

  static Size measureOpenCard(
    String title,
    String body, {
    TextDirection textDirection = TextDirection.ltr,
  }) {
    const padH = 16.0;
    const padV = 16.0;
    const closeW = 28.0;
    const gap = 4.0;
    final innerMax = openMaxWidth - padH;
    final titlePainter = TextPainter(
      text: TextSpan(
        text: title.isEmpty ? ' ' : title,
        style: const TextStyle(
          fontSize: 13,
          height: 1.3,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: innerMax - closeW);
    final bodyPainter = TextPainter(
      text: TextSpan(
        text: body.isEmpty ? ' ' : body,
        style: const TextStyle(fontSize: 12, height: 1.35),
      ),
      textDirection: textDirection,
    )..layout(maxWidth: innerMax);
    final innerW = math.max(titlePainter.width + closeW, bodyPainter.width);
    return Size(
      (innerW + padH).clamp(80.0, openMaxWidth),
      padV + titlePainter.height + gap + math.max(bodyPainter.height, 16),
    );
  }

  static double _closedFontSize(String label) {
    final len = label.length;
    if (len <= 12) return 11;
    if (len <= 18) return 10;
    if (len <= 28) return 9;
    return 8;
  }

  /// Lengthen every ray from [origin] by [deltaRadius]. The opened node stays put.
  ///
  /// Applies from [base] (pre-expand positions) so repeated size updates stay exact.
  static void lengthenRays({
    required Offset origin,
    required int originId,
    required Map<int, Offset> base,
    required Map<int, Offset> positions,
    required double deltaRadius,
  }) {
    var slot = 0;
    for (final id in base.keys) {
      if (id == originId) {
        positions[id] = origin;
        continue;
      }
      final start = base[id]!;
      final delta = start - origin;
      final dist = delta.distance;
      if (dist < 1) {
        final angle = slot * 2.399963;
        positions[id] = origin + Offset(
          math.cos(angle) * deltaRadius,
          math.sin(angle) * deltaRadius,
        );
        slot += 1;
        continue;
      }
      positions[id] = origin + delta / dist * (dist + deltaRadius);
      slot += 1;
    }
  }

  /// Compose several open cards: each keeps [origin], everyone else is pushed
  /// by that card's ΔR. Recomputed from [base] so closing one card is exact.
  static void applyOpenPushes({
    required Map<int, Offset> base,
    required Map<int, Offset> positions,
    required List<({int originId, Offset origin, double deltaRadius})> opens,
  }) {
    positions
      ..clear()
      ..addAll(base);
    if (opens.isEmpty) return;
    for (final open in opens) {
      positions[open.originId] = open.origin;
    }
    var stepBase = Map<int, Offset>.of(positions);
    for (final open in opens) {
      lengthenRays(
        origin: open.origin,
        originId: open.originId,
        base: stepBase,
        positions: positions,
        deltaRadius: open.deltaRadius,
      );
      for (final pinned in opens) {
        positions[pinned.originId] = pinned.origin;
      }
      stepBase = Map<int, Offset>.of(positions);
    }
  }

  static Offset? savedOffset(ObjectGraphNode node) {
    final x = node.diagramX;
    final y = node.diagramY;
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  /// Object ids that have at least one related edge to another node in [nodes].
  static Set<int> connectedObjectIds({
    required Iterable<ObjectGraphNode> nodes,
    required Iterable<ObjectGraphEdge> edges,
  }) {
    final ids = {for (final n in nodes) n.objectId};
    final connected = <int>{};
    for (final edge in edges) {
      if (!ids.contains(edge.sourceId) || !ids.contains(edge.targetId)) {
        continue;
      }
      if (edge.sourceId == edge.targetId) continue;
      connected.add(edge.sourceId);
      connected.add(edge.targetId);
    }
    return connected;
  }

  /// True when 2+ points sit on top of each other (a bad persist, not a layout).
  static bool isCollapsed(Iterable<Offset> points) {
    final list = points.toList();
    if (list.length < 2) return false;
    final first = list.first;
    return list.every((point) => (point - first).distance < 24);
  }

  /// Fill [positions] for ids that are not yet placed. Returns newly assigned ids.
  ///
  /// Saved `diagram_x` / `diagram_y` win unless [ignoreSaved] — used when the
  /// user asks to arrange the whole map from the links again.
  static Set<int> placeUnplaced({
    required List<ObjectGraphNode> nodes,
    required List<ObjectGraphEdge> edges,
    required Map<int, Offset> positions,
    bool ignoreSaved = false,
  }) {
    final newly = <int>{};
    if (ignoreSaved) {
      positions.clear();
    } else {
      for (final node in nodes) {
        if (positions.containsKey(node.objectId)) continue;
        final saved = savedOffset(node);
        if (saved != null) {
          positions[node.objectId] = saved;
        }
      }
      if (isCollapsed(positions.values)) {
        positions.clear();
      }
    }

    final unplaced = [
      for (final node in nodes)
        if (!positions.containsKey(node.objectId)) node.objectId,
    ];
    if (unplaced.isEmpty) return newly;

    final adj = <int, List<int>>{
      for (final node in nodes) node.objectId: <int>[],
    };
    for (final edge in edges) {
      adj[edge.sourceId]?.add(edge.targetId);
      adj[edge.targetId]?.add(edge.sourceId);
    }

    var progressed = true;
    while (progressed) {
      progressed = false;
      for (final id in List<int>.from(unplaced)) {
        final placedNeighbors = [
          for (final n in adj[id] ?? const <int>[])
            if (positions.containsKey(n)) n,
        ];
        if (placedNeighbors.isEmpty) continue;
        final anchor = positions[placedNeighbors.first]!;
        positions[id] = _freeSpotNear(anchor, positions.values);
        unplaced.remove(id);
        newly.add(id);
        progressed = true;
      }
    }

    final remaining = unplaced.toSet();
    if (remaining.isEmpty) return newly;

    final components = _components(remaining, adj);
    final origin = _nextGroupOrigin(positions.values);
    final cols = math.max(3, math.sqrt(components.length).ceil());
    for (var i = 0; i < components.length; i++) {
      final component = components[i];
      final cell = origin + Offset(
        (i % cols) * spacingX * 2.2,
        (i ~/ cols) * spacingY * 1.8,
      );
      _seedComponent(component, cell, positions, adj);
      newly.addAll(component);
    }

    _forceDirected(newly, positions, adj);
    return newly;
  }

  /// Throw away saved spots and lay every node out from the links.
  static Set<int> layoutAll({
    required List<ObjectGraphNode> nodes,
    required List<ObjectGraphEdge> edges,
    required Map<int, Offset> positions,
  }) {
    return placeUnplaced(
      nodes: nodes,
      edges: edges,
      positions: positions,
      ignoreSaved: true,
    );
  }

  static Offset _freeSpotNear(Offset anchor, Iterable<Offset> taken) {
    const candidates = <Offset>[
      Offset(spacingX, 0),
      Offset(-spacingX, 0),
      Offset(0, spacingY),
      Offset(0, -spacingY),
      Offset(spacingX * 0.75, spacingY * 0.75),
      Offset(-spacingX * 0.75, spacingY * 0.75),
      Offset(spacingX * 0.75, -spacingY * 0.75),
      Offset(-spacingX * 0.75, -spacingY * 0.75),
    ];
    for (final delta in candidates) {
      final next = anchor + delta;
      if (_isClear(next, taken)) return next;
    }
    return anchor + Offset(spacingX, taken.length * 8.0);
  }

  static bool _isClear(Offset point, Iterable<Offset> taken) {
    const minDist = 160.0;
    for (final other in taken) {
      if ((point - other).distance < minDist) return false;
    }
    return true;
  }

  static Offset _nextGroupOrigin(Iterable<Offset> taken) {
    if (taken.isEmpty) return Offset.zero;
    var maxX = taken.first.dx;
    var minY = taken.first.dy;
    for (final p in taken) {
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
    }
    return Offset(maxX + spacingX * 1.6, minY);
  }

  static void _seedComponent(
    List<int> ids,
    Offset origin,
    Map<int, Offset> positions,
    Map<int, List<int>> adj,
  ) {
    if (ids.length == 1) {
      positions[ids.first] = origin;
      return;
    }
    var root = ids.first;
    var bestDegree = -1;
    for (final id in ids) {
      final degree = (adj[id] ?? const <int>[]).where(ids.contains).length;
      if (degree > bestDegree) {
        bestDegree = degree;
        root = id;
      }
    }
    final layers = <List<int>>[];
    final seen = {root};
    var frontier = [root];
    while (frontier.isNotEmpty) {
      layers.add(List<int>.from(frontier));
      final next = <int>[];
      for (final id in frontier) {
        for (final n in adj[id] ?? const <int>[]) {
          if (!ids.contains(n) || !seen.add(n)) continue;
          next.add(n);
        }
      }
      next.sort();
      frontier = next;
    }
    for (final id in ids) {
      if (seen.add(id)) layers.add([id]);
    }
    const layerGap = spacingX;
    const rowGap = spacingY * 0.7;
    for (var li = 0; li < layers.length; li++) {
      final layer = layers[li];
      final y0 = -(layer.length - 1) * rowGap / 2;
      for (var i = 0; i < layer.length; i++) {
        positions[layer[i]] = origin + Offset(li * layerGap, y0 + i * rowGap);
      }
    }
  }

  /// Fruchterman–Reingold-style springs: pull related nodes together, push
  /// everything else apart so edges stay short and crossings stay rare.
  static void _forceDirected(
    Set<int> movable,
    Map<int, Offset> positions,
    Map<int, List<int>> adj,
  ) {
    if (movable.length < 2) return;
    const ideal = 240.0;
    var cool = ideal;
    final ids = movable.toList();
    for (var iter = 0; iter < 36; iter++) {
      final disp = {for (final id in ids) id: Offset.zero};
      for (var i = 0; i < ids.length; i++) {
        for (var j = i + 1; j < ids.length; j++) {
          final a = ids[i];
          final b = ids[j];
          final delta = positions[a]! - positions[b]!;
          var dist = delta.distance;
          if (dist < 1) dist = 1;
          final force = delta / dist * (ideal * ideal / dist);
          disp[a] = disp[a]! + force;
          disp[b] = disp[b]! - force;
        }
      }
      for (final id in ids) {
        for (final other in positions.entries) {
          if (movable.contains(other.key)) continue;
          final delta = positions[id]! - other.value;
          var dist = delta.distance;
          if (dist < 1) dist = 1;
          if (dist > ideal * 3) continue;
          disp[id] = disp[id]! + delta / dist * (ideal * ideal / dist);
        }
      }
      for (final id in ids) {
        for (final n in adj[id] ?? const <int>[]) {
          if (n <= id && movable.contains(n)) continue;
          final other = positions[n];
          if (other == null) continue;
          final delta = other - positions[id]!;
          var dist = delta.distance;
          if (dist < 1) dist = 1;
          final force = delta / dist * (dist * dist / ideal) * 0.55;
          disp[id] = disp[id]! + force;
          if (movable.contains(n)) {
            disp[n] = disp[n]! - force;
          }
        }
      }
      for (final id in ids) {
        final d = disp[id]!;
        final len = d.distance;
        if (len < 0.05) continue;
        positions[id] = positions[id]! + d / len * math.min(len, cool);
      }
      cool *= 0.91;
    }
  }

  static List<List<int>> _components(Set<int> ids, Map<int, List<int>> adj) {
    final seen = <int>{};
    final out = <List<int>>[];
    for (final start in ids) {
      if (seen.contains(start)) continue;
      final stack = [start];
      final group = <int>[];
      seen.add(start);
      while (stack.isNotEmpty) {
        final id = stack.removeLast();
        group.add(id);
        for (final n in adj[id] ?? const <int>[]) {
          if (!ids.contains(n) || !seen.add(n)) continue;
          stack.add(n);
        }
      }
      group.sort();
      out.add(group);
    }
    return out;
  }
}
