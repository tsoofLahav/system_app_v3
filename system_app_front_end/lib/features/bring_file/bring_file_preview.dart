import 'package:flutter/material.dart';

import '../../core/models/app_file.dart';

class OverlayFilePreviewData {
  const OverlayFilePreviewData({
    required this.file,
    this.summary = '',
  });

  final AppFile file;
  final String summary;

  static OverlayFilePreviewData fromFile(AppFile file) =>
      OverlayFilePreviewData(file: file);

  static const empty = OverlayFilePreviewData(
    file: AppFile(id: 0, topicId: 0, name: ''),
  );
}

class OverlayFileContentPreview extends StatelessWidget {
  const OverlayFileContentPreview({
    super.key,
    required this.preview,
  });

  final OverlayFilePreviewData preview;

  @override
  Widget build(BuildContext context) {
    return Text(
      preview.file.documentJson.isEmpty ? preview.file.name : preview.file.documentJson,
      maxLines: 6,
      overflow: TextOverflow.ellipsis,
    );
  }
}
