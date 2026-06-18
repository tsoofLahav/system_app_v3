class AiProposal {
  const AiProposal({
    required this.id,
    required this.proposalType,
    required this.payload,
    required this.status,
    this.topicId,
    this.targetFileId,
    this.createdAt,
    this.decidedAt,
  });

  final int id;
  final int? topicId;
  final int? targetFileId;
  final String proposalType;
  final Map<String, dynamic> payload;
  final String status;
  final String? createdAt;
  final String? decidedAt;

  bool get isPending => status == 'pending';

  factory AiProposal.fromJson(Map<String, dynamic> json) {
    final rawPayload = json['payload'];
    return AiProposal(
      id: json['id'] as int,
      topicId: json['topic_id'] as int?,
      targetFileId: json['target_file_id'] as int?,
      proposalType: json['proposal_type'] as String,
      payload: rawPayload is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawPayload)
          : <String, dynamic>{},
      status: json['status'] as String? ?? 'pending',
      createdAt: json['created_at'] as String?,
      decidedAt: json['decided_at'] as String?,
    );
  }
}
