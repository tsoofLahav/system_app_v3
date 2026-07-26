import 'block_text_focus.dart';

Future<void> runBlockTextAction(String action) async {
  switch (action) {
    case 'text:cut':
      await BlockTextFocusRegistry.cut();
    case 'text:copy':
      await BlockTextFocusRegistry.copy();
    case 'text:paste':
      await BlockTextFocusRegistry.paste();
    case 'text:bold':
    case 'text:italic':
    case 'text:underline':
    case 'text:size_up':
    case 'text:size_down':
      BlockTextFocusRegistry.applyTextFormat(action);
  }
}
