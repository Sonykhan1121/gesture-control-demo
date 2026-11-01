import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';

/// The approved Hand-mode notice design, shared by all transient messages.
class AppToastCard extends StatelessWidget {
  const AppToastCard({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    constraints: const BoxConstraints(minHeight: 56),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: AppColors.noticeSurface,
      border: Border.all(color: AppColors.primary),
      borderRadius: BorderRadius.circular(8),
    ),
    child: LText(
      message,
      textAlign: TextAlign.center,
      style: AppTypography.text(
        16,
        24,
        color: AppColors.primary,
        weight: FontWeight.w500,
      ),
    ),
  );
}

abstract final class AppToast {
  static void show(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        content: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppToastCard(message: message),
          ),
        ),
      ),
    );
  }
}
