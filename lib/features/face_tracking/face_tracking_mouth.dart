import 'package:flutter/material.dart';
import 'mouth_tracking.dart';

/// The selected face mouth, with measured smile and speech layered on top.
class TrackedMouth extends StatelessWidget {
  const TrackedMouth({
    super.key,
    required this.openness,
    required this.happy,
    required this.color,
    this.smile = 0,
    this.widthScale = 1,
    this.followExpression = false,
  });
  final double openness, smile, widthScale;
  final bool happy, followExpression;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<MouthMotion>(
      tween: _MouthTween(
        begin: const MouthMotion(),
        end: followExpression
            ? MouthMotion(
                openness: openness,
                smile: smile,
                widthScale: widthScale,
              )
            : const MouthMotion(),
      ),
      duration: const Duration(milliseconds: 60),
      curve: Curves.linear,
      builder: (context, value, _) => SizedBox(
        width: 312,
        height: 200,
        child: CustomPaint(painter: _MouthPainter(value, happy, color)),
      ),
    );
  }
}

class _MouthTween extends Tween<MouthMotion> {
  _MouthTween({required MouthMotion begin, required MouthMotion end})
    : super(begin: begin, end: end);
  @override
  MouthMotion lerp(double t) => MouthMotion.lerp(begin!, end!, t);
}

/// Normal faces use a rounded lip contour; the second face uses the approved
/// three rounded blocks. Expressions stay within the mouth band.
class MouthDrawing {
  const MouthDrawing(this.path, this.stroke);
  final Path path;
  final double stroke;
  Rect get bounds => path.getBounds().inflate(stroke / 2);
  // Visual styling only: neutral measurements/calibration still have smile=0.
  static const restingSmile = .65;
  static MouthDrawing forMotion(MouthMotion motion, {required bool happy}) {
    if (happy) {
      // Same contain transform as the approved 120x52 SVG in a 312x200 face.
      const scale = 312 / 120;
      const top = (200 - 52 * scale) / 2;
      final path = Path();
      for (final block in [
        const Rect.fromLTWH(44, 34, 8, 8),
        const Rect.fromLTWH(52, 42, 16, 8),
        const Rect.fromLTWH(68, 34, 8, 8),
      ]) {
        final centerBlock = block.left == 52;
        final y =
            top +
            block.top * scale +
            (centerBlock ? 28 * motion.openness : -8 * motion.smile);
        final rect = Rect.fromLTWH(
          156 + (block.left * scale - 156) * motion.widthScale,
          y,
          block.width * scale * motion.widthScale,
          block.height * scale,
        );
        path.addRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(scale)),
        );
      }
      return MouthDrawing(path, 0);
    }
    final smile = restingSmile + (1 - restingSmile) * motion.smile;
    // Give the resting smile a clearly visible, rounded line.
    const stroke = 8.0;
    final width = 112 * motion.widthScale - stroke;
    final gap = (happy ? 30 : 24) * motion.openness;
    final base = happy ? 145.0 : 192 - gap / 2;
    final bandTop = happy ? 112.0 : 160.0;
    final corner = (base - 27 * smile).clamp(
      bandTop + stroke / 2,
      200 - stroke / 2,
    );
    final upper = (base - gap / 2).clamp(
      bandTop + stroke / 2,
      200 - stroke / 2,
    );
    final lower = (base + gap / 2).clamp(
      bandTop + stroke / 2,
      200 - stroke / 2,
    );
    final left = 156 - width / 2, right = 156 + width / 2;
    double toward(double y) => corner + (y - corner) * 2 / 3;
    final path = Path()
      ..moveTo(left, corner)
      ..cubicTo(
        left + width / 6,
        toward(upper),
        156 - width / 6,
        upper,
        156,
        upper,
      )
      ..cubicTo(
        156 + width / 6,
        upper,
        right - width / 6,
        toward(upper),
        right,
        corner,
      )
      ..cubicTo(
        right - width / 6,
        toward(lower),
        156 + width / 6,
        lower,
        156,
        lower,
      )
      ..cubicTo(
        156 - width / 6,
        lower,
        left + width / 6,
        toward(lower),
        left,
        corner,
      )
      ..close();
    return MouthDrawing(path, stroke);
  }
}

class _MouthPainter extends CustomPainter {
  const _MouthPainter(this.motion, this.happy, this.color);
  final MouthMotion motion;
  final bool happy;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 312, size.height / 200);
    final drawing = MouthDrawing.forMotion(motion, happy: happy);
    canvas.drawPath(drawing.path, Paint()..color = color);
    if (drawing.stroke > 0) {
      canvas.drawPath(
        drawing.path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = drawing.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MouthPainter old) =>
      old.motion != motion || old.happy != happy || old.color != color;
}
