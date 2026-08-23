import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/objects/data/object_service.dart';
import 'package:system_app_front_end/areas/objects/diagram/diagram_layout.dart';

ObjectGraphNode node(int id, {double? x, double? y}) {
  return ObjectGraphNode(
    objectId: id,
    type: 'info',
    title: 'n$id',
    fileId: 1,
    tagIds: const [],
    diagramX: x,
    diagramY: y,
  );
}

ObjectGraphEdge edge(int id, int a, int b) {
  return ObjectGraphEdge(
    id: id,
    kind: 'related',
    sourceId: a,
    targetId: b,
  );
}

void main() {
  test('saved coordinates win over auto layout', () {
    final positions = <int, Offset>{};
    final newly = DiagramLayout.placeUnplaced(
      nodes: [node(1, x: 40, y: -20), node(2, x: 400, y: 80)],
      edges: [edge(1, 1, 2)],
      positions: positions,
    );
    expect(newly, isEmpty);
    expect(positions[1], const Offset(40, -20));
    expect(positions[2], const Offset(400, 80));
  });

  test('unplaced connected nodes sit farther apart than the old 140×64 grid', () {
    final positions = <int, Offset>{};
    DiagramLayout.placeUnplaced(
      nodes: [node(1), node(2), node(3), node(4)],
      edges: [edge(1, 1, 2), edge(2, 2, 3), edge(3, 3, 4)],
      positions: positions,
    );
    expect(positions.keys, {1, 2, 3, 4});
    final pairs = <double>[];
    for (final a in positions.entries) {
      for (final b in positions.entries) {
        if (a.key >= b.key) continue;
        pairs.add((a.value - b.value).distance);
      }
    }
    expect(pairs.every((d) => d > 140), isTrue);
  });

  test('unconnected nodes spread across more than one row', () {
    final positions = <int, Offset>{};
    DiagramLayout.placeUnplaced(
      nodes: [for (var i = 1; i <= 6; i++) node(i)],
      edges: const [],
      positions: positions,
    );
    final rows = {for (final p in positions.values) (p.dy / 80).round()};
    expect(rows.length, greaterThan(1));
  });

  test('expand push moves close neighbors out and leaves far ones', () {
    final positions = {
      1: Offset.zero,
      2: const Offset(40, 0),
      3: const Offset(800, 0),
    };
    DiagramLayout.pushNeighbors(
      originId: 1,
      positions: positions,
      connectedIds: {2},
    );
    expect(positions[1], Offset.zero);
    expect(positions[2]!.dx, greaterThanOrEqualTo(DiagramLayout.expandClearance));
    expect(positions[3], const Offset(800, 0));
  });
}
