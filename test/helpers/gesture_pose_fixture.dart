import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

HandObservation poseFixture(
  HandPose pose, {
  double confidence = .95,
  String hand = 'Right',
  double handScore = .99,
}) {
  final p = <Offset>[
    const Offset(.5, .85),
    const Offset(.65, .75),
    const Offset(.72, .66),
    const Offset(.68, .60),
    const Offset(.57, .63),
    const Offset(.64, .58),
    const Offset(.65, .44),
    const Offset(.66, .30),
    const Offset(.67, .18),
    const Offset(.53, .55),
    const Offset(.53, .40),
    const Offset(.53, .26),
    const Offset(.53, .13),
    const Offset(.43, .57),
    const Offset(.42, .43),
    const Offset(.41, .31),
    const Offset(.40, .20),
    const Offset(.34, .61),
    const Offset(.32, .50),
    const Offset(.30, .41),
    const Offset(.28, .33),
  ];
  void curl(int base) {
    p[base + 2] = Offset(p[base + 1].dx, p[base].dy + .04);
    p[base + 3] = Offset(p[base].dx - .03, p[base].dy + .07);
  }

  if ([
    HandPose.pointUp,
    HandPose.pointDown,
    HandPose.pointLeft,
    HandPose.pointRight,
  ].contains(pose)) {
    for (final base in [9, 13, 17]) {
      curl(base);
    }
    for (var i = 0; i < p.length; i++) {
      final v = p[i];
      p[i] = switch (pose) {
        HandPose.pointRight => Offset(1 - v.dy, v.dx),
        HandPose.pointLeft => Offset(v.dy, 1 - v.dx),
        HandPose.pointDown => Offset(1 - v.dx, 1 - v.dy),
        _ => v,
      };
    }
  }
  if (pose == HandPose.ok) {
    p[8] = const Offset(.62, .48);
    p[4] = p[8];
  }
  if (pose == HandPose.rockOn) {
    curl(9);
    curl(13);
  }
  if (pose == HandPose.dorsal) {
    for (var i = 0; i < p.length; i++) {
      p[i] = Offset(1 - p[i].dx, p[i].dy);
    }
  }
  final label = switch (pose) {
    HandPose.fist || HandPose.punch => 'Closed_Fist',
    HandPose.victory => 'Victory',
    HandPose.thumbUp => 'Thumb_Up',
    HandPose.thumbDown => 'Thumb_Down',
    HandPose.openPalm || HandPose.dorsal => 'Open_Palm',
    _ => 'None',
  };
  return HandObservation(
    points: hand == 'Left'
        ? p
              .map(
                (v) => pose == HandPose.pointLeft || pose == HandPose.pointRight
                    ? Offset(v.dx, 1 - v.dy)
                    : Offset(1 - v.dx, v.dy),
              )
              .toList()
        : p,
    imageSize: const Size(1000, 1000),
    hand: hand,
    handScore: handScore,
    gesture: label,
    scores: {label: confidence},
    fistScore: pose == HandPose.fist || pose == HandPose.punch ? confidence : 0,
  );
}

/// Reposition/resize a known pose without changing its finger geometry.
HandObservation placePose(
  HandObservation sample, {
  required Offset center,
  required double extent,
}) {
  final minX = sample.points.map((p) => p.dx).reduce(math.min);
  final maxX = sample.points.map((p) => p.dx).reduce(math.max);
  final minY = sample.points.map((p) => p.dy).reduce(math.min);
  final maxY = sample.points.map((p) => p.dy).reduce(math.max);
  final origin = Offset((minX + maxX) / 2, (minY + maxY) / 2);
  final factor = extent / math.max(maxX - minX, maxY - minY);
  return HandObservation(
    points: sample.points.map((p) => center + (p - origin) * factor).toList(),
    worldPoints: sample.worldPoints,
    imageSize: sample.imageSize,
    hand: sample.hand,
    handScore: sample.handScore,
    mirrored: sample.mirrored,
    gesture: sample.gesture,
    scores: sample.scores,
    fistScore: sample.fistScore,
  );
}
