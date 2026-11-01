import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/eye_calibration.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';

FaceObservation eyes(double left, double right, {bool valid = true}) =>
    FaceObservation(
      center: const Offset(.5, .5),
      confidence: .9,
      faceHeight: .4,
      imageSize: const Size(240, 320),
      blinkScreenLeft: left,
      blinkScreenRight: right,
      blinkValid: valid,
    );

void collect(
  EyeCalibration calibration,
  double left,
  double right, {
  int from = 0,
}) {
  for (var ms = 0; ms <= 2800; ms += 100) {
    calibration.sample(
      left,
      right,
      Duration(milliseconds: from + ms),
      valid: true,
    );
  }
}

void main() {
  test('High natural closure scores learn independent personal ranges', () {
    final calibration = EyeCalibration()..startOpen();
    collect(calibration, .65, .5);
    expect(calibration.stage, EyeCalibrationStage.closePrompt);
    calibration.startClosed();
    collect(calibration, .95, .9, from: 3000);
    expect(calibration.stage, EyeCalibrationStage.complete);
    final blink = EyeBlinkState()..profile = calibration.profile;
    blink.update(eyes(.65, .5));
    expect(blink.leftClosed || blink.rightClosed, isFalse);
    blink.update(eyes(.9, .5));
    expect(blink.leftClosed, isTrue);
    expect(blink.rightClosed, isFalse);
    blink.update(eyes(.78, .5));
    expect(
      blink.leftClosed,
      isTrue,
      reason: 'Personal hysteresis retains closed state',
    );
    blink.update(eyes(.7, .5));
    expect(blink.leftClosed, isFalse);
    blink.update(eyes(.95, .9, valid: false));
    expect(blink.leftClosed || blink.rightClosed, isFalse);
  });

  test('Missing data and long gaps cannot count as calibration progress', () {
    final calibration = EyeCalibration()..startOpen();
    calibration.sample(.3, .3, Duration.zero, valid: true);
    calibration.sample(.3, .3, const Duration(seconds: 3), valid: true);
    expect(calibration.stage, EyeCalibrationStage.open);
    expect(calibration.progress, 0);
    calibration.sample(0, 0, const Duration(milliseconds: 3100), valid: false);
    collect(calibration, .3, .3, from: 3200);
    expect(calibration.stage, EyeCalibrationStage.closePrompt);
  });

  test(
    'Indistinguishable eyes fail rather than save unreliable thresholds',
    () {
      final calibration = EyeCalibration()..startOpen();
      collect(calibration, .6, .5);
      calibration.startClosed();
      collect(calibration, .65, .9, from: 3000);
      expect(calibration.stage, EyeCalibrationStage.failed);
      expect(calibration.profile, isNull);
    },
  );

  test('Profiles round-trip and reject malformed or reversed ranges', () {
    const profile = EyeBlinkProfile(.6, .95, .4, .9);
    final restored = EyeBlinkProfile.decode(profile.encode())!;
    expect(restored.leftOpen, .6);
    expect(restored.rightClosed, .9);
    expect(EyeBlinkProfile.decode(null), isNull);
    expect(
      EyeBlinkProfile.decode('{"version":1,"values":[0.8,0.4,0.2,0.9]}'),
      isNull,
    );
    expect(
      EyeBlinkProfile.decode('{"version":2,"values":[0.1,0.9,0.2,0.9]}'),
      isNull,
    );
  });
}
