import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/eye_diagnostics.dart';
import 'package:hand_gesture/features/face_tracking/eye_capture_store.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';

/// Synthetic frame; canonical group A is image-left before optional mirroring.
Map<Object?, Object?> eyeFrame({
  bool leftClosed = false,
  bool rightClosed = false,
  bool mirror = false,
  double roll = 0,
  double? leftAperture,
  double? rightAperture,
  Size size = const Size(400, 400),
}) {
  final a = leftAperture ?? (leftClosed ? .02 : .20),
      b = rightAperture ?? (rightClosed ? .02 : .20);
  final p = [
    const Offset(110, 145),
    const Offset(170, 145),
    Offset(140, 145 - a * 30),
    Offset(140, 145 + a * 30),
    const Offset(290, 145),
    const Offset(230, 145),
    Offset(260, 145 - b * 30),
    Offset(260, 145 + b * 30),
  ];
  final scale = math.min(size.width / 400, size.height / 400);
  final points = p.map((v) {
    final local = v - const Offset(200, 200);
    var point =
        Offset(
              local.dx * math.cos(roll) - local.dy * math.sin(roll),
              local.dx * math.sin(roll) + local.dy * math.cos(roll),
            ) *
            scale +
        Offset(size.width / 2, size.height / 2);
    if (mirror) point = Offset(size.width - point.dx, point.dy);
    return [point.dx / size.width, point.dy / size.height];
  }).toList();
  final rawLeft = rightClosed ? .95 : .10, rawRight = leftClosed ? .95 : .10;
  return {
    'detected': true,
    'x': .5,
    'y': .5,
    'confidence': .9,
    'faceHeight': .4,
    'width': size.width,
    'height': size.height,
    'blinkValid': true,
    'blinkScreenLeft': mirror ? rawLeft : rawRight,
    'blinkScreenRight': mirror ? rawRight : rawLeft,
    'eyeDebugValid': true,
    'eyeLandmarks': points,
    'eyeBlinkNativeLeft': rawLeft,
    'eyeBlinkNativeRight': rawRight,
    'screenLeftFromRight': !mirror,
  };
}

void main() {
  test(
    'Independent eyelid gaps preserve screen sides, roll and aspect ratio',
    () {
      for (final size in [
        const Size(400, 400),
        const Size(240, 320),
        const Size(640, 480),
      ]) {
        for (final roll in [-.4, 0.0, .4]) {
          for (final mirror in [false, true]) {
            final frame = eyeFrame(
              leftClosed: true,
              mirror: mirror,
              roll: roll,
              size: size,
            );
            final face = FaceObservation.fromMap(frame)!;
            final eyes = face.eyeMeasurement!;
            expect(eyes.leftAperture, closeTo(mirror ? .20 : .02, 1e-8));
            expect(eyes.rightAperture, closeTo(mirror ? .02 : .20, 1e-8));
            expect(eyes.rawLeft, .10);
            expect(eyes.rawRight, .95);
            expect(eyes.screenLeftFromRight, !mirror);
            expect(face.blinkScreenLeft, mirror ? .10 : .95);
          }
        }
      }
    },
  );
  test(
    'Invalid optional diagnostics do not change the current blink inputs',
    () {
      for (final bad in [
        null,
        [],
        List.filled(8, [.5, .5]),
        List.filled(8, [double.nan, .5]),
      ]) {
        final face = FaceObservation.fromMap({
          ...eyeFrame(leftClosed: true),
          'eyeLandmarks': bad,
        })!;
        expect(face.eyeMeasurement, isNull);
        expect(face.blinkValid, isTrue);
        expect(face.blinkScreenLeft, .95);
        expect(face.blinkScreenRight, .10);
        final blink = EyeBlinkState()..update(face);
        expect(blink.leftClosed, isTrue);
        expect(blink.rightClosed, isFalse);
      }
    },
  );
  test('Guided check records all four phases and actual avatar decisions', () {
    final check = EyeDiagnosticCheck()..start(Duration.zero);
    for (var i = 0; i < 4; i++) {
      final begin = Duration(seconds: 2 + i * 5);
      check.tick(begin);
      expect(check.measuring, isTrue);
      final face = FaceObservation.fromMap(
        eyeFrame(leftClosed: i == 1 || i == 3, rightClosed: i == 2 || i == 3),
      )!;
      final blink = EyeBlinkState()..update(face);
      for (var j = 0; j < 12; j++) {
        check.add(
          EyeDebugSample(
            measured: face.eyeMeasurement!,
            screenLeft: face.blinkScreenLeft,
            screenRight: face.blinkScreenRight,
            normalizedLeft: face.blinkScreenLeft,
            normalizedRight: face.blinkScreenRight,
            leftClosed: blink.leftClosed,
            rightClosed: blink.rightClosed,
            latencyMs: 40,
          ),
        );
      }
      expect(check.tick(begin + const Duration(seconds: 3)), isTrue);
    }
    expect(check.running, isFalse);
    expect(check.history.length, 4);
    expect(check.history['leftClosed']!['leftClosedFraction'], 1);
    expect(check.history['leftClosed']!['rightClosedFraction'], 0);
    expect(check.history['rightClosed']!['leftClosedFraction'], 0);
    expect(check.history['rightClosed']!['rightClosedFraction'], 1);
    expect(check.history['bothClosed']!['samples'], 12);
    final empty = EyeDiagnosticCheck()..start(Duration.zero);
    empty.tick(const Duration(seconds: 2));
    empty.add(null);
    empty.tick(const Duration(seconds: 5));
    expect(empty.history['normal']!['samples'], 0);
    expect(empty.history['normal']!['invalid'], 1);
    empty.cancel();
    expect(empty.running, isFalse);
  });
  test(
    'Eye captures save atomically in their own file and preserve mouth tuning',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lazivoo-eye-synthetic-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final mouth = File('${directory.path}/mouth-debug-captures.json');
      await mouth.writeAsString('{"synthetic":true}');
      final store = EyeCaptureStore(directory: () async => directory);
      await store.save({
        'version': 1,
        'captures': {
          'normal': {'samples': 12},
        },
      });
      final saved = jsonDecode(
        await File('${directory.path}/eye-debug-captures.json').readAsString(),
      );
      expect(saved['captures']['normal']['samples'], 12);
      expect(await mouth.readAsString(), '{"synthetic":true}');
      expect(
        await File('${directory.path}/eye-debug-captures.json.tmp').exists(),
        isFalse,
      );
    },
  );
}
