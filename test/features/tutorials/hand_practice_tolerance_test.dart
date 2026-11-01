import '../../helpers/gesture_pose_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/tutorials/gesture_tolerance.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

void main() {
  test('Only left Move Left and right Move Right get the outward profile', () {
    List<Object> values(GestureTolerance t) => [
      t.poseScore,
      t.handConfidence,
      t.insideRatio,
      t.minLongAxisRatio,
      t.minShortAxisRatio,
      t.outlineSlackX,
      t.outlineSlackY,
      t.holdDuration,
      t.holdWobbleGrace,
    ];
    for (final step in gestureTutorialSteps) {
      for (final hand in ['Left', 'Right']) {
        final feedback = GestureFeedback(
          step.pose,
          selectedHand: hand,
          handPractice: true,
        );
        final target =
            (hand == 'Left' && step.pose == HandPose.pointLeft) ||
            (hand == 'Right' && step.pose == HandPose.pointRight);
        final previous = GestureTolerance.handPractice(step.pose);
        if (target) {
          expect(feedback.tolerance.poseScore, .45);
          expect(
            feedback.tolerance.holdDuration,
            const Duration(milliseconds: 600),
          );
          expect(feedback.tolerance.insideRatio, .35);
          expect(feedback.tolerance.handConfidence, previous.handConfidence);
          for (var ms = 0; ms <= 600; ms += 200) {
            feedback.update(
              poseFixture(step.pose, hand: hand),
              DateTime(2026).add(Duration(milliseconds: ms)),
            );
            expect(feedback.ready, ms == 600);
          }
          feedback.update(
            poseFixture(step.pose, hand: hand == 'Left' ? 'Right' : 'Left'),
            DateTime(2026).add(const Duration(milliseconds: 800)),
          );
          expect(feedback.ready, isFalse);
          final opposite = step.pose == HandPose.pointLeft
              ? HandPose.pointRight
              : HandPose.pointLeft;
          for (var ms = 1000; ms <= 1800; ms += 200) {
            feedback.update(
              poseFixture(opposite, hand: hand),
              DateTime(2026).add(Duration(milliseconds: ms)),
            );
            expect(feedback.ready, isFalse);
          }
        } else {
          expect(
            values(feedback.tolerance),
            values(previous),
            reason: '$hand ${step.pose}',
          );
        }
        final social = GestureFeedback(
          step.pose,
          selectedHand: hand,
          handPractice: true,
          freePlacement: true,
        );
        expect(
          values(social.tolerance),
          values(GestureTolerance.socialPractice(step.pose)),
        );
      }
    }
  });
  test(
    'Only Hand practice relaxes alignment and duration for all thirteen poses',
    () {
      for (final step in gestureTutorialSteps) {
        final baseline = GestureTolerance.forPose(step.pose);
        final hand = GestureTolerance.handPractice(step.pose);
        expect(hand.poseScore, baseline.poseScore);
        expect(hand.handConfidence, baseline.handConfidence);
        expect(hand.insideRatio, lessThan(baseline.insideRatio));
        expect(hand.minLongAxisRatio, lessThan(baseline.minLongAxisRatio));
        expect(hand.minShortAxisRatio, lessThan(baseline.minShortAxisRatio));
        expect(hand.outlineSlackX, greaterThan(baseline.outlineSlackX));
        expect(hand.outlineSlackY, greaterThan(baseline.outlineSlackY));
        expect(hand.holdDuration, const Duration(milliseconds: 800));
        expect(
          baseline.holdDuration.inMilliseconds,
          step.pose == HandPose.pointDown ? 1000 : 1200,
        );
        expect(baseline.holdWobbleGrace, const Duration(milliseconds: 200));
        final social = GestureFeedback(
          step.pose,
          selectedHand: 'Left',
          freePlacement: true,
          handPractice: true,
        );
        expect(social.tolerance.holdDuration, baseline.holdDuration);
        expect(
          social.tolerance.holdWobbleGrace,
          const Duration(milliseconds: 500),
        );
      }
    },
  );
}
