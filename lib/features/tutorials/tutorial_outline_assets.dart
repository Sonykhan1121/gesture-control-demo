import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

/// Each distinct hand pose has one LEFT and one RIGHT camera-guide image.
///
/// For example:
/// HandPose.pointRight uses images with BOTH fingers pointing right.
/// Do not mirror these assets automatically: each side is approved separately.
///
/// The Social Media tutorial reuses the same images by HandPose.
/// Hand Punch and Video Play/Pause share one pair: 13 poses x 2 hands = 26 PNGs.
class TutorialOutlinePair {
  const TutorialOutlinePair({required this.left, required this.right});

  final String left;
  final String right;

  String forHand(bool isLeftHand) => isLeftHand ? left : right;
}

abstract final class TutorialOutlineAssets {
  static const Map<HandPose, TutorialOutlinePair> byPose = {
    HandPose.fist: TutorialOutlinePair(
      left: 'assets/tutorials/fist-left-outline.png',
      right: 'assets/tutorials/fist-right-outline.png',
    ),
    HandPose.punch: TutorialOutlinePair(
      left: 'assets/tutorials/punch-left-outline.png',
      right: 'assets/tutorials/punch-right-outline.png',
    ),
    HandPose.pointRight: TutorialOutlinePair(
      left: 'assets/tutorials/point-right-left-outline.png',
      right: 'assets/tutorials/point-right-right-outline.png',
    ),
    HandPose.pointLeft: TutorialOutlinePair(
      left: 'assets/tutorials/point-left-left-outline.png',
      right: 'assets/tutorials/point-left-right-outline.png',
    ),
    HandPose.ok: TutorialOutlinePair(
      left: 'assets/tutorials/ok-left-outline.png',
      right: 'assets/tutorials/ok-right-outline.png',
    ),
    HandPose.victory: TutorialOutlinePair(
      left: 'assets/tutorials/victory-left-outline.png',
      right: 'assets/tutorials/victory-right-outline.png',
    ),
    HandPose.pointDown: TutorialOutlinePair(
      left: 'assets/tutorials/point-down-left-outline.png',
      right: 'assets/tutorials/point-down-right-outline.png',
    ),
    HandPose.pointUp: TutorialOutlinePair(
      left: 'assets/tutorials/point-up-left-outline.png',
      right: 'assets/tutorials/point-up-right-outline.png',
    ),
    HandPose.rockOn: TutorialOutlinePair(
      left: 'assets/tutorials/rock-on-left-outline.png',
      right: 'assets/tutorials/rock-on-right-outline.png',
    ),
    HandPose.thumbDown: TutorialOutlinePair(
      left: 'assets/tutorials/thumb-down-left-outline.png',
      right: 'assets/tutorials/thumb-down-right-outline.png',
    ),
    HandPose.thumbUp: TutorialOutlinePair(
      left: 'assets/tutorials/thumb-up-left-outline.png',
      right: 'assets/tutorials/thumb-up-right-outline.png',
    ),
    HandPose.dorsal: TutorialOutlinePair(
      left: 'assets/tutorials/dorsal-left-outline.png',
      right: 'assets/tutorials/dorsal-right-outline.png',
    ),
    HandPose.openPalm: TutorialOutlinePair(
      left: 'assets/tutorials/open-palm-left-outline.png',
      right: 'assets/tutorials/open-palm-right-outline.png',
    ),
  };

  static String forPose(HandPose pose, {required bool isLeftHand}) {
    return byPose[pose]!.forHand(isLeftHand);
  }
}
