import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'face_debug_panel.dart';
import 'face_tracking.dart';

/// Translation ranges of stable artwork reference points, in Home's viewport.
/// These are anchor travel limits, not bounds of the blinking/speaking pixels.
class FaceMovementGeometry {
  const FaceMovementGeometry({
    required this.mapping,
    required this.limits,
    required this.happy,
  });
  final FaceScreenMapping mapping;
  final Rect limits;
  final bool happy;

  List<Offset> get anchors => [
    AvatarLocationMarkers.leftEye(happy),
    AvatarLocationMarkers.rightEye(happy),
    AvatarLocationMarkers.mouth(happy),
  ];

  Rect range(int index) => Rect.fromPoints(
    mapping.screenPoint(anchors[index] + limits.topLeft),
    mapping.screenPoint(anchors[index] + limits.bottomRight),
  );

  Offset position(int index, Offset shift) =>
      mapping.screenPoint(anchors[index] + shift);

  static const colors = [
    Color(0xFF60DCFF),
    Color(0xFFC6A4FF),
    Color(0xFFFFC66B),
  ];
  static const labels = ['L eye', 'R eye', 'Mouth'];
  static const marks = ['L', 'R', 'M'];
}

class FaceMovementLimitsPainter extends CustomPainter {
  const FaceMovementLimitsPainter({
    required this.geometry,
    required this.currentShift,
    this.uiScale = 1,
  });
  final FaceMovementGeometry geometry;
  final Offset currentShift;
  final double uiScale;

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 3; i++) {
      final color = FaceMovementGeometry.colors[i];
      final path = Path()..addRect(geometry.range(i));
      final shadow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5 * uiScale
        ..color = const Color(0xB3000000);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 * uiScale
        ..color = color;
      for (final metric in path.computeMetrics()) {
        for (var start = 0.0; start < metric.length; start += 12 * uiScale) {
          final dash = metric.extractPath(start, start + 7 * uiScale);
          canvas.drawPath(dash, shadow);
          canvas.drawPath(dash, line);
        }
      }
      final point = geometry.position(i, currentShift);
      canvas.drawCircle(point, 7 * uiScale, Paint()..color = AppColors.surface);
      canvas.drawCircle(point, 5 * uiScale, line..strokeWidth = 2 * uiScale);
      canvas.drawCircle(point, 2 * uiScale, Paint()..color = color);
      final label = TextPainter(
        text: TextSpan(
          text: FaceMovementGeometry.marks[i],
          style: TextStyle(
            color: color,
            backgroundColor: AppColors.surface,
            fontSize: 13 * uiScale,
            fontWeight: FontWeight.w700,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, point + const Offset(10, -18) * uiScale);
    }
  }

  @override
  bool shouldRepaint(FaceMovementLimitsPainter old) =>
      old.currentShift != currentShift ||
      old.geometry.mapping != geometry.mapping ||
      old.geometry.limits != geometry.limits ||
      old.geometry.happy != geometry.happy ||
      old.uiScale != uiScale;
}

class FaceMovementDebugLegend extends StatelessWidget {
  const FaceMovementDebugLegend({
    super.key,
    required this.geometry,
    required this.visible,
    required this.onToggle,
    this.uiScale = 1,
  });
  final FaceMovementGeometry geometry;
  final bool visible;
  final VoidCallback onToggle;
  final double uiScale;

  @override
  Widget build(BuildContext context) => MediaQuery.withClampedTextScaling(
    minScaleFactor: uiScale,
    child: _content(context),
  );

  Widget _content(BuildContext context) {
    if (!visible) {
      return Align(
        alignment: Alignment.topRight,
        child: TextButton.icon(
          key: const ValueKey('face-movement-debug-toggle'),
          onPressed: onToggle,
          icon: const Icon(Icons.open_with_rounded, size: 17),
          label: const Text('Show movement limits'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            backgroundColor: AppColors.surface,
          ),
        ),
      );
    }
    String percentage(double value, double extent) =>
        (value / extent * 100).toStringAsFixed(0);
    String rangeLabel(int index) {
      final range = geometry.range(index);
      final size = geometry.mapping.viewport;
      return 'X ${percentage(range.left, size.width)}–${percentage(range.right, size.width)}%'
          '   Y ${percentage(range.top, size.height)}–${percentage(range.bottom, size.height)}%';
    }

    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 8, 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Movement limits',
                    style: AppTypography.text(14, 20, weight: FontWeight.w600),
                  ),
                ),
                IconButton(
                  key: const ValueKey('face-movement-debug-toggle'),
                  tooltip: 'Hide movement limits',
                  onPressed: onToggle,
                  constraints: BoxConstraints(
                    minWidth: 44 * uiScale,
                    minHeight: 44 * uiScale,
                  ),
                  icon: const Icon(Icons.visibility_off_outlined, size: 20),
                  color: AppColors.textPrimary,
                ),
              ],
            ),
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 62 * uiScale,
                      child: Text(
                        FaceMovementGeometry.labels[i],
                        style: AppTypography.text(
                          12,
                          17,
                          color: FaceMovementGeometry.colors[i],
                          weight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        rangeLabel(i),
                        style: AppTypography.text(12, 17),
                      ),
                    ),
                  ],
                ),
              ),
            Text(
              'Boxes: anchor limits · Dots: live positions',
              style: AppTypography.text(10, 15, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
