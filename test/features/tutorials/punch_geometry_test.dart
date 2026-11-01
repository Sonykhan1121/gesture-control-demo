import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/tutorials/punch_geometry.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

List<HandPoint3D> closedHand() {
  final p = List<HandPoint3D>.filled(21, const HandPoint3D(0, 0, 0));
  p[1] = const HandPoint3D(.035, .02, 0);
  p[2] = const HandPoint3D(.03, .035, -.01);
  p[3] = const HandPoint3D(.02, .04, -.01);
  p[4] = const HandPoint3D(.015, .045, -.01);
  for (final entry in {5: .03, 9: .01, 13: -.01, 17: -.03}.entries) {
    final base = entry.key, x = entry.value;
    p[base] = HandPoint3D(x, .06, 0);
    p[base + 1] = HandPoint3D(x, .085, 0);
    p[base + 2] = HandPoint3D(x, .07, -.02);
    p[base + 3] = HandPoint3D(x, .045, -.01);
  }
  return p;
}

HandObservation observation(List<HandPoint3D> p, {String hand = 'Right'}) =>
    HandObservation(
      points: List.filled(21, const Offset(.5, .5)),
      imageSize: const Size(480, 640),
      worldPoints: p,
      hand: hand,
      handScore: .99,
    );

void main() {
  test('Compact front Punch tolerates an occluded thumb depth outlier', () {
    final world = closedHand();
    world[4] = const HandPoint3D(.065, .12, -.01);
    final image = List<Offset>.filled(21, const Offset(.5, .5));
    image[5] = const Offset(.25, .4);
    image[17] = const Offset(.75, .42);
    image[8] = const Offset(.30, .60);
    image[12] = const Offset(.45, .62);
    image[16] = const Offset(.60, .62);
    image[20] = const Offset(.70, .60);
    image[4] = const Offset(.25, .64);
    HandObservation hand() => HandObservation(
      points: image,
      imageSize: const Size(480, 640),
      worldPoints: world,
      hand: 'Right',
      handScore: .99,
    );
    expect(gestureMatch(hand(), HandPose.punch), greaterThanOrEqualTo(.8));
    // A vertical knuckle row (the side-on thumbs-up/down view) must not use
    // the occluded-thumb fallback.
    image[5] = const Offset(.4, .25);
    image[17] = const Offset(.42, .75);
    expect(gestureMatch(hand(), HandPose.punch), lessThan(.55));
  });
  test('Depth-folded punch matches without a Closed_Fist model label', () {
    final hand = observation(closedHand());
    expect(hand.scoreFor('Closed_Fist'), 0);
    expect(gestureMatch(hand, HandPose.punch), greaterThanOrEqualTo(.8));
    final mirrored = observation(
      closedHand().map((p) => HandPoint3D(-p.x, p.y, p.z)).toList(),
      hand: 'Left',
    );
    expect(gestureMatch(mirrored, HandPose.punch), greaterThanOrEqualTo(.8));
  });
  test(
    'Extended index and extended thumb cannot qualify as punch geometry',
    () {
      final indexExtended = closedHand();
      indexExtended[6] = const HandPoint3D(.03, .085, 0);
      indexExtended[7] = const HandPoint3D(.03, .11, 0);
      indexExtended[8] = const HandPoint3D(.03, .13, 0);
      expect(punchGeometryMatch(observation(indexExtended)), lessThan(.55));
      final thumbExtended = closedHand();
      thumbExtended[4] = const HandPoint3D(.065, .12, -.01);
      expect(punchGeometryMatch(observation(thumbExtended)), lessThan(.55));
    },
  );
  test(
    'Missing depth or the wrong selected hand still prevents completion',
    () {
      expect(punchGeometryMatch(observation([])), 0);
      final feedback = GestureFeedback(HandPose.punch, selectedHand: 'Left');
      final start = DateTime(2026);
      for (final ms in [0, 500, 1000, 1500, 2000, 2500]) {
        feedback.update(
          observation(closedHand()),
          start.add(Duration(milliseconds: ms)),
        );
      }
      expect(feedback.ready, isFalse);
      expect(feedback.confidence, 0);
    },
  );
}
