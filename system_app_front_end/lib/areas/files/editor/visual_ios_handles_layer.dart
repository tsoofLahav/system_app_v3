import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:super_editor/super_editor.dart';

import '../../ui/app_colors.dart';
import '../rich_text/rtl/ios_visual_handles.dart';

/// iOS handles whose expanded stems keep Super Editor identity and sit on
/// the tight wash (RTL-safe).
class VisualIosHandlesDocumentLayerBuilder
    extends SuperEditorIosHandlesDocumentLayerBuilder {
  const VisualIosHandlesDocumentLayerBuilder({
    super.handleColor,
    super.caretWidth,
    super.handleBallDiameter,
  });

  @override
  ContentLayerWidget build(
    BuildContext context,
    SuperEditorContext editContext,
  ) {
    if (defaultTargetPlatform != TargetPlatform.iOS ||
        SuperEditorIosControlsScope.maybeNearestOf(context) == null) {
      return const ContentLayerProxyWidget(child: SizedBox.shrink());
    }

    final controls = SuperEditorIosControlsScope.rootOf(context);
    return VisualIosHandlesDocumentLayer(
      document: editContext.document,
      documentLayout: editContext.documentLayout,
      selection: editContext.composer.selectionNotifier,
      changeSelection: (newSelection, changeType, reason) {
        editContext.editor.execute([
          ChangeSelectionRequest(newSelection, changeType, reason),
          const ClearComposingRegionRequest(),
        ]);
      },
      areSelectionHandlesAllowed: controls.areSelectionHandlesAllowed,
      handleBeingDragged: controls.handleBeingDragged,
      handleColor: handleColor ?? controls.handleColor ?? AppColors.primary,
      caretWidth: caretWidth ?? 2,
      handleBallDiameter: handleBallDiameter ?? defaultIosHandleBallDiameter,
      shouldCaretBlink: controls.shouldCaretBlink,
      floatingCursorController: controls.floatingCursorController,
    );
  }
}

class VisualIosHandlesDocumentLayer extends IosHandlesDocumentLayer {
  const VisualIosHandlesDocumentLayer({
    super.key,
    required super.document,
    required super.documentLayout,
    required super.selection,
    required super.changeSelection,
    super.areSelectionHandlesAllowed,
    super.handleBeingDragged,
    required super.handleColor,
    super.caretWidth,
    super.handleBallDiameter,
    required super.shouldCaretBlink,
    super.floatingCursorController,
    super.showDebugPaint,
  });

  @override
  DocumentLayoutLayerState<IosHandlesDocumentLayer, DocumentSelectionLayout>
  createState() => _VisualIosHandlesState();
}

// Super Editor marks this State @visibleForTesting. We only replace
// expanded-handle geometry so Hebrew stems sit on the wash.
// ignore: invalid_use_of_visible_for_testing_member
class _VisualIosHandlesState extends IosControlsDocumentLayerState {
  @override
  DocumentSelectionLayout? computeLayoutDataWithDocumentLayout(
    BuildContext contentLayersContext,
    BuildContext documentContext,
    DocumentLayout documentLayout,
  ) {
    final selection = widget.selection.value;
    if (selection != null && !selection.isCollapsed) {
      final visual = visualIosExpandedHandleLayout(
        document: widget.document,
        documentLayout: documentLayout,
        selection: selection,
      );
      if (visual != null) return visual;
    }
    return super.computeLayoutDataWithDocumentLayout(
      contentLayersContext,
      documentContext,
      documentLayout,
    );
  }
}
