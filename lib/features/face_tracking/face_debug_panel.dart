import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'face_tracking.dart';

/// Live positions only. Avatar coordinates come from the same animation tick
/// as the rendered transform, rather than its eventual target.
class FaceLocationDebugPanel extends StatelessWidget {
  const FaceLocationDebugPanel({
    super.key,
    required this.camera,
    required this.face,
    required this.currentShift,
    required this.targetShift,
    required this.movementBounds,
    required this.happy,
    required this.onCenter,
    required this.status,
    this.screenMapping,
    this.savedStartRatio,
    this.requestedRatio,
  });
  final Widget camera;
  final FaceObservation? face;
  final Offset currentShift, targetShift;
  final Rect movementBounds;
  final bool happy;
  final VoidCallback? onCenter;
  final String status;
  final FaceScreenMapping? screenMapping;
  final Offset? savedStartRatio, requestedRatio;

  Offset get faceCenter => const Offset(156, 100) + currentShift;
  Offset get leftEye => AvatarLocationMarkers.leftEye(happy) + currentShift;
  Offset get rightEye => AvatarLocationMarkers.rightEye(happy) + currentShift;
  Offset get mouthAnchor => AvatarLocationMarkers.mouth(happy) + currentShift;

  @override
  Widget build(BuildContext context) {
    String xy(Offset p) =>
        'X ${p.dx.toStringAsFixed(1)} · Y ${p.dy.toStringAsFixed(1)}';
    final detected = face;
    final mapping = screenMapping;
    final desiredRatio = requestedRatio ?? detected?.center;
    final edgeLimited =
        mapping != null &&
        desiredRatio != null &&
        (mapping.ratioForShift(
                      mapping.shiftForRatio(desiredRatio, movementBounds),
                    ) -
                    desiredRatio)
                .distance >
            .0001;
    return Material(
      key: const ValueKey('face-location-debug-panel'),
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: DefaultTextStyle(
          style: AppTypography.text(11, 15, color: AppColors.textPrimary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: LText(
                      'Locations · $status',
                      key: const ValueKey('face-debug-status'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.text(
                        12,
                        16,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  if (screenMapping == null)
                    TextButton(
                      key: const ValueKey('face-debug-center'),
                      onPressed: onCenter,
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: AppTypography.text(11, 15),
                      ),
                      child: const LText('Center here'),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, box) => Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      SizedBox(
                        width: box.maxWidth * .40,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              camera,
                              if (detected != null)
                                IgnorePointer(
                                  child: CustomPaint(
                                    painter: _CameraLocationMarker(detected),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              LText(
                                'Camera position\n${detected == null ? "No recent face" : "X ${(detected.center.dx * 100).toStringAsFixed(1)}% · Y ${(detected.center.dy * 100).toStringAsFixed(1)}%"}',
                                key: const ValueKey('location-real-face'),
                              ),
                              const Divider(color: AppColors.border),
                              if (savedStartRatio != null)
                                LText(
                                  'Saved start\nX ${(savedStartRatio!.dx * 100).toStringAsFixed(1)}% · Y ${(savedStartRatio!.dy * 100).toStringAsFixed(1)}%',
                                  key: const ValueKey('location-saved-start'),
                                ),
                              if (savedStartRatio != null &&
                                  requestedRatio != null)
                                LText(
                                  'Tracking target\nX ${(requestedRatio!.dx * 100).toStringAsFixed(1)}% · Y ${(requestedRatio!.dy * 100).toStringAsFixed(1)}%',
                                  key: const ValueKey(
                                    'location-tracking-target',
                                  ),
                                ),
                              LText(
                                'Animated face F\n${xy(faceCenter)}',
                                key: const ValueKey('location-avatar-face'),
                              ),
                              if (screenMapping != null)
                                LText(
                                  'Screen position\nX ${(screenMapping!.ratioForShift(currentShift).dx * 100).toStringAsFixed(1)}% · Y ${(screenMapping!.ratioForShift(currentShift).dy * 100).toStringAsFixed(1)}%${edgeLimited ? "\nEdge limited" : ""}',
                                  key: const ValueKey('location-screen-ratio'),
                                ),
                              const SizedBox(height: 6),
                              LText(
                                'Left eye L · ${xy(leftEye)}\nRight eye R · ${xy(rightEye)}',
                                key: const ValueKey('location-avatar-eyes'),
                              ),
                              const SizedBox(height: 6),
                              LText(
                                'Mouth anchor M\n${xy(mouthAnchor)}',
                                key: const ValueKey('location-avatar-mouth'),
                              ),
                              const Divider(color: AppColors.border),
                              LText(
                                'Current shift · ${xy(currentShift)}\nTarget shift · ${xy(targetShift)}\n'
                                'Vertical travel ${movementBounds.top.toStringAsFixed(0)} … +${movementBounds.bottom.toStringAsFixed(0)} px',
                                key: const ValueKey('location-shift'),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 5),
              const LText('Avatar coordinates: 312 × 200 canvas pixels'),
            ],
          ),
        ),
      ),
    );
  }
}

class _CameraLocationMarker extends CustomPainter {
  const _CameraLocationMarker(this.face);
  final FaceObservation face;
  @override
  void paint(Canvas canvas, Size size) {
    final center = facePointOnPreview(face, size);
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 6, paint);
    canvas.drawLine(
      center - const Offset(10, 0),
      center + const Offset(10, 0),
      paint,
    );
    canvas.drawLine(
      center - const Offset(0, 10),
      center + const Offset(0, 10),
      paint,
    );
  }

  @override
  bool shouldRepaint(_CameraLocationMarker old) => old.face != face;
}

/// Mark stable component anchors inside the actual translated avatar. Mouth
/// shape changes around M; it is not a measurement of the speaking lip bounds.
class AvatarLocationMarkers extends CustomPainter {
  const AvatarLocationMarkers({required this.happy});
  final bool happy;
  // PNG eye spans are 0..200 and 424..624 on a 624x400 image. The SVG
  // spans are 0..32 and 88..120 at 120x52. Y follows the blink pivot.
  static Offset leftEye(bool happy) =>
      Offset(happy ? 16 * 312 / 120 : 50, 200 * (happy ? .279 : .31));
  static Offset rightEye(bool happy) =>
      Offset(happy ? 104 * 312 / 120 : 262, 200 * (happy ? .279 : .31));
  static Offset mouth(bool happy) => Offset(156, happy ? 145 : 192);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 312, size.height / 200);
    for (final entry in {
      'F': const Offset(156, 100),
      'L': leftEye(happy),
      'R': rightEye(happy),
      'M': mouth(happy),
    }.entries) {
      final point = entry.value;
      canvas.drawCircle(point, 5, Paint()..color = AppColors.surface);
      canvas.drawCircle(point, 3, Paint()..color = AppColors.primary);
      final text = TextPainter(
        text: TextSpan(
          text: entry.key,
          style: const TextStyle(
            color: AppColors.primary,
            backgroundColor: AppColors.surface,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      text.paint(canvas, point + const Offset(5, -15));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(AvatarLocationMarkers old) => old.happy != happy;
}
