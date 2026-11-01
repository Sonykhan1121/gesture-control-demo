import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'punch_geometry.dart';
import 'gesture_hold.dart';
import 'gesture_tolerance.dart';
import 'gesture_diagnostics.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';

/// Native classifier confidence for supported poses; continuous landmark fit
/// for directions, thumbs, OK, Rock On and Dorsal. Fit is not a model probability.
double gestureMatch(
  HandObservation hand,
  HandPose target, {
  bool freePlacement = false,
  void Function(String name, double fit)? onPoseComponent,
}) {
  if (!hand.hasHand ||
      !hand.imageSize.width.isFinite ||
      !hand.imageSize.height.isFinite ||
      hand.imageSize.width <= 0 ||
      hand.imageSize.height <= 0) {
    return 0;
  }
  if (!_wholeHandVisible(hand, freePlacement: freePlacement)) {
    return 0;
  }
  switch (target) {
    case HandPose.fist:
      return hand.scoreFor('Closed_Fist');
    case HandPose.punch:
      return math.max(
        hand.scoreFor('Closed_Fist'),
        punchGeometryMatch(hand, onComponent: onPoseComponent),
      );
    case HandPose.victory:
      return hand.scoreFor('Victory');
    default:
      break;
  }
  var p = hand.points
      .map(
        (v) =>
            Offset(v.dx * hand.imageSize.width, v.dy * hand.imageSize.height),
      )
      .toList();
  final thumbModelScore = switch (target) {
    HandPose.thumbUp => hand.scoreFor('Thumb_Up'),
    HandPose.thumbDown => hand.scoreFor('Thumb_Down'),
    _ => 0.0,
  };
  var scale = (p[5] - p[17]).distance;
  if (scale < .0001 ||
      (!freePlacement &&
          scale <
              math.min(hand.imageSize.width, hand.imageSize.height) * .035)) {
    onPoseComponent?.call('palmLargeEnoughForShape', 0);
    return thumbModelScore;
  }
  if (freePlacement) {
    // Social practice judges finger geometry, independent of camera position
    // and apparent size. Normalize to the wrist and palm span, not the demo PNG.
    final wrist = p[0];
    p = p.map((point) => (point - wrist) / scale).toList();
    scale = 1;
  }
  double rise(double value, double low, double high) =>
      ((value - low) / (high - low)).clamp(0.0, 1.0);
  double fall(double value, double low, double high) =>
      1 - rise(value, low, high);
  double angle(int a, int b, int c) {
    final u = p[a] - p[b], v = p[c] - p[b];
    final denominator = u.distance * v.distance;
    if (denominator < .0001) return 0;
    return math.acos(
          ((u.dx * v.dx + u.dy * v.dy) / denominator).clamp(-1.0, 1.0),
        ) *
        180 /
        math.pi;
  }

  double extended(int base, {bool relaxed = false}) {
    final distance = (p[base + 1] - p[0]).distance;
    if (distance < .0001) return 0;
    final reach = (p[base + 3] - p[0]).distance / distance;
    return math.min(
      rise(
        angle(base, base + 1, base + 2),
        relaxed ? 95 : 120,
        relaxed ? 145 : 170,
      ),
      rise(reach, relaxed ? .92 : 1.02, relaxed ? 1.18 : 1.32),
    );
  }

  double curled(int base, {bool relaxed = false}) {
    final distance = (p[base + 1] - p[0]).distance;
    if (distance < .0001) return 0;
    final reach = (p[base + 3] - p[0]).distance / distance;
    return math.max(
      fall(
        angle(base, base + 1, base + 2),
        relaxed ? 110 : 100,
        relaxed ? 178 : 155,
      ),
      fall(reach, relaxed ? 1.02 : .9, relaxed ? 1.34 : 1.15),
    );
  }

  double minimum(List<double> values) => values.reduce(math.min);
  double componentMinimum(Map<String, double> values) {
    if (onPoseComponent != null) values.forEach(onPoseComponent);
    return minimum(values.values.toList());
  }

  final index = extended(5),
      middle = extended(9),
      ring = extended(13),
      pinky = extended(17);
  if (target == HandPose.thumbUp || target == HandPose.thumbDown) {
    // Back/side-facing thumbs may have low canned-classifier confidence.
    // Independently fit a straight, separated thumb and four curled fingers.
    // Keep the original model probability intact in HandObservation.scores.
    final thumb = p[4] - p[2];
    if (thumb.distance < .0001) {
      onPoseComponent?.call('thumbReach', 0);
      return thumbModelScore;
    }
    final sign = target == HandPose.thumbUp ? -1.0 : 1.0;
    final fingertipsY = (p[8].dy + p[12].dy + p[16].dy + p[20].dy) / 4;
    final components = <String, double>{
      'indexCurled': curled(5, relaxed: freePlacement),
      'middleCurled': curled(9, relaxed: freePlacement),
      'ringCurled': curled(13, relaxed: freePlacement),
      'pinkyCurled': curled(17, relaxed: freePlacement),
      // A naturally bent thumb projects to ~150 degrees in the approved pose.
      // Requiring near-180-degree extension rejects a correctly raised thumb.
      'thumbStraight': rise(angle(2, 3, 4), 110, 150),
      'thumbReach': rise(thumb.distance / scale, .45, .75),
      // Do not require a second radial distance from the index knuckle:
      // perspective foreshortens it. Vertical tip separation below already
      // requires the thumb to extend beyond the four curled fingers.
      'thumbVertical': rise(sign * thumb.dy / thumb.distance, .65, .9),
      'thumbBeyondFingers': rise(
        sign * (p[4].dy - fingertipsY) / scale,
        .3,
        .7,
      ),
    };
    if (onPoseComponent != null) components.forEach(onPoseComponent);
    final geometryFit = minimum(components.values.toList());
    return math.max(thumbModelScore, geometryFit);
  }
  if (target == HandPose.ok) {
    return componentMinimum({
      'thumbIndexTouch': fall((p[4] - p[8]).distance / scale, .16, .6),
      'middleExtended': middle,
      'ringExtended': ring,
      'pinkyExtended': pinky,
    });
  }
  if (target == HandPose.rockOn) {
    return componentMinimum({
      'indexExtended': index,
      'pinkyExtended': pinky,
      'middleCurled': curled(9, relaxed: freePlacement),
      'ringCurled': curled(13, relaxed: freePlacement),
      'thumbTucked': fall((p[4] - p[5]).distance / scale, .7, 1.2),
    });
  }
  if (target == HandPose.dorsal || target == HandPose.openPalm) {
    if (hand.hand != 'Left' && hand.hand != 'Right') return 0;
    final u = p[5] - p[0], v = p[17] - p[0];
    final denominator = u.distance * v.distance;
    if (denominator < .0001) return 0;
    // Use the native image-space label, not the normalized physical hand.
    final facing =
        (u.dx * v.dy - u.dy * v.dx) /
        denominator *
        (hand.hand == 'Right' ? -1 : 1);
    final orientation = rise(
      target == HandPose.openPalm ? facing : -facing,
      .15,
      .5,
    );
    final fingers = math.max(
      minimum([index, middle, ring, pinky]),
      hand.scoreFor('Open_Palm'),
    );
    return componentMinimum({
      'fingersExtended': fingers,
      'palmFacing': orientation,
    });
  }
  final direction = p[8] - p[5];
  final down = target == HandPose.pointDown;
  if (direction.distance < scale * (down ? .3 : .4)) {
    onPoseComponent?.call('indexReach', 0);
    return 0;
  }
  final axis = switch (target) {
    HandPose.pointRight => const Offset(1, 0),
    HandPose.pointLeft => const Offset(-1, 0),
    HandPose.pointUp => const Offset(0, -1),
    HandPose.pointDown => const Offset(0, 1),
    _ => Offset.zero,
  };
  final alignment =
      (direction.dx * axis.dx + direction.dy * axis.dy) / direction.distance;
  // Downward pointing and Social practice allow natural finger bending.
  // The other three fingers must still curl, and the direction must match.
  final pointing = math.max(
    (down || freePlacement) ? extended(5, relaxed: true) : index,
    hand.scoreFor('Pointing_Up'),
  );
  return componentMinimum({
    'indexExtended': pointing,
    'middleCurled': curled(9, relaxed: down || freePlacement),
    'ringCurled': curled(13, relaxed: down || freePlacement),
    'pinkyCurled': curled(17, relaxed: down || freePlacement),
    // At the Down threshold of .45 this accepts about 65 degrees of tilt.
    'pointingDirection': down
        ? fall(math.acos(alignment.clamp(-1.0, 1.0)) * 180 / math.pi, 40, 85)
        : freePlacement
        ? rise(alignment, .55, .94)
        : rise(alignment, .7, .97),
  });
}

bool _wholeHandVisible(HandObservation hand, {required bool freePlacement}) {
  final margin = freePlacement ? 0.0 : .01;
  return !hand.points.any(
    (p) =>
        p.dx < margin ||
        p.dx > 1 - margin ||
        p.dy < margin ||
        p.dy > 1 - margin,
  );
}

/// Pose-only feedback; the guide uses the same hold logic with placement too.
/// Callers can optionally require a release between repeated non-Punch poses.
class GestureFeedback {
  GestureFeedback(
    this.pose, {
    required this.selectedHand,
    bool requireRelease = false,
    this.freePlacement = false,
    bool handPractice = false,
  }) : _awaitingRelease = requireRelease,
       tolerance = freePlacement
           ? GestureTolerance.socialPractice(pose)
           : handPractice
           ? GestureTolerance.handPractice(pose, selectedHand: selectedHand)
           : GestureTolerance.forPose(pose) {
    _hold = GestureHold(
      tolerance.holdDuration,
      wobbleGrace: tolerance.holdWobbleGrace,
    );
  }

  final HandPose pose;

  /// Social lessons use pose geometry anywhere in the camera frame.
  /// Normal Hand lessons retain their existing visibility/size safeguards.
  final bool freePlacement;
  final GestureTolerance tolerance;
  late final GestureHold _hold;

  double get poseThreshold => _hold.isMatching || _hold.progress > 0
      ? tolerance.continuingPoseScore
      : tolerance.poseScore;
  final String selectedHand;
  bool _awaitingRelease;
  bool get ready => _hold.ready;
  bool canPause = false;
  double confidence = 0;
  final List<GestureCheck> checks = [];
  final Map<String, double> components = {};

  /// A valid match is being held, including before automatic advancement.
  bool get isMatching => _hold.isMatching;
  bool get awaitingRelease => _awaitingRelease;

  void reset() {
    _hold.reset();
    canPause = false;
    confidence = 0;
    checks.clear();
    components.clear();
  }

  String update(HandObservation observation, DateTime now) {
    // Expire before choosing a retention threshold; stale progress must never
    // make it easier to start a new attempt.
    _hold.expire(now);
    canPause = false;
    confidence = 0;
    checks.clear();
    components.clear();
    final tracked =
        observation.hasHand &&
        observation.imageSize.width.isFinite &&
        observation.imageSize.height.isFinite &&
        observation.imageSize.width > 0 &&
        observation.imageSize.height > 0;
    checks.add(
      GestureCheck(
        'tracking',
        'Tracking',
        tracked ? '21/21 valid landmarks' : 'No complete hand / invalid frame',
        tracked,
      ),
    );
    if (!tracked) {
      _trackingInterrupted(now);
      return 'Show your $selectedHand hand to the camera';
    }
    // Gate before matching and before release detection: the opposite hand
    // cannot advance, turn the guide lime, or rearm a repeated fist tutorial.
    final reliableHand =
        observation.physicalHand.isNotEmpty &&
        observation.handScore.isFinite &&
        observation.handScore >= tolerance.handConfidence &&
        observation.handScore <= 1;
    checks.add(
      GestureCheck(
        'hand-confidence',
        'Hand confidence',
        '${gesturePercent(observation.handScore)} / need ${gesturePercent(tolerance.handConfidence)}',
        reliableHand,
      ),
    );
    final correctHand = observation.physicalHand == selectedHand;
    checks.add(
      GestureCheck(
        'hand',
        'Physical hand',
        '${observation.physicalHand.isEmpty ? 'Unknown' : observation.physicalHand} / need $selectedHand',
        correctHand,
      ),
    );
    if (!reliableHand) {
      if (observation.physicalHand.isNotEmpty && !correctHand) {
        _hold.reset();
      } else {
        _trackingInterrupted(now);
      }
      return 'Show your $selectedHand hand clearly';
    }
    if (!correctHand) {
      _hold.reset();
      return 'Use your $selectedHand hand';
    }
    confidence = gestureMatch(
      observation,
      pose,
      freePlacement: freePlacement,
      onPoseComponent: (name, fit) => components[name] = fit,
    );
    final wholeHand = _wholeHandVisible(
      observation,
      freePlacement: freePlacement,
    );
    checks.add(
      GestureCheck(
        'visibility',
        'Whole hand',
        wholeHand ? 'Inside camera edges' : 'Clipped at camera edge',
        wholeHand,
      ),
    );
    checks.add(
      GestureCheck(
        'pose',
        'Pose score',
        wholeHand
            ? '${gesturePercent(confidence)} / need ${gesturePercent(poseThreshold)}'
            : 'Not evaluated: hand clipped',
        wholeHand ? confidence >= poseThreshold : null,
      ),
    );
    if (_awaitingRelease) {
      // A confidence flicker or a missing frame is not an intentional release.
      // Require a visible different pose or clearly extended open-hand geometry.
      final differentPose =
          observation.gesture != 'None' &&
          observation.scoreFor(observation.gesture) >= .5;
      final openHand =
          math.max(
            gestureMatch(
              observation,
              HandPose.openPalm,
              freePlacement: freePlacement,
            ),
            gestureMatch(
              observation,
              HandPose.dorsal,
              freePlacement: freePlacement,
            ),
          ) >=
          const GestureTolerance.forPose(HandPose.openPalm).poseScore;
      if (observation.hasHand &&
          confidence < .2 &&
          (differentPose || openHand)) {
        _awaitingRelease = false;
      }
      _hold.reset();
      checks.add(
        GestureCheck(
          'release',
          'New pose',
          _awaitingRelease
              ? 'Release required before holding again'
              : 'Released; form the target gesture',
          !_awaitingRelease,
        ),
      );
      return _awaitingRelease
          ? 'Open your hand, then try again'
          : 'Hand released — form the target gesture';
    }
    if (!wholeHand) {
      _trackingInterrupted(now);
      return 'Keep your whole hand in view';
    }
    canPause = true;
    _hold.update(now, matches: confidence >= poseThreshold);
    if (isMatching) {
      return ready ? 'Gesture detected' : 'Hold your gesture steady';
    }
    return 'Match the gesture shown in the guide';
  }

  void _trackingInterrupted(DateTime now) {
    if (freePlacement && !_awaitingRelease) {
      // Motion blur can briefly hide landmarks or lower hand confidence.
      // Freeze the earned hold; no missing/uncertain interval earns time.
      canPause = true;
      _hold.update(now, matches: false);
    } else {
      _hold.reset();
    }
  }
}
