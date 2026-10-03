import '../../../../shared/utils/platform_text.dart';
import '../model/document_text_codec.dart';
import './editor_save_registry.dart';

/// Clipboard contains identity only; paste resolves the source into a new object.
Future<void> copyObjectPointer(int objectId, String objectType) async {
  await EditorSaveRegistry.flushObject(objectId);
  await setClipboardText(DocumentTextCodec.pointerLine(objectId, objectType));
}
