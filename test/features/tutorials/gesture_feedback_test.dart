import '../../helpers/gesture_pose_fixture.dart';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:hand_gesture/features/tutorials/gesture_tolerance.dart';

void main() {
  test(
    'Social poses work at different positions and sizes with no outline target',
    () {
      for (final hand in ['Left', 'Right']) {
        for (final step in videoTutorialSteps) {
          for (final placement in [
            (const Offset(.025, .025), .04),
            (const Offset(.975, .025), .04),
            (const Offset(.025, .975), .04),
            (const Offset(.975, .975), .04),
            (const Offset(.5, .5), .12),
            (const Offset(.5, .5), .85),
          ]) {
            final sample = placePose(
              poseFixture(step.pose, hand: hand),
              center: placement.$1,
              extent: placement.$2,
            );
            final feedback = GestureFeedback(
              step.pose,
              selectedHand: hand,
              freePlacement: true,
            );
            final requiredMs = feedback.tolerance.holdDuration.inMilliseconds;
            for (var ms = 0; ms <= requiredMs; ms += 200) {
              feedback.update(
                sample,
                DateTime(2026).add(Duration(milliseconds: ms)),
              );
              expect(
                feedback.isMatching,
                isTrue,
                reason: '$hand ${step.title} at $placement',
              );
            }
            expect(feedback.ready, isTrue);
          }
        }
      }
    },
  );
  test(
    'Social size independence retains wrong-hand, wrong-pose, visibility and confidence checks',
    () {
      final small = placePose(
        poseFixture(HandPose.pointUp),
        center: const Offset(.025, .025),
        extent: .04,
      );
      expect(
        gestureMatch(small, HandPose.pointUp),
        0,
        reason: 'Normal Hand practice keeps its size check',
      );
      expect(
        gestureMatch(small, HandPose.pointUp, freePlacement: true),
        greaterThan(.55),
      );
      for (final sample in [
        placePose(
          poseFixture(HandPose.pointDown),
          center: const Offset(.025, .025),
          extent: .04,
        ),
        placePose(
          poseFixture(HandPose.pointUp, hand: 'Left'),
          center: const Offset(.025, .025),
          extent: .04,
        ),
        placePose(
          poseFixture(HandPose.pointUp, handScore: .2),
          center: const Offset(.025, .025),
          extent: .04,
        ),
        placePose(
          poseFixture(HandPose.pointUp),
          center: Offset.zero,
          extent: .04,
        ),
        const HandObservation(),
        HandObservation(points: List.filled(21, const Offset(double.nan, .5))),
      ]) {
        final feedback = GestureFeedback(
          HandPose.pointUp,
          selectedHand: 'Right',
          freePlacement: true,
        );
        for (var ms = 0; ms <= 1600; ms += 200) {
          feedback.update(
            sample,
            DateTime(2026).add(Duration(milliseconds: ms)),
          );
        }
        expect(feedback.ready, isFalse);
        expect(feedback.isMatching, isFalse);
      }
    },
  );

  test('An explicitly requested release needs the selected hand to open', () {
    final start = DateTime(2026);
    final feedback = GestureFeedback(
      HandPose.punch,
      selectedHand: 'Right',
      requireRelease: true,
    );
    for (final ms in [0, 400, 800, 1200, 1600]) {
      feedback.update(
        poseFixture(HandPose.punch),
        start.add(Duration(milliseconds: ms)),
      );
      expect(feedback.isMatching, isFalse);
    }
    feedback.update(
      poseFixture(HandPose.openPalm, hand: 'Left'),
      start.add(const Duration(milliseconds: 2000)),
    );
    expect(feedback.awaitingRelease, isTrue);
    feedback.update(
      poseFixture(HandPose.openPalm),
      start.add(const Duration(milliseconds: 2400)),
    );
    expect(feedback.awaitingRelease, isFalse);
    for (final ms in [2800, 3200, 3600, 4000]) {
      feedback.update(
        poseFixture(HandPose.punch),
        start.add(Duration(milliseconds: ms)),
      );
    }
    expect(feedback.ready, isTrue);
  });
  test('All poses use the relaxed hand confidence boundary for both hands', () {
    for (final pose in HandPose.values) {
      final minimum = GestureTolerance.forPose(pose).handConfidence;
      for (final selected in ['Left', 'Right']) {
        final feedback = GestureFeedback(pose, selectedHand: selected);
        feedback.update(
          poseFixture(pose, hand: selected, handScore: minimum - .0001),
          DateTime(2026),
        );
        expect(feedback.isMatching, isFalse);
        expect(feedback.canPause, isFalse);
        feedback.update(
          poseFixture(pose, hand: selected, handScore: minimum),
          DateTime(2026),
        );
        expect(feedback.isMatching, isTrue, reason: '$pose / $selected');
        expect(feedback.canPause, isTrue);
      }
    }
  });
  test(
    'Classifier-based Fist, Punch and Victory accept their new score boundaries',
    () {
      for (final pose in [HandPose.fist, HandPose.punch, HandPose.victory]) {
        final minimum = GestureTolerance.forPose(pose).poseScore;
        final feedback = GestureFeedback(pose, selectedHand: 'Right');
        feedback.update(
          poseFixture(pose, confidence: minimum - .0001),
          DateTime(2026),
        );
        expect(feedback.isMatching, isFalse);
        feedback.update(poseFixture(pose, confidence: minimum), DateTime(2026));
        expect(feedback.isMatching, isTrue);
      }
    },
  );
  test(
    'Down accepts a bent index and loosely curled fingers for both hands',
    () {
      for (final hand in ['Left', 'Right']) {
        final sample = poseFixture(HandPose.pointDown, hand: hand);
        final points = [...sample.points];
        final u = points[5] - points[6];
        final angle = 118 * math.pi / 180;
        points[7] =
            points[6] +
            Offset(
              u.dx * math.cos(angle) - u.dy * math.sin(angle),
              u.dx * math.sin(angle) + u.dy * math.cos(angle),
            );
        for (final base in [9, 13, 17]) {
          final reach = points[base + 1] - points[0];
          points[base + 2] = points[0] + reach * 1.06;
          points[base + 3] = points[0] + reach * 1.175;
        }
        final relaxed = HandObservation(
          points: points,
          imageSize: sample.imageSize,
          hand: hand,
          handScore: .7,
        );
        final feedback = GestureFeedback(
          HandPose.pointDown,
          selectedHand: hand,
        );
        feedback.update(relaxed, DateTime(2026));
        expect(feedback.isMatching, isTrue, reason: hand);
        expect(gestureMatch(relaxed, HandPose.pointUp), 0);
      }
    },
  );
  test('Point Down tolerates about 65-degree tilt for both hands', () {
    for (final hand in ['Left', 'Right']) {
      for (final tilt in [-90.0, -66.0, -64.5, 64.5, 66.0, 90.0, 180.0]) {
        final sample = poseFixture(HandPose.pointDown, hand: hand);
        final finger = sample.points[8] - sample.points[5];
        // Rotate the index itself, accounting for the fixture's initial lean.
        final angle =
            math.pi / 2 -
            tilt * math.pi / 180 -
            math.atan2(finger.dy, finger.dx);
        final tilted = HandObservation(
          points: sample.points.map((p) {
            final x = p.dx - .5, y = p.dy - .5;
            return Offset(
              .5 + x * math.cos(angle) - y * math.sin(angle),
              .5 + x * math.sin(angle) + y * math.cos(angle),
            );
          }).toList(),
          imageSize: sample.imageSize,
          hand: hand,
          handScore: .99,
        );
        expect(
          gestureMatch(tilted, HandPose.pointDown),
          tilt.abs() < 65 ? greaterThanOrEqualTo(.45) : lessThan(.45),
          reason: '$hand at $tilt degrees',
        );
        if (tilt.abs() < 65) expect(gestureMatch(tilted, HandPose.pointUp), 0);
        final feedback = GestureFeedback(
          HandPose.pointDown,
          selectedHand: hand == 'Left' ? 'Right' : 'Left',
        );
        feedback.update(tilted, DateTime(2026));
        expect(feedback.isMatching, isFalse);
      }
    }
  });
  test('Down keeps a one-second hold with the reduced 45 percent score', () {
    for (final step in [
      ...gestureTutorialSteps,
      ...videoTutorialSteps,
    ].where((step) => step.pose == HandPose.pointDown)) {
      final tolerance = GestureTolerance.forPose(step.pose);
      expect(tolerance.poseScore, .45);
      expect(tolerance.holdDuration, const Duration(seconds: 1));
      expect(tolerance.handConfidence, .70);
    }
  });
  test('Open fingers cannot pass the relaxed downward-pointing pose', () {
    final open = poseFixture(HandPose.openPalm);
    final downwardOpen = HandObservation(
      points: open.points.map((p) => Offset(1 - p.dx, 1 - p.dy)).toList(),
      imageSize: open.imageSize,
      hand: open.hand,
    );
    expect(gestureMatch(downwardOpen, HandPose.pointDown), lessThan(.45));
  });
  for (final pose in HandPose.values) {
    test('${pose.name} matches its own valid pose', () {
      expect(gestureMatch(poseFixture(pose), pose), greaterThanOrEqualTo(.8));
      expect(gestureMatch(const HandObservation(), pose), 0);
    });
  }
  test('Opposite pointing directions and open/dorsal faces are distinct', () {
    expect(
      gestureMatch(poseFixture(HandPose.pointLeft), HandPose.pointRight),
      0,
    );
    expect(gestureMatch(poseFixture(HandPose.pointDown), HandPose.pointUp), 0);
    expect(gestureMatch(poseFixture(HandPose.dorsal), HandPose.openPalm), 0);
    expect(gestureMatch(poseFixture(HandPose.openPalm), HandPose.dorsal), 0);
    expect(gestureMatch(poseFixture(HandPose.victory), HandPose.fist), 0);
  });
  test('Palm/dorsal recognition is consistent for both mirrored hands', () {
    for (final pose in [HandPose.openPalm, HandPose.dorsal]) {
      final right = poseFixture(pose);
      final left = HandObservation(
        points: right.points.map((p) => Offset(1 - p.dx, p.dy)).toList(),
        imageSize: right.imageSize,
        hand: 'Left',
        scores: right.scores,
      );
      expect(gestureMatch(left, pose), greaterThanOrEqualTo(.8));
    }
  });
  test('Clipped, invalid and ambiguous small hands never qualify', () {
    final sample = poseFixture(HandPose.pointUp);
    final clipped = [...sample.points]..[8] = const Offset(.5, -.1);
    expect(
      gestureMatch(
        HandObservation(points: clipped, imageSize: sample.imageSize),
        HandPose.pointUp,
      ),
      0,
    );
    expect(
      gestureMatch(
        HandObservation(points: List.filled(21, const Offset(double.nan, .5))),
        HandPose.ok,
      ),
      0,
    );
    expect(
      gestureMatch(
        HandObservation(points: List.filled(21, const Offset(.5, .5))),
        HandPose.pointUp,
      ),
      0,
    );
  });
  test('all 20 tutorials accept only the selected hand for the full hold', () {
    final start = DateTime(2026);
    for (final step in [...gestureTutorialSteps, ...videoTutorialSteps]) {
      for (final selected in ['Left', 'Right']) {
        final opposite = selected == 'Left' ? 'Right' : 'Left';
        final feedback = GestureFeedback(step.pose, selectedHand: selected);
        for (final ms in [0, 500, 1000, 1500, 2000, 2500]) {
          expect(
            feedback.update(
              poseFixture(step.pose, hand: opposite),
              start.add(Duration(milliseconds: ms)),
            ),
            'Use your $selected hand',
          );
          expect(feedback.ready, isFalse);
          expect(feedback.isMatching, isFalse);
          expect(feedback.confidence, 0);
        }
        final requiredMs = feedback.tolerance.holdDuration.inMilliseconds;
        for (var ms = 3000; ms < 3000 + requiredMs; ms += 200) {
          feedback.update(
            poseFixture(step.pose, hand: selected),
            start.add(Duration(milliseconds: ms)),
          );
          expect(feedback.ready, isFalse);
          expect(
            feedback.isMatching,
            isTrue,
            reason: '${step.title}: selected $selected hand should qualify',
          );
        }
        feedback.update(
          poseFixture(step.pose, hand: selected),
          start.add(Duration(milliseconds: 3000 + requiredMs)),
        );
        expect(feedback.ready, isTrue);
      }
    }
  });
  test(
    'wrong or uncertain hand resets the hold and the lime outline state',
    () {
      final start = DateTime(2026);
      final feedback = GestureFeedback(HandPose.fist, selectedHand: 'Right');
      for (final invalid in [
        poseFixture(HandPose.fist, hand: 'Left'),
        poseFixture(HandPose.fist, hand: ''),
        poseFixture(HandPose.fist, hand: 'Unknown'),
        poseFixture(HandPose.fist, handScore: .7499),
        poseFixture(HandPose.fist, handScore: double.nan),
        poseFixture(HandPose.fist, handScore: 1.1),
      ]) {
        feedback.reset();
        for (final ms in [0, 500, 1000]) {
          feedback.update(
            poseFixture(HandPose.fist),
            start.add(Duration(milliseconds: ms)),
          );
        }
        expect(feedback.isMatching, isTrue);
        feedback.update(invalid, start.add(const Duration(milliseconds: 1500)));
        expect(feedback.isMatching, isFalse);
        expect(feedback.confidence, 0);
        for (final ms in [2000, 2400, 2800, 3199]) {
          feedback.update(
            poseFixture(HandPose.fist, handScore: .8),
            start.add(Duration(milliseconds: ms)),
          );
          expect(feedback.ready, isFalse);
        }
        feedback.update(
          poseFixture(HandPose.fist, handScore: .8),
          start.add(const Duration(milliseconds: 3200)),
        );
        expect(feedback.ready, isTrue);
      }
    },
  );
  test('the opposite hand cannot release the repeated-fist gate', () {
    final start = DateTime(2026);
    final feedback = GestureFeedback(
      HandPose.fist,
      selectedHand: 'Right',
      requireRelease: true,
    );
    feedback.update(poseFixture(HandPose.openPalm, hand: 'Left'), start);
    for (final ms in [500, 1000, 1500, 2000, 2500]) {
      feedback.update(
        poseFixture(HandPose.fist),
        start.add(Duration(milliseconds: ms)),
      );
      expect(feedback.isMatching, isFalse);
      expect(feedback.ready, isFalse);
    }
    feedback.update(
      poseFixture(HandPose.openPalm),
      start.add(const Duration(milliseconds: 3000)),
    );
    for (final ms in [3500, 4000, 4500, 5000, 5500]) {
      feedback.update(
        poseFixture(HandPose.fist),
        start.add(Duration(milliseconds: ms)),
      );
    }
    expect(feedback.ready, isTrue);
  });

  test(
    'Hold requires fresh 55 percent results for 1.2s and resets after a long dip or gap',
    () {
      final feedback = GestureFeedback(HandPose.victory, selectedHand: 'Right');
      final start = DateTime(2026);
      void frame(int ms, double score) => feedback.update(
        poseFixture(HandPose.victory, confidence: score),
        start.add(Duration(milliseconds: ms)),
      );
      frame(0, .5499);
      frame(500, .5499);
      frame(1000, .5499);
      expect(feedback.ready, isFalse);
      expect(feedback.isMatching, isFalse);
      frame(1100, .55);
      expect(feedback.isMatching, isTrue);
      expect(feedback.ready, isFalse);
      frame(1600, .55);
      frame(2100, .55);
      expect(feedback.isMatching, isTrue);
      expect(feedback.ready, isFalse);
      frame(2299, .55);
      expect(feedback.ready, isFalse);
      frame(2300, .55);
      expect(feedback.ready, isTrue);
      frame(2400, .5499);
      expect(feedback.isMatching, isFalse);
      expect(feedback.ready, isFalse);
      frame(3300, .9);
      frame(4400, .9);
      expect(feedback.ready, isFalse);
      frame(4900, .9);
      frame(5400, .9);
      expect(feedback.ready, isFalse);
      frame(5900, .9);
      frame(6400, .9);
      expect(feedback.ready, isTrue);
      feedback.update(
        const HandObservation(),
        start.add(const Duration(milliseconds: 6500)),
      );
      expect(feedback.ready, isFalse);
      expect(feedback.isMatching, isFalse);
    },
  );
  test('An explicitly enabled release gate requires a real release', () {
    final feedback = GestureFeedback(
      HandPose.fist,
      selectedHand: 'Right',
      requireRelease: true,
    );
    final start = DateTime(2026);
    for (final ms in [0, 500, 1000, 1500]) {
      feedback.update(
        poseFixture(HandPose.fist),
        start.add(Duration(milliseconds: ms)),
      );
      expect(feedback.ready, isFalse);
    }
    feedback.update(
      poseFixture(HandPose.fist, confidence: .79),
      start.add(const Duration(milliseconds: 1600)),
    );
    for (final ms in [1700, 2200, 2700]) {
      feedback.update(
        poseFixture(HandPose.fist),
        start.add(Duration(milliseconds: ms)),
      );
      expect(
        feedback.ready,
        isFalse,
        reason: 'A confidence dip is not a physical release',
      );
    }
    feedback.update(
      const HandObservation(),
      start.add(const Duration(milliseconds: 2800)),
    );
    feedback.update(
      poseFixture(HandPose.fist),
      start.add(const Duration(milliseconds: 2900)),
    );
    expect(
      feedback.ready,
      isFalse,
      reason: 'A missing frame is not a physical release',
    );
    feedback.update(
      poseFixture(HandPose.openPalm),
      start.add(const Duration(milliseconds: 3000)),
    );
    for (final ms in [3100, 3600, 4100, 4600, 5100]) {
      feedback.update(
        poseFixture(HandPose.fist),
        start.add(Duration(milliseconds: ms)),
      );
    }
    expect(feedback.ready, isTrue);
  });
}
