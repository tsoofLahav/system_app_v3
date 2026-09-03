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
    state.descriptionLinksForSegment(fileId: fileId, segmentId: segmentId),
  );
}

Future<void> persistRemappedDescriptionAnchors(
  AppState state,
  List<DescriptionTextRange> ranges,
) async {
  for (final range in ranges) {
    await state.patchDescriptionLinkAnchor(
      link: range.link,
      start: range.start,
      end: range.end,
    );
  }
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

/// Pieces of `[linkStart, linkEnd)` that stay connected after cutting
/// `[markStart, markEnd)` out. Empty means the whole link goes.
List<({int start, int end})> descriptionLinkRemainders({
  required int linkStart,
  required int linkEnd,
  required int markStart,
  required int markEnd,
}) {
  final cutStart = markStart < markEnd ? markStart : markEnd;
  final cutEnd = markStart < markEnd ? markEnd : markStart;
  if (cutEnd <= linkStart || cutStart >= linkEnd) {
    return [(start: linkStart, end: linkEnd)];
  }
  return [
    if (linkStart < cutStart) (start: linkStart, end: cutStart),
    if (cutEnd < linkEnd) (start: cutEnd, end: linkEnd),
  ];
}

/// The description span under the current mark (or caret line).
DescriptionTextRange? descriptionRangeCoveringMark(
  List<DescriptionTextRange> ranges,
) {
  if (ranges.isEmpty) return null;
  final span = BlockTextFocusRegistry.resolveMark().first;
  if (span == null) return null;
  return descriptionRangeCoveringOffsets(
    ranges,
    start: span.safeStart,
    end: span.safeEnd,
  );
}

/// The description span that overlaps `[start, end)` (caret when they match).
DescriptionTextRange? descriptionRangeCoveringOffsets(
  List<DescriptionTextRange> ranges, {
  required int start,
  required int end,
}) {
  for (final range in ranges) {
    if (range.end <= range.start) continue;
    final overlaps = start < range.end && end > range.start;
    final caretInside =
        start == end && start >= range.start && start < range.end;
    if (overlaps || caretInside) return range;
  }
  return null;
}

Future<void> disconnectInfoAtMark({
  required AppState state,
  required List<DescriptionTextRange> ranges,
}) async {
  final span = BlockTextFocusRegistry.resolveMark().first;
  if (span == null) return;
  await _clearDescriptionOnRange(
    state: state,
    ranges: ranges,
    markStart: span.safeStart,
    markEnd: span.safeEnd,
    anchorTemplate: {
      if (span.segmentId != null) 'segment_id': span.segmentId,
    },
  );
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
    similarTo: mark.text,
    topicId: topicIdForHost(state, host: host),
  );
  if (pick == null) return;

  final ranges = descriptionRangesForSegment(
    state: state,
    fileId: host.fileId,
    segmentId: '${anchor['segment_id'] ?? ''}',
  );
  await _applyInfoPick(
    state: state,
    pick: pick,
    ranges: ranges,
    markStart: anchor['start'] as int,
    markEnd: anchor['end'] as int,
    anchor: anchor,
    hostObjectId: host.id,
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
    similarTo: mark.text,
    topicId: topicIdForHost(state, fileId: fileId, taskId: taskId),
  );
  if (pick == null) return;

  final task = state.tasksById[taskId];
  final ranges = descriptionRangesFromLinks(task?.descriptionLinks ?? const []);
  await _applyInfoPick(
    state: state,
    pick: pick,
    ranges: ranges,
    markStart: anchor['start'] as int,
    markEnd: anchor['end'] as int,
    anchor: anchor,
    taskId: taskId,
  );
}

Future<void> _applyInfoPick({
  required AppState state,
  required InfoConnectionPick pick,
  required List<DescriptionTextRange> ranges,
  required int markStart,
  required int markEnd,
  required Map<String, dynamic> anchor,
  int? hostObjectId,
  int? taskId,
}) async {
  await _clearDescriptionOnRange(
    state: state,
    ranges: ranges,
    markStart: markStart,
    markEnd: markEnd,
    anchorTemplate: anchor,
    hostObjectId: hostObjectId,
    taskId: taskId,
  );
  if (pick.clear || pick.objectId == null) return;
  if (taskId != null) {
    await state.createTaskDescriptionLink(
      taskId: taskId,
      targetObjectId: pick.objectId!,
      anchor: anchor,
    );
    return;
  }
  if (hostObjectId == null) return;
  await state.createDescriptionLink(
    hostObjectId: hostObjectId,
    targetObjectId: pick.objectId!,
    anchor: anchor,
  );
}

Future<void> _clearDescriptionOnRange({
  required AppState state,
  required List<DescriptionTextRange> ranges,
  required int markStart,
  required int markEnd,
  required Map<String, dynamic> anchorTemplate,
  int? hostObjectId,
  int? taskId,
}) async {
  for (final range in ranges) {
    final remainders = descriptionLinkRemainders(
      linkStart: range.start,
      linkEnd: range.end,
      markStart: markStart,
      markEnd: markEnd,
    );
    if (remainders.length == 1 &&
        remainders.first.start == range.start &&
        remainders.first.end == range.end) {
      continue;
    }
    if (remainders.isEmpty) {
      await state.removeDescriptionLink(range.link);
      continue;
    }
    await state.patchDescriptionLinkAnchor(
      link: range.link,
      start: remainders.first.start,
      end: remainders.first.end,
    );
    for (final extra in remainders.skip(1)) {
      final targetId = descriptionTargetObjectId(range.link);
      if (targetId == null) continue;
      final nextAnchor = <String, dynamic>{
        ...anchorTemplate,
        if (range.link['anchor'] is Map)
          ...Map<String, dynamic>.from(range.link['anchor'] as Map),
        'start': extra.start,
        'end': extra.end,
      };
      final sourceType = '${range.link['source_type'] ?? ''}';
      final sourceId = _asInt(range.link['source_id']);
      if (sourceType == 'task' || taskId != null) {
        final id = taskId ?? sourceId;
        if (id == null) continue;
        await state.createTaskDescriptionLink(
          taskId: id,
          targetObjectId: targetId,
          anchor: nextAnchor,
        );
      } else {
        final id = hostObjectId ?? sourceId;
        if (id == null) continue;
        await state.createDescriptionLink(
          hostObjectId: id,
          targetObjectId: targetId,
          anchor: nextAnchor,
        );
      }
    }
  }
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
