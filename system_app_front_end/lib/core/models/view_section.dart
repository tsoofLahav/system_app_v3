class ViewSection {
  const ViewSection({
    required this.id,
    required this.viewType,
    required this.name,
    this.orderIndex = 0,
  });

  final int id;
  final String viewType;
  final String name;
  final int orderIndex;

  factory ViewSection.fromJson(Map<String, dynamic> json) {
    return ViewSection(
      id: json['id'] as int,
      viewType: json['view_type'] as String,
      name: json['section_name'] as String,
      orderIndex: json['order_index'] as int? ?? 0,
    );
  }
}
