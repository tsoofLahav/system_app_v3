/// Catalog of supported block types. File type does not restrict rendering.
abstract final class BlockRegistry {
  static const allBlockTypes = [
    'header',
    'text',
    'summary',
    'list',
    'task_list',
    'task',
    'image',
    'table',
    'graph',
    'measurement',
    'board',
    'details',
  ];

  static bool isKnownBlockType(String blockType) =>
      allBlockTypes.contains(blockType);
}
