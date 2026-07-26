import 'document_model.dart';

/// Undo/redo stack for document snapshots.
class DocumentEditHistory {
  final _undo = <RichDocument>[];
  final _redo = <RichDocument>[];
  static const _maxEntries = 50;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void record(RichDocument doc) {
    _undo.add(doc);
    if (_undo.length > _maxEntries) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  RichDocument? undo(RichDocument current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  RichDocument? redo(RichDocument current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }
}
