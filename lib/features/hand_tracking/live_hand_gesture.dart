import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/tutorials/gesture_tolerance.dart';
import 'hand_gesture_icons.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'hand_recognition.dart';

class DetectedHandGesture {
  const DetectedHandGesture(this.pose, this.hand, this.score);
  final HandPose pose;
  final String hand;
  final double score;
  String get asset =>
      HandGestureIcons.forPose(pose, isLeftHand: hand == 'Left');
  String get label =>
      gestureTutorialSteps.firstWhere((step) => step.pose == pose).title;
}

/// Classifies the twelve Hand poses without tutorial placement or completion.
/// Punch is taught separately for Play/Pause; its Closed_Fist score is not a
/// distinct native class and must not compete with Fist in Home mode.
DetectedHandGesture? detectHandGesture(
  HandObservation observation, {
  required String selectedHand,
  HandPose? previous,
  void Function(String)? onDecision,
}) {
  if (!observation.hasHand) {
    onDecision?.call('No complete hand detected');
    return null;
  }
  if (!observation.hasHand ||
      observation.physicalHand != selectedHand ||
      !observation.handScore.isFinite ||
      observation.handScore > 1) {
    onDecision?.call(
      observation.physicalHand != selectedHand
          ? 'Wrong hand: detected ${observation.physicalHand}, selected $selectedHand'
          : 'Invalid hand confidence',
    );
    return null;
  }
  final matches = <DetectedHandGesture>[];
  for (final step in gestureTutorialSteps) {
    if (step.pose == HandPose.punch) continue;
    final tolerance = GestureTolerance.forPose(step.pose);
    if (observation.handScore < tolerance.handConfidence) continue;
    final fit = gestureMatch(observation, step.pose);
    if (fit.isFinite && fit >= tolerance.poseScore) {
      matches.add(DetectedHandGesture(step.pose, selectedHand, fit));
    }
  }
  if (matches.isEmpty) {
    onDecision?.call(
      observation.handScore < .75
          ? 'No eligible pose: hand confidence needs .75 (.70 for Down)'
          : 'No pose passes its score, visibility and geometry checks',
    );
    return null;
  }
  matches.sort((a, b) => b.score.compareTo(a.score));
  final preferred = switch (observation.gesture) {
    'Closed_Fist' => HandPose.fist,
    'Victory' => HandPose.victory,
    'Thumb_Up' => HandPose.thumbUp,
    'Thumb_Down' => HandPose.thumbDown,
    _ => null,
  };
  // Favor a supported native class when it agrees with the geometric best.
  // A much stronger thumb/point fit can still beat a weak canned prediction.
  for (final match in matches) {
    if (match.pose == preferred && match.score >= matches.first.score - .15) {
      onDecision?.call('Candidate: ${match.label} (native class agrees)');
      return match;
    }
  }
  if (matches.length > 1 && matches.first.score - matches[1].score < .08) {
    for (final match in matches) {
      if (match.pose == previous && match.score >= matches.first.score - .08) {
        onDecision?.call('Keeping ${match.label}: close scores');
        return match;
      }
    }
    onDecision?.call(
      'Ambiguous: ${matches[0].label} ${matches[0].score.toStringAsFixed(2)} / ${matches[1].label} ${matches[1].score.toStringAsFixed(2)}',
    );
    return null; // Do not invent a winner for an ambiguous pose.
  }
  onDecision?.call('Candidate: ${matches.first.label}');
  return matches.first;
}

/// UI stability only: no tutorial hold/release or automatic navigation. Uses
/// fresh observations; missing/wrong hands clear immediately, weak fits get a
/// short grace interval and stalled inference cannot leave a frozen icon.
class LiveHandGestureState {
  static const settleTime = Duration(milliseconds: 180);
  static const staleTime = Duration(milliseconds: 350);
  // Inference can take longer than the icon's display grace on slower hosts.
  // Keep two-result confirmation possible without leaving an old icon visible.
  static const maxResultGap = Duration(milliseconds: 1500);
  DetectedHandGesture? current;
  DetectedHandGesture? _candidate;
  Duration? _candidateSince, _lastResult, _lastMatch;
  int _candidateFrames = 0;
  String status = 'Waiting for camera results';

  void reset({String reason = 'Waiting for fresh camera results'}) {
    current = _candidate = null;
    _candidateSince = _lastResult = _lastMatch = null;
    _candidateFrames = 0;
    status = reason;
  }

  void update(
    HandObservation observation,
    Duration now, {
    required String selectedHand,
  }) {
    if (_lastResult != null && now - _lastResult! > maxResultGap) reset();
    _lastResult = now;
    if (!observation.hasHand ||
        observation.physicalHand != selectedHand ||
        !observation.handScore.isFinite ||
        observation.handScore < .70 ||
        observation.handScore > 1) {
      reset(
        reason: !observation.hasHand
            ? 'No hand detected'
            : observation.physicalHand != selectedHand
            ? 'Wrong hand: detected ${observation.physicalHand}, selected $selectedHand'
            : 'Hand confidence too low or invalid',
      );
      return;
    }
    final detected = detectHandGesture(
      observation,
      selectedHand: selectedHand,
      previous: current?.pose,
      onDecision: (reason) => status = reason,
    );
    if (detected == null) {
      _candidate = null;
      _candidateSince = null;
      _candidateFrames = 0;
      expire(now);
      return;
    }
    if (current?.pose == detected.pose && current?.hand == detected.hand) {
      current = detected;
      _lastMatch = now;
      _candidate = null;
      _candidateSince = null;
      _candidateFrames = 0;
      status = 'Showing ${detected.label}';
      return;
    }
    if (_candidate?.pose != detected.pose ||
        _candidate?.hand != detected.hand) {
      _candidate = detected;
      _candidateSince = now;
      _candidateFrames = 1;
    } else {
      _candidateFrames++;
      if (_candidateFrames >= 2 && now - _candidateSince! >= settleTime) {
        current = detected;
        _lastMatch = now;
        _candidate = null;
        _candidateSince = null;
        _candidateFrames = 0;
        status = 'Showing ${detected.label}';
      }
    }
    if (_candidate != null) {
      status =
          'Stabilizing ${detected.label}: ${(now - _candidateSince!).inMilliseconds}/180ms, $_candidateFrames frames';
    }
    expire(now);
  }

  bool expire(Duration now) {
    if (_lastResult != null && now - _lastResult! > maxResultGap) {
      final changed = current != null || _candidate != null;
      reset(reason: 'No fresh recognition results for 1500ms');
      return changed;
    }
    if (current != null &&
        ((_lastResult != null && now - _lastResult! > staleTime) ||
            (_lastMatch != null && now - _lastMatch! > staleTime))) {
      // Hide stale artwork, but retain a pending new pose until its next
      // result. The old watchdog reset this candidate every 350ms forever.
      current = null;
      _lastMatch = null;
      status = 'Waiting for a fresh gesture result';
      return true;
    }
    return false;
  }
}
