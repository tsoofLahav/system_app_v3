import 'package:flutter/material.dart';

import '../core/platform/app_form_factor.dart';
import 'app_typography.dart';
import 'glass_surface.dart';

Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool useBottomSheet = true,
  bool isDismissible = true,
}) {
  // Phone uses showDialog — Scaffold already has a persistent bottom tools strip,
  // and nested modal bottom sheets are unreliable on iOS.
  if (isPhoneLayout) {
    return showDialog<T>(
      context: context,
      barrierDismissible: isDismissible,
      builder: builder,
    );
  }
  return showDialog<T>(
    context: context,
    barrierDismissible: isDismissible,
    builder: builder,
  );
}

/// Phone-friendly shell around [AppGlassDialog] content.
class AppAdaptiveDialogShell extends StatelessWidget {
  const AppAdaptiveDialogShell({
    super.key,
    required this.title,
    required this.child,
    this.actions = const [],
    this.width = 420,
  });

  final Widget title;
  final Widget child;
  final List<Widget> actions;
  final double width;

  @override
  Widget build(BuildContext context) {
    if (isPhoneLayout) {
      return Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.9,
            maxWidth: double.infinity,
          ),
          child: GlassSurface(
            borderRadius: BorderRadius.circular(20),
            tintOpacity: 0.94,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: DefaultTextStyle(
                    style: AppTypography.noteTitleStyle,
                    child: title,
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                    child: child,
                  ),
                ),
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return AppGlassDialog(
      title: title,
      actions: actions,
      width: width,
      child: child,
    );
  }
}
