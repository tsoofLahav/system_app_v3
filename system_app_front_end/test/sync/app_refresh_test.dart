import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/core/services/api_service.dart';

class MemoryApi extends ApiService {
  final requests = <String>[];
  Completer<void>? hold;
  bool failTopics = false;
  @override
  Future<dynamic> post(String path, Map<String, dynamic> body) async => {
    'workspace_id': 1,
  };
  @override
  Future<dynamic> get(String path) async {
    requests.add(path);
    if (path == '/bootstrap/status') return {'workspace_id': 1};
    if (path.startsWith('/home-visits'))
      return {'file_ids': [], 'canvas_order': []};
    if (path.startsWith('/automations') && hold != null) await hold!.future;
    if (path.startsWith('/topics?') && failTopics) throw StateError('offline');
    return <dynamic>[];
  }

  int get topicReads => requests.where((r) => r.startsWith('/topics?')).length;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
    'minute metadata refresh, pause, immediate resume and retirement',
    () async {
      var now = DateTime(2026, 9, 14);
      final api = MemoryApi();
      final state = AppState(api: api, clock: () => now);
      await state.initialize();
      expect(state.error, isNull);
      final initial = api.topicReads;
      await state.refreshSectionWindows();
      expect(api.topicReads, initial);
      now = now.add(const Duration(seconds: 61));
      await state.refreshSectionWindows();
      expect(api.topicReads, initial + 1);
      state.didChangeAppLifecycleState(AppLifecycleState.paused);
      final before = api.requests.length;
      await state.refreshSectionWindows(full: true);
      expect(api.requests.length, before);
      state.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(api.topicReads, initial + 2);
      expect(state.pendingFocusFileId, isNull);
      expect(state.refreshing.value, isFalse);
      state.dispose();
      final stopped = api.requests.length;
      await state.refreshSectionWindows(full: true);
      expect(api.requests.length, stopped);
    },
  );
  test(
    'full refresh requested during poll is queued, not overlapped or lost',
    () async {
      final api = MemoryApi();
      final state = AppState(api: api);
      await state.initialize();
      api.hold = Completer<void>();
      final poll = state.refreshSectionWindows();
      await Future<void>.delayed(Duration.zero);
      final before = api.topicReads;
      await state.refreshSectionWindows(full: true);
      expect(api.topicReads, before);
      api.hold!.complete();
      await poll;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(api.topicReads, before + 1);
      expect(state.refreshing.value, isFalse);
      state.dispose();
    },
  );
  test(
    'failed refresh releases loading and retries without clearing cache',
    () async {
      final api = MemoryApi();
      final state = AppState(api: api);
      await state.initialize();
      api.failTopics = true;
      await state.refreshSectionWindows(full: true);
      expect(state.refreshing.value, isFalse);
      expect(state.appReady, isTrue);
      api.failTopics = false;
      await state.refreshSectionWindows(full: true);
      expect(state.refreshing.value, isFalse);
      state.dispose();
    },
  );
}
