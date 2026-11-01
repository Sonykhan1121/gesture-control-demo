import 'package:hand_gesture/l10n/app_strings.dart';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'eye_diagnostics.dart';
import 'eye_calibration.dart';
import 'face_tracking.dart';

class EyeDebugPanel extends StatefulWidget {
  const EyeDebugPanel({
    super.key,
    required this.camera,
    required this.sample,
    required this.check,
    required this.now,
    required this.storage,
    required this.status,
    required this.onStart,
    this.profile,
  });
  final Widget camera;
  final EyeDebugSample? sample;
  final EyeDiagnosticCheck check;
  final Duration now;
  final String storage, status;
  final VoidCallback onStart;
  final EyeBlinkProfile? profile;
  @override
  State<EyeDebugPanel> createState() => _EyeDebugPanelState();
}

class _EyeDebugPanelState extends State<EyeDebugPanel> {
  bool _details = false;
  String _eye(bool left) {
    final s = widget.sample;
    if (s == null) return 'WAIT';
    return (left ? s.leftClosed : s.rightClosed) ? 'CLOSED' : 'OPEN';
  }

  String _threshold(bool left, double fraction) {
    if (widget.sample?.usesLidGap == true) {
      return (fraction == .6 ? EyeGapTuning.closed : EyeGapTuning.reopen)
          .toStringAsFixed(3);
    }
    final p = widget.profile;
    if (p == null || !p.isValid) {
      return (fraction == .6 ? .55 : .30).toStringAsFixed(3);
    }
    final open = left ? p.leftOpen : p.rightOpen,
        closed = left ? p.leftClosed : p.rightClosed;
    return (open + (closed - open) * fraction).toStringAsFixed(3);
  }

  @override
  Widget build(BuildContext context) {
    final check = widget.check, s = widget.sample;
    final done =
        check.history.length == 4 && widget.storage == 'Saved on phone (4/4)';
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DefaultTextStyle(
          style: const TextStyle(
            fontFamily: AppTypography.bodyFont,
            fontSize: 11,
            height: 1.3,
            color: AppColors.textPrimary,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LText(
                check.running
                    ? 'Eye check · ${check.step}/4'
                    : done
                    ? 'Done — eye check saved'
                    : 'Eye debug',
                key: const ValueKey('eye-debug-status'),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 5),
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
                            widget.camera,
                            if (s != null)
                              IgnorePointer(
                                child: CustomPaint(
                                  painter: _EyeMarkers(s.measured),
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
                                '${widget.status}\n'
                                'Native L/R: ${s?.measured.rawLeft.toStringAsFixed(3) ?? "–"} / ${s?.measured.rawRight.toStringAsFixed(3) ?? "–"}\n'
                                'Screen L/R: ${s?.screenLeft.toStringAsFixed(3) ?? "–"} / ${s?.screenRight.toStringAsFixed(3) ?? "–"}\n'
                                'Relative L/R: ${s?.normalizedLeft.toStringAsFixed(2) ?? "–"} / ${s?.normalizedRight.toStringAsFixed(2) ?? "–"}\n'
                                'Close ${s?.usesLidGap == true ? "gap" : "score"} L/R: ${_threshold(true, .6)} / ${_threshold(false, .6)}\n'
                                'Reopen ${s?.usesLidGap == true ? "gap" : "score"} L/R: ${_threshold(true, .3)} / ${_threshold(false, .3)}\n'
                                'Lid gap L/R: ${s?.measured.leftAperture.toStringAsFixed(3) ?? "–"} / ${s?.measured.rightAperture.toStringAsFixed(3) ?? "–"}\n'
                                'Screen L uses native: ${s == null
                                    ? "–"
                                    : s.measured.screenLeftFromRight
                                    ? "Right"
                                    : "Left"}\n'
                                '${s?.latencyMs ?? 0} ms',
                                key: const ValueKey('eye-debug-values'),
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  LText(
                                    'Camera left: ${_eye(true)}',
                                    key: const ValueKey('eye-output-left'),
                                  ),
                                  LText(
                                    'Camera right: ${_eye(false)}',
                                    key: const ValueKey('eye-output-right'),
                                  ),
                                  const SizedBox(height: 8),
                                  LText(
                                    check.running
                                        ? check.instruction
                                        : s == null
                                        ? 'Show your face to start'
                                        : done
                                        ? 'Eye readings saved'
                                        : 'Tap Start eye check',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (check.running)
                                    LText(
                                      '${check.preparing ? "Get ready" : "Hold"}… ${check.secondsLeft(widget.now)}',
                                      style: const TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 14,
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
                check.running
                    ? 'Keep the other eye open for LEFT / RIGHT'
                    : widget.storage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                key: const ValueKey('eye-debug-storage'),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('eye-check-start'),
                      onPressed: check.running || s == null
                          ? null
                          : widget.onStart,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.darkText,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        minimumSize: const Size(0, 40),
                      ),
                      child: LText(
                        check.running ? 'Checking…' : 'Start eye check',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('eye-check-details'),
                    onPressed: () => setState(() => _details = !_details),
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

class _EyeMarkers extends CustomPainter {
  const _EyeMarkers(this.measured);
  final EyeMeasurement measured;
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
        .map(
          (v) =>
              Offset(
                v.dx * measured.imageSize.width * scale,
                v.dy * measured.imageSize.height * scale,
              ) +
              crop,
        )
        .toList();
    final firstLeft = (p[0].dx + p[1].dx) < (p[4].dx + p[5].dx);
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1;
    for (final base in [0, 4]) {
      canvas.drawLine(p[base + 2], p[base + 3], paint);
      for (var i = base; i < base + 4; i++) {
        canvas.drawCircle(p[i], 1.8, paint);
      }
      final label = (base == 0) == firstLeft ? 'L' : 'R';
      final text = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(fontSize: 11, color: AppColors.primary),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, (p[base] + p[base + 1]) / 2 + const Offset(-3, -17));
    }
  }

  @override
  bool shouldRepaint(_EyeMarkers old) => old.measured != measured;
}
