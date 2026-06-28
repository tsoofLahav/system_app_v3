import '../models/app_file.dart';

class RecommendedFile {
  const RecommendedFile({
    required this.name,
    required this.type,
    required this.isMain,
    this.orderIndex = 0,
  });

  final String name;
  final String type;
  final bool isMain;
  final int orderIndex;
}

class FileRegistry {
  static const mainTopicName = 'main';
  static const maxMainFilesPerTopic = 3;

  /// Every file type the app supports.
  static const allFileTypes = [
    RecommendedFile(name: 'Text', type: 'text', isMain: true, orderIndex: 0),
    RecommendedFile(
      name: 'Recap',
      type: 'overview',
      isMain: true,
      orderIndex: 1,
    ),
    RecommendedFile(name: 'Plan', type: 'plan', isMain: true, orderIndex: 2),
    RecommendedFile(
      name: 'Tasks',
      type: 'tasks',
      isMain: false,
      orderIndex: 3,
    ),
    RecommendedFile(
      name: 'Documentation',
      type: 'doc',
      isMain: false,
      orderIndex: 4,
    ),
  ];

  static const projectFiles = [
    RecommendedFile(
      name: 'Recap',
      type: 'overview',
      isMain: true,
      orderIndex: 0,
    ),
    RecommendedFile(name: 'Text', type: 'text', isMain: true, orderIndex: 1),
    RecommendedFile(name: 'Tasks', type: 'tasks', isMain: true, orderIndex: 2),
  ];

  static const processFiles = [
    RecommendedFile(
      name: 'Recap',
      type: 'overview',
      isMain: true,
      orderIndex: 0,
    ),
    RecommendedFile(name: 'Plan', type: 'plan', isMain: true, orderIndex: 1),
    RecommendedFile(name: 'Tasks', type: 'tasks', isMain: true, orderIndex: 2),
    RecommendedFile(
      name: 'Documentation',
      type: 'doc',
      isMain: false,
      orderIndex: 3,
    ),
  ];

  static const areaFiles = [
    RecommendedFile(name: 'Tasks', type: 'tasks', isMain: true, orderIndex: 0),
    RecommendedFile(
      name: 'Documentation',
      type: 'doc',
      isMain: false,
      orderIndex: 1,
    ),
  ];

  static List<RecommendedFile> recommendedForTopicType(String type) {
    switch (type) {
      case 'project':
        return projectFiles;
      case 'process':
        return processFiles;
      case 'area':
        return areaFiles;
      default:
        return areaFiles;
    }
  }

  static List<RecommendedFile> allowedFilesForTopic({
    required String topicType,
    required bool isMainTopic,
    required List<String> existingTypes,
  }) {
    final source = allFileTypes;
    return source.where((f) => !existingTypes.contains(f.type)).toList();
  }

  static bool isMainFile({
    required String topicType,
    required String fileType,
    required bool isMainTopic,
  }) {
    final source = isMainTopic
        ? allFileTypes
        : recommendedForTopicType(topicType);
    for (final file in source) {
      if (file.type == fileType) return file.isMain;
    }
    if (isMainTopic && fileType == 'main') return true;
    return false;
  }

  /// Resolved main/secondary visibility for a file (persisted override or registry default).
  static bool fileIsMain({
    required AppFile file,
    required String topicType,
    required bool isMainTopic,
  }) {
    if (file.isMain != null) return file.isMain!;
    return isMainFile(
      topicType: topicType,
      fileType: file.type,
      isMainTopic: isMainTopic,
    );
  }

  static RecommendedFile? definitionFor({
    required String topicType,
    required String fileType,
    required bool isMainTopic,
  }) {
    final source = isMainTopic
        ? allFileTypes
        : recommendedForTopicType(topicType);
    for (final file in source) {
      if (file.type == fileType) return file;
    }
    return null;
  }

  static String defaultNameForType(
    String fileType, {
    bool isMainTopic = false,
  }) {
    for (final file in allFileTypes) {
      if (file.type == fileType) return file.name;
    }
    return fileType;
  }
}
