import 'tutorial_steps.dart';

/// Baseline recognition settings, with explicitly scoped Hand practice profiles.
/// Hand and Social practice opt into separate alignment/hold settings.
/// Home classification retains its baseline. Direction practice can opt into a
/// lower pose-fit threshold for the two outward-pointing hand/pose pairs.
/// Pose scores are classifier confidence or geometric fit, not accuracy rates.
class GestureTolerance {
  const GestureTolerance.forPose(this.pose)
    : _handPractice = false,
      _socialPractice = false,
      selectedHand = null;
  const GestureTolerance.handPractice(this.pose, {this.selectedHand})
    : _handPractice = true,
      _socialPractice = false;
  const GestureTolerance.socialPractice(this.pose)
    : _handPractice = false,
      _socialPractice = true,
      selectedHand = null;

  final HandPose pose;
  final bool _handPractice;
  final bool _socialPractice;
  final String? selectedHand;
  bool get _outwardPractice =>
      _handPractice &&
      ((pose == HandPose.pointLeft && selectedHand == 'Left') ||
          (pose == HandPose.pointRight && selectedHand == 'Right'));
  bool get _down => pose == HandPose.pointDown;

  double get poseScore => (_socialPractice || _outwardPractice)
      ? .45
      : switch (pose) {
          HandPose.fist => .45,
          HandPose.pointDown => .45,
          _ => .55,
        };
  double get handConfidence => (_socialPractice || _down) ? .70 : .75;
  // Once Social has acquired the pose, tolerate small score fluctuations from
  // hand tremor. A new attempt still requires the normal poseScore threshold.
  double get continuingPoseScore => _socialPractice ? .35 : poseScore;
  double get insideRatio => _outwardPractice
      ? .35
      : _handPractice
      ? (_down ? .35 : .45)
      : (_down ? .40 : .60);
  double get minLongAxisRatio => _outwardPractice
      ? .25
      : _handPractice
      ? (_down ? .25 : .30)
      : (_down ? .30 : .40);
  double get minShortAxisRatio => _outwardPractice
      ? .10
      : _handPractice
      ? (_down ? .10 : .12)
      : (_down ? .12 : .18);
  double get outlineSlackX => _outwardPractice
      ? .18
      : _handPractice
      ? (_down ? .18 : .14)
      : (_down ? .14 : .08);
  double get outlineSlackY => _outwardPractice
      ? .16
      : _handPractice
      ? (_down ? .16 : .12)
      : (_down ? .12 : .07);
  Duration get holdDuration => Duration(
    milliseconds: _outwardPractice
        ? 600
        : (_handPractice ? 800 : (_down ? 1000 : 1200)),
  );
  Duration get holdWobbleGrace => _socialPractice
      ? const Duration(milliseconds: 500)
      : _handPractice
      ? const Duration(milliseconds: 350)
      : wobbleGrace;

  static const wobbleGrace = Duration(milliseconds: 200);
  static const maxResultGap = Duration(milliseconds: 600);
}
