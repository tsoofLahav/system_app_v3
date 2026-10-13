import 'dart:async';
import 'package:system_app_front_end/areas/objects/views/view_frame_task_list_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/core/app_state.dart';
import 'package:system_app_front_end/core/services/api_service.dart';
import 'package:system_app_front_end/areas/objects/data/app_view.dart';
import 'package:system_app_front_end/areas/objects/data/view_layout.dart';

const daily = AppView(id: 1, workspaceId: 1, name: 'Daily', layoutConfig: {
  'sections': [{'name': 'Morning'}],
});
const weekly = AppView(id: 2, workspaceId: 1, name: 'Weekly', layoutConfig: {
  'sections': [{'name': 'Weekend'}],
});

class DelayedViewApi extends ApiService {
  final saved = Completer<dynamic>();
  Completer<dynamic>? delayedMemberships;
  String? savedPath;
  Map<String, dynamic>? savedBody;
  String? membershipPath;
  Map<String, dynamic>? membershipBody;
  @override
  Future<dynamic> patch(String path, Map<String, dynamic> body) {
    savedPath = path;
    savedBody = body;
    return saved.future;
  }
  @override
  Future<dynamic> get(String path) async => [
    if (path.contains('/memberships')) {
      'id': path.contains('/2/') ? 20 : 10,
      'view_id': path.contains('/2/') ? 2 : 1,
      'section_name': path.contains('/2/') ? 'Weekend' : 'Morning',
    },
  ];
  @override
  Future<dynamic> put(String path, Map<String, dynamic> body) async {
    membershipPath = path;
    membershipBody = body;
    if (delayedMemberships != null) return delayedMemberships!.future;
    return [{'id': 10, 'view_id': 1, 'section_name': 'Evening'}];
  }
  void complete() => saved.complete({
    'id': 1, 'workspace_id': 1, 'name': 'Daily',
    'layout_config': savedBody!['layout_config'],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('late membership save does not leak Daily rows into Weekly', () async {
    final api = DelayedViewApi()..delayedMemberships = Completer<dynamic>();
    final state = AppState(api: api)..userViews = [daily, weekly];
    await state.selectView(daily.type);
    final save = state.reorderViewMemberships([
      for (final row in state.viewMemberships) row.toReplaceJson(),
    ]);
    await state.selectView(weekly.type);
    api.delayedMemberships!.complete([
      {'id': 10, 'view_id': 1, 'section_name': 'Morning'},
    ]);
    await save;
    expect(state.viewMemberships.single.viewId, weekly.id);
    expect(state.sectionsForSelectedView().map((s) => s.name), ['Weekend']);
    state.dispose();
  });
  test('old view frame cannot write into the new view', () async {
    final api = DelayedViewApi();
    final state = AppState(api: api)..userViews = [daily, weekly];
    await state.selectView(daily.type);
    final bridge = ViewFrameTaskListBridge(state: state, frameTasks: [],
      sectionName: 'Morning', sectionFlag: null, topicKey: null);
    await state.selectView(weekly.type);
    expect(bridge.dragGroupId, daily.id);
    await bridge.reorder([]);
    expect(api.membershipPath, isNull);
    expect(api.membershipPath, isNull);
    expect(state.sectionsForSelectedView().map((s) => s.name), ['Weekend']);
    state.dispose();
  });
  test('normal reorder and move between sections remain available', () async {
    final api = DelayedViewApi();
    final state = AppState(api: api)..userViews = [daily, weekly];
    await state.selectView(daily.type);
    state.viewMemberships = const [
      ViewMembership(id: 10, viewId: 1, taskId: 50, sectionName: 'Morning'),
      ViewMembership(id: 11, viewId: 1, taskId: 51, sectionName: 'Evening'),
    ];
    await state.reorderViewMemberships([
      state.viewMemberships[1].copyWith(orderIndex: 0).toReplaceJson(),
      state.viewMemberships[0].copyWith(orderIndex: 1).toReplaceJson(),
    ]);
    expect(api.membershipPath, '/views/1/memberships');
    expect((api.membershipBody!['memberships'] as List).map((m) => m['task_id']), [51, 50]);
    state.viewMemberships = const [
      ViewMembership(id: 10, viewId: 1, taskId: 50, sectionName: 'Morning'),
    ];
    await state.updateViewTaskPlacement(taskId: 50, sectionName: 'Evening');
    expect((api.membershipBody!['memberships'] as List).single['section_name'], 'Evening');
    state.dispose();
  });
  for (final operation in ['reorder', 'rename section', 'delete section']) {
    test('late Daily $operation cannot replace Weekly sections', () async {
      final api = DelayedViewApi();
      final state = AppState(api: api)..userViews = [daily, weekly];
      await state.selectView(daily.type);
      final save = switch (operation) {
        'rename section' => state.updateViewSection(oldName: 'Morning', next: const ViewSectionDef(name: 'Evening')),
        'delete section' => state.deleteViewSection('Morning'),
        _ => state.reorderViewSectionKeys(['section:Morning']),
      };
      expect(api.savedPath, '/views/1');
      await state.selectView(weekly.type);
      api.complete();
      await save;
      expect(state.selectedView?.id, weekly.id);
      expect(state.selectedViewType, weekly.type);
      expect(state.sectionsForSelectedView().map((s) => s.name), ['Weekend']);
      expect(state.userViews.first.id, daily.id);
      expect(state.viewMemberships.single.viewId, weekly.id);
      if (operation != 'reorder') {
        expect(api.membershipPath, '/views/1/memberships');
        final sent = (api.membershipBody!['memberships'] as List).single as Map;
        expect(sent['section_name'], operation == 'delete section' ? null : 'Evening');
      }
      state.dispose();
    });
  }
}
