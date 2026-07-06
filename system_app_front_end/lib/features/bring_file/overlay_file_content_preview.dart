import 'package:flutter/material.dart';

import '../../core/l10n/app_strings.dart';
import 'bring_file_preview.dart';
import 'overlay_file_recognition_summary.dart';

/// Quick-recognition preview body for overlay file cards.
class OverlayFileContentPreview extends StatelessWidget {
  const OverlayFileContentPreview({
    super.key,
    required this.preview,
    required this.loaded,
    required this.strings,
  });

  final OverlayFilePreviewData? preview;
  final bool loaded;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    return OverlayFileRecognitionSummary(
      preview: preview,
      loaded: loaded,
      strings: strings,
    );
  }
}
