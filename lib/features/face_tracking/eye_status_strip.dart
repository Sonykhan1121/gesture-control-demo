import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'eye_diagnostics.dart';

/// Optional camera eye classifications; the avatar uses its own blink timer.
class EyeStatusStrip extends StatelessWidget {
  const EyeStatusStrip({super.key, required this.sample});
  final EyeDebugSample? sample;

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final left in [true, false]) ...[
        if (!left) const SizedBox(width: 8),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: LText(
              'Your ${left ? "left" : "right"} eye\n${sample == null
                  ? "NO READING"
                  : (left ? sample!.leftClosed : sample!.rightClosed)
                  ? "CLOSED"
                  : "OPEN"}',
              key: ValueKey(left ? 'live-eye-left' : 'live-eye-right'),
              textAlign: TextAlign.center,
              style: AppTypography.text(12, 18, color: AppColors.textPrimary),
            ),
          ),
        ),
      ],
    ],
  );
}
