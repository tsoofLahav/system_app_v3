import './view_section_flags.dart';

/// Section definition stored on [AppView.layoutConfig].
class ViewSectionDef {
  const ViewSectionDef({
    required this.name,
    this.flag,
    this.colorHex,
    this.orderIndex = 0,
  });

  final String name;
  final String? flag;
  final String? colorHex;
  final int orderIndex;

  bool get isImportant => sectionFlagIsImportant(flag);

  ViewSectionDef copyWith({
    String? name,
    String? flag,
    String? colorHex,
    int? orderIndex,
    bool clearFlag = false,
    bool clearColor = false,
  }) {
    return ViewSectionDef(
      name: name ?? this.name,
      flag: clearFlag ? null : (flag ?? this.flag),
      colorHex: clearColor ? null : (colorHex ?? this.colorHex),
      orderIndex: orderIndex ?? this.orderIndex,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (flag != null) 'flag': flag,
        if (colorHex != null) 'color': colorHex,
        'order': orderIndex,
      };

  factory ViewSectionDef.fromJson(Map<String, dynamic> json, int fallbackOrder) {
    return ViewSectionDef(
      name: '${json['name'] ?? ''}',
      flag: json['flag'] as String?,
      colorHex: json['color'] as String?,
      orderIndex: json['order'] as int? ?? fallbackOrder,
    );
  }
}

/// Helpers for `views.layout_config`.
abstract final class ViewLayoutConfig {
  static const displayModeKey = 'display_mode';
  static const sectionsKey = 'sections';
  static const topicOrderKey = 'topic_order';
  /// Frame keys (`section:<name>`, `section:` for uncategorized) — like [topicOrderKey].
  static const sectionOrderKey = 'section_order';

  static const modeBySection = 'by_section';
  static const modeByTopic = 'by_topic';

  static String displayMode(Map<String, dynamic> config) {
    final raw = config[displayModeKey];
    if (raw == modeByTopic) return modeByTopic;
    return modeBySection;
  }

  static Map<String, dynamic> withDisplayMode(
    Map<String, dynamic> config,
    String mode,
  ) {
    return {
      ...config,
      displayModeKey: mode == modeByTopic ? modeByTopic : modeBySection,
    };
  }

  static List<ViewSectionDef> sections(Map<String, dynamic> config) {
    final raw = config[sectionsKey];
    if (raw is! List) return const [];
    final out = <ViewSectionDef>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) continue;
      final def = ViewSectionDef.fromJson(
        Map<String, dynamic>.from(item),
        i,
      );
      if (def.name.trim().isEmpty) continue;
      out.add(def);
    }
    out.sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    return out;
  }

  static Map<String, dynamic> withSections(
    Map<String, dynamic> config,
    List<ViewSectionDef> sections,
  ) {
    final ordered = [
      for (var i = 0; i < sections.length; i++)
        sections[i].copyWith(orderIndex: i),
    ];
    return {
      ...config,
      sectionsKey: [for (final s in ordered) s.toJson()],
    };
  }

  static List<String> topicOrder(Map<String, dynamic> config) {
    return _dedupeStringList(config[topicOrderKey]);
  }

  static Map<String, dynamic> withTopicOrder(
    Map<String, dynamic> config,
    List<String> keys,
  ) {
    return {...config, topicOrderKey: _dedupeKeys(keys)};
  }

  static List<String> sectionOrder(Map<String, dynamic> config) {
    return _dedupeStringList(config[sectionOrderKey]);
  }

  static Map<String, dynamic> withSectionOrder(
    Map<String, dynamic> config,
    List<String> keys,
  ) {
    return {...config, sectionOrderKey: _dedupeKeys(keys)};
  }

  static List<String> _dedupeStringList(dynamic raw) {
    if (raw is! List) return const [];
    final seen = <String>{};
    return [
      for (final item in raw)
        if (seen.add('$item')) '$item',
    ];
  }

  static List<String> _dedupeKeys(List<String> keys) {
    final seen = <String>{};
    return [
      for (final k in keys)
        if (seen.add(k)) k,
    ];
  }
}
