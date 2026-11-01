import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/tutorials/gesture_debug_overlay.dart';
import 'package:hand_gesture/features/tutorials/gesture_diagnostics.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

import '../../helpers/gesture_pose_fixture.dart' show poseFixture;

void main() {
  test('all geometric poses expose details without changing score', () {
    for (final pose in HandPose.values) {
      for (final hand in ['Left', 'Right']) {
        final observation = poseFixture(pose, hand: hand);
        final feedback = GestureFeedback(pose, selectedHand: hand);
        feedback.update(observation, DateTime(2026));
        expect(feedback.confidence, gestureMatch(observation, pose));
        if (![HandPose.fist, HandPose.victory, HandPose.punch].contains(pose)) {
          expect(feedback.components, isNotEmpty, reason: '$hand ${pose.name}');
        }
        feedback.reset();
        expect(feedback.checks, isEmpty);
        expect(feedback.components, isEmpty);
      }
    }
  });

  testWidgets('small debug panel scrolls, explains fits, and collapses', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 300,
            height: 220,
            child: GestureDebugOverlay(
              target: 'Left · Scroll Down',
              status: 'Match the gesture shown in the guide',
              hold: '0.0 / 1.0 s',
              matching: false,
              complete: false,
              checks: const [
                GestureCheck('hand', 'Physical hand', 'Left / need Left', true),
                GestureCheck('pose', 'Pose score', '32.0% / need 45.0%', false),
              ],
              nativeReading: 'Model: None 0.0% · 3D points: 21/21',
              components: const {'indexExtended': .9, 'pointingDirection': .32},
            ),
          ),
        ),
      ),
    );
    expect(find.text('PASS'), findsOneWidget);
    expect(find.text('FAIL'), findsOneWidget);
    await tester.ensureVisible(
      find.byKey(const ValueKey('gesture-debug-details')),
    );
    await tester.tap(find.byKey(const ValueKey('gesture-debug-details')));
    await tester.pump();
    await tester.ensureVisible(find.text('Pointing direction: 32.0%'));
    await tester.pump();
    expect(find.textContaining('not accuracy'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('gesture-debug-toggle')));
    await tester.pump();
    expect(find.byKey(const ValueKey('gesture-debug-readings')), findsNothing);
    expect(find.text('0.0 / 1.0 s'), findsOneWidget);
    expect(find.text('Match the gesture shown in the guide'), findsOneWidget);
  });
}
