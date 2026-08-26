import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../../objects/data/object_embed.dart';
import '../../objects/links/add_connection_dialog.dart';
import '../editor/description_anchor.dart';
import '../editor/document_text_flow.dart';
import './block_text_focus.dart';
import './formatted_text_field.dart';

int? _asInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value');
}

List<DescriptionTextRange> descriptionRangesFromLinks(
  List<Map<String, dynamic>> links,
) {
  return [
    for (final link in links)
      if (link['anchor'] is Map)
        DescriptionTextRange(
          start: _asInt((link['anchor'] as Map)['start']) ?? 0,
          end: _asInt((link['anchor'] as Map)['end']) ?? 0,
          link: link,
        ),
  ].where((r) => r.end > r.start).toList();
}

List<DescriptionTextRange> descriptionRangesForSegment({
  required AppState state,
  required int fileId,
  required String segmentId,
}) {
  return descriptionRangesFromLinks(
    state.descriptionLinksForSegment(
      fileId: fileId,
      segmentId: segmentId,
    ),
  );
}

int? descriptionTargetObjectId(Map<String, dynamic> link) {
  final fromLink = _asInt(link['target_id']);
  if (fromLink != null) return fromLink;
  final peer = link['peer'];
  if (peer is Map) return _asInt(peer['id']);
  return null;
}

int? descriptionTargetFileId(Map<String, dynamic> link) {
  final peer = link['peer'];
  if (peer is Map) return _asInt(peer['file_id']);
  return null;
}

(String, String) descriptionPeerCopy(Map<String, dynamic> link) {
  final peer = link['peer'];
  if (peer is Map) {
    return ('${peer['title'] ?? ''}', '${peer['body'] ?? ''}');
  }
  return ('${link['label'] ?? ''}', '');
}

bool objectHasRelatedTo(ObjectEmbed embed, int targetId) {
  return embed.connections.any((c) {
    final kind = '${c['kind'] ?? 'related'}';
    if (kind != 'related') return false;
    final peer = c['peer'];
    return peer is Map && _asInt(peer['id']) == targetId;
  });
}

Future<void> connectInfoFromMark({
  required BuildContext context,
  required AppState state,
  required ObjectEmbed host,
  String? segmentId,
}) async {
  final mark = BlockTextFocusRegistry.resolveMark();
  final anchor = descriptionAnchorFromMark(
    mark,
    segmentId: segmentId,
    fileId: host.fileId,
  );
  if (anchor == null) return;
  if (!context.mounted) return;

  final pick = await showPickInfoObjectDialog(
    context: context,
    state: state,
    excludeObjectIds: {host.id},
  );
  if (pick == null) return;

  await state.createDescriptionLink(
    hostObjectId: host.id,
    targetObjectId: pick.objectId,
    anchor: anchor,
    alsoRelated: host.type == 'info' && !objectHasRelatedTo(host, pick.objectId),
  );
}

Future<void> connectInfoFromTask({
  required BuildContext context,
  required AppState state,
  required int taskId,
  int? fileId,
}) async {
  final mark = BlockTextFocusRegistry.resolveMark();
  final anchor = descriptionAnchorFromMark(
    mark,
    segmentId: taskIdSegmentId(taskId),
    fileId: fileId,
  );
  if (anchor == null) return;
  anchor['segment_id'] = taskIdSegmentId(taskId);
  if (!context.mounted) return;

  final pick = await showPickInfoObjectDialog(
    context: context,
    state: state,
  );
  if (pick == null) return;

  await state.createTaskDescriptionLink(
    taskId: taskId,
    targetObjectId: pick.objectId,
    anchor: anchor,
  );
}

Future<void> openDescriptionTarget({
  required AppState state,
  required Map<String, dynamic> link,
}) async {
  final objectId = descriptionTargetObjectId(link);
  if (objectId == null) return;
  await state.openObjectInFile(
    objectId: objectId,
    fileId: descriptionTargetFileId(link),
  );
}
