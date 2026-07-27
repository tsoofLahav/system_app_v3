import 'dart:convert';

import 'package:flutter/material.dart';

import '../../files/data/app_file.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';

class OverlayFilePreviewData {
  const OverlayFilePreviewData({
    required this.file,
    this.summary = '',
  });

  final AppFile file;
  final String summary;

  static OverlayFilePreviewData fromFile(AppFile file) => OverlayFilePreviewData(
        file: file,
        summary: _teaserFromDocument(file.documentJson),
      );

  static const empty = OverlayFilePreviewData(
    file: AppFile(id: 0, topicId: 0, name: ''),
  );
}

/// A clipped teaser of a file's content for overlay cards.
///
/// The card's size comes from the layout slot around it — never from how much
/// text is inside. Only a few lines are shown, ellipsized, so a long document
/// cannot stretch a hero "small" slot.
class OverlayFileContentPreview extends StatelessWidget {
  const OverlayFileContentPreview({
    super.key,
    required this.preview,
  });

  final OverlayFilePreviewData preview;

  static const _maxLines = 5;

  @override
  Widget build(BuildContext context) {
    final text = preview.summary.trim().isNotEmpty
        ? preview.summary.trim()
        : preview.file.name;
    if (text.isEmpty) return const SizedBox.shrink();

    return ClipRect(
      child: Align(
        alignment: AlignmentDirectional.topStart,
        child: Text(
          text,
          maxLines: _maxLines,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.metaStyle.copyWith(
            fontSize: 11,
            height: 1.35,
            color: AppColors.text.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}

String _teaserFromDocument(String raw) {
  if (raw.trim().isEmpty) return '';
  try {
    final decoded = jsonDecode(raw);
    final buffer = StringBuffer();
    _collectText(decoded, buffer);
    return buffer.toString().trim();
  } catch (_) {
    // Not JSON — show a short plain slice rather than the whole blob.
    return raw.length <= 180 ? raw : raw.substring(0, 180);
  }
}

void _collectText(dynamic node, StringBuffer out) {
  if (out.length > 280) return;
  if (node is Map) {
    final text = node['text'];
    if (text is String && text.trim().isNotEmpty) {
      if (out.isNotEmpty) out.writeln();
      out.write(text.trim());
    }
    final content = node['content'];
    if (content is Map) {
      final inner = content['text'];
      if (inner is String && inner.trim().isNotEmpty) {
        if (out.isNotEmpty) out.writeln();
        out.write(inner.trim());
      }
    }
    for (final value in node.values) {
      _collectText(value, out);
      if (out.length > 280) return;
    }
  } else if (node is List) {
    for (final item in node) {
      _collectText(item, out);
      if (out.length > 280) return;
    }
  }
}
