import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../data/object_service.dart';

/// Default map placement and temporary expand-push.
///
/// [interactive_graph_view] has no layout or persistence — we own coordinates
/// via [NodeWidget.position]. Saved `diagram_x` / `diagram_y` stay put; only
/// nodes without a stored point get a sparse first placement.
class DiagramLayout {
  DiagramLayout._();

  /// Collapsed node is ~96×40; this keeps first-run nodes from lining up.
  static const spacingX = 280.0;
  static const spacingY = 200.0;

  /// Center-to-center room for the ~280×180 expanded card plus a gap.
  static const expandClearance = 260.0;

  static Offset? savedOffset(ObjectGraphNode node) {
    final x = node.diagramX;
    final y = node.diagramY;
    if (x == null || y == null) return null;
    return Offset(x, y);
  }

  /// Fill [positions] for ids that are not yet placed. Returns newly assigned ids.
  static Set<int> placeUnplaced({
    required List<ObjectGraphNode> nodes,
    required List<ObjectGraphEdge> edges,
    required Map<int, Offset> positions,
  }) {
    final newly = <int>{};
    for (final node in nodes) {
      if (positions.containsKey(node.objectId)) continue;
      final saved = savedOffset(node);
      if (saved != null) {
        positions[node.objectId] = saved;
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
        (i % cols) * spacingX,
        (i ~/ cols) * spacingY,
      );
      _placeComponent(component, cell, positions);
      newly.addAll(component);
    }

    _relaxUnplaced(newly, positions, adj);
    return newly;
  }

  /// Radial push so an expanded card does not cover neighbors. Mutates [positions].
  static void pushNeighbors({
    required int originId,
    required Map<int, Offset> positions,
    Set<int> connectedIds = const {},
    double clearance = expandClearance,
  }) {
    final origin = positions[originId];
    if (origin == null) return;
    var slot = 0;
    for (final id in positions.keys.toList()) {
      if (id == originId) continue;
      final current = positions[id]!;
      final need = connectedIds.contains(id) ? clearance + 40 : clearance;
      var delta = current - origin;
      var dist = delta.distance;
      if (dist < 1) {
        final angle = slot * 2.399963;
        positions[id] = origin + Offset(math.cos(angle) * need, math.sin(angle) * need);
        slot += 1;
        continue;
      }
      if (dist < need) {
        positions[id] = origin + delta * (need / dist);
      }
      slot += 1;
    }
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

  static void _placeComponent(
    List<int> ids,
    Offset origin,
    Map<int, Offset> positions,
  ) {
    if (ids.length == 1) {
      positions[ids.first] = origin;
      return;
    }
    final radius = math.max(spacingX, ids.length * spacingX / (2 * math.pi));
    for (var i = 0; i < ids.length; i++) {
      final angle = (2 * math.pi * i / ids.length) - math.pi / 2;
      positions[ids[i]] = origin + Offset(
        math.cos(angle) * radius,
        math.sin(angle) * radius,
      );
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

  static void _relaxUnplaced(
    Set<int> movable,
    Map<int, Offset> positions,
    Map<int, List<int>> adj,
  ) {
    if (movable.isEmpty) return;
    const minDist = 180.0;
    for (var iter = 0; iter < 18; iter++) {
      for (final id in movable) {
        final current = positions[id];
        if (current == null) continue;
        var force = Offset.zero;
        for (final other in positions.entries) {
          if (other.key == id) continue;
          final delta = current - other.value;
          final dist = delta.distance;
          if (dist < 1) {
            force += Offset(8, iter.toDouble());
            continue;
          }
          if (dist < minDist) {
            force += delta / dist * (minDist - dist) * 0.35;
          }
        }
        for (final n in adj[id] ?? const <int>[]) {
          final other = positions[n];
          if (other == null) continue;
          final delta = other - current;
          final dist = delta.distance;
          if (dist > spacingX) {
            force += delta / dist * (dist - spacingX) * 0.08;
          }
        }
        positions[id] = current + force;
      }
    }
  }
}
