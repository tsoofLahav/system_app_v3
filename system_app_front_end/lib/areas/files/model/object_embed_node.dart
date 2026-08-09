/// Super Editor block node for an object pointer (`[INFO id="N"]`, etc.).
library;

import 'package:flutter/foundation.dart';
import 'package:super_editor/super_editor.dart';

import './document_text_codec.dart';

/// Custom Super Editor node representing a System App object embed.
@immutable
class ObjectEmbedNode extends BlockNode {
  ObjectEmbedNode({
    required this.id,
    required this.objectId,
    required this.objectType,
    super.metadata,
  }) {
    initAddToMetadata({
      'blockType': objectEmbedAttribution,
    });
  }

  static String idFor(int objectId) => 'embed:$objectId';

  static const objectEmbedAttribution = NamedAttribution('objectEmbed');

  @override
  final String id;
  final int objectId;
  final String objectType;

  @override
  String? copyContent(NodeSelection selection) {
    if (selection is! UpstreamDownstreamNodeSelection) return null;
    return !selection.isCollapsed
        ? DocumentTextCodec.pointerLine(objectId, objectType)
        : null;
  }

  @override
  bool hasEquivalentContent(DocumentNode other) {
    return other is ObjectEmbedNode &&
        other.objectId == objectId &&
        other.objectType == objectType;
  }

  @override
  DocumentNode copyWithAddedMetadata(Map<String, dynamic> newProperties) {
    return ObjectEmbedNode(
      id: id,
      objectId: objectId,
      objectType: objectType,
      metadata: {...metadata, ...newProperties},
    );
  }

  @override
  DocumentNode copyAndReplaceMetadata(Map<String, dynamic> newMetadata) {
    return ObjectEmbedNode(
      id: id,
      objectId: objectId,
      objectType: objectType,
      metadata: newMetadata,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ObjectEmbedNode &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          objectId == other.objectId &&
          objectType == other.objectType;

  @override
  int get hashCode => Object.hash(id, objectId, objectType);
}
