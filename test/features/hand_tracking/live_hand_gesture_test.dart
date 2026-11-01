import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/hand_tracking/live_hand_gesture.dart';
import 'package:hand_gesture/features/hand_tracking/hand_gesture_icons.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import '../../helpers/gesture_pose_fixture.dart' show poseFixture;

void main() {
  test('All twelve Hand poses choose the filled selected-hand artwork', () {
    for (final hand in ['Left', 'Right']) {
      for (final step in gestureTutorialSteps) {
        if (step.pose == HandPose.punch) continue;
        final detected = detectHandGesture(
          poseFixture(step.pose, hand: hand),
          selectedHand: hand,
        );
        expect(detected?.pose, step.pose, reason: '${step.pose} / $hand');
        expect(
          detected?.asset,
          HandGestureIcons.forPose(step.pose, isLeftHand: hand == 'Left'),
        );
        expect(detected?.label, step.title);
      }
    }
  });

  test(
    'Captured public-photo native observations classify without tutorial placement',
    () {
      final fixtures =
          jsonDecode(
                File(
                  'test/fixtures/native-gesture-observations.json',
                ).readAsStringSync(),
              )
              as Map;
      for (final entry in {
        'fist.jpg': HandPose.fist,
        'thumb_up.jpg': HandPose.thumbUp,
        'victory.jpg': HandPose.victory,
        'pointing_up.jpg': HandPose.pointUp,
        'left_pointing_up.jpg': HandPose.pointUp,
      }.entries) {
        final observation = HandObservation.fromMap(
          Map<Object?, Object?>.from(fixtures[entry.key]),
        );
        expect(
          detectHandGesture(
            observation,
            selectedHand: observation.physicalHand,
          )?.pose,
          entry.value,
          reason: entry.key,
        );
        expect(
          detectHandGesture(
            observation,
            selectedHand: observation.physicalHand == 'Right'
                ? 'Left'
                : 'Right',
          ),
          isNull,
        );
      }
    },
  );

  test(
    'No hand, invalid frame, unknown/low-confidence or wrong physical hand cannot show an icon',
    () {
      expect(
        detectHandGesture(const HandObservation(), selectedHand: 'Right'),
        isNull,
      );
      final pose = poseFixture(HandPose.fist);
      for (final observation in [
        poseFixture(HandPose.fist, hand: 'Left'),
        poseFixture(HandPose.fist, handScore: .69),
        poseFixture(HandPose.fist, handScore: double.nan),
        HandObservation(
          points: pose.points,
          imageSize: Size(double.nan, 1),
          hand: 'Right',
          handScore: .99,
        ),
        HandObservation(
          points: List.filled(21, const Offset(double.nan, .5)),
          hand: 'Right',
          handScore: .99,
        ),
      ]) {
        expect(detectHandGesture(observation, selectedHand: 'Right'), isNull);
      }
    },
  );

  test(
    'Stability requires fresh repeated results and clears immediately for missing or wrong hands',
    () {
      final state = LiveHandGestureState();
      final fist = poseFixture(HandPose.fist);
      void update(HandObservation hand, int ms) =>
          state.update(hand, Duration(milliseconds: ms), selectedHand: 'Right');
      update(fist, 0);
      expect(state.status, contains('Stabilizing Fist'));
      update(fist, 100);
      expect(state.current, isNull);
      update(fist, 200);
      expect(state.current?.pose, HandPose.fist);
      expect(state.status, 'Showing Fist');
      update(poseFixture(HandPose.thumbUp), 280);
      expect(state.current?.pose, HandPose.fist);
      update(fist, 360);
      expect(state.current?.pose, HandPose.fist);
      update(poseFixture(HandPose.fist, hand: 'Left'), 440);
      expect(state.current, isNull);
      expect(
        state.status,
        contains('Wrong hand: detected Left, selected Right'),
      );
      update(fist, 520);
      update(fist, 720);
      expect(state.current?.pose, HandPose.fist);
      update(const HandObservation(), 800);
      expect(state.current, isNull);
      expect(state.status, 'No hand detected');
    },
  );

  test(
    'A new stable pose replaces the icon; stalled inference cannot freeze it',
    () {
      final state = LiveHandGestureState();
      void update(HandPose pose, int ms) => state.update(
        poseFixture(pose),
        Duration(milliseconds: ms),
        selectedHand: 'Right',
      );
      update(HandPose.fist, 0);
      update(HandPose.fist, 200);
      update(HandPose.thumbUp, 280);
      update(HandPose.thumbUp, 480);
      expect(state.current?.pose, HandPose.thumbUp);
      expect(state.expire(const Duration(milliseconds: 831)), isTrue);
      expect(state.current, isNull);
      update(HandPose.fist, 900);
      update(HandPose.fist, 2501);
      expect(
        state.current,
        isNull,
        reason: 'A gap cannot count as stable frames',
      );
    },
  );

  test(
    'slow recognition can stabilize while the watchdog hides stale icons',
    () {
      final state = LiveHandGestureState();
      final fist = poseFixture(HandPose.fist);
      state.update(fist, Duration.zero, selectedHand: 'Right');
      state.expire(const Duration(milliseconds: 400));
      state.update(
        fist,
        const Duration(milliseconds: 500),
        selectedHand: 'Right',
      );
      expect(state.current?.pose, HandPose.fist);
      state.expire(const Duration(milliseconds: 900));
      expect(state.current, isNull, reason: 'Do not freeze old artwork');
      state.update(
        fist,
        const Duration(milliseconds: 1000),
        selectedHand: 'Right',
      );
      state.expire(const Duration(milliseconds: 1400));
      state.update(
        fist,
        const Duration(milliseconds: 1500),
        selectedHand: 'Right',
      );
      expect(state.current?.pose, HandPose.fist);
      state.update(
        poseFixture(HandPose.fist, hand: 'Left'),
        const Duration(milliseconds: 1700),
        selectedHand: 'Right',
      );
      expect(
        state.current,
        isNull,
        reason: 'Wrong hand still clears immediately',
      );
    },
  );
}
