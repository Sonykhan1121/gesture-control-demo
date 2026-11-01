import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/features/tutorials/face_tutorial_progress.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/mouth_tracking.dart';

FaceObservation observation({
  double x = .5,
  double y = .5,
  bool mouth = true,
}) => FaceObservation(
  center: Offset(x, y),
  confidence: .9,
  faceHeight: .3,
  imageSize: const Size(480, 640),
  mouthValid: mouth,
  mouthMeasurement: mouth
      ? const MouthMeasurement(
          points: [],
          imageSize: Size(480, 640),
          gapRatio: .1,
          widthRatio: .6,
          smileScore: .7,
          smileValid: true,
        )
      : null,
);

void main() {
  test('face needs continuous readings, not a stale single result', () {
    final p = FaceTutorialProgress(FaceLesson.findFace);
    p.update(observation(), const MouthMotion(), Duration.zero);
    p.update(observation(), const MouthMotion(), const Duration(seconds: 2));
    expect(p.matched, false);
    for (var ms = 2200; ms <= 3600; ms += 200) {
      p.update(observation(), const MouthMotion(), Duration(milliseconds: ms));
    }
    expect(p.matched, true);
  });
  for (final lesson in [FaceLesson.horizontal, FaceLesson.vertical]) {
    test('$lesson requires both directions and resets on lost face', () {
      final p = FaceTutorialProgress(lesson);
      FaceObservation pos(double v) => observation(
        x: lesson == FaceLesson.horizontal ? v : .5,
        y: lesson == FaceLesson.vertical ? v : .5,
      );
      p.update(pos(.5), const MouthMotion(), Duration.zero);
      p.update(pos(.4), const MouthMotion(), const Duration(milliseconds: 100));
      p.update(pos(.4), const MouthMotion(), const Duration(milliseconds: 300));
      expect(p.firstDirection, true);
      expect(p.matched, false);
      p.update(null, const MouthMotion(), const Duration(milliseconds: 400));
      expect(p.firstDirection, false);
      p.update(pos(.5), const MouthMotion(), const Duration(milliseconds: 500));
      p.update(pos(.4), const MouthMotion(), const Duration(milliseconds: 600));
      p.update(pos(.4), const MouthMotion(), const Duration(milliseconds: 800));
      p.update(pos(.6), const MouthMotion(), const Duration(milliseconds: 900));
      p.update(
        pos(.6),
        const MouthMotion(),
        const Duration(milliseconds: 1100),
      );
      expect(p.matched, true);
    });
  }
  test('smile uses measured expression, never resting artwork', () {
    final p = FaceTutorialProgress(FaceLesson.smile);
    for (var ms = 0; ms <= 2000; ms += 200) {
      p.update(observation(), const MouthMotion(), Duration(milliseconds: ms));
    }
    expect(p.matched, false);
    for (var ms = 2200; ms <= 3000; ms += 200) {
      p.update(
        observation(),
        const MouthMotion(smile: .4),
        Duration(milliseconds: ms),
      );
    }
    expect(p.matched, true);
  });
  test('talk requires repeated mouth variation with valid measurements', () {
    final p = FaceTutorialProgress(FaceLesson.talk);
    for (var ms = 0; ms <= 2000; ms += 200) {
      p.update(
        observation(),
        const MouthMotion(openness: .5),
        Duration(milliseconds: ms),
      );
    }
    expect(p.matched, false);
    for (final entry in [0.0, .4, 0.0, .4, 0.0].asMap().entries) {
      p.update(
        observation(),
        MouthMotion(openness: entry.value),
        Duration(milliseconds: 2200 + entry.key * 300),
      );
    }
    expect(p.matched, true);
    p.reset();
    for (final entry in [0.0, .4, 0.0, .4, 0.0].asMap().entries) {
      p.update(
        observation(mouth: false),
        MouthMotion(openness: entry.value),
        Duration(milliseconds: 4000 + entry.key * 300),
      );
    }
    expect(p.matched, false);
  });
}
