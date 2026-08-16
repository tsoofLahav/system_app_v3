import '../../core/services/api_service.dart';

class PendingReviewHunk {
  const PendingReviewHunk({
    required this.id,
    required this.op,
    required this.oldLines,
    required this.newLines,
    required this.oldStart,
    required this.oldEnd,
    required this.newStart,
    required this.newEnd,
  });

  factory PendingReviewHunk.fromJson(Map<String, dynamic> json) {
    return PendingReviewHunk(
      id: json['id']?.toString() ?? '',
      op: json['op']?.toString() ?? 'change',
      oldLines:
          (json['old_lines'] as List?)?.map((e) => '$e').toList() ?? const [],
      newLines:
          (json['new_lines'] as List?)?.map((e) => '$e').toList() ?? const [],
      // BE: old_start is 1-based; old_end is exclusive 0-based end index.
      oldStart: (json['old_start'] as int?) ?? 1,
      oldEnd: (json['old_end'] as int?) ?? 0,
      newStart: (json['new_start'] as int?) ?? 1,
      newEnd: (json['new_end'] as int?) ?? 0,
    );
  }

  final String id;
  final String op;
  final List<String> oldLines;
  final List<String> newLines;
  final int oldStart;
  final int oldEnd;
  final int newStart;
  final int newEnd;

  /// 0-based inclusive start on the old side.
  int get oldIndex0 => (oldStart - 1).clamp(0, 1 << 30);

  /// 0-based exclusive end on the old side.
  int get oldIndexEnd => oldEnd;

  int get newIndex0 => (newStart - 1).clamp(0, 1 << 30);

  int get newIndexEnd => newEnd;
}

class PendingReview {
  const PendingReview({
    required this.id,
    required this.fileId,
    required this.oldAgentText,
    required this.newAgentText,
    required this.hunks,
  });

  factory PendingReview.fromJson(Map<String, dynamic> json) {
    final hunksRaw = json['hunks'];
    return PendingReview(
      id: json['id'] as int? ?? 0,
      fileId: json['file_id'] as int? ?? 0,
      oldAgentText: json['old_agent_text']?.toString() ?? '',
      newAgentText: json['new_agent_text']?.toString() ?? '',
      hunks: hunksRaw is List
          ? hunksRaw
              .whereType<Map>()
              .map(
                (e) => PendingReviewHunk.fromJson(Map<String, dynamic>.from(e)),
              )
              .toList()
          : const [],
    );
  }

  final int id;
  final int fileId;
  final String oldAgentText;
  final String newAgentText;
  final List<PendingReviewHunk> hunks;
}

class PendingReviewService {
  PendingReviewService(this._api);

  final ApiService _api;

  Future<PendingReview?> getForFile(int fileId) async {
    final data =
        await _api.get('/files/$fileId/pending-review') as Map<String, dynamic>;
    final pending = data['pending'];
    if (pending is! Map) return null;
    return PendingReview.fromJson(Map<String, dynamic>.from(pending));
  }

  Future<void> discard(int fileId) async {
    await _api.delete('/files/$fileId/pending-review');
  }

  Future<Map<String, dynamic>> finish(
    int fileId, {
    required List<Map<String, String>> decisions,
  }) async {
    final data = await _api.post('/files/$fileId/pending-review/finish', {
      'decisions': decisions,
    }) as Map<String, dynamic>;
    return Map<String, dynamic>.from(data);
  }
}
