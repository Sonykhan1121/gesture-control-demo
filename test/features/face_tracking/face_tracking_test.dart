import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';

FaceObservation faceAt(double y) => FaceObservation(
  center: Offset(.5, y),
  confidence: .9,
  faceHeight: .4,
  imageSize: const Size(480, 640),
);

void main() {
  test('Measured blinks close/reopen each eye with hysteresis', () {
    final blink = EyeBlinkState();
    FaceObservation eyes(double left, double right) => FaceObservation(
      center: const Offset(.5, .5),
      confidence: .9,
      faceHeight: .4,
      imageSize: const Size(240, 320),
      blinkScreenLeft: left,
      blinkScreenRight: right,
    );
    blink.update(eyes(.8, .1));
    expect(blink.leftClosed, isTrue);
    expect(blink.rightClosed, isFalse);
    blink.update(eyes(.4, .85));
    expect(blink.leftClosed, isTrue);
    expect(blink.rightClosed, isTrue);
    blink.update(eyes(.2, .1));
    expect(blink.leftClosed, isFalse);
    expect(blink.rightClosed, isFalse);
    blink.update(eyes(.9, .9));
    blink.reset();
    expect(blink.leftClosed || blink.rightClosed, isFalse);
  });
  test('Invalid blink coefficients do not close the eyes', () {
    final face = FaceObservation.fromMap({
      'detected': true,
      'x': .5,
      'y': .5,
      'confidence': .9,
      'faceHeight': .4,
      'width': 240,
      'height': 320,
      'blinkScreenLeft': double.nan,
      'blinkScreenRight': 2,
    })!;
    final blink = EyeBlinkState()..update(face);
    expect(blink.leftClosed || blink.rightClosed, isFalse);
  });
  test('Normal vertical travel produces visible motion in both directions', () {
    final motion = FaceFollowMotion();
    expect(motion.update(faceAt(.4)).dy, 0);
    expect(motion.update(faceAt(.48)).dy * 32, greaterThan(18));
    expect(motion.update(faceAt(.32)).dy * 32, lessThan(-18));
    expect(motion.update(faceAt(.9)).dy, 1);
    motion.reset();
    expect(motion.update(faceAt(.7)).dy, 0);
  });
  test(
    'Both axes follow from an off-center neutral with pixel-correct sensitivity',
    () {
      FaceObservation at(double x, double y, Size image) => FaceObservation(
        center: Offset(x, y),
        confidence: .9,
        faceHeight: .4,
        imageSize: image,
      );
      for (final image in [const Size(480, 640), const Size(640, 480)]) {
        final motion = FaceFollowMotion();
        expect(motion.update(at(.4, .45, image)), Offset.zero);
        // Same physical displacement in camera pixels on either axis.
        final xTravel = .08 * image.height / image.width;
        final right = motion.update(at(.4 + xTravel, .45, image)).dx;
        final down = motion.update(at(.4, .53, image)).dy;
        expect(right, closeTo(down, .0001));
        expect(right * FaceFollowMotion.maxShift.dx, greaterThan(13));
        expect(
          motion.update(at(.4 - xTravel, .45, image)).dx,
          closeTo(-right, .0001),
        );
        expect(motion.update(at(.4, .37, image)).dy, closeTo(-down, .0001));
        expect(motion.update(at(.4, .45, image)), Offset.zero);
        motion.reset();
        expect(motion.update(at(.7, .7, image)), Offset.zero);
      }
    },
  );
  test(
    'Small camera noise is held but accumulated slow movement still follows',
    () {
      final motion = FaceFollowMotion();
      motion.update(faceAt(.5));
      for (final y in [.501, .499, .502, .498]) {
        expect(motion.update(faceAt(y)), Offset.zero);
      }
      var previous = motion.update(faceAt(.55));
      expect(motion.update(faceAt(.551)), previous);
      for (var step = 1; step <= 20; step++) {
        final next = motion.update(faceAt(.55 + step * .001));
        expect(next.dy, greaterThanOrEqualTo(previous.dy));
        previous = next;
      }
      expect(previous.dy, greaterThan(.48));
      expect(motion.update(faceAt(.9)).dy, 1);
      expect(motion.update(faceAt(.1)).dy, -1);
    },
  );
  test('Debug circle uses the same cover crop as the camera', () {
    final center = faceAt(.5);
    expect(
      facePointOnPreview(center, const Size(312, 200)),
      const Offset(156, 100),
    );
    expect(
      facePointOnPreview(faceAt(.6), const Size(312, 200)).dy,
      greaterThan(100),
    );
  });
  test('Incomplete or invalid face observations cannot drive the eyes', () {
    expect(
      FaceObservation.fromMap({'detected': true, 'x': .5, 'y': .5}),
      isNull,
    );
    expect(FaceObservation.fromMap({'detected': false}), isNull);
    expect(
      FaceObservation.fromMap({
        'detected': true,
        'x': .5,
        'y': double.nan,
        'confidence': .9,
        'faceHeight': .4,
        'width': 480,
        'height': 640,
      }),
      isNull,
    );
  });
}
