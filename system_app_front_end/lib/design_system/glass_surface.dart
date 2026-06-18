import 'dart:ui';

import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Frosted glass panel — blurs content behind it (liquid glass).
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius,
    this.blurSigma = 10,
    this.tintOpacity = 0.16,
    this.tintColor,
    this.showTopHighlight = true,
    this.border,
    this.padding,
    this.elevation = 0,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final double blurSigma;
  final double tintOpacity;
  final Color? tintColor;
  final bool showTopHighlight;
  final BoxBorder? border;
  final EdgeInsetsGeometry? padding;
  final double elevation;

  Color _blendTint(double alpha) {
    final base = Colors.white.withValues(alpha: alpha);
    if (tintColor == null) return base;
    return Color.alphaBlend(tintColor!.withValues(alpha: alpha * 0.42), base);
  }

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    final highlight = Colors.white;

    final content = padding != null
        ? Padding(padding: padding!, child: child)
        : child;

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: radius,
                  border:
                      border ??
                      Border.all(
                        color: highlight.withValues(alpha: 0.62),
                        width: 0.85,
                      ),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      _blendTint(tintOpacity + 0.06),
                      _blendTint(tintOpacity - 0.02),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (tintColor ?? AppColors.noteShadow).withValues(
                        alpha: tintColor != null ? 0.1 : 0.05,
                      ),
                      blurRadius: 20 + elevation,
                      offset: Offset(0, 5 + elevation * 0.5),
                    ),
                  ],
                ),
              ),
            ),
            if (showTopHighlight)
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
            // Non-positioned child gives the Stack its size.
            content,
          ],
        ),
      ),
    );
  }
}

/// Floating glass capsule with horizontal inset from the window edges.
class FloatingGlassPill extends StatelessWidget {
  const FloatingGlassPill({
    super.key,
    required this.child,
    this.tintColor,
    this.horizontalMargin = 20,
    this.verticalMargin = 0,
    this.height,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    this.blurSigma = 10,
    this.tintOpacity = 0.16,
    this.expandWidth = false,
  });

  final Widget child;
  final Color? tintColor;
  final double horizontalMargin;
  final double verticalMargin;
  final double? height;
  final EdgeInsetsGeometry padding;
  final double blurSigma;
  final double tintOpacity;
  final bool expandWidth;

  @override
  Widget build(BuildContext context) {
    final surface = GlassSurface(
      borderRadius: BorderRadius.circular(999),
      blurSigma: blurSigma,
      tintOpacity: tintOpacity,
      tintColor: tintColor,
      showTopHighlight: true,
      elevation: 2,
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
      child: GlassSurface(
        borderRadius: BorderRadius.circular(999),
        blurSigma: 10,
        tintOpacity: 0.14,
        showTopHighlight: true,
        elevation: 2,
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
        child: GlassSurface(
          borderRadius: BorderRadius.circular(22),
          blurSigma: 24,
          tintOpacity: 0.78,
          tintColor: const Color(0xFFDDF6F2),
          showTopHighlight: true,
          elevation: 7,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.68),
            width: 0.85,
          ),
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
