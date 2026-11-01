import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/mouth_tracking.dart';
import 'package:hand_gesture/features/face_tracking/mouth_diagnostics.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_mouth.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';

Map<Object?, Object?> mouthFrame({
  double gap = 0,
  double width = .65,
  double smile = .05,
  double tilt = 0,
  bool mirror = false,
  Size size = const Size(400, 400),
}) {
  final w = 140 * width;
  final p = [
    Offset(200 - w / 2, 260),
    Offset(200 + w / 2, 260),
    Offset(200, 260 - gap * w / 2),
    Offset(200, 260 + gap * w / 2),
    const Offset(200, 246),
    const Offset(200, 274),
    const Offset(130, 130),
    const Offset(270, 130),
  ];
  final scale = math.min(size.width / 400, size.height / 400);
  final points = p.map((v) {
    final local = v - const Offset(200, 200);
    var point =
        Offset(
              local.dx * math.cos(tilt) - local.dy * math.sin(tilt),
              local.dx * math.sin(tilt) + local.dy * math.cos(tilt),
            ) *
            scale +
        Offset(size.width / 2, size.height / 2);
    if (mirror) point = Offset(size.width - point.dx, point.dy);
    return [point.dx / size.width, point.dy / size.height];
  }).toList();
  return {
    'mouthGeometryValid': true,
    'mouthLandmarks': points,
    'mouthSmileValid': true,
    'mouthSmile': smile,
    'detected': true,
    'x': .5,
    'y': .5,
    'confidence': .9,
    'faceHeight': .4,
    'width': size.width,
    'height': size.height,
    'mouthValid': true,
    'mouthOpen': .8,
    'blinkValid': true,
    'blinkScreenLeft': .95,
    'blinkScreenRight': .95,
  };
}

MouthMeasurement measurement({
  double gap = 0,
  double width = .65,
  double smile = .05,
}) => FaceObservation.fromMap(
  mouthFrame(gap: gap, width: width, smile: smile),
)!.mouthMeasurement!;

void main() {
  test(
    'One-button check guides prepare/capture phases and cancels cleanly',
    () {
      final guide = MouthGuidedCheck()..start(Duration.zero);
      expect(guide.ready(const Duration(seconds: 1)), isFalse);
      for (var i = 0; i < 3; i++) {
        expect(guide.phase, MouthCapturePhase.values[i]);
        expect(guide.ready(Duration(seconds: 2 + i * 5)), isTrue);
        guide.measuring();
        expect(guide.readyAt, isNull);
        guide.advance(Duration(seconds: 5 + i * 5));
      }
      expect(guide.running, isFalse);
      guide.start(Duration.zero);
      guide.cancel();
      expect(guide.running, isFalse);
    },
  );
  test(
    'Lip gap and width are invariant under head roll, mirror, image size',
    () {
      for (final size in [
        const Size(400, 400),
        const Size(240, 320),
        const Size(640, 480),
      ]) {
        for (final angle in [-.6, 0.0, .6]) {
          for (final mirror in [false, true]) {
            final reading = FaceObservation.fromMap(
              mouthFrame(
                gap: .16,
                width: .7,
                tilt: angle,
                mirror: mirror,
                size: size,
              ),
            )!.mouthMeasurement!;
            expect(reading.gapRatio, closeTo(.16, 1e-8));
            expect(reading.widthRatio, closeTo(.7, 1e-8));
          }
        }
      }
    },
  );
  test(
    'Normal is normal; smile and talking use independent measured signals',
    () {
      final state = MouthMotionState();
      void update(double gap, double smile, {double width = .65}) =>
          state.update(
            measurement(gap: gap, smile: smile, width: width),
            jawOpen: .8,
            jawValid: true,
          );
      update(0, .05);
      expect(
        state.motion.atRest,
        isTrue,
        reason: 'Closed lips must override a large jaw score',
      );
      expect(state.neutralSamples, 1);
      update(0, .65, width: .75);
      expect(state.motion.openness, 0);
      expect(state.motion.smile, 1);
      expect(
        state.neutralSamples,
        1,
        reason: 'A smile cannot become the neutral width',
      );
      update(0, .35);
      expect(state.motion.smile, greaterThan(0));
      update(0, .28);
      expect(state.motion.smile, 0);
      update(.12, .05);
      final partial = state.motion.openness;
      expect(partial, inExclusiveRange(0, 1));
      update(.22, .65);
      expect(state.motion.openness, closeTo(1, 1e-8));
      expect(state.motion.smile, 1);
      update(.03, .05, width: .50);
      expect(state.motion.openness, lessThan(partial));
      expect(state.motion.widthScale, lessThan(1));
      update(0, .05);
      expect(state.motion.atRest, isTrue);
    },
  );
  test(
    'Missing or corrupt geometry resets smile and uses only valid jaw fallback',
    () {
      final original = mouthFrame();
      for (final bad in [
        null,
        [],
        [
          [double.nan, 0],
        ],
        List.filled(8, [.5, .5]),
        [...(original['mouthLandmarks'] as List).skip(1)],
      ]) {
        final face = FaceObservation.fromMap({
          ...original,
          'mouthLandmarks': bad,
        })!;
        expect(face.mouthMeasurement, isNull);
        expect(face.blinkValid, isTrue);
        expect(face.mouthValid, isTrue);
        final state = MouthMotionState()
          ..update(measurement(smile: .8), jawOpen: 0, jawValid: true);
        state.update(
          face.mouthMeasurement,
          jawOpen: face.mouthOpen,
          jawValid: face.mouthValid,
        );
        expect(state.motion.smile, 0);
        expect(state.motion.openness, 1);
        state.update(null, jawOpen: double.nan, jawValid: true);
        expect(state.motion.atRest, isTrue);
      }
    },
  );
  test('Missing smile data does not discard actual moving lips', () {
    final face = FaceObservation.fromMap({
      ...mouthFrame(gap: .12),
      'mouthSmileValid': false,
    })!;
    expect(face.mouthMeasurement, isNotNull);
    final state = MouthMotionState()
      ..update(face.mouthMeasurement, jawOpen: 0, jawValid: true);
    expect(state.motion.openness, greaterThan(0));
    expect(state.motion.smile, 0);
    state.reset();
    expect(state.motion.atRest, isTrue);
  });
  test(
    'Resting mouth smiles gently and every expression stays in its mouth band',
    () {
      for (final happy in [false, true]) {
        double smileDepth(MouthDrawing drawing) {
          final outline = drawing.path.computeMetrics().single;
          final corner = outline.getTangentForOffset(0)!.position;
          final center = outline
              .getTangentForOffset(outline.length / 4)!
              .position;
          return center.dy - corner.dy;
        }

        final rest = MouthDrawing.forMotion(const MouthMotion(), happy: happy);
        final smiling = MouthDrawing.forMotion(
          const MouthMotion(smile: 1),
          happy: happy,
        );
        if (!happy) {
          expect(smileDepth(rest), greaterThan(5));
          expect(smileDepth(rest), lessThan(smileDepth(smiling)));
        } else {
          expect(rest.path.computeMetrics().length, 3);
          expect(smiling.path.computeMetrics().length, 3);
          expect(rest.stroke, 0);
          expect(rest.bounds.top, closeTo(120.8, .001));
          expect(rest.bounds.bottom, closeTo(162.4, .001));
          expect(rest.path.contains(const Offset(124.8, 131.2)), isTrue);
          expect(rest.path.contains(const Offset(156, 152)), isTrue);
          expect(rest.path.contains(const Offset(187.2, 131.2)), isTrue);
          expect(rest.path.contains(const Offset(156, 131.2)), isFalse);
        }
        expect(rest.bounds.width, closeTo(happy ? 83.2 : 112, .01));
        for (final open in [0.0, .5, 1.0]) {
          for (final smile in [0.0, .5, 1.0]) {
            for (final width in [.68, 1.0, 1.28]) {
              final drawing = MouthDrawing.forMotion(
                MouthMotion(openness: open, smile: smile, widthScale: width),
                happy: happy,
              );
              final b = drawing.bounds;
              // Path coordinates are stored as floats; allow subpixel rounding.
              expect(b.top, greaterThanOrEqualTo((happy ? 112 : 160) - .0001));
              expect(b.bottom, lessThanOrEqualTo(200.0001));
              expect(b.left, greaterThan(0));
              expect(b.right, lessThan(312));
              expect(b.width, greaterThan(0));
            }
          }
        }
      }
    },
  );
  test(
    'Three-second diagnostic captures aggregate measurements and never save empty success',
    () {
      final capture = MouthDiagnosticCapture();
      capture.start(MouthCapturePhase.talk, Duration.zero);
      capture.add(measurement(gap: .02), 10);
      capture.add(measurement(gap: .20), 30);
      capture.add(null, 15);
      expect(capture.finishIfDue(const Duration(milliseconds: 2999)), isFalse);
      expect(capture.finishIfDue(const Duration(seconds: 3)), isTrue);
      expect(capture.completed!['samples'], 2);
      expect(capture.completed!['invalid'], 1);
      expect(capture.completed!['gapMin'], closeTo(.02, 1e-8));
      expect(capture.completed!['gapMax'], closeTo(.20, 1e-8));
      expect(capture.completed!['latencyMeanMs'], 20);
      capture.start(MouthCapturePhase.normal, const Duration(seconds: 4));
      capture.finishIfDue(const Duration(seconds: 7));
      expect(capture.summary, contains('no valid mouth samples'));
      capture.start(MouthCapturePhase.smile, const Duration(seconds: 8));
      capture.cancel();
      expect(capture.active, isFalse);
      expect(capture.completed, isNull);
    },
  );
}
