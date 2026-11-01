import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';

void main() {
  test(
    'Resting noise and isolated bad detections do not shake a large avatar',
    () {
      final filter = FaceMotionStabilizer();
      var ms = 0;
      Offset sample(Offset p) =>
          filter.update(p, Duration(milliseconds: ms += 33));
      sample(Offset.zero);
      for (var i = 0; i < 60; i++) {
        final p = sample(
          Offset(i.isEven ? .07 : -.06, i % 3 == 0 ? .055 : -.04),
        );
        expect(p.distance, lessThan(.045));
      }
      expect(sample(const Offset(1, -1)).distance, lessThan(.045));
      expect(sample(Offset.zero).distance, lessThan(.045));
      expect(sample(Offset.zero).distance, lessThan(.045));
    },
  );
  test(
    'Deliberate motion follows promptly and then stays stable away from center',
    () {
      final filter = FaceMotionStabilizer();
      var ms = 0;
      Offset sample(Offset p) =>
          filter.update(p, Duration(milliseconds: ms += 33));
      sample(Offset.zero);
      const target = Offset(.8, -.7);
      var result = Offset.zero;
      for (var i = 0; i < 10; i++) {
        result = sample(target);
      }
      expect((result - target).distance, lessThan(.04));
      final settled = result;
      for (var i = 0; i < 60; i++) {
        result = sample(
          target + Offset(i.isEven ? .03 : -.03, i.isEven ? -.025 : .025),
        );
        expect((result - settled).distance, lessThan(.035));
      }
    },
  );
  test(
    'Both signs reach full travel at different camera rates, and reset clears old motion',
    () {
      for (final interval in [33, 66, 100]) {
        final filter = FaceMotionStabilizer();
        var ms = 0;
        Offset sample(Offset p) =>
            filter.update(p, Duration(milliseconds: ms += interval));
        sample(Offset.zero);
        for (final target in [const Offset(1, 1), const Offset(-1, -1)]) {
          var result = Offset.zero;
          for (var i = 0; i < 600 ~/ interval; i++) {
            result = sample(target);
          }
          expect(result, target);
        }
        filter.reset();
        expect(sample(Offset.zero), Offset.zero);
      }
    },
  );
}
