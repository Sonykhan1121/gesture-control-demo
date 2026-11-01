import 'package:hand_gesture/app/theme/app_colors.dart';
import 'dart:async';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hand_gesture/features/auth/services/auth_service.dart';
import 'package:hand_gesture/features/auth/services/auth_session.dart';
import 'package:hand_gesture/features/auth/services/auth_api.dart';

enum FlowPage {
  splash,
  login,
  createAccount,
  home,
  connect,
  camera,
  hand,
  tutorial,
  tutorialCompleted,
  control,
  settings,
  selectMode,
  tutorialMenu,
  faceTutorial,
  reactions,
  about,
}

enum GestureMode { face, hand, social }

extension ModeLabel on GestureMode {
  String get label => switch (this) {
    GestureMode.face => 'Face',
    GestureMode.hand => 'Hand',
    GestureMode.social => 'Social media',
  };
}

/// Persisted setup with live BLE discovery and on-device hand recognition.
/// Authentication uses Gister; device connection/control remain demos.
class GestureController extends ChangeNotifier {
  GestureController(this.preferences, {DeviceDiscovery? discovery, this.auth})
    : discovery = discovery ?? BleDeviceDiscovery() {
    this.discovery.addListener(_onDiscoveryChanged);
    auth?.addListener(_onAuthChanged);
    name = preferences.getString('gesture.name') ?? 'Guest';
    device = preferences.getString('gesture.device');
    cameraPoint = preferences.getString('gesture.camera') ?? 'Centre';
    cameraX = preferences.getDouble('gesture.cameraX') ?? .5;
    cameraY = preferences.getDouble('gesture.cameraY') ?? .5;
    hand = preferences.getString('gesture.hand') ?? 'Right';
    mode = GestureMode.values.firstWhere(
      (m) => m.name == preferences.getString('gesture.mode'),
      orElse: () => GestureMode.face,
    );
    reaction = preferences.getString('gesture.reaction') ?? 'Next item';
    faceEmoji = preferences.getInt('gesture.faceEmoji') ?? 0;
    faceColor =
        preferences.getInt('gesture.faceColor') ??
        AppColors.defaultReactionColor;
    faceBackground =
        preferences.getInt('gesture.faceBackground') ??
        AppColors.background.toARGB32();
    trained = preferences.getBool('gesture.trained') ?? false;
    _setupPage = switch (preferences.getString('gesture.setupPage')) {
      'hand' => FlowPage.hand,
      'tutorial' => FlowPage.tutorial,
      'tutorialCompleted' => FlowPage.tutorialCompleted,
      _ => FlowPage.camera,
    };
    _setupTutorialGroup =
        preferences.getString('gesture.setupTutorialGroup') == 'video'
        ? TutorialGroup.video
        : TutorialGroup.hand;
    _setupTutorialIndex =
        (preferences.getInt('gesture.setupTutorialIndex') ?? 0).clamp(
          0,
          stepsForGroup(_setupTutorialGroup).length - 1,
        );
    if ((preferences.getInt('gesture.socialLessonOrder') ?? 1) < 2) {
      if (_setupTutorialGroup == TutorialGroup.video) {
        _setupTutorialIndex = [3, 2, 5, 4, 0, 1, 6, 7][_setupTutorialIndex];
        unawaited(
          preferences.setInt('gesture.setupTutorialIndex', _setupTutorialIndex),
        );
      }
      unawaited(preferences.setInt('gesture.socialLessonOrder', 2));
    }
    if ((preferences.getInt('gesture.socialLessonOrder') ?? 1) < 3) {
      if (_setupTutorialGroup == TutorialGroup.video) {
        // Preserve the active action when upgrading the prior lesson order.
        _setupTutorialIndex = [4, 5, 1, 0, 3, 2, 6, 7][_setupTutorialIndex];
        unawaited(
          preferences.setInt('gesture.setupTutorialIndex', _setupTutorialIndex),
        );
      }
      unawaited(preferences.setInt('gesture.socialLessonOrder', 3));
    }
    page =
        preferences.getBool('gesture.demoSession') == true &&
            (auth == null ||
                preferences.getBool('gesture.guestSession') == true)
        ? (device != null && trained ? FlowPage.control : FlowPage.home)
        : FlowPage.splash;
  }
  final SharedPreferences preferences;
  final DeviceDiscovery discovery;
  final AuthService? auth;
  bool restoringAuth = false;
  bool _hadAuthSession = false;
  String? authMessage;
  String authEmailDraft = '';

  void _onAuthChanged() {
    if (auth?.session != null) {
      _hadAuthSession = true;
    } else if (_hadAuthSession) {
      _hadAuthSession = false;
      authMessage = 'Your session has ended. Please log in again.';
      unawaited(preferences.setBool('gesture.realSession', false));
      open(FlowPage.login);
    }
  }

  Future<void> restoreAuth() async {
    final service = auth;
    if (service == null) return;
    // Explicit logout/guest access wins even if the keystore could not clear
    // its old item. Never restore an account the user chose to leave.
    if (preferences.getBool('gesture.authSignedOut') == true) return;
    restoringAuth = true;
    notifyListeners();
    try {
      if (await service.restore()) {
        await acceptAuthSession(service.session!);
        unawaited(service.foregroundActivity(opened: true));
      } else if (preferences.getBool('gesture.realSession') == true) {
        open(FlowPage.login);
      }
    } on AuthFailure catch (failure) {
      authMessage = failure.message;
      open(FlowPage.login);
    } finally {
      restoringAuth = false;
      notifyListeners();
    }
  }

  Future<void> acceptAuthSession(AuthSession session) async {
    name = session.name;
    await preferences.setString('gesture.name', name);
    await preferences.setBool('gesture.demoSession', false);
    await preferences.setBool('gesture.guestSession', false);
    await preferences.setBool('gesture.realSession', true);
    await preferences.setBool('gesture.authSignedOut', false);
    open(device != null && trained ? FlowPage.control : FlowPage.home);
  }

  void _onDiscoveryChanged() => notifyListeners();

  Future<void> refreshAutoSearch() async {
    if (page != FlowPage.connect || connectionMethod != 'Auto') return;
    connectionError = null;
    await discovery.restart();
  }

  @override
  void dispose() {
    _newTutorialSession();
    discovery.removeListener(_onDiscoveryChanged);
    discovery.dispose();
    auth?.removeListener(_onAuthChanged);
    auth?.dispose();
    super.dispose();
  }

  late String name, cameraPoint, hand, reaction;
  late double cameraX, cameraY;
  late int faceEmoji, faceColor, faceBackground;
  late GestureMode mode;
  late FlowPage page;
  String? device;
  late bool trained;
  int tutorialIndex = 0;
  TutorialGroup tutorialGroup = TutorialGroup.hand;
  (TutorialGroup, int, String)? _matchedTutorialStep;
  int _tutorialSession = 0;
  int get tutorialSession => _tutorialSession;
  int? _advancingTutorialSession;
  bool get _advancingTutorial => _advancingTutorialSession == _tutorialSession;
  bool get canAdvanceTutorial =>
      page == FlowPage.tutorial &&
      !_advancingTutorial &&
      _matchedTutorialStep == (tutorialGroup, tutorialIndex, hand);
  List<GestureTutorialStep> get tutorialSteps => stepsForGroup(tutorialGroup);
  bool setupTutorial = true;
  String connectionMethod = 'Auto';
  String? connectionError;
  String lastAction = 'Ready to preview a gesture';
  FlowPage cameraReturn = FlowPage.hand;
  FlowPage handReturn = FlowPage.tutorial;
  FlowPage settingsReturn = FlowPage.control;
  FlowPage tutorialReturn = FlowPage.settings;
  late FlowPage _setupPage;
  late int _setupTutorialIndex;
  late TutorialGroup _setupTutorialGroup;

  void _newTutorialSession() {
    _tutorialSession++;
    _matchedTutorialStep = null;
  }

  void open(FlowPage destination) {
    if (page == FlowPage.connect && destination != FlowPage.connect) {
      unawaited(discovery.stop());
    }
    // A reopened tutorial can have the same group/index/hand as an old one.
    // Give each visit an identity so old async completions cannot affect it.
    _newTutorialSession();
    page = destination;
    notifyListeners();
  }

  Future<void> signInDemo(String displayName) async {
    if (auth?.session != null) await auth!.logout();
    name = displayName.trim().isEmpty ? 'Guest' : displayName.trim();
    await preferences.setString('gesture.name', name);
    await preferences.setBool('gesture.demoSession', true);
    open(device != null && trained ? FlowPage.control : FlowPage.home);
  }

  /// Local guest access follows the same saved setup flow, without credentials.
  Future<void> continueAsGuest() async {
    if (auth != null) {
      _hadAuthSession = false;
      await preferences.setBool('gesture.authSignedOut', true);
      await auth!.logout();
      await preferences.setBool('gesture.realSession', false);
      await preferences.setBool('gesture.guestSession', true);
    }
    await signInDemo('Guest');
  }

  void chooseConnection(String method) {
    connectionMethod = method;
    connectionError = null;
    open(FlowPage.connect);
    if (method == 'Auto') {
      unawaited(refreshAutoSearch());
    } else {
      unawaited(discovery.stop());
    }
  }

  void openSettings({FlowPage returnTo = FlowPage.control}) {
    settingsReturn = returnTo;
    open(FlowPage.settings);
  }

  /// Continue onboarding without inheriting Settings/replay return routes.
  void resumeSetup() {
    if (device == null) {
      open(FlowPage.home);
      return;
    }
    if (trained) {
      open(FlowPage.control);
      return;
    }
    cameraReturn = FlowPage.hand;
    handReturn = FlowPage.tutorial;
    setupTutorial = true;
    tutorialIndex = _setupTutorialIndex;
    tutorialGroup = _setupTutorialGroup;
    open(_setupPage);
  }

  void _recordSetup(FlowPage destination) {
    _setupPage = destination;
    _setupTutorialIndex = tutorialIndex;
    _setupTutorialGroup = tutorialGroup;
    unawaited(preferences.setString('gesture.setupPage', destination.name));
    unawaited(
      preferences.setInt('gesture.setupTutorialIndex', _setupTutorialIndex),
    );
    unawaited(
      preferences.setString('gesture.setupTutorialGroup', tutorialGroup.name),
    );
  }

  void failConnection() {
    connectionError =
        'Demo device unavailable. Retry or choose another connection method.';
    notifyListeners();
  }

  Future<void> connectDemoDevice({String? deviceName}) async {
    final selectedName = deviceName?.trim();
    device = selectedName == null || selectedName.isEmpty
        ? 'Gesture Controller · Demo'
        : selectedName;
    await preferences.setString('gesture.device', device!);
    trained = false;
    await preferences.setBool('gesture.trained', false);
    cameraReturn = FlowPage.hand;
    handReturn = FlowPage.tutorial;
    setupTutorial = true;
    tutorialIndex = 0;
    tutorialGroup = TutorialGroup.hand;
    _recordSetup(FlowPage.camera);
    open(FlowPage.camera);
  }

  Future<void> setCameraPoint(String value) async {
    cameraPoint = value;
    await preferences.setString('gesture.camera', value);
    notifyListeners();
  }

  Future<void> setCameraPosition(double x, double y) async {
    cameraX = x;
    cameraY = y;
    cameraPoint = x == .5 && y == .5 ? 'Centre' : 'Custom position';
    await preferences.setDouble('gesture.cameraX', x);
    await preferences.setDouble('gesture.cameraY', y);
    await preferences.setString('gesture.camera', cameraPoint);
    notifyListeners();
  }

  Future<void> setHand(String value) async {
    if (hand != value) _newTutorialSession();
    hand = value;
    await preferences.setString('gesture.hand', value);
    notifyListeners();
  }

  Future<void> setMode(GestureMode value) async {
    mode = value;
    await preferences.setString('gesture.mode', value.name);
    lastAction = 'Mode changed to ${value.label}';
    notifyListeners();
  }

  Future<void> setReaction(String value) async {
    reaction = value;
    await preferences.setString('gesture.reaction', value);
    notifyListeners();
  }

  Future<void> saveAppearance({
    required int emoji,
    required int color,
    required int background,
  }) async {
    await preferences.setInt('gesture.faceEmoji', emoji);
    await preferences.setInt('gesture.faceColor', color);
    await preferences.setInt('gesture.faceBackground', background);
    faceEmoji = emoji;
    faceColor = color;
    faceBackground = background;
    notifyListeners();
  }

  Future<void> nextTutorial() async {
    if (!canAdvanceTutorial) return;
    await _advanceTutorial(matched: true);
  }

  Future<void> _advanceTutorial({required bool matched}) async {
    final session = _tutorialSession;
    if (tutorialGroup == TutorialGroup.video) {
      final skipped =
          (preferences.getStringList('gesture.socialSkippedActions') ?? [])
              .toSet();
      final action = tutorialSteps[tutorialIndex].socialAction!.name;
      if (matched) {
        skipped.remove(action);
      } else {
        skipped.add(action);
      }
      unawaited(
        preferences.setStringList(
          'gesture.socialSkippedActions',
          skipped.toList(),
        ),
      );
    }
    _matchedTutorialStep = null;
    _advancingTutorialSession = session;
    try {
      if (tutorialIndex < tutorialSteps.length - 1) {
        tutorialIndex++;
        if (setupTutorial) _recordSetup(FlowPage.tutorial);
        notifyListeners();
        return;
      }
      final completedGroup = tutorialGroup;
      final completedIndex = tutorialIndex;
      if (matched &&
          (completedGroup != TutorialGroup.video ||
              !hasSkippedSocialExercises)) {
        await preferences.setBool(
          'gesture.${completedGroup.name}TutorialCompleted',
          true,
        );
      }
      // Back, Skip or replay may have changed pages while preferences were saved.
      if (session != _tutorialSession ||
          page != FlowPage.tutorial ||
          tutorialGroup != completedGroup ||
          tutorialIndex != completedIndex) {
        return;
      }
      if (setupTutorial) _recordSetup(FlowPage.tutorialCompleted);
      open(FlowPage.tutorialCompleted);
    } finally {
      if (_advancingTutorialSession == session) {
        _advancingTutorialSession = null;
      }
    }
  }

  bool get hasSkippedSocialExercises =>
      (preferences.getStringList('gesture.socialSkippedActions') ?? [])
          .isNotEmpty;

  Future<void> finishSocialTutorial() async {
    if (page != FlowPage.tutorialCompleted ||
        tutorialGroup != TutorialGroup.video) {
      return;
    }
    if (setupTutorial) {
      await _finishTutorial();
    } else {
      open(device == null ? FlowPage.home : FlowPage.control);
    }
  }

  Future<void> acceptTutorialMatch(
    TutorialGroup group,
    int index, {
    required String hand,
    required int session,
  }) async {
    if (session != _tutorialSession ||
        page != FlowPage.tutorial ||
        tutorialGroup != group ||
        tutorialIndex != index ||
        this.hand != hand ||
        _advancingTutorial) {
      return;
    }
    _matchedTutorialStep = (group, index, hand);
    await nextTutorial();
  }

  Future<void> continueAfterTutorial() async {
    if (page != FlowPage.tutorialCompleted) return;
    if (setupTutorial && tutorialGroup == TutorialGroup.hand) {
      tutorialGroup = TutorialGroup.video;
      tutorialIndex = 0;
      _recordSetup(FlowPage.tutorial);
      open(FlowPage.tutorial);
    } else {
      await _finishTutorial();
    }
  }

  /// Skip only this exercise; never treat it as a successful camera match.
  Future<void> skipTutorial() async {
    if (page != FlowPage.tutorial || _advancingTutorial) return;
    _newTutorialSession();
    await _advanceTutorial(matched: false);
  }

  Future<void> _finishTutorial() async {
    if (page != FlowPage.tutorial && page != FlowPage.tutorialCompleted) return;
    if (!setupTutorial) {
      open(tutorialReturn);
      return;
    }
    final session = _tutorialSession;
    trained = true;
    await preferences.setBool('gesture.trained', true);
    if (session != _tutorialSession) return;
    open(FlowPage.control);
  }

  void replayTutorial(
    int index, {
    FlowPage returnTo = FlowPage.settings,
    TutorialGroup group = TutorialGroup.hand,
  }) {
    tutorialReturn = returnTo;
    tutorialGroup = group;
    tutorialIndex = index.clamp(0, tutorialSteps.length - 1);
    setupTutorial = false;
    open(FlowPage.tutorial);
  }

  void editCamera() {
    cameraReturn = FlowPage.settings;
    open(FlowPage.camera);
  }

  void editHand() {
    handReturn = FlowPage.settings;
    open(FlowPage.hand);
  }

  void finishCamera() {
    if (cameraReturn == FlowPage.hand) _recordSetup(FlowPage.hand);
    open(cameraReturn);
  }

  void finishHand() {
    if (handReturn == FlowPage.tutorial) {
      setupTutorial = true;
      tutorialIndex = 0;
      tutorialGroup = TutorialGroup.hand;
      _recordSetup(FlowPage.tutorial);
    }
    open(handReturn);
  }

  void previewReaction() {
    lastAction = 'Demo only: $reaction';
    notifyListeners();
  }

  Future<void> logout() async {
    _hadAuthSession = false;
    authMessage = null;
    if (auth != null) await preferences.setBool('gesture.authSignedOut', true);
    try {
      await auth?.logout();
    } catch (_) {
      authMessage =
          'Unable to clear secure storage. Please try logging out again.';
    }
    if (auth != null) await preferences.setBool('gesture.realSession', false);
    if (auth != null) await preferences.setBool('gesture.guestSession', false);
    await preferences.setBool('gesture.demoSession', false);
    open(FlowPage.login);
  }

  void back() {
    if (page == FlowPage.tutorialCompleted) {
      if (setupTutorial) _recordSetup(FlowPage.tutorial);
      open(FlowPage.tutorial);
      return;
    }
    if (page == FlowPage.tutorial && tutorialIndex > 0) {
      _matchedTutorialStep = null;
      tutorialIndex--;
      if (setupTutorial) _recordSetup(FlowPage.tutorial);
      notifyListeners();
      return;
    }
    if (page == FlowPage.tutorial &&
        tutorialGroup == TutorialGroup.video &&
        setupTutorial) {
      tutorialGroup = TutorialGroup.hand;
      tutorialIndex = gestureTutorialSteps.length - 1;
      _recordSetup(FlowPage.tutorialCompleted);
      open(FlowPage.tutorialCompleted);
      return;
    }
    open(switch (page) {
      FlowPage.splash || FlowPage.login => FlowPage.splash,
      FlowPage.createAccount => FlowPage.login,
      FlowPage.home => FlowPage.login,
      FlowPage.connect => FlowPage.home,
      FlowPage.camera =>
        cameraReturn == FlowPage.settings ? FlowPage.settings : FlowPage.home,
      FlowPage.hand =>
        handReturn == FlowPage.settings ? FlowPage.settings : FlowPage.camera,
      FlowPage.tutorial => setupTutorial ? FlowPage.hand : tutorialReturn,
      FlowPage.tutorialCompleted => tutorialReturn,
      FlowPage.faceTutorial => FlowPage.tutorialMenu,
      FlowPage.control => FlowPage.home,
      FlowPage.settings => settingsReturn,
      FlowPage.reactions ||
      FlowPage.about ||
      FlowPage.selectMode ||
      FlowPage.tutorialMenu => FlowPage.settings,
    });
  }
}
