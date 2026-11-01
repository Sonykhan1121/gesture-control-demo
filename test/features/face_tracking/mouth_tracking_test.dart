import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/eye_calibration.dart';

FaceObservation expression(
  double mouth, {
  bool valid = true,
  double blink = .1,
}) => FaceObservation(
  center: const Offset(.5, .5),
  confidence: .9,
  faceHeight: .4,
  imageSize: const Size(240, 320),
  mouthOpen: mouth,
  mouthValid: valid,
  blinkScreenLeft: blink,
  blinkScreenRight: blink,
);

void main() {
  test('Mouth follows measured speech opening and closes at rest', () {
    final mouth = MouthOpenState();
    mouth.update(expression(.03));
    expect(mouth.openness, 0);
    mouth.update(expression(.25));
    final speaking = mouth.openness;
    expect(speaking, greaterThan(0));
    expect(speaking, lessThan(1));
    mouth.update(expression(.55));
    expect(mouth.openness, 1);
    mouth.update(expression(.1));
    expect(mouth.openness, lessThan(speaking));
    mouth.update(expression(0));
    expect(mouth.openness, 0);
  });
  test(
    'Invalid expression, missing coefficients and reset close the mouth',
    () {
      final mouth = MouthOpenState();
      for (final face in [
        expression(.8, valid: false),
        expression(double.nan),
        expression(double.infinity),
        expression(-1),
        expression(2),
      ]) {
        mouth.update(expression(.8));
        mouth.update(face);
        expect(mouth.openness, 0);
      }
      final missing = FaceObservation.fromMap({
        'detected': true,
        'x': .5,
        'y': .5,
        'confidence': .9,
        'faceHeight': .4,
        'width': 240,
        'height': 320,
      })!;
      mouth.update(missing);
      expect(mouth.openness, 0);
      mouth.update(expression(.8));
      mouth.reset();
      expect(mouth.openness, 0);
    },
  );
  test(
    'Talking and fixed-profile blinking work independently on the same frame',
    () {
      final mouth = MouthOpenState();
      final blink = EyeBlinkState()..profile = EyeBlinkProfile.lastMeasured;
      final talkingBlink = expression(.45, blink: .95);
      mouth.update(talkingBlink);
      blink.update(talkingBlink);
      expect(mouth.openness, greaterThan(0));
      expect(blink.leftClosed && blink.rightClosed, isTrue);
      final talkingOpenEyes = expression(.45);
      mouth.update(talkingOpenEyes);
      blink.update(talkingOpenEyes);
      expect(mouth.openness, greaterThan(0));
      expect(blink.leftClosed || blink.rightClosed, isFalse);
    },
  );
}
