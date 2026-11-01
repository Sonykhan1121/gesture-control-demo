import 'package:hand_gesture/l10n/app_strings.dart';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';

/// Use screen orientation rather than the keyboard-reduced body constraints.
bool landscapeLayout(BuildContext context) =>
    MediaQuery.orientationOf(context) == Orientation.landscape;

/// Shared landscape frame. A short viewport can scroll without shrinking text.
class LandscapePage extends StatelessWidget {
  const LandscapePage({
    super.key,
    required this.title,
    required this.onBack,
    required this.child,
    this.action,
    this.subtitle,
  });
  final String title;
  final VoidCallback onBack;
  final Widget child;
  final Widget? action;
  final Widget? subtitle;
  @override
  Widget build(BuildContext context) => SafeArea(
    minimum: const EdgeInsets.fromLTRB(20, 8, 20, 12),
    child: LayoutBuilder(
      builder: (context, bounds) => SingleChildScrollView(
        child: SizedBox(
          height: math.max(280, bounds.maxHeight),
          child: Column(
            children: [
              SizedBox(
                height: subtitle == null ? 44 : 68,
                child: Row(
                  children: [
                    SizedBox(
                      width: 44,
                      child: IconButton(
                        tooltip: tr(context, 'Back'),
                        onPressed: onBack,
                        style: IconButton.styleFrom(
                          backgroundColor: AppColors.surface,
                        ),
                        icon: const Icon(CupertinoIcons.chevron_back, size: 20),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          LText(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTypography.text(
                              24,
                              32,
                              weight: FontWeight.w700,
                            ),
                          ),
                          if (subtitle != null) subtitle!,
                        ],
                      ),
                    ),
                    SizedBox(width: 44, child: action),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget landscapeAction(
  String label,
  VoidCallback? onPressed, {
  bool secondary = false,
  Key? key,
}) => SizedBox(
  height: 44,
  child: secondary
      ? OutlinedButton(
          key: key,
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            shape: const StadiumBorder(),
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.textPrimary),
          ),
          child: LText(label),
        )
      : FilledButton(
          key: key,
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            shape: const StadiumBorder(),
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.background,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: .35),
            disabledForegroundColor: AppColors.textSecondary,
          ),
          child: LText(label),
        ),
);
