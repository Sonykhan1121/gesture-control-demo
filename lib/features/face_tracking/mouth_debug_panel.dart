import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'mouth_tracking.dart';
import 'mouth_diagnostics.dart';

class MouthDebugPanel extends StatefulWidget {
  const MouthDebugPanel({
    super.key,
    required this.camera,
    required this.status,
    required this.motion,
    this.calibration,
    required this.measured,
    required this.jaw,
    required this.latencyMs,
    required this.reference,
    required this.capture,
    required this.guide,
    this.storage = '',
    required this.now,
    required this.onStart,
  });
  final Widget camera;
  final String status;
  final MouthMotion motion;
  final MouthCalibration? calibration;
  final MouthMeasurement? measured;
  final double jaw, reference;
  final int latencyMs;
  final MouthDiagnosticCapture capture;
  final MouthGuidedCheck guide;
  final String storage;
  final Duration now;
  final VoidCallback onStart;

  @override
  State<MouthDebugPanel> createState() => _MouthDebugPanelState();
}

class _MouthDebugPanelState extends State<MouthDebugPanel> {
  bool _details = false;

  @override
  Widget build(BuildContext context) {
    final camera = widget.camera,
        status = widget.status,
        motion = widget.motion,
        measured = widget.measured,
        jaw = widget.jaw,
        latencyMs = widget.latencyMs,
        reference = widget.reference,
        capture = widget.capture,
        storage = widget.storage,
        now = widget.now,
        guide = widget.guide;
    final complete =
        capture.history.length == 3 && storage == 'Saved on phone (3/3)';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: AppTypography.bodyFont,
            fontSize: 11,
            height: 1.35,
            color: AppColors.textPrimary,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LText(
                guide.running
                    ? 'Mouth check · ${guide.step}/3'
                    : complete
                    ? 'Done — results saved'
                    : widget.calibration != null
                    ? 'Mouth tracking'
                    : 'Mouth check',
                key: const ValueKey('mouth-debug-status'),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 96,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            camera,
                            if (measured != null)
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _MouthLandmarks(measured),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SingleChildScrollView(
                        child: _details
                            ? LText(
                                '$status\nLip gap: ${measured?.gapRatio.toStringAsFixed(3) ?? "missing"}\n'
                                'Gap range: ${(widget.calibration?.gapRest ?? MouthTuning.gapRest).toStringAsFixed(3)}–${(widget.calibration?.gapFull ?? MouthTuning.gapFull).toStringAsFixed(3)}\n'
                                'Width: ${measured?.widthRatio.toStringAsFixed(3) ?? "missing"} / ${reference.toStringAsFixed(3)}\n'
                                'Smile: ${measured?.smileValid == true ? measured!.smileScore.toStringAsFixed(2) : "missing"} (on ${(widget.calibration?.smileOn ?? MouthTuning.smileOn).toStringAsFixed(2)} / off ${(widget.calibration?.smileOff ?? MouthTuning.smileOff).toStringAsFixed(2)})\n'
                                'Jaw: ${jaw.toStringAsFixed(2)} · $latencyMs ms\n'
                                'Output open: ${motion.openness.toStringAsFixed(2)}\n'
                                'Output smile: ${motion.smile.toStringAsFixed(2)}\n'
                                'Output width: ${motion.widthScale.toStringAsFixed(2)}',
                                key: const ValueKey('mouth-debug-values'),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LText(
                                    guide.running
                                        ? guide.instruction
                                        : measured == null
                                        ? 'Show your face to start'
                                        : complete
                                        ? 'All done. Thank you!'
                                        : capture.history.length == 3
                                        ? 'Saving your results…'
                                        : widget.calibration != null
                                        ? 'Your saved tuning is active'
                                        : 'Tap Start and follow the prompts.',
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  if (guide.running)
                                    LText(
                                      guide.readyAt != null
                                          ? 'Get ready… ${guide.prepareSeconds(now)}'
                                          : 'Keep going… ${capture.secondsLeft(now).ceil()}',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                ],
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              LText(
                guide.running && !capture.active
                    ? 'Get ready for the next step'
                    : capture.active
                    ? '${capture.phase!.name}: ${capture.secondsLeft(now).toStringAsFixed(1)}s · ${capture.count} samples'
                    : (_details ? capture.summary : 'Relax → Smile → Talk'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                key: const ValueKey('mouth-debug-capture'),
              ),
              if (!guide.running)
                LText(
                  storage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  key: const ValueKey('mouth-debug-storage'),
                  style: const TextStyle(color: AppColors.primary),
                ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('mouth-check-start'),
                      onPressed: guide.running || measured == null
                          ? null
                          : widget.onStart,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.darkText,
                        minimumSize: const Size(0, 40),
                      ),
                      child: LText(
                        guide.running
                            ? 'Checking…'
                            : widget.calibration != null
                            ? 'Check again'
                            : 'Start mouth check',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _details = !_details),
                    key: const ValueKey('mouth-check-details'),
                    child: LText(
                      _details ? 'Hide details' : 'Details',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MouthLandmarks extends CustomPainter {
  const _MouthLandmarks(this.measured);
  final MouthMeasurement measured;
  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(
      size.width / measured.imageSize.width,
      size.height / measured.imageSize.height,
    );
    final crop = Offset(
      (size.width - measured.imageSize.width * scale) / 2,
      (size.height - measured.imageSize.height * scale) / 2,
    );
    final p = measured.points
        .take(6)
        .map(
          (v) =>
              Offset(
                v.dx * measured.imageSize.width * scale,
                v.dy * measured.imageSize.height * scale,
              ) +
              crop,
        )
        .toList();
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.5;
    canvas.drawLine(p[2], p[3], paint);
    for (final point in p) {
      canvas.drawCircle(point, 2.2, paint);
    }
  }

  @override
  bool shouldRepaint(_MouthLandmarks old) => old.measured != measured;
}
