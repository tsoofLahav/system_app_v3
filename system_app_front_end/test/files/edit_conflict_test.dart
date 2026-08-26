import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/edit_conflict.dart';
import 'package:system_app_front_end/areas/objects/data/object_embed.dart';

void main() {
  tearDown(() {
    UnsavedEmbedEdits.mark(1, false);
    UnsavedEmbedEdits.mark(2, false);
    UnsavedEmbedEdits.fileConflictPending = false;
    UnsavedEmbedEdits.takeLocalOverInbound = false;
  });

  test('clean local takes inbound', () {
    expect(
      decideRemoteEdit(
        localDirty: false,
        inboundEqualsLocal: false,
        inboundEqualsBaseline: false,
      ),
      RemoteEditDecision.takeRemote,
    );
  });

  test('inbound that matches local is ignored', () {
    expect(
      decideRemoteEdit(
        localDirty: true,
        inboundEqualsLocal: true,
        inboundEqualsBaseline: false,
      ),
      RemoteEditDecision.ignore,
    );
  });

  test('stale cache matching baseline is ignored while dirty', () {
    expect(
      decideRemoteEdit(
        localDirty: true,
        inboundEqualsLocal: false,
        inboundEqualsBaseline: true,
      ),
      RemoteEditDecision.ignore,
    );
  });

  test('dirty local and a new inbound asks', () {
    expect(
      decideRemoteEdit(
        localDirty: true,
        inboundEqualsLocal: false,
        inboundEqualsBaseline: false,
      ),
      RemoteEditDecision.ask,
    );
  });

  test('dirty object A does not conflict when inbound only changed B', () {
    UnsavedEmbedEdits.mark(1, true, baselineKey: embedConflictKey(_info(1, 'mine')));
    expect(
      UnsavedEmbedEdits.anyDirtyConflictsWith([
        _info(1, 'mine'),
        _info(2, 'agent-b'),
      ]),
      isFalse,
    );
  });

  test('dirty object A conflicts when inbound also changed A', () {
    UnsavedEmbedEdits.mark(1, true, baselineKey: embedConflictKey(_info(1, 'mine')));
    expect(
      UnsavedEmbedEdits.anyDirtyConflictsWith([_info(1, 'agent-a')]),
      isTrue,
    );
  });
}

ObjectEmbed _info(int id, String body) {
  return ObjectEmbed(
    id: id,
    fileId: 10,
    type: 'info',
    information: {'title': '', 'body': body, 'metadata': const {}},
  );
}
