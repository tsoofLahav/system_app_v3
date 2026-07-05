import 'app_file.dart';

class ArchiveFilesPage {
  const ArchiveFilesPage({
    required this.files,
    required this.total,
    required this.hasMore,
    required this.headerTextsByFileId,
  });

  final List<AppFile> files;
  final int total;
  final bool hasMore;
  final Map<int, List<String>> headerTextsByFileId;

  factory ArchiveFilesPage.fromJson(Map<String, dynamic> json) {
    final rawHeaders =
        json['header_texts_by_file_id'] as Map<String, dynamic>? ?? {};
    final headerTexts = <int, List<String>>{};
    rawHeaders.forEach((key, value) {
      final id = int.tryParse(key);
      if (id == null || value is! List) return;
      headerTexts[id] = [
        for (final item in value)
          if (item.toString().trim().isNotEmpty) item.toString().trim(),
      ];
    });

    return ArchiveFilesPage(
      files: (json['files'] as List<dynamic>? ?? const [])
          .map((e) => AppFile.fromJson(e as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? 0,
      hasMore: json['has_more'] as bool? ?? false,
      headerTextsByFileId: headerTexts,
    );
  }
}
