import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:system_app_front_end/core/services/api_service.dart';

void main() {
  test('each profile client keeps its own workspace on all JSON requests', () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      return http.Response(jsonEncode({}), 200);
    });
    final personal = ApiService(client: client)..workspaceId = 1;
    final demo = ApiService(client: client)..workspaceId = 2;
    await personal.get('/topics');
    await demo.post('/files', {});
    await demo.patch('/files/3', {});
    await demo.put('/files/order', {});
    await demo.delete('/files/3');
    await personal.get('/topics');
    expect(calls.map((r) => r.headers['X-Workspace-Id']), ['1','2','2','2','2','1']);
  });
}
