/// Makes Super Editor selection visible for RTL/Hebrew.
///
/// SE paints selection in a SuperText layer beneath the glyphs. That layer can
/// fail to show a wash for RTL runs even when selection boxes exist. Applying
/// a [BackgroundColorAttribution] after the selection styler paints the mark as
/// span background (same path as bold/color), which is direction-safe.
library;

import 'package:flutter/painting.dart';
import 'package:super_editor/super_editor.dart';

import '../../../shared/utils/platform_text.dart';

/// Appends a post-selection style phase that fills the selected span.
class VisibleSelectionPlugin extends SuperEditorPlugin {
  VisibleSelectionPlugin({required Color color}) : _phase = _SelectionBackgroundPhase(color);

  final _SelectionBackgroundPhase _phase;

  @override
  List<SingleColumnLayoutStylePhase> get appendedStylePhases => [_phase];
}

class _SelectionBackgroundPhase extends SingleColumnLayoutStylePhase {
  _SelectionBackgroundPhase(this.color);

  final Color color;

  @override
  SingleColumnLayoutViewModel style(
    Document document,
    SingleColumnLayoutViewModel viewModel,
  ) {
    return SingleColumnLayoutViewModel(
      padding: viewModel.padding,
      componentViewModels: [
        for (final vm in viewModel.componentViewModels) _apply(vm.copy()),
      ],
    );
  }

  SingleColumnLayoutComponentViewModel _apply(
    SingleColumnLayoutComponentViewModel vm,
  ) {
    if (vm is! TextComponentViewModel) return vm;
    final sel = vm.selection;
    if (sel == null || sel.isCollapsed) return vm;

    final plain = vm.text.toPlainText();
    if (plain.isEmpty) return vm;
    final (start, end) = normalizeUtf16Range(plain, sel.start, sel.end);
    if (end <= start) return vm;

    final last = (end - 1).clamp(0, plain.length - 1);
    if (last < start) return vm;

    vm.text = vm.text.copy()
      ..addAttribution(
        BackgroundColorAttribution(color),
        SpanRange(start, last),
        overwriteConflictingSpans: true,
      );
    // Keep the beneath-layer color in sync (LTR still uses it).
    vm.selectionColor = color;
    return vm;
  }
}
