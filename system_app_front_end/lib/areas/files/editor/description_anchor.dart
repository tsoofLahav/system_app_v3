import './document_mark.dart';

/// Object-local span stored on a description link (`segment_id` + offsets).
Map<String, dynamic>? descriptionAnchorFromMark(
  DocumentMark mark, {
  String? segmentId,
  int? fileId,
}) {
  final span = mark.first;
  if (span == null || span.isEmpty) return null;
  final id = span.segmentId ?? segmentId;
  if (id == null || id.isEmpty) return null;
  return {
    'segment_id': id,
    'start': span.safeStart,
    'end': span.safeEnd,
    'file_id': ?fileId,
  };
}
