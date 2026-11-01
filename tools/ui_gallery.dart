// Documentation renderer: uses production widgets with local test adapters.
// Run explicitly with `fvm flutter test tools/ui_gallery.dart --no-pub`.
// No network, real account, device discovery, camera image or credentials used.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/flow/gesture_screen.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/auth/email_auth_screen.dart';
import 'package:hand_gesture/features/auth/social_sign_in_screen.dart';
import 'package:hand_gesture/features/devices/bluetooth_setup_dialog.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'package:hand_gesture/features/settings/language_screen.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:hand_gesture/shared/logout_confirmation.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Documentation adapter for the video_player transitive platform interface.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../test/features/auth/auth_test_support.dart';
import '../test/shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;

class _Discovery extends DeviceDiscovery {
  BluetoothSetupIssue? issue;
  @override
  List<DiscoveredDevice> get devices => issue == null
      ? const [DiscoveredDevice('Gesture Control', '00:00:00:00:00:01')]
      : const [];
  @override
  bool get scanning => false;
  @override
  String? get error => issue == BluetoothSetupIssue.poweredOff
      ? 'Turn on Bluetooth to find nearby devices.'
      : null;
  @override
  BluetoothSetupIssue? get setupIssue => issue;
  @override
  Future<void> restart() async {}
  @override
  Future<void> stop() async {}
}

class _Video extends VideoPlayerPlatform {
  int _nextId = 0;
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async =>
      ++_nextId;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 30),
      size: const Size(960, 540),
    ),
  );
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> seekTo(int playerId, Duration position) async {}
  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;
  @override
  Widget buildViewWithOptions(VideoViewOptions options) => Image.file(
    File('docs/screenshots/ui/video-frame.png'),
    fit: BoxFit.cover,
  );
}

void main() {
  testWidgets('render current UI gallery with sample data', (t) async {
    final oldCamera = CameraPlatform.instance;
    final oldVideo = VideoPlayerPlatform.instance;
    CameraPlatform.instance = FakeCameraPlatform();
    VideoPlayerPlatform.instance = _Video();
    addTearDown(() {
      CameraPlatform.instance = oldCamera;
      VideoPlayerPlatform.instance = oldVideo;
      t.view.reset();
    });
    final sdk = Directory(
      Platform.environment['FLUTTER_ROOT'] ??
          File(
            Platform.resolvedExecutable,
          ).parent.parent.parent.parent.parent.path,
    );
    final roboto = File(
      '${sdk.path}/bin/cache/artifacts/material_fonts/Roboto-Regular.ttf',
    );
    if (!roboto.existsSync()) {
      throw StateError('Flutter SDK Roboto font not found: ${roboto.path}');
    }
    await (FontLoader('Roboto')..addFont(
          Future.value(ByteData.sublistView(roboto.readAsBytesSync())),
        ))
        .load();
    for (final entry in {
      'GalleryCJK':
          Platform.environment['GALLERY_CJK_FONT'] ??
          '/System/Library/Fonts/Hiragino Sans GB.ttc',
      'GalleryThai':
          Platform.environment['GALLERY_THAI_FONT'] ??
          '/System/Library/Fonts/Supplemental/SukhumvitSet.ttc',
    }.entries) {
      final file = File(entry.value);
      if (!file.existsSync()) {
        throw StateError(
          'Set GALLERY_CJK_FONT and GALLERY_THAI_FONT to local CJK/Thai fonts. Missing: ${file.path}',
        );
      }
      await (FontLoader(entry.key)..addFont(
            Future.value(ByteData.sublistView(file.readAsBytesSync())),
          ))
          .load();
    }
    final version = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(File('pubspec.yaml').readAsStringSync())![1]!.split('+');
    t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('lazivoo/app_info'),
      (_) async => {
        'version': version.first,
        'buildNumber': version.length > 1 ? version[1] : '',
      },
    );
    Directory('docs/screenshots/ui').createSync(recursive: true);
    for (final font in {
      'Manrope': 'assets/fonts/Manrope.ttf',
      'Poppins': 'assets/fonts/Poppins-Regular.ttf',
      'packages/cupertino_icons/CupertinoIcons':
          'packages/cupertino_icons/assets/CupertinoIcons.ttf',
      'MaterialIcons': 'fonts/MaterialIcons-Regular.otf',
    }.entries) {
      await (FontLoader(font.key)..addFont(rootBundle.load(font.value))).load();
    }
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    final discovery = _Discovery();
    var socialCase = 'link';
    final h = AuthHarness((r) async {
      if (r.url.path.endsWith('/native/start')) return ok(startData());
      if (r.url.path.endsWith('/login')) return ok(bundle());
      return ok({'message': 'Done'});
    });
    h.browser.respond = (_) async => socialCase == 'link'
        ? h.browser.callback(status: 'error', error: 'ACCOUNT_LINK_REQUIRED')
        : h.browser.callback(status: 'email_verification_required');
    final c = GestureController(
      await SharedPreferences.getInstance(),
      discovery: discovery,
      auth: h.auth,
    );
    final boundary = GlobalKey();
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(402, 874);
    await t.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: GestureApp(controller: c),
      ),
    );

    Future<void> settle() async {
      for (var i = 0; i < 8; i++) {
        await t.pump(const Duration(milliseconds: 30));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 5)),
        );
      }
    }

    final captures = <String>[];
    Future<void> capture(String name) async {
      captures.add(name);
      for (final portrait in [true, false]) {
        t.view.physicalSize = portrait
            ? const Size(402, 874)
            : const Size(874, 402);
        t.view.padding = portrait
            ? const FakeViewPadding(top: 24, bottom: 24)
            : const FakeViewPadding(left: 24, right: 24, bottom: 24);
        await settle();
        expect(t.takeException(), isNull, reason: name);
        await t.runAsync(() async {
          final image =
              await (boundary.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 1.5);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final orientation = portrait ? 'portrait' : 'landscape';
          await File(
            'docs/screenshots/ui/$name-$orientation.png',
          ).writeAsBytes(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    }

    BuildContext context() =>
        t.element(find.byType(GestureScreen, skipOffstage: false));
    Future<void> route(Widget screen) async {
      unawaited(
        Navigator.of(
          context(),
        ).push(MaterialPageRoute<void>(builder: (_) => screen)),
      );
      await settle();
    }

    Future<void> pop() async {
      Navigator.of(context()).pop();
      await settle();
    }

    Future<void> tap(String label) async {
      await t.ensureVisible(find.text(label).last);
      await t.tap(find.text(label).last);
      await settle();
    }

    for (final page in [
      FlowPage.splash,
      FlowPage.login,
      FlowPage.createAccount,
      FlowPage.home,
    ]) {
      c.open(page);
      await capture(page.name);
    }
    c.chooseConnection('Auto');
    await capture('add-device-auto');
    discovery.issue = BluetoothSetupIssue.poweredOff;
    c.open(FlowPage.connect);
    await capture('bluetooth-off');
    discovery.issue = null;
    c.chooseConnection('Manual');
    await capture('add-device-manual');
    c.device = 'Gesture Control';
    for (final page in [
      FlowPage.camera,
      FlowPage.hand,
      FlowPage.control,
      FlowPage.settings,
      FlowPage.selectMode,
      FlowPage.reactions,
      FlowPage.tutorialMenu,
      FlowPage.about,
    ]) {
      c.open(page);
      await capture(page.name);
    }
    c.faceEmoji = 1;
    c.open(FlowPage.control);
    await capture('home-soft-corners');
    c.mode = GestureMode.hand;
    c.open(FlowPage.control);
    await capture('home-hand');
    c.mode = GestureMode.social;
    c.open(FlowPage.control);
    await capture('home-social');
    c.open(FlowPage.settings);
    final theme = Theme.of(context());
    await route(
      Theme(
        data: theme.copyWith(
          textTheme: theme.textTheme.apply(
            fontFamilyFallback: const ['GalleryCJK', 'GalleryThai'],
          ),
        ),
        child: const LanguageScreen(),
      ),
    );
    await capture('language');
    await pop();
    unawaited(confirmLogout(context(), c));
    await capture('logout-dialog');
    await pop();
    unawaited(
      showDialog<void>(
        context: context(),
        builder: (ctx) => BluetoothSetupDialog(
          issue: BluetoothSetupIssue.permissionDenied,
          onLater: () => Navigator.pop(ctx),
        ),
      ),
    );
    await capture('bluetooth-permission');
    await pop();

    for (final purpose in EmailAuthPurpose.values) {
      c.open(FlowPage.login);
      await route(
        EmailAuthScreen(
          auth: h.auth,
          purpose: purpose,
          email: 'demo@example.com',
          name: 'Demo user',
          password: 'example-only-password',
        ),
      );
      await capture('email-${purpose.name}');
      if (purpose != EmailAuthPurpose.registration) {
        await tap(
          purpose == EmailAuthPurpose.reset ? 'Send reset code' : 'Send code',
        );
        await capture('email-${purpose.name}-code');
      }
      await pop();
    }
    await route(SocialSignInScreen(auth: h.auth, provider: 'google'));
    await capture('link-account');
    await tap('Log in to existing account');
    await capture('link-login');
    await t.enterText(find.byKey(const ValueKey('Email')), 'demo@example.com');
    await t.enterText(
      find.byKey(const ValueKey('Password')),
      'example-only-password',
    );
    await tap('Continue');
    await capture('link-confirm');
    await pop();
    socialCase = 'email';
    await route(SocialSignInScreen(auth: h.auth, provider: 'google'));
    await capture('social-email');
    await t.enterText(find.byKey(const ValueKey('Email')), 'demo@example.com');
    await tap('Send code');
    await capture('social-email-code');
    await pop();

    for (var i = 0; i < stepsForGroup(TutorialGroup.hand).length; i++) {
      c.replayTutorial(i);
      await capture('hand-${(i + 1).toString().padLeft(2, '0')}');
    }
    c.hand = 'Left';
    c.replayTutorial(0);
    await capture('hand-left');
    c.hand = 'Right';
    c.open(FlowPage.tutorialCompleted);
    await capture('tutorial-completed');
    for (var i = 0; i < videoTutorialSteps.length; i++) {
      c.replayTutorial(i, group: TutorialGroup.video);
      await capture('social-${(i + 1).toString().padLeft(2, '0')}');
    }
    c.replayTutorial(0, group: TutorialGroup.video);
    await settle();
    await t.pump(const Duration(seconds: 4));
    await capture('social-your-turn');
    c.open(FlowPage.faceTutorial);
    for (var i = 0; i < 5; i++) {
      await capture('face-${i + 1}');
      if (i < 4) await tap('Skip');
    }
    await tap('Skip');
    await capture('face-practice-finished');
    final manifest = const JsonEncoder.withIndent('  ').convert({
      'source': 'Production Flutter widgets with local sample adapters',
      'portrait': {'width': 402, 'height': 874},
      'landscape': {'width': 874, 'height': 402},
      'pixelRatio': 1.5,
      'states': captures,
    });
    File('docs/screenshots/ui/manifest.json').writeAsStringSync('$manifest\n');
    await t.pumpWidget(const SizedBox());
    await settle();
    c.dispose();
  });
}
