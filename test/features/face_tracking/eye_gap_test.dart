import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'eye_diagnostics_test.dart' show eyeFrame;

void main() {
  test('Tiny visible gaps stay open despite high native closure scores', () {
    final blink = EyeBlinkState(useLidGap: true);
    for (final size in [const Size(400, 400), const Size(240, 320)]) {
      for (final mirror in [false, true]) {
        for (final roll in [-.4, 0.0, .4]) {
          blink.update(
            FaceObservation.fromMap({
              ...eyeFrame(
                leftAperture: .035,
                rightAperture: .035,
                size: size,
                mirror: mirror,
                roll: roll,
              ),
              'blinkScreenLeft': .99,
              'blinkScreenRight': .99,
            })!,
          );
          expect(blink.leftClosed, isFalse);
          expect(blink.rightClosed, isFalse);
        }
      }
    }
  });

  test(
    'Each eye closes independently with hysteresis, then reopens at a tiny gap',
    () {
      final blink = EyeBlinkState(useLidGap: true);
      void update(double left, double right) => blink.update(
        FaceObservation.fromMap(
          eyeFrame(leftAperture: left, rightAperture: right),
        )!,
      );
      update(.035, .035);
      update(.026, .026);
      expect(blink.leftClosed || blink.rightClosed, isFalse);
      update(.005, .035);
      expect(blink.leftClosed, isTrue);
      expect(blink.rightClosed, isFalse);
      update(.026, .026);
      expect(blink.leftClosed, isTrue);
      expect(blink.rightClosed, isFalse);
      update(.035, .005);
      expect(blink.leftClosed, isFalse);
      expect(blink.rightClosed, isTrue);
      update(0, 0);
      expect(blink.leftClosed && blink.rightClosed, isTrue);
      update(.035, .035);
      expect(blink.leftClosed || blink.rightClosed, isFalse);
    },
  );

  test('Missing, invalid or stale landmarks cannot keep an eye closed', () {
    final blink = EyeBlinkState(useLidGap: true);
    for (final override in [
      {'eyeLandmarks': null},
      {
        'eyeLandmarks': List.filled(8, [.5, .5]),
      },
      {
        'eyeLandmarks': List.filled(8, [double.nan, .5]),
      },
      {'blinkValid': false},
    ]) {
      blink.update(
        FaceObservation.fromMap(eyeFrame(leftClosed: true, rightClosed: true))!,
      );
      expect(blink.leftClosed && blink.rightClosed, isTrue);
      blink.update(
        FaceObservation.fromMap({
          ...eyeFrame(leftClosed: true, rightClosed: true),
          ...override,
        })!,
      );
      expect(blink.leftClosed || blink.rightClosed, isFalse);
    }
    blink.update(FaceObservation.fromMap(eyeFrame(leftClosed: true))!);
    blink.reset();
    expect(blink.leftClosed || blink.rightClosed, isFalse);
  });
}
