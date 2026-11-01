enum TutorialGroup { hand, video }

enum SocialTutorialAction {
  previousVideo,
  nextVideo,
  previousShort,
  nextShort,
  play,
  pause,
  volumeUp,
  volumeDown;

  bool get changesVideo =>
      this == nextVideo || this == previousVideo || isShort;
  bool get isShort => this == nextShort || this == previousShort;
  bool get previous => this == previousVideo || this == previousShort;
  bool get changesVolume => this == volumeUp || this == volumeDown;
}

enum HandPose {
  fist,
  punch,
  pointRight,
  pointLeft,
  ok,
  victory,
  pointDown,
  pointUp,
  rockOn,
  thumbDown,
  thumbUp,
  dorsal,
  openPalm,
}

// The supplied Figma tutorial frames, in their displayed order.
class GestureTutorialStep {
  const GestureTutorialStep(
    this.title,
    this.instruction,
    this.asset,
    this.left,
    this.top,
    this.width,
    this.height,
    this.panelTop, {
    this.pose = HandPose.fist,
    this.socialAction,
    this.panelHeight = 536,
    this.artworkIsLeftHand = false,
  });
  final String title, instruction, asset;
  final double left, top, width, height, panelTop;
  final double panelHeight;
  final HandPose pose;
  final SocialTutorialAction? socialAction;

  /// Source artwork handedness in the mirrored front-camera preview, matching
  /// the Left/Right hand selection illustrations. Exports mix both hands.
  final bool artworkIsLeftHand;

  bool get pointsHorizontally =>
      pose == HandPose.pointLeft || pose == HandPose.pointRight;

  // Reflect across the pointing axis: change hands without reversing the
  // requested direction. Other poses use the usual horizontal mirror.
  bool flipArtworkX(bool isLeftHand) =>
      isLeftHand != artworkIsLeftHand && !pointsHorizontally;
  bool flipArtworkY(bool isLeftHand) =>
      isLeftHand != artworkIsLeftHand && pointsHorizontally;
}

const gestureTutorialSteps = <GestureTutorialStep>[
  GestureTutorialStep(
    "Fist",
    "Close your fist and match the outline.",
    "assets/tutorials/gesture-01.png",
    136,
    441,
    130,
    136,
    241,
    artworkIsLeftHand: true,
  ),
  GestureTutorialStep(
    "Move Right",
    "Point your finger and keep it centered on the icon.",
    "assets/tutorials/gesture-03.png",
    133,
    452,
    136,
    114,
    241,
    pose: HandPose.pointRight,
    artworkIsLeftHand: true,
  ),
  GestureTutorialStep(
    "Move Left",
    "Point your finger and keep it centered on the icon.",
    "assets/tutorials/gesture-02.png",
    133,
    452,
    136,
    114,
    241,
    pose: HandPose.pointLeft,
    artworkIsLeftHand: false,
  ),
  GestureTutorialStep(
    "OK",
    "Make an OK sign and keep it centered on the icon.",
    "assets/tutorials/gesture-04.png",
    145,
    437,
    112,
    144,
    241,
    pose: HandPose.ok,
    artworkIsLeftHand: false,
  ),
  GestureTutorialStep(
    "Victory",
    "Make a peace sign and keep it centered on the icon.",
    "assets/tutorials/gesture-05.png",
    143,
    427,
    116,
    164,
    241,
    pose: HandPose.victory,
    artworkIsLeftHand: true,
  ),
  GestureTutorialStep(
    "Move Down",
    "Point your index finger downward near the outline and hold for 1 second.",
    "assets/tutorials/gesture-06.png",
    144,
    440,
    114,
    138,
    241,
    pose: HandPose.pointDown,
    artworkIsLeftHand: false,
  ),
  GestureTutorialStep(
    "Move Up",
    "Point your finger and keep it centered on the icon.",
    "assets/tutorials/gesture-07.png",
    144,
    440,
    114,
    138,
    241,
    pose: HandPose.pointUp,
    artworkIsLeftHand: true,
  ),
  GestureTutorialStep(
    "Rock On",
    "Make a rock-on sign and keep it centered on the icon.",
    "assets/tutorials/gesture-08.png",
    146,
    427,
    110,
    164,
    241,
    pose: HandPose.rockOn,
    artworkIsLeftHand: true,
  ),
  GestureTutorialStep(
    "Thumbs Down",
    "Give a thumbs down and keep it centered on the icon.",
    "assets/tutorials/gesture-09.png",
    133,
    427,
    136,
    164,
    241,
    pose: HandPose.thumbDown,
    artworkIsLeftHand: false,
  ),
  GestureTutorialStep(
    "Thumbs Up",
    "Give a thumbs up and keep it centered on the icon.",
    "assets/tutorials/gesture-10.png",
    133,
    427,
    136,
    164,
    241,
    pose: HandPose.thumbUp,
    artworkIsLeftHand: true,
  ),
  GestureTutorialStep(
    "Dorsal",
    "Show the back of your hand with fingers pointing up,\nand keep it centered on the icon.",
    "assets/tutorials/gesture-11.png",
    137,
    433,
    122,
    185,
    260,
    pose: HandPose.dorsal,
    artworkIsLeftHand: true,
  ),
  GestureTutorialStep(
    "Open Palm",
    "Open your palm and keep it centered on the icon.",
    "assets/tutorials/gesture-12.png",
    127,
    435,
    144,
    144,
    241,
    pose: HandPose.openPalm,
    artworkIsLeftHand: false,
  ),
  // Append so saved indices for the original twelve lessons remain valid.
  GestureTutorialStep(
    'Punch',
    'Make a punch with your knuckles facing the camera.',
    'assets/tutorials/video-05.png',
    0,
    0,
    160,
    150,
    261,
    pose: HandPose.punch,
    panelHeight: 520,
    artworkIsLeftHand: false,
  ),
];

const videoTutorialSteps = <GestureTutorialStep>[
  GestureTutorialStep(
    'Go to Previous Video',
    'Point your index finger to the left, as shown in the image, and hold the gesture steady to complete the tutorial.',
    'assets/tutorials/video-01.png',
    0,
    0,
    136,
    114,
    281,
    socialAction: SocialTutorialAction.previousVideo,
    pose: HandPose.pointLeft,
    panelHeight: 500,
    artworkIsLeftHand: false,
  ),

  GestureTutorialStep(
    'Go to Next Video',
    'Point your index finger to the right, as shown in the image, and hold the gesture steady to complete the tutorial.',
    'assets/tutorials/video-02.png',
    0,
    0,
    136,
    114,
    281,
    socialAction: SocialTutorialAction.nextVideo,
    pose: HandPose.pointRight,
    panelHeight: 500,
    artworkIsLeftHand: true,
  ),

  GestureTutorialStep(
    'Scroll Up',
    'Point your index finger upward, as shown in the image, and hold the gesture steady to complete the tutorial.',
    'assets/tutorials/video-03.png',
    0,
    0,
    114,
    138,
    261,
    socialAction: SocialTutorialAction.previousShort,
    pose: HandPose.pointUp,
    panelHeight: 520,
    artworkIsLeftHand: true,
  ),

  GestureTutorialStep(
    'Scroll Down',
    'Point your index finger downward near the outline and hold for 1 second.',
    'assets/tutorials/video-04.png',
    0,
    0,
    114,
    138,
    281,
    socialAction: SocialTutorialAction.nextShort,
    pose: HandPose.pointDown,
    panelHeight: 500,
    artworkIsLeftHand: false,
  ),

  GestureTutorialStep(
    'Play Video',
    'Make a punch to play the video.',
    'assets/tutorials/video-05.png',
    0,
    0,
    160,
    150,
    261,
    socialAction: SocialTutorialAction.play,
    pose: HandPose.punch,
    panelHeight: 520,
    artworkIsLeftHand: false,
  ),

  GestureTutorialStep(
    'Pause Video',
    'Make a punch to pause the video.',
    'assets/tutorials/video-06.png',
    0,
    0,
    160,
    150,
    281,
    socialAction: SocialTutorialAction.pause,
    pose: HandPose.punch,
    panelHeight: 500,
    artworkIsLeftHand: false,
  ),

  GestureTutorialStep(
    'Volume Up',
    'Make a thumbs-up gesture, as shown in the image, and hold it steady to increase the volume and complete the tutorial.',
    'assets/tutorials/video-07.png',
    0,
    0,
    136,
    164,
    281,
    socialAction: SocialTutorialAction.volumeUp,
    pose: HandPose.thumbUp,
    panelHeight: 500,
    artworkIsLeftHand: true,
  ),

  GestureTutorialStep(
    'Volume Down',
    'Make a thumbs-down gesture, as shown in the image, and hold it steady to decrease the volume and complete the tutorial.',
    'assets/tutorials/video-08.png',
    0,
    0,
    136,
    164,
    281,
    socialAction: SocialTutorialAction.volumeDown,
    pose: HandPose.thumbDown,
    panelHeight: 500,
    artworkIsLeftHand: false,
  ),
];

List<GestureTutorialStep> stepsForGroup(TutorialGroup group) =>
    group == TutorialGroup.hand ? gestureTutorialSteps : videoTutorialSteps;
