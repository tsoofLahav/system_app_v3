import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_app_front_end/core/services/api_service.dart';

void main() {
  test('task saves time out without replaying the HTTP request', () async {
    var calls = 0;
    final late = Completer<http.Response>();
    final api = ApiService(
      saveTimeout: const Duration(milliseconds: 5),
      client: MockClient((_) {
        calls++;
        return late.future;
      }),
    );
    await expectLater(
      api.patch('/tasks/1', {'status': 'done'}),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
    late.complete(http.Response('{}', 200));
  });
}
