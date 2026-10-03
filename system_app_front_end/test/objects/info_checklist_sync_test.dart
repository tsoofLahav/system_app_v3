import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/core/services/api_service.dart';
import 'package:system_app_front_end/areas/objects/data/object_embed.dart';
import 'package:system_app_front_end/areas/objects/data/task.dart';

class ChecklistApi extends ApiService {
  String body = '☐ first\n☐ second\n• ordinary';
  String status = 'active';
  final writes = <String>[];
  Completer<void>? hold;
  Completer<void>? readHold;
  bool fail = false;
  Map<String, dynamic> get object => {
    'id': 10,
    'file_id': 2,
    'type': 'info',
    'information_id': 20,
    'information': {
      'title': 'Title',
      'body': body,
      'metadata': {
        'title_spans': [
          {'start': 0, 'end': 5, 'bold': true},
        ],
        'spans': [],
      },
    },
  };
  @override
  Future<dynamic> get(String path) async {
    if (path == '/objects/10') return object;
    if (path == '/files/2/objects') {
      final snapshot = object;
      await readHold?.future;
      return [snapshot];
    }
    return <dynamic>[];
  }

  @override
  Future<dynamic> patch(String path, Map<String, dynamic> data) async {
    writes.add(path);
    await hold?.future;
    if (fail) throw StateError('offline');
    if (path == '/information/20') {
      body = data['body'] as String;
      return object['information'];
    }
    if (path == '/tasks/1') {
      status = data['status'] as String;
      return {
        'id': 1,
        'title': 'Task',
        'status': status,
        'description_links': task.descriptionLinks,
      };
    }
    throw StateError('Unexpected write $path');
  }

  Task get task => Task(
    id: 1,
    title: 'Task',
    status: status,
    descriptionLinks: [
      {
        'target_id': 10,
        'peer': {'id': 10, 'title': 'Title', 'body': body},
      },
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<void> tick() => Future<void>.delayed(Duration.zero);

  test(
    'view-only preview loads the info and preserves title and other lines',
    () async {
      final api = ChecklistApi();
      final state = AppState(api: api);
      addTearDown(state.dispose);
      state.tasksById[1] = api.task;
      final next = await state.toggleInnerTaskOnInfo(
        infoObjectId: 10,
        body: api.body,
        markOffset: 0,
      );
      expect(next, '☑ first\n☐ second\n• ordinary');
      expect(api.body, next);
      expect(
        state.embedsByFileId,
        isEmpty,
        reason: 'Do not cache a partial file',
      );
      expect(state.tasksById[1]!.status, 'active');
      expect(state.tasksById[1]!.descriptionLinks.first['peer']['body'], next);
    },
  );

  test(
    'inner completion updates outer before save, failure restores it',
    () async {
      final api = ChecklistApi()
        ..body = '☐ first'
        ..hold = Completer<void>();
      final state = AppState(api: api);
      addTearDown(state.dispose);
      state.tasksById[1] = api.task;
      state.embedsByFileId[2] = [ObjectEmbed.fromJson(api.object)];
      final save = state.toggleInnerTaskOnInfo(
        infoObjectId: 10,
        body: api.body,
        markOffset: 0,
      );
      final failure = expectLater(save, throwsStateError);
      await tick();
      expect(state.tasksById[1]!.status, 'done');
      expect(api.body, '☐ first');
      api.fail = true;
      api.hold!.complete();
      await failure;
      expect(state.tasksById[1]!.status, 'active');
      expect(state.embedsByFileId[2]!.single.information!['body'], '☐ first');
    },
  );

  test(
    'queued inner toggles compose instead of replacing one another',
    () async {
      final api = ChecklistApi()..hold = Completer<void>();
      final state = AppState(api: api);
      addTearDown(state.dispose);
      state.tasksById[1] = api.task;
      final first = state.toggleInnerTaskOnInfo(
        infoObjectId: 10,
        body: api.body,
        markOffset: 0,
      );
      final second = state.toggleInnerTaskOnInfo(
        infoObjectId: 10,
        body: api.body,
        markOffset: api.body.indexOf('☐ second'),
      );
      await tick();
      expect(api.writes, ['/information/20']);
      api.hold!.complete();
      await Future.wait([first, second]);
      expect(api.body, '☑ first\n☑ second\n• ordinary');
      expect(state.tasksById[1]!.status, 'done');
    },
  );

  test('outer toggle mirrors immediately with only one status write', () async {
    final api = ChecklistApi()..hold = Completer<void>();
    final state = AppState(api: api);
    addTearDown(state.dispose);
    final task = api.task;
    state.tasksById[1] = task;
    state.embedsByFileId[2] = [ObjectEmbed.fromJson(api.object)];
    final save = state.toggleTaskStatus(task);
    await tick();
    expect(state.tasksById[1]!.status, 'done');
    expect(
      state.embedsByFileId[2]!.single.information!['body'],
      '☑ first\n☑ second\n• ordinary',
    );
    expect(api.writes, ['/tasks/1']);
    api.hold!.complete();
    await save;
    expect(api.writes, ['/tasks/1']);
  });

  test(
    'a poll started before the click cannot revert a completed save',
    () async {
      final api = ChecklistApi()
        ..body = '☐ first'
        ..readHold = Completer<void>();
      final state = AppState(api: api);
      addTearDown(state.dispose);
      state.tasksById[1] = api.task;
      state.embedsByFileId[2] = [ObjectEmbed.fromJson(api.object)];
      final poll = state.loadEmbedsForFile(2, notify: false);
      await tick();
      await state.toggleInnerTaskOnInfo(
        infoObjectId: 10,
        body: api.body,
        markOffset: 0,
      );
      api.readHold!.complete();
      await poll;
      expect(state.embedsByFileId[2]!.single.information!['body'], '☑ first');
      expect(state.tasksById[1]!.status, 'done');
    },
  );

  test(
    'stale preview cannot overwrite newer prose or a renamed checklist',
    () async {
      final api = ChecklistApi()
        ..body = 'New prose\n☐ first\n☐ second\n• ordinary';
      final state = AppState(api: api);
      addTearDown(state.dispose);
      final saved = await state.toggleInnerTaskOnInfo(
        infoObjectId: 10,
        body: '☐ first\n☐ second\n• ordinary',
        markOffset: 0,
      );
      expect(saved, 'New prose\n☑ first\n☐ second\n• ordinary');
      api.body = '☐ renamed';
      final rejected = await state.toggleInnerTaskOnInfo(
        infoObjectId: 10,
        body: '☐ first',
        markOffset: 0,
      );
      expect(rejected, isNull);
      expect(api.body, '☐ renamed');
      expect(api.writes.length, 1);
    },
  );

  test('linked outer and inner commands save in click order', () async {
    final api = ChecklistApi()..hold = Completer<void>();
    final state = AppState(api: api);
    addTearDown(state.dispose);
    state.tasksById[1] = api.task;
    state.embedsByFileId[2] = [ObjectEmbed.fromJson(api.object)];
    final outer = state.toggleTaskStatus(api.task);
    await tick();
    final inner = state.toggleInnerTaskOnInfo(
      infoObjectId: 10,
      body: '☑ first\n☑ second\n• ordinary',
      markOffset: 0,
    );
    await tick();
    expect(api.writes, ['/tasks/1']);
    api.hold!.complete();
    await Future.wait([outer, inner]);
    expect(api.writes, ['/tasks/1', '/information/20']);
    expect(api.body, '☐ first\n☑ second\n• ordinary');
  });

  test(
    'inactive, pending, and skipped outer tasks do not follow inner marks',
    () {
      final state = AppState();
      addTearDown(state.dispose);
      for (final status in ['inactive', 'pending', 'skipped']) {
        state.tasksById[1] = ChecklistApi().task.copyWith(status: status);
        state.applyOuterTaskMarksFromInfo(infoObjectId: 10, body: '☑ first');
        expect(state.tasksById[1]!.status, status);
      }
    },
  );
}
