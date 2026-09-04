import '../files/data/app_file.dart';
import '../objects/links/info_pick_rank.dart';

/// Distinct display names from live files, first spelling kept.
List<String> uniqueFileNames(Iterable<AppFile> files) {
  final seen = <String>{};
  final out = <String>[];
  for (final file in files) {
    final key = normalizeComparable(file.name);
    if (key.isEmpty || !seen.add(key)) continue;
    out.add(file.name);
  }
  return out;
}

String? nameForFileId(int? id, Iterable<AppFile> files) {
  if (id == null) return null;
  for (final file in files) {
    if (file.id == id) {
      final name = file.name.trim();
      return name.isEmpty ? null : name;
    }
  }
  return null;
}

String? stepFileName(Map<String, dynamic> step, Iterable<AppFile> files) {
  final stored = (step['file_name'] as String? ?? '').trim();
  if (stored.isNotEmpty) return stored;
  return nameForFileId(_asInt(step['file_id']) ?? _firstFileId(step), files);
}

int? _asInt(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  return int.tryParse('$value');
}

int? _firstFileId(Map<String, dynamic> step) {
  final raw = step['file_ids'];
  if (raw is! List || raw.isEmpty) return null;
  return _asInt(raw.first);
}
