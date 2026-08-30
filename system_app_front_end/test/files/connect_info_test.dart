import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/block_text_focus.dart';
import 'package:system_app_front_end/areas/files/rich_text/connect_info.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/objects/data/object_service.dart';
import 'package:system_app_front_end/areas/objects/links/add_connection_dialog.dart';

void main() {
  ObjectGraphNode node(int id, String title, {String body = ''}) =>
      ObjectGraphNode(
        objectId: id,
        type: 'info',
        title: title,
        body: body,
        fileId: 1,
        tagIds: const [],
      );

  test('named info picker hides empty titles and matches by name', () {
    final nodes = [
      node(1, 'Alpha'),
      node(2, ''),
      node(3, '   '),
      node(4, 'Alphabet'),
      node(5, 'Beta'),
      node(6, 'Info'),
      node(7, 'info'),
      node(8, 'Info', body: 'has a body'),
    ];
    expect(namedInfoNodes(nodes).map((n) => n.objectId).toList(), [1, 4, 5, 8]);
    expect(
      namedInfoNodes(nodes, query: 'alph').map((n) => n.objectId).toList(),
      [1, 4],
    );
    expect(
      namedInfoNodes(nodes, excludeObjectIds: {1}).map((n) => n.objectId),
      [4, 5, 8],
    );
  });

  test('description range under a marking can be disconnected', () {
    TestWidgetsFlutterBinding.ensureInitialized();
    final controller = TextEditingController(text: 'hello world');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection(baseOffset: 0, extentOffset: 5);
    BlockTextFocusRegistry.register(controller: controller, changed: () {});
    addTearDown(() => BlockTextFocusRegistry.unregister(controller));

    final hit = descriptionRangeCoveringMark([
      const DescriptionTextRange(start: 0, end: 5, link: {'id': 9}),
    ]);
    expect(hit?.link['id'], 9);
    expect(
      descriptionRangeCoveringMark([
        const DescriptionTextRange(start: 8, end: 11, link: {'id': 2}),
      ]),
      isNull,
    );
  });
}
