import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/tutorials/gesture_tolerance.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'hand_recognition.dart';

/// Measurements from the existing Home stream only. No extra camera, capture,
/// storage, threshold changes or diagnostic-only match overrides.
class HandDebugPanel extends StatelessWidget {
  const HandDebugPanel({
    super.key,
    required this.camera,
    required this.selectedHand,
    required this.status,
    required this.frames,
    required this.submitted,
    required this.results,
    required this.processing,
    required this.latencyMs,
    required this.now,
    required this.lastFrame,
    required this.lastResult,
    required this.resetReason,
    this.observation,
    this.nativeError,
  });
  final Widget camera;
  final String selectedHand, status, resetReason;
  final int frames, submitted, results, latencyMs;
  final bool processing;
  final Duration now;
  final Duration? lastFrame, lastResult;
  final HandObservation? observation;
  final String? nativeError;

  String _age(Duration? time) =>
      time == null ? 'none' : '${(now - time).inMilliseconds}ms ago';

  @override
  Widget build(BuildContext context) {
    final hand = observation;
    return Material(
      key: const ValueKey('home-hand-debug-panel'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: DefaultTextStyle(
          style: AppTypography.text(12, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                'Hand mode debug',
                style: AppTypography.text(
                  14,
                  21,
                  weight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 96,
                      height: 110,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          camera,
                          if (hand?.hasHand == true)
                            IgnorePointer(
                              child: CustomPaint(painter: _HandPoints(hand!)),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText('Selected: $selectedHand'),
                        LText(
                          'Detected: ${hand?.physicalHand.isNotEmpty == true ? hand!.physicalHand : 'none'}',
                        ),
                        LText('Points: ${hand?.points.length ?? 0}/21'),
                        LText(
                          'Hand confidence: ${hand?.handScore.toStringAsFixed(2) ?? '—'}',
                        ),
                        const LText('Need .75 (.70 for Down)'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LText(
                status,
                key: const ValueKey('home-hand-debug-status'),
                style: AppTypography.text(12, 18, color: AppColors.primary),
              ),
              const SizedBox(height: 8),
              LText(
                'Frames: $frames · Sent: $submitted · Results: $results',
                key: const ValueKey('home-hand-debug-counts'),
              ),
              LText('Camera: ${_age(lastFrame)} · Result: ${_age(lastResult)}'),
              LText(
                'Model: ${processing ? 'processing' : 'idle'} · Latency: ${latencyMs}ms',
              ),
              LText(
                'Native: ${hand?.gesture ?? 'none'} · Image label: ${hand?.hand ?? 'none'} · Mirrored: ${hand?.mirrored ?? false}',
              ),
              LText('Last reset: $resetReason'),
              if (nativeError != null)
                LText(
                  nativeError!,
                  key: const ValueKey('home-hand-debug-error'),
                  style: AppTypography.text(12, 18, color: AppColors.error),
                ),
              const SizedBox(height: 10),
              const LText('Pose fit / required score'),
              for (final step in gestureTutorialSteps.where(
                (step) => step.pose != HandPose.punch,
              ))
                Builder(
                  builder: (context) {
                    final fit = hand == null
                        ? null
                        : gestureMatch(hand, step.pose);
                    final tolerance = GestureTolerance.forPose(step.pose);
                    return LText(
                      '${step.title}: ${fit?.toStringAsFixed(2) ?? '—'} / ${tolerance.poseScore.toStringAsFixed(2)}',
                      style: AppTypography.text(
                        12,
                        18,
                        color: fit != null && fit >= tolerance.poseScore
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HandPoints extends CustomPainter {
  const _HandPoints(this.hand);
  final HandObservation hand;
  @override
  void paint(Canvas canvas, Size size) {
    if (!hand.imageSize.width.isFinite ||
        !hand.imageSize.height.isFinite ||
        hand.imageSize.width <= 0 ||
        hand.imageSize.height <= 0) {
      return;
    }
    final paint = Paint()..color = AppColors.primary;
    for (final point in hand.points) {
      canvas.drawCircle(
        handPointOnPreview(point, hand.imageSize, size),
        2,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HandPoints oldDelegate) =>
      oldDelegate.hand != hand;
}
