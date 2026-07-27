import 'package:flutter/material.dart';

import '../../../core/app_state.dart';
import '../data/object_embed.dart';
import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';
import '../../files/rich_text/formatted_text_field.dart';
import '../../files/rich_text/span_text_editing_controller.dart';

class InfoEmbed extends StatefulWidget {
  const InfoEmbed({
    super.key,
    required this.embed,
    required this.state,
    required this.onRefresh,
  });

  final ObjectEmbed embed;
  final AppState state;
  final VoidCallback onRefresh;

  @override
  State<InfoEmbed> createState() => _InfoEmbedState();
}

class _InfoEmbedState extends State<InfoEmbed> {
  late TextEditingController _titleController;
  late SpanTextEditingController _bodyController;

  @override
  void initState() {
    super.initState();
    final info = widget.embed.information ?? const {};
    _titleController = TextEditingController(text: info['title'] as String? ?? '');
    final meta = info['metadata'];
    final spans = meta is Map ? meta['spans'] : null;
    _bodyController = SpanTextEditingController(
      text: info['body'] as String? ?? '',
      spans: spans is List
          ? [for (final s in spans) if (s is Map) Map<String, dynamic>.from(s)]
          : const [],
    );
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.state.updateInfoObject(
      widget.embed,
      title: _titleController.text,
      body: _bodyController.text,
      spans: _bodyController.spans,
    );
    widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: AppColors.detailsBlockDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _titleController,
            style: AppTypography.noteTitleStyle,
            decoration: const InputDecoration(
              hintText: 'Info title',
              border: InputBorder.none,
              isDense: true,
            ),
            onEditingComplete: _save,
          ),
          FormattedTextField(
            controller: _bodyController,
            style: AppTypography.noteBodyStyle,
            maxLines: null,
            onChanged: (_) => _save(),
          ),
        ],
      ),
    );
  }
}

class ImageEmbed extends StatelessWidget {
  const ImageEmbed({
    super.key,
    required this.embed,
    required this.onPayloadChanged,
  });

  final ObjectEmbed embed;
  final ValueChanged<Map<String, dynamic>> onPayloadChanged;

  @override
  Widget build(BuildContext context) {
    final payload = embed.payload ?? const {};
    final url = (payload['url'] as String?)?.trim() ?? '';
    final width = (payload['width'] as num?)?.toDouble();
    if (url.isEmpty) {
      return SizedBox(
        width: 240,
        height: 120,
        child: TextField(
          decoration: const InputDecoration(
            hintText: 'Image URL',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => onPayloadChanged({...payload, 'url': value}),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Image.network(
        url,
        width: width ?? 320,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            Text('Image failed to load', style: AppTypography.metaStyle),
      ),
    );
  }
}

class GraphEmbed extends StatelessWidget {
  const GraphEmbed({super.key, required this.embed});

  final ObjectEmbed embed;

  @override
  Widget build(BuildContext context) {
    final payload = embed.payload ?? const {};
    final labels = (payload['labels'] as List?)?.cast<String>() ?? const [];
    final values = [
      for (final v in payload['values'] as List? ?? const [])
        (v as num?)?.toDouble() ?? 0,
    ];
    if (labels.isEmpty || values.isEmpty) {
      return Text('[graph]', style: AppTypography.metaStyle);
    }
    final maxVal = values.reduce((a, b) => a > b ? a : b).clamp(1.0, double.infinity);
    return SizedBox(
      height: 80,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < labels.length && i < values.length; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: FractionallySizedBox(
                          heightFactor: values[i] / maxVal,
                          widthFactor: 0.6,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(labels[i], style: AppTypography.metaStyle, maxLines: 1),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
