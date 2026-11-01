import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

/// Filled, skin-colored artwork for the live detected-gesture badge.
/// Tutorial placement outlines deliberately use a different asset registry.
/// Each hand is authored separately; never mirror a pointing icon at runtime.
class HandGestureIconPair {
  const HandGestureIconPair({required this.left, required this.right});
  final String left, right;
  String forHand(bool isLeftHand) => isLeftHand ? left : right;
}

abstract final class HandGestureIcons {
  static const Map<HandPose, HandGestureIconPair> byPose = {
    HandPose.fist: HandGestureIconPair(
      left: 'assets/gestures/fist-left-filled.png',
      right: 'assets/gestures/fist-right-filled.png',
    ),
    HandPose.punch: HandGestureIconPair(
      left: 'assets/gestures/punch-left-filled.png',
      right: 'assets/gestures/punch-right-filled.png',
    ),
    HandPose.pointRight: HandGestureIconPair(
      left: 'assets/gestures/point-right-left-filled.png',
      right: 'assets/gestures/point-right-right-filled.png',
    ),
    HandPose.pointLeft: HandGestureIconPair(
      left: 'assets/gestures/point-left-left-filled.png',
      right: 'assets/gestures/point-left-right-filled.png',
    ),
    HandPose.ok: HandGestureIconPair(
      left: 'assets/gestures/ok-left-filled.png',
      right: 'assets/gestures/ok-right-filled.png',
    ),
    HandPose.victory: HandGestureIconPair(
      left: 'assets/gestures/victory-left-filled.png',
      right: 'assets/gestures/victory-right-filled.png',
    ),
    HandPose.pointDown: HandGestureIconPair(
      left: 'assets/gestures/point-down-left-filled.png',
      right: 'assets/gestures/point-down-right-filled.png',
    ),
    HandPose.pointUp: HandGestureIconPair(
      left: 'assets/gestures/point-up-left-filled.png',
      right: 'assets/gestures/point-up-right-filled.png',
    ),
    HandPose.rockOn: HandGestureIconPair(
      left: 'assets/gestures/rock-on-left-filled.png',
      right: 'assets/gestures/rock-on-right-filled.png',
    ),
    HandPose.thumbDown: HandGestureIconPair(
      left: 'assets/gestures/thumb-down-left-filled.png',
      right: 'assets/gestures/thumb-down-right-filled.png',
    ),
    HandPose.thumbUp: HandGestureIconPair(
      left: 'assets/gestures/thumb-up-left-filled.png',
      right: 'assets/gestures/thumb-up-right-filled.png',
    ),
    HandPose.dorsal: HandGestureIconPair(
      left: 'assets/gestures/dorsal-left-filled.png',
      right: 'assets/gestures/dorsal-right-filled.png',
    ),
    HandPose.openPalm: HandGestureIconPair(
      left: 'assets/gestures/open-palm-left-filled.png',
      right: 'assets/gestures/open-palm-right-filled.png',
    ),
  };

  static String forPose(HandPose pose, {required bool isLeftHand}) =>
      byPose[pose]!.forHand(isLeftHand);
}
