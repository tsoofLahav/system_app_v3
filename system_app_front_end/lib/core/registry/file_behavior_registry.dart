/// File-type behavior profiles: defaults and UX hints (not hard block restrictions).
class DefaultBlockSpec {
  const DefaultBlockSpec(this.type, [this.content = const {}]);

  final String type;
  final Map<String, dynamic> content;
}

class FileBehaviorProfile {
  const FileBehaviorProfile({
    required this.id,
    required this.defaultBlocks,
    required this.contextMenuBlocks,
    this.inlineInsertDefault = 'text',
  });

  final String id;
  final List<DefaultBlockSpec> defaultBlocks;
  final List<String> contextMenuBlocks;
  final String? inlineInsertDefault;
}

abstract final class FileBehaviorRegistry {
  static const _profiles = <String, FileBehaviorProfile>{
    'text': FileBehaviorProfile(
      id: 'text',
      defaultBlocks: [
        DefaultBlockSpec('text', {'text': ''}),
      ],
      contextMenuBlocks: ['header', 'text', 'summary', 'list', 'image'],
      inlineInsertDefault: 'text',
    ),
    'doc': FileBehaviorProfile(
      id: 'doc',
      defaultBlocks: [
        DefaultBlockSpec('table', {
          'rows': [
            ['', ''],
            ['', ''],
          ],
        }),
        DefaultBlockSpec('text', {'text': ''}),
      ],
      contextMenuBlocks: ['header', 'text', 'summary', 'graph'],
      inlineInsertDefault: 'text',
    ),
    'tasks': FileBehaviorProfile(
      id: 'tasks',
      defaultBlocks: [DefaultBlockSpec('task_list', {})],
      contextMenuBlocks: ['header', 'task_list'],
      inlineInsertDefault: null,
    ),
    'plan': FileBehaviorProfile(
      id: 'plan',
      defaultBlocks: [
        DefaultBlockSpec('text', {'text': ''}),
        DefaultBlockSpec('list', {
          'items': [
            {'text': ''},
          ],
        }),
        DefaultBlockSpec('text', {'text': ''}),
      ],
      contextMenuBlocks: ['header', 'text', 'summary', 'list', 'image'],
      inlineInsertDefault: 'text',
    ),
    'recap': FileBehaviorProfile(
      id: 'recap',
      defaultBlocks: [
        DefaultBlockSpec('summary', {'text': ''}),
        DefaultBlockSpec('task_list', {}),
        DefaultBlockSpec('table', {
          'rows': [
            ['Topic', 'Note'],
            ['', ''],
          ],
        }),
        DefaultBlockSpec('text', {'text': ''}),
      ],
      contextMenuBlocks: [
        'header',
        'text',
        'summary',
        'task_list',
        'table',
        'list',
      ],
      inlineInsertDefault: 'text',
    ),
    'board': FileBehaviorProfile(
      id: 'board',
      defaultBlocks: [DefaultBlockSpec('board', {'items': []})],
      contextMenuBlocks: const [],
      inlineInsertDefault: null,
    ),
    'execution': FileBehaviorProfile(
      id: 'execution',
      defaultBlocks: [
        DefaultBlockSpec('header', {'text': '', 'level': 2}),
        DefaultBlockSpec('list', {
          'items': [
            {'text': ''},
          ],
        }),
        DefaultBlockSpec('text', {'text': ''}),
      ],
      contextMenuBlocks: [
        'text',
        'header',
        'summary',
        'list',
        'graph',
        'image',
      ],
      inlineInsertDefault: 'text',
    ),
  };

  static const _fileTypeToProfile = <String, String>{
    'main': 'text',
    'text': 'text',
    'overview': 'recap',
    'plan': 'plan',
    'protocol': 'plan',
    'tasks': 'tasks',
    'doc': 'doc',
    'board': 'board',
    'execution': 'execution',
    'data': 'text',
  };

  static FileBehaviorProfile profileForFileType(String fileType) {
    final profileId = _fileTypeToProfile[fileType] ?? 'text';
    return _profiles[profileId] ?? _profiles['text']!;
  }

  static List<DefaultBlockSpec> defaultBlocksForFileType(String fileType) =>
      profileForFileType(fileType).defaultBlocks;

  static List<String> contextMenuForFileType(String fileType) =>
      profileForFileType(fileType).contextMenuBlocks;

  static String? inlineInsertForFileType(String fileType) =>
      profileForFileType(fileType).inlineInsertDefault;

  static bool showsTaskInputForFileType(String fileType) =>
      profileForFileType(fileType).id == 'tasks';

  static Map<String, dynamic> defaultContentForBlockType(String blockType) {
    for (final profile in _profiles.values) {
      for (final spec in profile.defaultBlocks) {
        if (spec.type == blockType) {
          return Map<String, dynamic>.from(spec.content);
        }
      }
    }
    switch (blockType) {
      case 'header':
        return {'text': '', 'level': 2};
      case 'text':
        return {'text': ''};
      case 'summary':
        return {'text': ''};
      case 'list':
        return {
          'items': [
            {'text': ''},
          ],
          'list_style': 'bullet',
        };
      case 'table':
        return {
          'rows': [
            ['', ''],
            ['', ''],
          ],
        };
      case 'graph':
        return {
          'chart_type': 'bar',
          'title': '',
          'labels': ['A', 'B', 'C'],
          'values': <double>[0, 0, 0],
          'palette_index': 0,
        };
      case 'task_list':
        return {};
      case 'image':
        return {'image_path': '', 'filename': ''};
      case 'board':
        return {'items': []};
      default:
        return {};
    }
  }
}
