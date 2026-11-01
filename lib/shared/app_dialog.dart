import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/l10n/app_strings.dart';

/// Approved centered dialog: bounded width, readable copy and pill actions.
/// Long content and short/keyboard-reduced windows scroll without scaling text.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.icon,
    this.message,
    this.content,
    this.actions = const [],
    this.leading,
  });
  final String title;
  final IconData icon;
  final String? message;
  final Widget? content, leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Dialog(
      backgroundColor: AppColors.dialogSurface,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      constraints: const BoxConstraints(maxWidth: 420),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.white.withValues(alpha: .05)),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: math.max(
            0,
            media.size.height -
                media.viewInsets.vertical -
                media.padding.vertical -
                48,
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 54,
                  height: 54,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  alignment: Alignment.center,
                  child:
                      leading ?? Icon(icon, size: 25, color: AppColors.primary),
                ),
              ),
              const SizedBox(height: 20),
              Semantics(
                namesRoute: true,
                child: LText(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTypography.text(23, 29, weight: FontWeight.w500),
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                LText(
                  message!,
                  textAlign: TextAlign.center,
                  style: AppTypography.text(
                    15,
                    24,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              if (content != null) ...[const SizedBox(height: 20), content!],
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 28),
                // Wrap translated labels naturally within equally sized actions.
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 12),
                      Expanded(child: actions[i]),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

Widget appDialogAction(
  String label,
  VoidCallback? onPressed, {
  bool primary = true,
  Key? key,
}) {
  final text = LText(
    label,
    textAlign: TextAlign.center,
    style: AppTypography.text(
      15,
      20,
      weight: FontWeight.w500,
      color: primary ? AppColors.darkText : AppColors.textPrimary,
    ),
  );
  const padding = EdgeInsets.symmetric(horizontal: 16, vertical: 14);
  return primary
      ? FilledButton(
          key: key,
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.darkText,
            minimumSize: const Size(0, 48),
            padding: padding,
            shape: const StadiumBorder(),
          ),
          child: text,
        )
      : OutlinedButton(
          key: key,
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.textPrimary,
            side: const BorderSide(color: AppColors.border),
            minimumSize: const Size(0, 48),
            padding: padding,
            shape: const StadiumBorder(),
          ),
          child: text,
        );
}
