import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import '../../helpers/gesture_pose_fixture.dart';

void main() {
  DateTime at(int ms) => DateTime(2026).add(Duration(milliseconds: ms));
  for (final hand in ['Left', 'Right']) {
    HandObservation punch([double score = .9]) =>
        poseFixture(HandPose.punch, hand: hand, confidence: score);
    GestureFeedback feedback() => GestureFeedback(
      HandPose.punch,
      selectedHand: hand,
      freePlacement: true,
    );

    test(
      '$hand Social tolerates score jitter only after acquiring the pose',
      () {
        final f = feedback();
        for (var ms = 0; ms <= 1200; ms += 200) {
          f.update(punch(.4), at(ms));
          expect(f.isMatching, isFalse);
          expect(f.ready, isFalse);
        }
        f.update(punch(), at(1400));
        for (var ms = 1600; ms <= 2600; ms += 200) {
          f.update(punch(ms % 400 == 0 ? .4 : .9), at(ms));
          expect(f.isMatching, isTrue);
          expect(f.ready, ms == 2600);
        }
        f.reset();
        f.update(punch(.4), at(2800));
        expect(f.isMatching, isFalse);
      },
    );

    test(
      '$hand Social pauses brief blur, uncertainty and clipping without credit',
      () {
        for (final interrupted in [
          const HandObservation(),
          poseFixture(HandPose.punch, hand: hand, handScore: .5),
          placePose(punch(), center: Offset.zero, extent: .5),
          punch(.1),
        ]) {
          final f = feedback();
          for (final ms in [0, 200, 400]) {
            f.update(punch(), at(ms));
          }
          for (final ms in [600, 800]) {
            f.update(interrupted, at(ms));
            expect(f.ready, isFalse);
            expect(f.isMatching, isFalse);
            expect(f.canPause, isTrue);
          }
          for (var ms = 1000; ms <= 1800; ms += 200) {
            f.update(punch(), at(ms));
            expect(
              f.ready,
              ms == 1800,
              reason: 'Recovery and failed intervals earn no time',
            );
          }
        }
      },
    );

    test(
      '$hand wrong hand resets, including uncertain opposite-hand reports',
      () {
        for (final handScore in [.5, .99]) {
          final f = feedback();
          for (final ms in [0, 200, 400]) {
            f.update(punch(), at(ms));
          }
          f.update(
            poseFixture(
              HandPose.punch,
              hand: hand == 'Left' ? 'Right' : 'Left',
              handScore: handScore,
            ),
            at(600),
          );
          expect(f.canPause, isFalse);
          for (var ms = 800; ms <= 2000; ms += 200) {
            f.update(punch(), at(ms));
            expect(f.ready, ms == 2000);
          }
        }
      },
    );

    test('$hand long loss and stale results require a fresh strong match', () {
      for (final stale in [false, true]) {
        final f = feedback();
        for (final ms in [0, 200, 400]) {
          f.update(punch(), at(ms));
        }
        if (!stale) {
          for (final ms in [600, 800, 1000, 1200]) {
            f.update(const HandObservation(), at(ms));
            expect(f.ready, isFalse);
          }
        }
        for (var ms = 1400; ms <= 2600; ms += 200) {
          f.update(punch(.4), at(ms));
          expect(f.isMatching, isFalse);
          expect(f.ready, isFalse);
        }
      }
    });
  }
}
