import 'package:flutter/material.dart';

import '../../ui/app_colors.dart';
import '../../ui/app_typography.dart';

/// A name row wearing the topic colour — used on phone lists (bring, reorder).
class PhoneTintedNameTile extends StatelessWidget {
  const PhoneTintedNameTile({
    super.key,
    required this.title,
    required this.fileId,
    this.kicker,
    this.subtitle,
    this.accent,
    this.isMainTopic = false,
    this.onTap,
    this.trailing,
  });

  final String title;
  final int fileId;
  final String? kicker;
  final String? subtitle;
  final Color? accent;
  final bool isMainTopic;
  final VoidCallback? onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final decoration = accent == null
        ? AppColors.noteDecoration()
        : AppColors.filePaneDecoration(
            accent!,
            fileId,
            isMainTopic: isMainTopic,
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: DecoratedBox(
            decoration: decoration,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (kicker != null && kicker!.trim().isNotEmpty) ...[
                          Text(
                            kicker!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.metaStyle,
                          ),
                          const SizedBox(height: 2),
                        ],
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.noteBodyStyle.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.metaStyle,
                          ),
                        ],
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
