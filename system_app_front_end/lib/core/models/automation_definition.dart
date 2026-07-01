class AutomationDefinition {
  const AutomationDefinition({
    required this.key,
    required this.name,
    required this.description,
    required this.actionType,
    required this.scopeFixed,
    required this.scopeAllowedKinds,
    required this.activations,
    required this.bindings,
    this.companion,
    this.ai,
    required this.timezoneDefault,
    required this.fanOut,
    this.defaultSchedule,
    required this.defaultEnabled,
    required this.defaultParams,
  });

  final String key;
  final String name;
  final String description;
  final String actionType;
  final Map<String, dynamic> scopeFixed;
  final List<String> scopeAllowedKinds;
  final List<String> activations;
  final List<AutomationFileBinding> bindings;
  final AutomationCompanionDefinition? companion;
  final AutomationAiDefinition? ai;
  final String timezoneDefault;
  final bool fanOut;
  final String? defaultSchedule;
  final bool defaultEnabled;
  final Map<String, dynamic> defaultParams;

  bool supportsActivation(String triggerType) {
    if (activations.contains(triggerType)) return true;
    return triggerType == 'manual';
  }

  String get scopeLabel {
    final kind = scopeFixed['kind'] as String? ?? 'all';
    return switch (kind) {
      'topic_type' => scopeFixed['topic_type'] as String? ?? 'topics',
      'topic' => scopeFixed['topic_name'] as String? ?? 'topic',
      _ => 'all topics',
    };
  }

  factory AutomationDefinition.fromJson(Map<String, dynamic> json) {
    final rawBindings = json['bindings'];
    final rawCompanion = json['companion'];
    final rawAi = json['ai'];
    final rawScope = json['scope'];
    final scopeMap = rawScope is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawScope)
        : <String, dynamic>{};
    final rawDefaultParams = json['default_params'];

    return AutomationDefinition(
      key: json['key'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      actionType: json['action_type'] as String,
      scopeFixed: Map<String, dynamic>.from(
        scopeMap['fixed'] as Map? ?? const {},
      ),
      scopeAllowedKinds: [
        for (final kind in scopeMap['allowed_kinds'] as List? ?? const [])
          kind.toString(),
      ],
      activations: [
        for (final activation in json['activations'] as List? ?? const [])
          activation.toString(),
      ],
      bindings: rawBindings is List
          ? rawBindings
              .map(
                (entry) => AutomationFileBinding.fromJson(
                  entry as Map<String, dynamic>,
                ),
              )
              .toList()
          : const [],
      companion: rawCompanion is Map<String, dynamic>
          ? AutomationCompanionDefinition.fromJson(rawCompanion)
          : null,
      ai: rawAi is Map<String, dynamic>
          ? AutomationAiDefinition.fromJson(rawAi)
          : null,
      timezoneDefault: json['timezone_default'] as String? ?? 'UTC',
      fanOut: json['fan_out'] as bool? ?? true,
      defaultSchedule: json['default_schedule'] as String?,
      defaultEnabled: json['default_enabled'] as bool? ?? true,
      defaultParams: rawDefaultParams is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawDefaultParams)
          : const {},
    );
  }
}

class AutomationFileBinding {
  const AutomationFileBinding({
    required this.role,
    required this.match,
  });

  final String role;
  final Map<String, dynamic> match;

  factory AutomationFileBinding.fromJson(Map<String, dynamic> json) {
    return AutomationFileBinding(
      role: json['role'] as String,
      match: Map<String, dynamic>.from(json['match'] as Map? ?? const {}),
    );
  }
}

class AutomationCompanionDefinition {
  const AutomationCompanionDefinition({
    required this.enabled,
    required this.flowKey,
    required this.titleTemplate,
    required this.defaultViewType,
    required this.defaultSectionName,
  });

  final bool enabled;
  final String flowKey;
  final String titleTemplate;
  final String defaultViewType;
  final String defaultSectionName;

  factory AutomationCompanionDefinition.fromJson(Map<String, dynamic> json) {
    return AutomationCompanionDefinition(
      enabled: json['enabled'] as bool? ?? true,
      flowKey: json['flow_key'] as String? ?? 'process_update_review',
      titleTemplate:
          json['title_template'] as String? ?? 'Review update: {topic_name}',
      defaultViewType: json['default_view_type'] as String? ?? 'daily',
      defaultSectionName:
          json['default_section_name'] as String? ?? 'Process updates',
    );
  }
}

class AutomationAiDefinition {
  const AutomationAiDefinition({
    this.actionKey,
    required this.proposalTypes,
    required this.reviewDocuments,
  });

  final String? actionKey;
  final List<String> proposalTypes;
  final List<String> reviewDocuments;

  factory AutomationAiDefinition.fromJson(Map<String, dynamic> json) {
    return AutomationAiDefinition(
      actionKey: json['action_key'] as String?,
      proposalTypes: [
        for (final type in json['proposal_types'] as List? ?? const [])
          type.toString(),
      ],
      reviewDocuments: [
        for (final doc in json['review_documents'] as List? ?? const [])
          doc.toString(),
      ],
    );
  }
}
