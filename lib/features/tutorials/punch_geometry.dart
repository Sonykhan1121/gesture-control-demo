import 'dart:math' as math;

import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';

/// Closed-hand geometry for the camera-facing Punch drawing. The canned
/// classifier often reports None for this view, and 2D angles lose depth.
/// This returns landmark fit, never a rewritten classifier probability.
double punchGeometryMatch(
  HandObservation hand, {
  void Function(String name, double fit)? onComponent,
}) {
  final p = hand.worldPoints;
  if (p.length != 21 || p.any((point) => !point.isFinite)) return 0;
  final scale = (p[5] - p[17]).length;
  if (scale < .0001) return 0;
  double fall(double value, double low, double high) =>
      1 - ((value - low) / (high - low)).clamp(0.0, 1.0);
  double rise(double value, double low, double high) =>
      1 - fall(value, low, high);
  double angle(int a, int b, int c) {
    final u = p[a] - p[b], v = p[c] - p[b];
    final denominator = u.length * v.length;
    if (denominator < .0000001) return 180;
    return math.acos((u.dot(v) / denominator).clamp(-1.0, 1.0)) * 180 / math.pi;
  }

  double curl(int base) {
    final palmLength = (p[base] - p[0]).length;
    if (palmLength < .0001) return 0;
    final flexion = math.max(
      fall(angle(base, base + 1, base + 2), 90, 155),
      fall(angle(base + 1, base + 2, base + 3), 80, 150),
    );
    final reach = (p[base + 3] - p[0]).length / palmLength;
    return math.min(flexion, fall(reach, 1.05, 1.65));
  }

  final thumbNearFingers = [
    8,
    12,
    16,
    20,
  ].map((tip) => (p[4] - p[tip]).length / scale).reduce(math.min);
  final components = <String, double>{
    'punchIndexCurled': curl(5),
    'punchMiddleCurled': curl(9),
    'punchRingCurled': curl(13),
    'punchPinkyCurled': curl(17),
    'punchThumbTucked': fall(thumbNearFingers, .65, 1.15),
    'punchThumbNotExtended': fall((p[4] - p[2]).length / scale, .7, 1.2),
  };
  final worldFit = components.values.reduce(math.min);
  final fingersFit = [5, 9, 13, 17].map(curl).reduce(math.min);
  var frontFit = 0.0;
  if (hand.points.length == 21 &&
      hand.imageSize.width > 0 &&
      hand.imageSize.height > 0) {
    final image = hand.points
        .map(
          (point) => HandPoint3D(
            point.dx * hand.imageSize.width,
            point.dy * hand.imageSize.height,
            0,
          ),
        )
        .toList();
    final knuckles = image[17] - image[5];
    if (knuckles.length > .0001) {
      // The tucked thumb is partially occluded in the approved end-on Punch.
      // World depth can hallucinate an extended thumb. Only allow this fallback
      // for a horizontal knuckle row with the visible thumb close to the curled
      // fingertips; a vertical-row thumbs-up/down pose does not qualify.
      final horizontal = rise(knuckles.x.abs() / knuckles.length, .65, .9);
      final gap = [8, 12, 16, 20]
          .map((tip) => (image[4] - image[tip]).length / knuckles.length)
          .reduce(math.min);
      final compactThumb = fall(gap, .35, .75);
      components['punchKnucklesHorizontal'] = horizontal;
      components['punchThumbCloseInImage'] = compactThumb;
      frontFit = math.min(fingersFit, math.min(horizontal, compactThumb));
    }
  }
  components['punchWorldFit'] = worldFit;
  components['punchFrontFit'] = frontFit;
  if (onComponent != null) components.forEach(onComponent);
  final fit = math.max(worldFit, frontFit);
  return fit.clamp(0.0, 1.0);
}
