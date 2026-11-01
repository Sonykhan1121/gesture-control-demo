import 'dart:ui' show Rect, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';

void main() {
  test('collapsed movement limits tolerate floating-point inversion', () {
    const mapping = FaceScreenMapping(
      viewport: Size(800, 1333),
      avatar: Rect.fromLTWH(18, 420, 764, 489.7435897435897),
    );
    const rounding = 1.8151500993942534e-14;
    for (final ratio in [
      Offset.zero,
      const Offset(.5, .5),
      const Offset(1, 1),
    ]) {
      expect(
        mapping.shiftForRatio(
          ratio,
          const Rect.fromLTRB(rounding, rounding, -rounding, -rounding),
        ),
        Offset.zero,
      );
      final shift = mapping.shiftForRatio(
        ratio,
        const Rect.fromLTRB(rounding, -10, -rounding, 10),
      );
      expect(shift.dx, 0);
      expect(shift.dy, inInclusiveRange(-10, 10));
    }
  });
  test(
    'Camera 30/70 means screen 30/70 in both orientations and avatar scales',
    () {
      for (final viewport in [const Size(1000, 600), const Size(600, 1000)]) {
        for (final scale in [1.0, .5]) {
          final avatar = Rect.fromCenter(
            center: Offset(viewport.width / 2, viewport.height / 2),
            width: 312 * scale,
            height: 200 * scale,
          );
          final mapping = FaceScreenMapping(viewport: viewport, avatar: avatar);
          final bounds = Rect.fromLTRB(
            (18 - avatar.left) / scale,
            (18 - avatar.top) / scale,
            (viewport.width - 18 - avatar.right) / scale,
            (viewport.height - 18 - avatar.bottom) / scale,
          );
          const ratio = Offset(.3, .7);
          final shift = mapping.shiftForRatio(ratio, bounds);
          final point = mapping.screenPoint(const Offset(156, 100) + shift);
          expect(point.dx, closeTo(viewport.width * .3, .0001));
          expect(point.dy, closeTo(viewport.height * .7, .0001));
          expect(
            (mapping.ratioForShift(shift) - ratio).distance,
            lessThan(.0001),
          );
        }
      }
    },
  );
  test('Edge positions clamp the whole avatar inside the visible screen', () {
    const mapping = FaceScreenMapping(
      viewport: Size(1000, 600),
      avatar: Rect.fromLTWH(344, 200, 312, 200),
    );
    const limits = Rect.fromLTRB(-326, -182, 326, 182);
    final topLeft = mapping.shiftForRatio(Offset.zero, limits);
    final bottomRight = mapping.shiftForRatio(const Offset(1, 1), limits);
    expect(mapping.avatar.shift(topLeft).topLeft, const Offset(18, 18));
    expect(
      mapping.avatar.shift(bottomRight).bottomRight,
      const Offset(982, 582),
    );
  });
  test(
    'Precise stabilization settles to narrow center offsets without a calibration bias',
    () {
      final filter = FaceMotionStabilizer();
      var ms = 0;
      filter.update(Offset.zero, Duration.zero, precise: true);
      for (final target in [
        const Offset(-.02, .02),
        const Offset(-.4, .4),
        const Offset(.4, -.4),
      ]) {
        var output = Offset.zero;
        for (var i = 0; i < 45; i++) {
          output = filter.update(
            target,
            Duration(milliseconds: ms += 33),
            precise: true,
          );
        }
        expect(output, target);
      }
    },
  );
}
