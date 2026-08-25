import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/editor/edit_conflict.dart';

void main() {
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
}
