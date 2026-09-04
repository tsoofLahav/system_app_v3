import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/ux/bring_file/home_visit_merge.dart';

void main() {
  test('empty server and last-session prefs stay empty', () {
    expect(
      mergeHomeVisitIds(
        serverIds: const [],
        pendingOps: const [],
        fallback: const [42],
      ),
      isEmpty,
    );
  });

  test('empty server and this-session add keeps the file', () {
    expect(
      mergeHomeVisitIds(
        serverIds: const [],
        pendingOps: const [HomeVisitOp.add(42)],
      ),
      [42],
    );
  });

  test('server has A and this-session remove A is gone', () {
    expect(
      mergeHomeVisitIds(
        serverIds: const [7, 42],
        pendingOps: const [HomeVisitOp.remove(42)],
      ),
      [7],
    );
  });

  test('failed GET keeps fallback and does not drop session adds', () {
    expect(
      mergeHomeVisitIds(
        serverIds: null,
        pendingOps: const [HomeVisitOp.add(9)],
        fallback: const [3],
      ),
      [3],
    );
  });

  test('ack drops ops the server already reflects', () {
    expect(
      ackHomeVisitOps(const [1], const [HomeVisitOp.add(1), HomeVisitOp.add(2)]),
      [isA<HomeVisitOp>().having((o) => o.fileId, 'fileId', 2)],
    );
    expect(
      ackHomeVisitOps(const [], const [HomeVisitOp.remove(1)]),
      isEmpty,
    );
  });
}
