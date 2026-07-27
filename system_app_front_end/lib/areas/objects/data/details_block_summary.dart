class DetailsBlockSummary {
  const DetailsBlockSummary({
    required this.blockId,
    required this.fileId,
    required this.fileName,
    required this.title,
    required this.textPreview,
    this.text = '',
  });

  final int blockId;
  final int fileId;
  final String fileName;
  final String title;
  final String textPreview;
  final String text;

  factory DetailsBlockSummary.fromJson(Map<String, dynamic> json) {
    return DetailsBlockSummary(
      blockId: json['block_id'] as int,
      fileId: json['file_id'] as int,
      fileName: json['file_name'] as String? ?? '',
      title: json['title'] as String? ?? '',
      textPreview: json['text_preview'] as String? ?? '',
      text: json['text'] as String? ?? '',
    );
  }
}
