import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import '../../helpers/gesture_pose_fixture.dart';

void main() {
  test(
    'All eight Social lessons retain their original duration for either hand',
    () {
      for (final hand in ['Left', 'Right']) {
        for (final step in videoTutorialSteps) {
          final f = GestureFeedback(
            step.pose,
            selectedHand: hand,
            freePlacement: true,
          );
          expect(
            f.tolerance.holdWobbleGrace,
            const Duration(milliseconds: 500),
          );
          for (
            var ms = 0;
            ms <= f.tolerance.holdDuration.inMilliseconds;
            ms += 200
          ) {
            f.update(
              poseFixture(step.pose, hand: hand),
              DateTime(2026).add(Duration(milliseconds: ms)),
            );
            expect(
              f.ready,
              ms == f.tolerance.holdDuration.inMilliseconds,
              reason: '$hand ${step.title} at $ms',
            );
          }
          f.update(
            poseFixture(step.pose, hand: hand == 'Left' ? 'Right' : 'Left'),
            DateTime(2026).add(const Duration(milliseconds: 1400)),
          );
          expect(f.ready, isFalse);
        }
      }
    },
  );

  test(
    'Social allows natural 35-degree pointing tilt; Hand baseline stays strict',
    () {
      for (final hand in ['Left', 'Right']) {
        for (final pose in [
          HandPose.pointLeft,
          HandPose.pointRight,
          HandPose.pointUp,
        ]) {
          for (final degrees in [-35, 35]) {
            final sample = placePose(
              poseFixture(pose, hand: hand),
              center: const Offset(.5, .5),
              extent: .55,
            );
            final a = degrees * math.pi / 180;
            final tilted = HandObservation(
              points: sample.points.map((p) {
                final v = p - const Offset(.5, .5);
                return const Offset(.5, .5) +
                    Offset(
                      v.dx * math.cos(a) - v.dy * math.sin(a),
                      v.dx * math.sin(a) + v.dy * math.cos(a),
                    );
              }).toList(),
              imageSize: sample.imageSize,
              hand: sample.hand,
              handScore: sample.handScore,
              gesture: sample.gesture,
              scores: sample.scores,
            );
            final social = GestureFeedback(
              pose,
              selectedHand: hand,
              freePlacement: true,
            );
            final baseline = GestureFeedback(pose, selectedHand: hand);
            for (var ms = 0; ms <= 1200; ms += 200) {
              final now = DateTime(2026).add(Duration(milliseconds: ms));
              social.update(tilted, now);
              baseline.update(tilted, now);
            }
            expect(
              social.ready,
              isTrue,
              reason:
                  '$hand $pose $degrees score=${social.confidence} components=${social.components}',
            );
            expect(social.confidence, greaterThan(baseline.confidence));
          }
        }
      }
    },
  );
}
