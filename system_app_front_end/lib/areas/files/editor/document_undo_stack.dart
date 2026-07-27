import '../model/document_model.dart';

class DocumentUndoStack {
  final _entries = <RichDocument>[];

  void push(RichDocument doc) {
    _entries.add(doc);
    if (_entries.length > 50) {
      _entries.removeAt(0);
    }
  }

  RichDocument? pop() {
    if (_entries.isEmpty) return null;
    return _entries.removeLast();
  }
}
