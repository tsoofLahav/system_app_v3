import 'package:flutter_test/flutter_test.dart';
import 'package:system_app_front_end/areas/files/rich_text/formatted_text_field.dart';
import 'package:system_app_front_end/areas/objects/tasks/task_list_surface.dart';

void main() {
  test('keeps pasted text instead of an empty create payload', () {
    expect(
      keepLocalTaskTitle(
        local: 'Pasted line',
        incoming: '',
        focused: false,
        savePending: false,
      ),
      isTrue,
    );
  });

  test('keeps the field while it is focused or a save is in flight', () {
    expect(
      keepLocalTaskTitle(
        local: 'Still typing',
        incoming: '',
        focused: true,
        savePending: false,
      ),
      isTrue,
    );
    expect(
      keepLocalTaskTitle(
        local: 'Queued',
        incoming: 'old',
        focused: false,
        savePending: true,
      ),
      isTrue,
    );
  });

  test('takes a real inbound title when the local field is clean and empty', () {
    expect(
      keepLocalTaskTitle(
        local: '',
        incoming: 'From the server',
        focused: false,
        savePending: false,
      ),
      isFalse,
    );
    expect(
      keepLocalTaskTitle(
        local: imeEmptySentinel,
        incoming: 'From the server',
        focused: false,
        savePending: false,
      ),
      isFalse,
    );
  });
}
