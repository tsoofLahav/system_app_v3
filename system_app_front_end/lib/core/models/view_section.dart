import 'view_section_flags.dart';

class ViewSection {
  const ViewSection({
    required this.id,
    required this.viewType,
    required this.name,
    this.orderIndex = 0,
    this.sectionFlag,
  });

  final int id;
  final String viewType;
  final String name;
  final int orderIndex;
  final String? sectionFlag;

  bool get isImportant => sectionFlagIsImportant(sectionFlag);

  ViewSection copyWith({
    int? id,
    String? viewType,
    String? name,
    int? orderIndex,
    String? sectionFlag,
    bool clearSectionFlag = false,
  }) {
    return ViewSection(
      id: id ?? this.id,
      viewType: viewType ?? this.viewType,
      name: name ?? this.name,
      orderIndex: orderIndex ?? this.orderIndex,
      sectionFlag:
          clearSectionFlag ? null : (sectionFlag ?? this.sectionFlag),
    );
  }

  factory ViewSection.fromJson(Map<String, dynamic> json) {
    return ViewSection(
      id: json['id'] as int,
      viewType: json['view_type'] as String,
      name: json['section_name'] as String,
      orderIndex: json['order_index'] as int? ?? 0,
      sectionFlag: json['section_flag'] as String?,
    );
  }
}
