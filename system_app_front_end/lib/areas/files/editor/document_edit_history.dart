/// Undo/redo stack for marker-text buffer snapshots.
class DocumentEditHistory {
  final _undo = <String>[];
  final _redo = <String>[];
  static const _maxEntries = 50;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  void record(String text) {
    _undo.add(text);
    if (_undo.length > _maxEntries) {
      _undo.removeAt(0);
    }
    _redo.clear();
  }

  String? undo(String current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  String? redo(String current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }
}
