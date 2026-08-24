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
  test('a persisted pile is thrown away and laid out again', () {
    final positions = <int, Offset>{};
    DiagramLayout.placeUnplaced(
      nodes: [
        node(1, x: 0, y: 0),
        node(2, x: 0, y: 0),
        node(3, x: 0, y: 0),
        node(4, x: 0, y: 0),
      ],
      edges: const [],
      positions: positions,
    );
    expect(DiagramLayout.isCollapsed(positions.values), isFalse);
    expect(positions.length, 4);
  });

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

  test('circumradius is half the diagonal of the card', () {
    expect(DiagramLayout.circumradius(const Size(8, 6)), 5);
  });

  test('lengthenRays grows every ray by ΔR and keeps the opened center', () {
    const origin = Offset.zero;
    final base = {
      1: origin,
      2: const Offset(100, 0),
      3: const Offset(0, 80),
      4: const Offset(300, 0),
    };
    final positions = Map<int, Offset>.of(base);
    DiagramLayout.lengthenRays(
      origin: origin,
      originId: 1,
      base: base,
      positions: positions,
      deltaRadius: 20,
    );
    expect(positions[1], origin);
    expect(positions[2], const Offset(120, 0));
    expect(positions[3]!.dy, closeTo(100, 0.001));
    expect(positions[4], const Offset(320, 0));
  });

  test('lengthenRays reapplies from the pre-expand base', () {
    const origin = Offset.zero;
    final base = {1: origin, 2: const Offset(50, 0)};
    final positions = Map<int, Offset>.of(base);
    DiagramLayout.lengthenRays(
      origin: origin,
      originId: 1,
      base: base,
      positions: positions,
      deltaRadius: 10,
    );
    DiagramLayout.lengthenRays(
      origin: origin,
      originId: 1,
      base: base,
      positions: positions,
      deltaRadius: 30,
    );
    expect(positions[2], const Offset(80, 0));
  });

  test('applyOpenPushes keeps every open center and stacks ΔR', () {
    const a = Offset.zero;
    const b = Offset(100, 0);
    final base = {
      1: a,
      2: b,
      3: const Offset(0, 80),
    };
    final positions = <int, Offset>{};
    DiagramLayout.applyOpenPushes(
      base: base,
      positions: positions,
      opens: [
        (originId: 1, origin: a, deltaRadius: 20),
        (originId: 2, origin: const Offset(120, 0), deltaRadius: 10),
      ],
    );
    expect(positions[1], a);
    expect(positions[2], const Offset(120, 0));
    expect(positions[3]!.dy, greaterThan(80));
  });

  test('connectedObjectIds keeps only nodes with a related edge', () {
    expect(
      DiagramLayout.connectedObjectIds(
        nodes: [node(1), node(2), node(3)],
        edges: [edge(1, 1, 2)],
      ),
      {1, 2},
    );
  });

  test('a related chain sits nearer along links than across them', () {
    final positions = <int, Offset>{};
    DiagramLayout.placeUnplaced(
      nodes: [node(1), node(2), node(3), node(4)],
      edges: [edge(1, 1, 2), edge(2, 2, 3), edge(3, 3, 4)],
      positions: positions,
    );
    double hop(int a, int b) => (positions[a]! - positions[b]!).distance;
    final neighbor = (hop(1, 2) + hop(2, 3) + hop(3, 4)) / 3;
    final far = hop(1, 4);
    expect(neighbor, lessThan(far));
  });

  test('layoutAll ignores saved coordinates', () {
    final positions = <int, Offset>{
      1: const Offset(10, 10),
      2: const Offset(20, 20),
    };
    DiagramLayout.layoutAll(
      nodes: [
        node(1, x: 10, y: 10),
        node(2, x: 20, y: 20),
        node(3, x: 30, y: 30),
        node(4, x: 40, y: 40),
      ],
      edges: [edge(1, 1, 2), edge(2, 2, 3), edge(3, 3, 4)],
      positions: positions,
    );
    expect(positions.keys, {1, 2, 3, 4});
    expect(positions[1], isNot(const Offset(10, 10)));
    expect(positions[2], isNot(const Offset(20, 20)));
    expect(DiagramLayout.isCollapsed(positions.values), isFalse);
    expect((positions[1]! - positions[4]!).distance, greaterThan(200));
  });

  test('placeUnplaced keeps arranged spots even when nodes still carry old coords', () {
    final positions = <int, Offset>{};
    DiagramLayout.layoutAll(
      nodes: [
        node(1, x: 1, y: 1),
        node(2, x: 2, y: 2),
        node(3, x: 3, y: 3),
      ],
      edges: [edge(1, 1, 2), edge(2, 2, 3)],
      positions: positions,
    );
    final arranged = Map<int, Offset>.from(positions);
    final newly = DiagramLayout.placeUnplaced(
      nodes: [
        node(1, x: 1, y: 1),
        node(2, x: 2, y: 2),
        node(3, x: 3, y: 3),
      ],
      edges: [edge(1, 1, 2), edge(2, 2, 3)],
      positions: positions,
    );
    expect(newly, isEmpty);
    expect(positions[1], arranged[1]);
    expect(positions[2], arranged[2]);
    expect(positions[3], arranged[3]);
  });

  test('open card is larger than the closed chip for the same text', () {
    const title = 'Short';
    const body = 'A longer body that needs more room than the chip.';
    final closed = DiagramLayout.measureClosedChip(title);
    final open = DiagramLayout.measureOpenCard(title, body);
    expect(DiagramLayout.circumradius(open),
        greaterThan(DiagramLayout.circumradius(closed)));
    expect(open.width, lessThanOrEqualTo(DiagramLayout.openMaxWidth));
  });
}
