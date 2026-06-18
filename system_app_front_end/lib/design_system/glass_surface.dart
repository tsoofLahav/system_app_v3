import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Shared glass parameters — use presets instead of ad-hoc values.
class GlassStyleSpec {
  const GlassStyleSpec({
    required this.blurSigma,
    required this.tintOpacity,
    this.tintColor,
    this.showTopHighlight = true,
    this.elevation = 0,
    this.border,
  });

  final double blurSigma;
  final double tintOpacity;
  final Color? tintColor;
  final bool showTopHighlight;
  final double elevation;
  final BoxBorder? border;
}

abstract final class AppGlassStyle {
  static const dialogTint = Color(0xFFDDF6F2);
  static const floatingRadius = 16.0;
  static const dialogRadius = 22.0;
  static const pillRadius = 999.0;

  static BoxBorder get _dialogBorder => Border.all(
        color: Colors.white.withValues(alpha: 0.68),
        width: 0.85,
      );

  static BoxBorder aiBorder([double alpha = 0.45]) => Border.all(
        color: AppColors.aiCyan.withValues(alpha: alpha),
        width: 0.85,
      );

  static const dialog = GlassStyleSpec(
    blurSigma: 24,
    tintOpacity: 0.78,
    tintColor: dialogTint,
    showTopHighlight: true,
    elevation: 7,
    border: null,
  );

  static final floating = GlassStyleSpec(
    blurSigma: 24,
    tintOpacity: 0.78,
    tintColor: dialogTint,
    showTopHighlight: true,
    elevation: 4,
    border: _dialogBorder,
  );

  static final aiAccent = GlassStyleSpec(
    blurSigma: 24,
    tintOpacity: 0.82,
    tintColor: dialogTint,
    showTopHighlight: true,
    elevation: 5,
    border: aiBorder(0.5),
  );
}

/// Frosted glass panel — blurs content behind it (liquid glass).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.style,
    this.borderRadius,
    this.blurSigma = 10,
    this.tintOpacity = 0.16,
    this.tintColor,
    this.showTopHighlight = true,
    this.border,
    this.padding,
    this.elevation = 0,
  });

  factory GlassSurface.styled({
    required GlassStyleSpec style,
    required Widget child,
    BorderRadius? borderRadius,
    EdgeInsetsGeometry? padding,
    BoxBorder? border,
    bool? showTopHighlight,
    double? elevation,
  }) {
    return GlassSurface(
      borderRadius: borderRadius,
      blurSigma: style.blurSigma,
      tintOpacity: style.tintOpacity,
      tintColor: style.tintColor,
      showTopHighlight: showTopHighlight ?? style.showTopHighlight,
      border: border ?? style.border,
      padding: padding,
      elevation: elevation ?? style.elevation,
      child: child,
    );
  }

  final Widget child;
  final GlassStyleSpec? style;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final double tintOpacity;
  final Color? tintColor;
  final bool showTopHighlight;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    final resolved = style;
    final radius = borderRadius ?? BorderRadius.zero;
    final highlight = Colors.white;
    final effectiveBlur = resolved?.blurSigma ?? blurSigma;
    final effectiveTintOpacity = resolved?.tintOpacity ?? tintOpacity;
    final effectiveTintColor = resolved?.tintColor ?? tintColor;
    final effectiveHighlight = resolved?.showTopHighlight ?? showTopHighlight;
    final effectiveElevation = resolved?.elevation ?? elevation;
    final effectiveBorder = resolved?.border ?? border;

    Color blendTint(double alpha) {
      final base = Colors.white.withValues(alpha: alpha);
      if (effectiveTintColor == null) return base;
      return Color.alphaBlend(
        effectiveTintColor.withValues(alpha: alpha * 0.42),
        base,
      );
    }

    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: effectiveBlur,
          sigmaY: effectiveBlur,
        ),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border: effectiveBorder ??
                      Border.all(
                        color: highlight.withValues(alpha: 0.62),
                        width: 0.85,
                      ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      blendTint(effectiveTintOpacity + 0.06),
                      blendTint(effectiveTintOpacity - 0.02),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (effectiveTintColor ?? AppColors.noteShadow)
                          .withValues(
                        alpha: effectiveTintColor != null ? 0.1 : 0.05,
                      ),
                      blurRadius: 20 + effectiveElevation,
                      offset: Offset(0, 5 + effectiveElevation * 0.5),
                    ),
                  ],
                ),
              ),
            ),
            if (effectiveHighlight)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: radius,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: const Alignment(0, 0.55),
                        colors: [
                          Colors.white.withValues(alpha: 0.42),
                          Colors.white.withValues(alpha: 0.06),
                          Colors.transparent,
                        ],
                        stops: const [0, 0.35, 1],
                      ),
                    ),
                  ),
                ),
              ),
            content,
          ],
        ),
      ),
    );
  }
}

/// Capsule segment for the bottom bar and similar floating tool groups.
class GlassBarSegment extends StatelessWidget {
  const GlassBarSegment({
    super.key,
    required this.child,
    this.style,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
    this.label,
  });

  final Widget child;
  final GlassStyleSpec? style;
  final double? height;
  final EdgeInsetsGeometry padding;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final segment = GlassSurface.styled(
      style: style ?? AppGlassStyle.floating,
      borderRadius: BorderRadius.circular(AppGlassStyle.pillRadius),
      padding: padding,
      child: height != null
          ? SizedBox(height: height, child: child)
          : child,
    );

    if (label == null) return segment;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        segment,
        Positioned(
          top: -5,
          left: 0,
          right: 0,
          child: Center(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppGlassStyle.dialogTint.withValues(alpha: 0.92),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: Text(
                  label!,
                  style: AppTypography.metaStyle.copyWith(
                    fontSize: 9,
                    letterSpacing: 0.6,
                    color: AppColors.aiCyan.withValues(alpha: 0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Floating glass capsule with horizontal inset from the window edges.
class FloatingGlassPill extends StatelessWidget {
  const FloatingGlassPill({
    super.key,
    required this.child,
    this.horizontalMargin = 20,
    this.verticalMargin = 0,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.expandWidth = false,
  });

  final Widget child;
  final double horizontalMargin;
  final double verticalMargin;
  final double? height;
  final EdgeInsetsGeometry padding;
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final surface = GlassSurface.styled(
      style: AppGlassStyle.floating,
      borderRadius: BorderRadius.circular(AppGlassStyle.pillRadius),
      padding: padding,
      child: height != null
          ? SizedBox(
              width: expandWidth ? double.infinity : null,
              height: height,
              child: child,
            )
          : child,
    );

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical: verticalMargin,
      ),
      child: expandWidth ? surface : Center(child: surface),
    );
  }
}

/// Small circular glass control — always neutral (no topic tint).
class GlassCircleButton extends StatelessWidget {
  const GlassCircleButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.size = 34,
    this.iconSize = 16,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GlassSurface.styled(
        style: AppGlassStyle.floating,
        borderRadius: BorderRadius.circular(AppGlassStyle.pillRadius),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: Icon(
                  icon,
                  size: iconSize,
                  color: AppColors.text.withValues(alpha: 0.78),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppGlassDialog extends StatelessWidget {
  const AppGlassDialog({
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
    final separator = AppColors.text.withValues(alpha: 0.11);
    final actionText = AppTypography.metaStyle.copyWith(
      color: AppColors.text.withValues(alpha: 0.88),
      fontSize: 12,
    );

    return Dialog(
      elevation: 0,
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: GlassSurface.styled(
          style: AppGlassStyle.dialog,
          borderRadius: BorderRadius.circular(AppGlassStyle.dialogRadius),
          border: AppGlassStyle._dialogBorder,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.center,
                child: DefaultTextStyle(
                  textAlign: TextAlign.center,
                  style: AppTypography.noteTitleStyle.copyWith(
                    fontSize: 15,
                    color: AppColors.text.withValues(alpha: 0.94),
                  ),
                  child: title,
                ),
              ),
              const SizedBox(height: 12),
              _GlassDivider(color: separator),
              const SizedBox(height: 12),
              DefaultTextStyle(
                style: AppTypography.noteBodyStyle.copyWith(
                  fontSize: 12,
                  color: AppColors.text.withValues(alpha: 0.9),
                ),
                child: child,
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                _GlassDivider(color: separator),
                const SizedBox(height: 10),
                DefaultTextStyle(
                  style: actionText,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      for (var i = 0; i < actions.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassDivider extends StatelessWidget {
  const _GlassDivider({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 0.8,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
