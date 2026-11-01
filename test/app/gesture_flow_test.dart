import 'package:flutter_svg/flutter_svg.dart';
import 'dart:io';
import 'package:hand_gesture/shared/software_version_text.dart';
import 'package:flutter/material.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/features/devices/device_discovery.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_mouth.dart';
import 'package:hand_gesture/features/home/control_screen.dart';
import 'package:provider/provider.dart';
import 'package:hand_gesture/features/tutorials/gesture_camera_guide.dart';
import 'package:hand_gesture/features/tutorials/gesture_border_icon.dart';
import 'package:hand_gesture/features/hand_tracking/hand_gesture_icons.dart';
import 'package:hand_gesture/features/tutorials/gesture_debug_overlay.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:hand_gesture/features/tutorials/tutorial_outline_assets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../helpers/outline_test_helpers.dart';

Future<void> completeStep(GestureController c) => c.acceptTutorialMatch(
  c.tutorialGroup,
  c.tutorialIndex,
  hand: c.hand,
  session: c.tutorialSession,
);

Future<void> finishSetup(GestureController c) async {
  for (var group = 0; group < 2; group++) {
    while (c.page == FlowPage.tutorial) {
      await completeStep(c);
    }
    await c.continueAfterTutorial();
  }
}

Future<void> finishSocialDemo(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1500));
  await tester.pump(const Duration(seconds: 2));
  await tester.pumpAndSettle();
}

void main() {
  late SharedPreferences preferences;
  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SoftwareVersionText.channel,
          (call) async => {'version': '0.1.0', 'buildNumber': '1'},
        );
    SharedPreferences.setMockInitialValues({});
    preferences = await SharedPreferences.getInstance();
  });
  test(
    'Social order migrates the saved lesson and preserves skipped practice',
    () async {
      await preferences.setInt('gesture.setupTutorialIndex', 0);
      await preferences.setString('gesture.setupTutorialGroup', 'video');
      await preferences.setString('gesture.setupPage', 'tutorial');
      await preferences.setString('gesture.device', 'Test stand');
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.resumeSetup();
      expect(
        c.tutorialSteps[c.tutorialIndex].socialAction,
        SocialTutorialAction.previousVideo,
      );
      expect(
        videoTutorialSteps.map((step) => step.socialAction),
        SocialTutorialAction.values,
      );
      c.replayTutorial(0, group: TutorialGroup.video);
      await c.skipTutorial();
      for (var step = 1; step < videoTutorialSteps.length; step++) {
        await completeStep(c);
      }
      expect(c.hasSkippedSocialExercises, isTrue);
      expect(preferences.getBool('gesture.videoTutorialCompleted'), isNull);
      await c.finishSocialTutorial();
      expect(c.page, FlowPage.control);
      c.replayTutorial(0, group: TutorialGroup.video);
      await completeStep(c);
      expect(c.hasSkippedSocialExercises, isFalse);
      c.dispose();
    },
  );
  test(
    'Version two Social progress preserves its action after reorder and restart',
    () async {
      const previousOrder = [
        SocialTutorialAction.play,
        SocialTutorialAction.pause,
        SocialTutorialAction.nextVideo,
        SocialTutorialAction.previousVideo,
        SocialTutorialAction.nextShort,
        SocialTutorialAction.previousShort,
        SocialTutorialAction.volumeUp,
        SocialTutorialAction.volumeDown,
      ];
      expect(videoTutorialSteps.map((step) => step.socialAction).toList(), [
        SocialTutorialAction.previousVideo,
        SocialTutorialAction.nextVideo,
        SocialTutorialAction.previousShort,
        SocialTutorialAction.nextShort,
        SocialTutorialAction.play,
        SocialTutorialAction.pause,
        SocialTutorialAction.volumeUp,
        SocialTutorialAction.volumeDown,
      ]);
      for (var index = 0; index < previousOrder.length; index++) {
        await preferences.clear();
        await preferences.setInt('gesture.socialLessonOrder', 2);
        await preferences.setInt('gesture.setupTutorialIndex', index);
        await preferences.setString('gesture.setupTutorialGroup', 'video');
        await preferences.setString('gesture.setupPage', 'tutorial');
        await preferences.setString('gesture.device', 'Test stand');
        final c = GestureController(preferences, discovery: FakeDiscovery());
        c.resumeSetup();
        expect(
          c.tutorialSteps[c.tutorialIndex].socialAction,
          previousOrder[index],
        );
        final savedIndex = c.tutorialIndex;
        c.dispose();
        final restored = GestureController(
          preferences,
          discovery: FakeDiscovery(),
        );
        restored.resumeSetup();
        expect(restored.tutorialIndex, savedIndex);
        expect(
          restored.tutorialSteps[savedIndex].socialAction,
          previousOrder[index],
        );
        restored.dispose();
      }
    },
  );
  testWidgets('cold launch waits for valid window metrics', (tester) async {
    tester.view.physicalSize = Size.zero;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.open(FlowPage.home);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(402, 874);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Hello!'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  testWidgets('Social debug toggles one live camera and diagnostics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.replayTutorial(0, group: TutorialGroup.video);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byType(GestureDebugOverlay), findsNothing);
    await tester.tap(find.byKey(const ValueKey('social-debug-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(GestureCameraGuide), findsOneWidget);
    expect(find.byType(GestureDebugOverlay), findsOneWidget);
    expect(find.text('Social control · live camera'), findsOneWidget);
    expect(
      tester
          .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
          .showDebugOverlay,
      isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('social-debug-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(GestureDebugOverlay), findsNothing);
    expect(find.byType(GestureCameraGuide), findsOneWidget);
    expect(c.tutorialIndex, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  testWidgets('Login places the guest button below Or and skips credentials', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.open(FlowPage.login);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    final guest = find.byKey(const ValueKey('continue-as-guest'));
    expect(tester.widget(guest), isA<OutlinedButton>());
    expect(find.text('Skip -use as guest'), findsOneWidget);
    expect(find.text('Or'), findsNWidgets(2));
    expect(
      tester.getTopLeft(guest).dy,
      greaterThan(tester.getBottomRight(find.text('Or').last).dy),
    );
    expect(tester.getSize(guest), const Size(364, 44));
    await tester.tap(guest);
    await tester.pumpAndSettle();
    expect(c.page, FlowPage.home);
    expect(c.name, 'Guest');
    expect(preferences.getBool('gesture.demoSession'), isTrue);
    expect(find.text('Enter a valid email address.'), findsNothing);
    c.open(FlowPage.createAccount);
    await tester.pumpAndSettle();
    expect(guest, findsNothing);
    expect(find.text('Or'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  for (final size in [const Size(402, 874), const Size(874, 402)]) {
    testWidgets('Social Demo then Try keeps the confirmed hand visible at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.replayTutorial(1, group: TutorialGroup.video);
      await tester.pumpWidget(GestureApp(controller: c));
      await tester.pump();
      expect(find.text('Demo'), findsOneWidget);
      final feedback = find.byKey(const ValueKey('social-screen-feedback'));
      final previewScreen = find.byKey(const ValueKey('youtube-preview'));
      expect(
        find.descendant(of: previewScreen, matching: feedback),
        findsOneWidget,
        reason:
            'Teaching status belongs inside the phone preview, below no subtitle',
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('social-phase-label')))
            .style!
            .fontSize,
        greaterThanOrEqualTo(22),
      );
      expect(
        find.descendant(of: feedback, matching: find.byType(AnimatedSwitcher)),
        findsOneWidget,
      );

      final watchGuide = tester.widget<GestureCameraGuide>(
        find.byType(GestureCameraGuide),
      );
      expect(watchGuide.practiceEnabled, isFalse);
      watchGuide.onMatched!();
      expect(c.tutorialIndex, 1);
      await tester.pumpAndSettle();
      expect(find.text('Your turn'), findsOneWidget);
      expect(
        tester
            .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
            .practiceEnabled,
        isTrue,
      );
      watchGuide.onMatched!();
      expect(
        c.tutorialIndex,
        1,
        reason: 'Old Demo callbacks cannot confirm practice',
      );
      final hand = find.byKey(const ValueKey('youtube-hand-position'));
      final preview = find
          .ancestor(of: hand, matching: find.byType(Stack))
          .first;
      expect(
        tester.getCenter(hand).dx,
        closeTo(tester.getCenter(preview).dx, .01),
      );
      expect(
        tester.getCenter(hand).dy,
        closeTo(tester.getCenter(preview).dy, .01),
      );
      final playlist = tester
          .widget<Text>(find.textContaining('Playlist ·'))
          .data;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      expect(
        tester.widget<Text>(find.textContaining('Playlist ·').last).data,
        playlist,
        reason: 'Waiting for the user must not change the video',
      );
      expect(c.tutorialIndex, 1, reason: 'A demo cannot complete the lesson');
      final guide = tester.widget<GestureCameraGuide>(
        find.byType(GestureCameraGuide),
      );
      expect(
        guide.handPractice,
        isFalse,
        reason: 'Social keeps its own profile',
      );
      guide.onWrongHand!(true);
      await tester.pump();
      final wrongHint = find.byKey(const ValueKey('social-wrong-hand-hint'));
      expect(wrongHint, findsOneWidget);
      expect(tester.widget<Text>(wrongHint).style!.fontSize, 18);
      expect(
        find.ancestor(of: wrongHint, matching: find.byType(AnimatedOpacity)),
        findsNothing,
        reason: 'The wrong-hand message must not inherit the faded demo hand',
      );
      expect(find.byType(SnackBar), findsNothing);
      expect(
        tester.getTopLeft(wrongHint).dy,
        greaterThanOrEqualTo(
          tester
              .getBottomLeft(find.byKey(const ValueKey('youtube-hand-guide')))
              .dy,
        ),
      );
      guide.onWrongHand!(false);
      await tester.pump();
      expect(wrongHint, findsNothing);
      guide.onReading!((progress: .15, status: 'Matching', matching: true));
      await tester.pump();
      expect(find.text('Response'), findsOneWidget);

      expect(
        tester
            .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
            .practiceEnabled,
        isTrue,
        reason: 'Response feedback must not reset the active gesture hold',
      );

      guide.onMatched!();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Success'), findsOneWidget);
      expect(
        find.descendant(
          of: feedback,
          matching: find.byIcon(Icons.check_circle),
        ),
        findsOneWidget,
      );
      final opacity = find.descendant(
        of: find.byKey(const ValueKey('youtube-hand-visibility')),
        matching: find.byType(FadeTransition),
      );
      expect(tester.widget<FadeTransition>(opacity).opacity.value, 1);
      expect(c.tutorialIndex, 1);
      // Skip during the result pause must not let the old auto-next skip again.
      await tester.tap(find.byKey(const ValueKey('social-skip')));
      await tester.pump();
      expect(c.tutorialIndex, 2);
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
      expect(c.tutorialIndex, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    });
  }
  testWidgets('Social background cancels auto-next and resumes demonstration', (
    tester,
  ) async {
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.replayTutorial(0, group: TutorialGroup.video);
    await tester.pumpWidget(GestureApp(controller: c));
    await finishSocialDemo(tester);
    tester
        .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
        .onMatched!();
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 5));
    expect(c.tutorialIndex, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await finishSocialDemo(tester);
    expect(
      tester
          .widget<AnimatedOpacity>(
            find.byKey(const ValueKey('youtube-hand-visibility')),
          )
          .opacity,
      .65,
    );
    expect(c.tutorialIndex, 0);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('social-next')))
          .onPressed,
      isNull,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });
  test(
    'Skip advances one exercise in both groups, including the last step',
    () async {
      final c = GestureController(preferences, discovery: FakeDiscovery());
      for (final group in TutorialGroup.values) {
        c.replayTutorial(0, group: group, returnTo: FlowPage.tutorialMenu);
        final oldSession = c.tutorialSession;
        for (var step = 0; step < c.tutorialSteps.length; step++) {
          await c.skipTutorial();
          if (step < c.tutorialSteps.length - 1) {
            expect(c.page, FlowPage.tutorial);
            expect(c.tutorialIndex, step + 1);
            expect(c.canAdvanceTutorial, isFalse);
          }
        }
        expect(c.page, FlowPage.tutorialCompleted);
        expect(
          preferences.getBool('gesture.${group.name}TutorialCompleted'),
          isNull,
        );
        await c.continueAfterTutorial();
        expect(c.page, FlowPage.tutorialMenu);
        expect(c.trained, isFalse);
        c.replayTutorial(0, group: group);
        await c.acceptTutorialMatch(
          group,
          0,
          hand: c.hand,
          session: oldSession,
        );
        expect(c.tutorialIndex, 0);
      }
      c.dispose();
    },
  );
  test(
    'leaving and reopening the same final step rejects old completion',
    () async {
      final c = GestureController(preferences, discovery: FakeDiscovery());
      final last = gestureTutorialSteps.length - 1;
      c.replayTutorial(last, returnTo: FlowPage.tutorialMenu);
      final completion = completeStep(c);
      c.open(FlowPage.tutorialMenu);
      c.replayTutorial(last, returnTo: FlowPage.tutorialMenu);
      await completion;
      expect(
        c.page,
        FlowPage.tutorial,
        reason: 'A previous visit cannot complete a reopened tutorial',
      );
      await completeStep(c);
      expect(c.page, FlowPage.tutorialCompleted);
      c.dispose();
    },
  );
  test(
    'a stale match cannot advance the same pose in a new tutorial visit',
    () async {
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.replayTutorial(0, returnTo: FlowPage.tutorialMenu);
      final oldSession = c.tutorialSession;
      await c.skipTutorial();
      c.replayTutorial(0, returnTo: FlowPage.tutorialMenu);
      await c.acceptTutorialMatch(
        TutorialGroup.hand,
        0,
        hand: c.hand,
        session: oldSession,
      );
      expect(c.tutorialIndex, 0);
      await completeStep(c);
      expect(c.tutorialIndex, 1);
      c.dispose();
    },
  );
  test(
    'Next and Continue cannot bypass camera success or set completion',
    () async {
      final c = GestureController(preferences, discovery: FakeDiscovery());
      for (final group in TutorialGroup.values) {
        c.replayTutorial(0, group: group);
        await c.nextTutorial();
        expect(c.tutorialIndex, 0);
        expect(c.canAdvanceTutorial, isFalse);
        c.replayTutorial(stepsForGroup(group).length - 1, group: group);
        await c.nextTutorial();
        expect(c.page, FlowPage.tutorial);
        expect(
          preferences.getBool('gesture.${group.name}TutorialCompleted'),
          isNull,
        );
        await c.acceptTutorialMatch(
          group,
          c.tutorialIndex,
          session: c.tutorialSession,
          hand: c.hand == 'Left' ? 'Right' : 'Left',
        );
        expect(c.page, FlowPage.tutorial);
        await completeStep(c);
        expect(c.page, FlowPage.tutorialCompleted);
        expect(
          preferences.getBool('gesture.${group.name}TutorialCompleted'),
          isTrue,
        );
      }
      c.dispose();
    },
  );

  test('first-time setup follows all twelve tutorials and persists', () async {
    final c = GestureController(preferences, discovery: FakeDiscovery());
    expect(c.page, FlowPage.splash);
    await c.signInDemo('Tester');
    expect(c.page, FlowPage.home);
    c.chooseConnection('Scan');
    await c.connectDemoDevice();
    expect(c.page, FlowPage.camera);
    await c.setCameraPoint('Centre');
    c.finishCamera();
    expect(c.page, FlowPage.hand);
    await c.setHand('Left');
    c.finishHand();
    expect(c.tutorialIndex, 0);
    await completeStep(c);
    expect(c.tutorialIndex, 1);
    await completeStep(c);
    expect(c.tutorialIndex, 2);
    for (var step = 2; step < gestureTutorialSteps.length; step++) {
      await completeStep(c);
    }
    expect(c.page, FlowPage.tutorialCompleted);
    expect(c.trained, isFalse);
    await c.continueAfterTutorial();
    expect(c.tutorialGroup, TutorialGroup.video);
    for (var step = 0; step < videoTutorialSteps.length; step++) {
      await completeStep(c);
    }
    expect(c.page, FlowPage.tutorialCompleted);
    await c.continueAfterTutorial();
    expect(c.page, FlowPage.control);
    final restored = GestureController(preferences, discovery: FakeDiscovery());
    expect(restored.page, FlowPage.control);
    expect(restored.cameraPoint, 'Centre');
    expect(restored.hand, 'Left');
    c.dispose();
    restored.dispose();
  });
  test(
    'video progress and completion survive restart and independent replay',
    () async {
      var c = GestureController(preferences, discovery: FakeDiscovery());
      await c.signInDemo('Tester');
      await c.connectDemoDevice();
      c.finishCamera();
      c.finishHand();
      for (var i = 0; i < gestureTutorialSteps.length; i++) {
        await completeStep(c);
      }
      expect(c.page, FlowPage.tutorialCompleted);
      c.dispose();
      c = GestureController(preferences, discovery: FakeDiscovery());
      c.resumeSetup();
      expect(c.page, FlowPage.tutorialCompleted);
      expect(c.tutorialGroup, TutorialGroup.hand);
      await c.continueAfterTutorial();
      await completeStep(c);
      await completeStep(c);
      expect(c.tutorialIndex, 2);
      c.replayTutorial(0);
      await c.skipTutorial();
      c.resumeSetup();
      expect(c.tutorialGroup, TutorialGroup.video);
      expect(c.tutorialIndex, 2);
      c.dispose();
      c = GestureController(preferences, discovery: FakeDiscovery());
      c.resumeSetup();
      expect(c.tutorialGroup, TutorialGroup.video);
      expect(c.tutorialIndex, 2);
      for (var i = 2; i < videoTutorialSteps.length; i++) {
        await completeStep(c);
      }
      expect(c.page, FlowPage.tutorialCompleted);
      expect(c.trained, isFalse);
      c.dispose();
      c = GestureController(preferences, discovery: FakeDiscovery());
      c.resumeSetup();
      expect(c.page, FlowPage.tutorialCompleted);
      expect(c.tutorialGroup, TutorialGroup.video);
      await c.continueAfterTutorial();
      expect(c.page, FlowPage.control);
      expect(preferences.getBool('gesture.handTutorialCompleted'), isTrue);
      expect(preferences.getBool('gesture.videoTutorialCompleted'), isTrue);
      c.dispose();
    },
  );
  test(
    'stale hand callbacks cannot advance a video page with the same index',
    () {
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.replayTutorial(0, group: TutorialGroup.video);
      c.acceptTutorialMatch(
        TutorialGroup.hand,
        0,
        hand: c.hand,
        session: c.tutorialSession,
      );
      expect(c.tutorialIndex, 0);
      c.acceptTutorialMatch(
        TutorialGroup.video,
        0,
        hand: c.hand,
        session: c.tutorialSession,
      );
      expect(c.tutorialIndex, 1);
      c.acceptTutorialMatch(
        TutorialGroup.video,
        0,
        hand: c.hand,
        session: c.tutorialSession,
      );
      expect(c.tutorialIndex, 1);
      c.dispose();
    },
  );
  test(
    'replay completion returns to menu and Skip advances only one exercise',
    () async {
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.replayTutorial(
        7,
        group: TutorialGroup.video,
        returnTo: FlowPage.tutorialMenu,
      );
      await completeStep(c);
      expect(c.page, FlowPage.tutorialCompleted);
      await c.continueAfterTutorial();
      expect(c.page, FlowPage.tutorialMenu);
      expect(c.trained, isFalse);
      c.replayTutorial(0, returnTo: FlowPage.tutorialMenu);
      await c.skipTutorial();
      expect(c.page, FlowPage.tutorial);
      expect(c.tutorialIndex, 1);
      expect(c.canAdvanceTutorial, isFalse);
      expect(preferences.getBool('gesture.handTutorialCompleted'), isNull);
      c.dispose();
    },
  );
  test('failed or cancelled discovery does not save a demo device', () async {
    final c = GestureController(preferences, discovery: FakeDiscovery());
    await c.signInDemo('Tester');
    c.chooseConnection('Search');
    c.failConnection();
    c.back();
    expect(c.page, FlowPage.home);
    expect(c.device, isNull);
    expect(preferences.containsKey('gesture.device'), isFalse);
    c.dispose();
  });
  test('interrupted setup resumes its saved stage and tutorial step', () async {
    var c = GestureController(preferences, discovery: FakeDiscovery());
    await c.signInDemo('Tester');
    await c.connectDemoDevice();
    c.dispose();
    c = GestureController(preferences, discovery: FakeDiscovery());
    expect(c.page, FlowPage.home);
    c.resumeSetup();
    expect(c.page, FlowPage.camera);
    c.finishCamera();
    c.dispose();
    c = GestureController(preferences, discovery: FakeDiscovery());
    c.resumeSetup();
    expect(c.page, FlowPage.hand);
    c.finishHand();
    await completeStep(c);
    await completeStep(c);
    c.back();
    c.dispose();
    c = GestureController(preferences, discovery: FakeDiscovery());
    c.resumeSetup();
    expect(c.page, FlowPage.tutorial);
    expect(c.tutorialIndex, 1);
    // Settings edits and replay must not replace onboarding's return routes
    // or its saved training step.
    c.open(FlowPage.home);
    c.openSettings(returnTo: FlowPage.home);
    c.editCamera();
    c.finishCamera();
    c.editHand();
    c.finishHand();
    c.replayTutorial(8);
    await completeStep(c);
    await c.skipTutorial();
    c.back();
    c.resumeSetup();
    expect(c.tutorialIndex, 1);
    expect(c.setupTutorial, isTrue);
    c.back();
    c.back();
    expect(c.page, FlowPage.hand);
    c.finishHand();
    expect(c.page, FlowPage.tutorial);
    await c.skipTutorial();
    expect(c.tutorialIndex, 1);
    expect(c.trained, isFalse);
    await finishSetup(c);
    expect(c.page, FlowPage.control);
    c.dispose();
    c = GestureController(preferences, discovery: FakeDiscovery());
    expect(c.page, FlowPage.control);
    c.dispose();
  });
  test(
    'adding a device starts fresh onboarding after a completed setup',
    () async {
      final c = GestureController(preferences, discovery: FakeDiscovery());
      await c.signInDemo('Tester');
      await c.connectDemoDevice();
      c.finishCamera();
      c.finishHand();
      await finishSetup(c);
      expect(c.trained, isTrue);
      await c.connectDemoDevice();
      expect(c.trained, isFalse);
      c.dispose();
      final restored = GestureController(
        preferences,
        discovery: FakeDiscovery(),
      );
      expect(restored.page, FlowPage.home);
      restored.resumeSetup();
      expect(restored.page, FlowPage.camera);
      restored.dispose();
    },
  );
  test('settings tutorials and logout preserve configuration', () async {
    final c = GestureController(preferences, discovery: FakeDiscovery());
    await c.signInDemo('Tester');
    await c.connectDemoDevice();
    c.finishCamera();
    c.finishHand();
    for (var step = 0; step < gestureTutorialSteps.length; step++) {
      await completeStep(c);
    }
    await c.continueAfterTutorial();
    for (var step = 0; step < videoTutorialSteps.length; step++) {
      await completeStep(c);
    }
    await c.continueAfterTutorial();
    await c.setMode(GestureMode.social);
    await c.setReaction('Play / pause');
    c.editHand();
    await c.setHand('Both');
    c.finishHand();
    expect(c.page, FlowPage.settings);
    c.replayTutorial(1);
    await completeStep(c);
    expect(c.tutorialIndex, 2);
    c.back();
    expect(c.tutorialIndex, 1);
    await c.skipTutorial();
    expect(c.page, FlowPage.tutorial);
    expect(c.tutorialIndex, 2);
    await c.logout();
    expect(c.page, FlowPage.login);
    await c.signInDemo('Tester');
    expect(c.page, FlowPage.control);
    expect(c.mode, GestureMode.social);
    expect(c.hand, 'Both');
    expect(c.reaction, 'Play / pause');
    c.dispose();
  });
  testWidgets('user can navigate the entire first-time flow on a small phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    await tester.pumpWidget(GestureApp(controller: c));
    Future<void> tapText(String text) async {
      final finder = find.text(text);
      await tester.scrollUntilVisible(
        finder,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    await tapText('Get Started');
    await tester.enterText(
      find.byKey(const ValueKey('Email')),
      'tester@example.com',
    );
    await tester.enterText(find.byKey(const ValueKey('Password')), 'demo12345');
    await tapText('Log In');
    await tapText('Add Device');
    await tester.tap(find.byKey(const ValueKey('connect-0')));
    await tester.pumpAndSettle();
    await tapText('Save');
    await tapText('Save');
    for (var step = 0; step < gestureTutorialSteps.length; step++) {
      expect(find.text(gestureTutorialSteps[step].title), findsOneWidget);
      expect(
        tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull,
      );
      tester
          .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
          .onMatched!();
      await tester.pumpAndSettle();
    }
    expect(find.text('Congratulations'), findsOneWidget);
    await tapText('Next');
    for (var step = 0; step < videoTutorialSteps.length; step++) {
      await finishSocialDemo(tester);
      expect(find.text(videoTutorialSteps[step].title), findsOneWidget);
      final next = find.byKey(const ValueKey('social-next'));
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      final navigationWidth = tester
          .getSize(find.byKey(const ValueKey('youtube-phone-navigation')))
          .width;
      expect(
        tester.getSize(next).width * 2 + 12,
        closeTo(navigationWidth, .01),
      );
      expect(
        tester.getSize(find.byType(FilledButton).first).width,
        navigationWidth,
      );
      expect(find.text('Facebook'), findsNothing);
      expect(find.text('TikTok'), findsNothing);
      await tester.ensureVisible(find.text('Replay demo'));
      await tester.tap(find.text('Replay demo'));
      await finishSocialDemo(tester);
      expect(c.tutorialIndex, step);
      expect(
        tester.widget<FilledButton>(next).onPressed,
        isNull,
        reason: 'An animated demonstration cannot complete a real gesture',
      );
      final guide = tester.widget<GestureCameraGuide>(
        find.byType(GestureCameraGuide),
      );
      final handGuide = tester.widget<Image>(
        find.byKey(const ValueKey('youtube-hand-guide')),
      );
      expect(
        (handGuide.image as AssetImage).assetName,
        TutorialOutlineAssets.forPose(
          videoTutorialSteps[step].pose,
          isLeftHand: c.hand == 'Left',
        ),
      );
      expect(handGuide.color, AppColors.textPrimary);
      final tryGesture = tester.widget<GestureBorderIcon>(
        find.byKey(const ValueKey('social-try-gesture')),
      );
      expect(
        tryGesture.assetPath,
        HandGestureIcons.forPose(
          videoTutorialSteps[step].pose,
          isLeftHand: c.hand == 'Left',
        ),
        reason: 'Try outlines the current lesson pose and selected hand',
      );
      expect(find.text('Open your hand, then try again'), findsNothing);
      expect(
        guide.requireRelease,
        isFalse,
        reason: 'Play/Pause accept the punch directly',
      );

      final oldStep = [3, 2, 5, 4, 0, 1, 6, 7][step];
      if (oldStep < 2) {
        final playback = find.byKey(const ValueKey('youtube-playback-control'));
        expect(
          find.descendant(
            of: playback,
            matching: find.byIcon(
              oldStep == 0 ? Icons.play_arrow : Icons.pause,
            ),
          ),
          findsOneWidget,
        );
      }

      final beforePlaylist = (oldStep == 2 || oldStep == 3)
          ? tester.widget<Text>(find.textContaining('Playlist ·').last).data
          : null;
      guide.onReading!((progress: .15, status: 'Matching', matching: true));
      await tester.pump();
      expect(find.text('Response'), findsOneWidget);
      if (oldStep < 2) {
        final playback = find.byKey(const ValueKey('youtube-playback-control'));
        expect(
          find.descendant(
            of: playback,
            matching: find.byIcon(
              oldStep == 0 ? Icons.pause : Icons.play_arrow,
            ),
          ),
          findsOneWidget,
          reason:
              'The player icon updates with the live action before confirmation',
        );
      }

      expect(c.tutorialIndex, step);
      if (oldStep == 2 || oldStep == 3) {
        expect(
          tester.widget<Text>(find.textContaining('Playlist ·').last).data,
          isNot(beforePlaylist),
          reason: 'Video changes before the hold is complete',
        );
      }
      if (oldStep >= 2 && oldStep <= 5) {
        final title = oldStep == 2 || oldStep == 4
            ? 'Ready for liftoff'
            : 'A little curiosity';
        expect(
          find.text(oldStep >= 4 ? '$title #shorts' : title),
          findsOneWidget,
        );
      }
      if (oldStep >= 6) {
        final volume = find.byKey(const ValueKey('youtube-volume-feedback'));
        expect(volume, findsOneWidget);
        final placement = tester.widget<Positioned>(
          find.ancestor(of: volume, matching: find.byType(Positioned)).first,
        );
        expect(
          placement.top,
          isNotNull,
          reason: 'Volume is positioned on the video',
        );
        expect(placement.bottom, isNull);
      }
      expect(
        find.byKey(const ValueKey('youtube-action-feedback')),
        findsOneWidget,
      );
      expect(
        find.text(
          [
            'Playing',
            'Paused',
            'Next video',
            'Previous video',
            'Next Short',
            'Previous Short',
            'Volume up · 70%',
            'Volume down · 30%',
          ][oldStep],
        ),
        findsOneWidget,
      );
      expect(find.text('YOUR GESTURE DID THIS'), findsNothing);
      expect(find.text('DEMO · WATCH YOUTUBE'), findsNothing);
      expect(
        find.byKey(const ValueKey('youtube-action-result')),
        findsNothing,
        reason: 'Teaching result text stays off the YouTube screen',
      );
      expect(tester.widget<FilledButton>(next).onPressed, isNull);
      await tester.pump(const Duration(seconds: 1));
      if (oldStep >= 2 && oldStep <= 5) {
        final slides = tester
            .widgetList<SlideTransition>(
              find.descendant(
                of: find.byKey(const ValueKey('youtube-preview')),
                matching: find.byType(SlideTransition),
              ),
            )
            .where((slide) => slide.key.toString().contains('youtube-slide-'));
        final destination = oldStep == 2 || oldStep == 4 ? 2 : 0;
        final incoming = slides.singleWhere(
          (slide) => slide.child!.key == ValueKey(destination),
        );
        final outgoing = slides.singleWhere(
          (slide) => slide.child!.key == const ValueKey(1),
        );
        final expectedDirection = oldStep == 3 || oldStep == 4 ? -1 : 1;
        final halfTransition = 1 - Curves.easeInOutCubic.transform(.5);
        final offset = incoming.position.value;
        final oldOffset = outgoing.position.value;
        expect(
          oldStep >= 4 ? offset.dy : offset.dx,
          closeTo(expectedDirection * halfTransition, .01),
          reason: 'Scroll Down enters above; Scroll Up enters below',
        );
        expect(
          oldStep >= 4 ? oldOffset.dy : oldOffset.dx,
          closeTo(-expectedDirection * halfTransition, .01),
          reason: 'The previous screen exits in the same travel direction',
        );
      }
      guide.onMatched!();
      await tester.pump();
      expect(find.text('Success'), findsOneWidget);
      expect(
        tester
            .widget<Image>(find.byKey(const ValueKey('youtube-hand-guide')))
            .color,
        AppColors.primary,
      );
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('youtube-hand-visibility')),
            )
            .opacity,
        1,
      );
      await tester.pump(const Duration(milliseconds: 900));
      expect(
        c.tutorialIndex,
        step,
        reason: 'Keep confirmation visible for one second',
      );
      await tester.pump(const Duration(milliseconds: 101));
      await tester.pumpAndSettle();
      if (step < videoTutorialSteps.length - 1) {
        expect(c.tutorialIndex, step + 1);
      } else {
        expect(c.page, FlowPage.tutorialCompleted);
      }
    }
    expect(find.text('Congratulations'), findsOneWidget);
    await tapText('Finish');
    expect(find.text('Hello!'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-face')), findsOneWidget);
    expect(find.text('Simulate recognised gesture'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('sign-up validates passwords and stores only the demo profile', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.open(FlowPage.createAccount);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('Full Name')), 'Tester');
    await tester.enterText(
      find.byKey(const ValueKey('Email')),
      'tester@example.com',
    );
    await tester.enterText(find.byKey(const ValueKey('Password')), 'demo12345');
    await tester.enterText(
      find.byKey(const ValueKey('Confirm Password')),
      'different',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(find.text('Your passwords do not match.'), findsOneWidget);
    expect(c.page, FlowPage.createAccount);

    await tester.tap(find.byTooltip('Show Password'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const ValueKey('Password')))
          .obscureText,
      isFalse,
    );
    await tester.enterText(
      find.byKey(const ValueKey('Confirm Password')),
      'demo12345',
    );
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
    expect(c.page, FlowPage.home);
    expect(c.name, 'Tester');
    expect(
      preferences.getKeys(),
      unorderedEquals([
        'gesture.name',
        'gesture.demoSession',
        'gesture.socialLessonOrder',
      ]),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets(
    'Auto lists MAC addresses and Manual shows one Gesture Control card',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.chooseConnection('Auto');
      await tester.pumpWidget(GestureApp(controller: c));
      await tester.pumpAndSettle();
      expect(find.textContaining('MAC Address:'), findsNWidgets(4));
      expect(find.textContaining('IP Address:'), findsNothing);
      final discovery = c.discovery as FakeDiscovery;
      expect(discovery.starts, 1);
      await tester.tap(find.byKey(const ValueKey('refresh-bluetooth')));
      await tester.pumpAndSettle();
      expect(discovery.starts, 2);
      await tester.tap(find.text('Manually'));
      await tester.pumpAndSettle();
      expect(find.textContaining('MAC Address:'), findsNothing);
      expect(find.text('Gesture Control'), findsOneWidget);
      expect(find.byKey(const ValueKey('refresh-bluetooth')), findsNothing);
      expect(discovery.stops, greaterThan(0));
      expect(find.text('Connect'), findsNothing);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Search'), findsNothing);
      expect(find.text('Scan'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('manual-gesture-control')));
      await tester.pumpAndSettle();
      expect(c.page, FlowPage.camera);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  for (final size in [
    const Size(402, 874),
    const Size(874, 402),
    const Size(320, 568),
  ]) {
    testWidgets('Home mode badge switches and persists all modes on $size', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.mode = GestureMode.face;
      c.open(FlowPage.control);
      await tester.pumpWidget(GestureApp(controller: c));
      await tester.pumpAndSettle();
      final cameraState = tester.state(
        find.byKey(const ValueKey('home-face-tracking')),
      );
      expect(
        tester
            .widget<FaceTrackingEyes>(
              find.byKey(const ValueKey('home-face-tracking')),
            )
            .faceDebugEnabled,
        isFalse,
      );
      expect(
        find.byKey(const ValueKey('face-location-debug-panel')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('face-debug-toggle')), findsNothing);
      final badge = find.byKey(const ValueKey('home-mode-badge'));
      final bounds = tester.getRect(badge);
      expect(bounds.left, greaterThanOrEqualTo(0));
      expect(bounds.right, lessThanOrEqualTo(size.width));
      expect(
        bounds.overlaps(tester.getRect(find.byTooltip('Settings'))),
        isFalse,
      );
      expect(
        bounds.overlaps(
          tester.getRect(find.byKey(const ValueKey('home-face'))),
        ),
        isFalse,
      );
      for (final mode in [
        GestureMode.hand,
        GestureMode.social,
        GestureMode.face,
      ]) {
        await tester.tap(badge);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('home-mode-${mode.name}')));
        await tester.pumpAndSettle();
        expect(c.page, FlowPage.control);
        expect(c.mode, mode);
        expect(preferences.getString('gesture.mode'), mode.name);
        expect(
          find.descendant(of: badge, matching: find.text('${mode.label} mode')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FaceTrackingEyes>(
                find.byKey(const ValueKey('home-face-tracking')),
              )
              .enabled,
          mode == GestureMode.face,
        );
        expect(
          tester.state(find.byKey(const ValueKey('home-face-tracking'))),
          same(cameraState),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    });
  }

  testWidgets('setup saves the camera position and V.1 hand selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.open(FlowPage.camera);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    final marker = find.byKey(const ValueKey('face-position-marker'));
    final original = tester.getCenter(marker);
    final area = find.byKey(const ValueKey('camera-position-area'));
    expect(original, tester.getCenter(area));
    await tester.tapAt(tester.getTopLeft(area) + const Offset(100, 100));
    await tester.pumpAndSettle();
    expect(tester.getCenter(marker), isNot(original));
    expect(preferences.getDouble('gesture.cameraX'), isNull);
    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(tester.getCenter(marker), original);
    await tester.tapAt(tester.getTopLeft(area) + const Offset(120, 140));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.page, FlowPage.hand);
    expect(c.cameraX, closeTo(120 / 362, .001));
    expect(c.cameraY, closeTo(140 / 594, .001));
    expect(find.text('Left Hand'), findsOneWidget);
    expect(find.text('Right Hand'), findsOneWidget);
    expect(find.text('Both'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('select-left-hand')));
    await tester.pumpAndSettle();
    expect(c.hand, 'Right');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.page, FlowPage.tutorial);
    final restored = GestureController(preferences, discovery: FakeDiscovery());
    expect(restored.hand, 'Left');
    expect(restored.cameraX, c.cameraX);
    expect(restored.cameraY, c.cameraY);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    restored.dispose();
    c.dispose();
  });

  testWidgets(
    'Saved camera setting drives Home position and proportional automatic resizing',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 874);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.mode = GestureMode.face;
      c.open(FlowPage.control);
      await tester.pumpWidget(GestureApp(controller: c));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change camera point position'));
      await tester.pumpAndSettle();
      final area = find.byKey(const ValueKey('camera-position-area'));
      await tester.tapAt(
        tester.getTopLeft(area) + const Offset(362 * .35, 594 * .65),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(c.page, FlowPage.settings);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      c.dispose();
      final restored = GestureController(
        preferences,
        discovery: FakeDiscovery(),
      );
      restored.mode = GestureMode.face;
      restored.faceEmoji = 0;
      restored.open(FlowPage.control);
      final sizes = <Size, Size>{};
      for (final size in [
        const Size(402, 874),
        const Size(874, 402),
        const Size(768, 1024),
        const Size(1024, 768),
        const Size(320, 568),
        const Size(568, 320),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(GestureApp(controller: restored));
        await tester.pumpAndSettle();
        final tracking = tester.widget<FaceTrackingEyes>(
          find.byKey(const ValueKey('home-face-tracking')),
        );
        expect(tracking.savedStartPosition!.dx, closeTo(.35, .0001));
        expect(tracking.savedStartPosition!.dy, closeTo(.65, .0001));
        final rect = tester.getRect(find.byKey(const ValueKey('home-face')));
        sizes[size] = rect.size;
        expect(rect.width / rect.height, closeTo(312 / 200, .0001));
        final mouth = tester.renderObject<RenderBox>(find.byType(TrackedMouth));
        final center = mouth.localToGlobal(const Offset(156, 100));
        // Face-mode sizing now leaves room to reach this saved point in either
        // orientation, while the avatar still stays inside its screen margins.
        expect(center.dx / size.width, closeTo(.35, .001));
        expect(center.dy / size.height, closeTo(.65, .001));
        final eye = tester.renderObject<RenderBox>(
          find.descendant(
            of: find.byKey(const ValueKey('blink-screen-left')),
            matching: find.byType(Image),
          ),
        );
        final spacing =
            mouth.localToGlobal(const Offset(156, 192)) -
            eye.localToGlobal(const Offset(78, 62));
        expect(
          (spacing / (rect.width / 312) - const Offset(78, 130)).distance,
          lessThan(.01),
        );
        expect(tester.takeException(), isNull);
      }
      for (final portrait in [
        const Size(402, 874),
        const Size(768, 1024),
        const Size(320, 568),
      ]) {
        final landscape = Size(portrait.height, portrait.width);
        expect(sizes[landscape]!.width, greaterThan(sizes[portrait]!.width));
        expect(sizes[landscape]!.height, greaterThan(sizes[portrait]!.height));
      }
      expect(
        sizes[const Size(1024, 768)]!.width,
        greaterThan(sizes[const Size(874, 402)]!.width),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      restored.dispose();
    },
  );

  testWidgets(
    'profile logout requires confirmation on both Home pages and orientations',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final size in [const Size(402, 874), const Size(874, 402)]) {
        tester.view.physicalSize = size;
        for (final page in [FlowPage.home, FlowPage.control]) {
          final c = GestureController(preferences, discovery: FakeDiscovery());
          c.mode = GestureMode.hand;
          c.open(page);
          await tester.pumpWidget(GestureApp(controller: c));
          await tester.pumpAndSettle();
          Future<void> openConfirmation() async {
            await tester.tap(find.byTooltip('Profile'));
            await tester.pumpAndSettle();
            await tester.tap(find.text('Log out'));
            await tester.pumpAndSettle();
            expect(find.text('Log out?'), findsOneWidget);
            expect(c.page, page);
          }

          await openConfirmation();
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(c.page, page);
          await openConfirmation();
          await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
          await tester.pumpAndSettle();
          expect(c.page, FlowPage.login);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          c.dispose();
        }
      }
    },
  );

  testWidgets('Home switches orientation and preserves settings navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.mode = GestureMode.hand;
    c.open(FlowPage.control);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-vertical')), findsOneWidget);
    final face = find.byKey(const ValueKey('home-face'));
    expect(tester.getTopLeft(face), const Offset(45, 337));
    final notice = find.ancestor(
      of: find.text('Hand gesture control enabled'),
      matching: find.byType(Positioned),
    );
    expect(
      tester.getBottomRight(notice).dy,
      850,
      reason: 'The designed notice sits 24 pixels above the bottom',
    );
    expect(tester.getCenter(notice).dx, 201);
    tester.view.physicalSize = const Size(874, 402);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('home-horizontal')), findsOneWidget);
    final landscapeFace = tester.getRect(face);
    expect(landscapeFace.center, const Offset(437, 201));
    expect(landscapeFace.height, closeTo(225.12, .001));
    expect(tester.getBottomRight(notice).dy, 378);
    expect(tester.getCenter(notice).dx, 437);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(c.page, FlowPage.settings);
    c.back();
    await tester.pumpAndSettle();
    expect(c.page, FlowPage.control);
    expect(find.byKey(const ValueKey('home-horizontal')), findsOneWidget);
    await tester.tap(find.byTooltip('Profile'));
    await tester.pumpAndSettle();
    expect(find.text('AI assistant tools'), findsNothing);
    expect(find.text('Log out'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets(
    'Opt-in location debug adapts to portrait, landscape and small phones while other diagnostics stay hidden',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.mode = GestureMode.face;
      c.open(FlowPage.control);
      for (final size in [
        const Size(402, 874),
        const Size(874, 402),
        const Size(568, 320),
        const Size(1200, 360),
        const Size(1024, 768),
        const Size(320, 568),
      ]) {
        tester.view.physicalSize = size;
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: c,
            child: const MaterialApp(
              home: ControlScreen(enableFaceDebug: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final faceRect = tester.getRect(
          find.byKey(const ValueKey('home-face')),
        );
        expect(faceRect.bottom, lessThanOrEqualTo(size.height));
        final canvasRect = tester.getRect(
          find.byKey(
            ValueKey(
              size.width > size.height ? 'home-horizontal' : 'home-vertical',
            ),
          ),
        );
        expect(canvasRect.left, closeTo(0, .001));
        expect(canvasRect.top, closeTo(0, .001));
        expect(canvasRect.width, closeTo(size.width, .001));
        expect(canvasRect.height, closeTo(size.height, .001));
        expect(
          (faceRect.center - Offset(size.width / 2, size.height / 2)).distance,
          lessThan(.001),
        );
        final tracking = tester.widget<FaceTrackingEyes>(
          find.byKey(const ValueKey('home-face-tracking')),
        );
        final travel = tracking.movementBounds;
        expect(tracking.screenMapping, isNotNull);
        expect(find.byKey(const ValueKey('face-debug-center')), findsNothing);
        final mapping = tracking.screenMapping!;
        // Keep requested centers inside the enlarged avatar's edge limits.
        for (final ratio in [const Offset(.45, .55), const Offset(.55, .45)]) {
          final mapped = mapping.ratioForShift(
            mapping.shiftForRatio(ratio, travel),
          );
          expect((mapped - ratio).distance, lessThan(.0001));
        }
        final scale = faceRect.width / 312;
        expect(
          travel.top,
          lessThanOrEqualTo(size.width > size.height ? -50 : -100),
        );
        expect(
          travel.bottom,
          greaterThanOrEqualTo(size.width > size.height ? 50 : 57),
        );
        if (size.width > size.height) {
          expect(travel.top, closeTo(-travel.bottom, .001));
          expect(
            faceRect.top + travel.top * scale,
            lessThan(size.height * .08),
          );
          expect(
            faceRect.bottom + travel.bottom * scale,
            greaterThan(size.height * .92),
          );
          final panelRect = tester.getRect(
            find.byKey(const ValueKey('face-location-debug-panel')),
          );
          expect(-travel.left * scale / size.width, greaterThan(.18));
          expect(travel.right * scale / size.width, greaterThan(.18));
          expect(travel.left, closeTo(-travel.right, .001));
          expect(faceRect.left + travel.left * scale, greaterThanOrEqualTo(0));
          expect(
            faceRect.right + travel.right * scale,
            lessThanOrEqualTo(size.width),
          );
          expect(faceRect.right, lessThan(panelRect.left));
          expect(panelRect.bottom, lessThanOrEqualTo(size.height));
          final owner = tester.state(
            find.byKey(const ValueKey('home-face-tracking')),
          );
          tracking.onPositionChanged!(Offset(travel.right, 0));
          await tester.pump();
          final leftPanel = tester.getRect(
            find.byKey(const ValueKey('face-location-debug-panel')),
          );
          expect(leftPanel.right, lessThan(faceRect.left));
          final updated = tester.widget<FaceTrackingEyes>(
            find.byKey(const ValueKey('home-face-tracking')),
          );
          updated.onPositionChanged!(Offset(travel.left, 0));
          await tester.pump();
          final rightPanel = tester.getRect(
            find.byKey(const ValueKey('face-location-debug-panel')),
          );
          expect(rightPanel.left, greaterThan(faceRect.right));
          expect(
            tester.state(find.byKey(const ValueKey('home-face-tracking'))),
            same(owner),
          );
        }
        expect(faceRect.top + travel.top * scale, greaterThanOrEqualTo(0));
        expect(
          faceRect.bottom + travel.bottom * scale,
          lessThanOrEqualTo(size.height),
        );
        if (size.height > size.width) {
          tracking.onPositionChanged!(Offset(0, travel.bottom));
          await tester.pump();
          final upperPanel = tester.getRect(
            find.byKey(const ValueKey('face-location-debug-panel')),
          );
          expect(
            upperPanel.bottom,
            lessThan(faceRect.top + travel.bottom * scale),
          );
          final updated = tester.widget<FaceTrackingEyes>(
            find.byKey(const ValueKey('home-face-tracking')),
          );
          updated.onPositionChanged!(Offset(0, travel.top));
          await tester.pump();
          final lowerPanel = tester.getRect(
            find.byKey(const ValueKey('face-location-debug-panel')),
          );
          expect(
            lowerPanel.top,
            greaterThan(faceRect.bottom + travel.top * scale),
          );
        }
        expect(find.byKey(const ValueKey('mouth-debug-status')), findsNothing);
        expect(find.byKey(const ValueKey('mouth-check-start')), findsNothing);
        expect(find.byKey(const ValueKey('mouth-debug-toggle')), findsNothing);
        expect(find.byKey(const ValueKey('mouth-debug-values')), findsNothing);
        expect(find.byKey(const ValueKey('eye-debug-status')), findsNothing);
        expect(find.byKey(const ValueKey('eye-check-start')), findsNothing);
        expect(find.byKey(const ValueKey('eye-debug-toggle')), findsNothing);
        expect(find.byKey(const ValueKey('eye-debug-values')), findsNothing);
        expect(tester.takeException(), isNull);
      }
      await tester.tap(find.byKey(const ValueKey('face-debug-toggle')));
      await tester.pumpAndSettle();
      final fullTravel = tester
          .widget<FaceTrackingEyes>(
            find.byKey(const ValueKey('home-face-tracking')),
          )
          .movementBounds;
      expect(fullTravel.bottom, greaterThan(250));
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(c.page, FlowPage.settings);
      await tester.pumpWidget(const SizedBox.shrink());
      c.dispose();
    },
  );

  testWidgets('all 21 guides select separate hand assets and keep Next locked', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.replayTutorial(0);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    for (final group in TutorialGroup.values) {
      final steps = stepsForGroup(group);
      for (var index = 0; index < steps.length; index++) {
        c.replayTutorial(index, group: group);
        await tester.pumpAndSettle();
        final guideElement = tester.element(find.byType(GestureCameraGuide));
        for (final hand in ['Left', 'Right']) {
          await c.setHand(hand);
          await tester.pumpAndSettle();
          expect(
            tester.element(find.byType(GestureCameraGuide)),
            isNot(same(guideElement)),
            reason: 'Changing the selected hand starts a fresh attempt',
          );
          expect(find.text('$hand hand'), findsNothing);
          expect(find.byKey(const ValueKey('fist-guidance')), findsNothing);
          expect(find.byKey(const ValueKey('fist-percentage')), findsNothing);
          expect(find.byType(GestureDebugOverlay), findsNothing);
          expect(
            tester
                .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
                .handPractice,
            group == TutorialGroup.hand,
          );
          if (group == TutorialGroup.video) {
            expect(find.byKey(const ValueKey('social-next')), findsOneWidget);
            expect(
              tester
                  .widget<FilledButton>(
                    find.byKey(const ValueKey('social-next')),
                  )
                  .onPressed,
              isNull,
            );
            expect(
              find.byKey(
                ValueKey(
                  'guide-${TutorialOutlineAssets.forPose(steps[index].pose, isLeftHand: hand == 'Left')}',
                ),
              ),
              findsNothing,
            );
            continue;
          }
          expect(find.byType(LinearProgressIndicator), findsNothing);
          expect(find.byType(OutlinedButton), findsOneWidget);
          expect(find.byType(FilledButton), findsOneWidget);
          final path = TutorialOutlineAssets.forPose(
            steps[index].pose,
            isLeftHand: hand == 'Left',
          );
          await settleOutline(tester, path);
          if (File(path).existsSync()) {
            final image = tester.widget<Image>(
              find.byKey(ValueKey('guide-$path')),
            );
            expect((image.image as AssetImage).assetName, path);
          }
          expect(
            find.byKey(const ValueKey('gesture-handed-artwork')),
            findsNothing,
          );
          expect(
            tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
            isNull,
          );
          expect(c.tutorialIndex, index);
        }
      }
    }
    final restored = GestureController(preferences, discovery: FakeDiscovery());
    expect(restored.hand, 'Right');
    restored.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('Fist score never advances without a detected hand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.replayTutorial(0);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    expect(find.text('Live hand tracking'), findsNothing);
    expect(find.byKey(const ValueKey('fist-guidance')), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(find.text('0%'), findsNothing);
    expect(c.tutorialIndex, 0);
    expect(find.text('Fist detected'), findsNothing);
    expect(preferences.getBool('gesture.trained'), isNull);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    await tester.tap(find.text('Next (01/13)'));
    await tester.pumpAndSettle();
    expect(c.tutorialIndex, 0);
    tester
        .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
        .onMatched!();
    await tester.pumpAndSettle();
    expect(find.text('Move Right'), findsOneWidget);
    expect(find.text('Live hand tracking'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('changing hand rejects a pending callback for the previous hand', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.replayTutorial(0);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    final oldMatch = tester
        .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
        .onMatched!;
    await c.setHand('Left');
    // Preferences have changed, but the next widget frame has not rebuilt yet.
    oldMatch();
    expect(c.tutorialIndex, 0);
    await tester.pumpAndSettle();
    final current = tester.widget<GestureCameraGuide>(
      find.byType(GestureCameraGuide),
    );
    expect(current.isLeftHand, isTrue);
    current.onMatched!();
    expect(c.tutorialIndex, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets('Fist match advances once and ignores results after navigation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.replayTutorial(0);
    await tester.pumpWidget(GestureApp(controller: c));
    await tester.pumpAndSettle();
    final matched = tester
        .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
        .onMatched!;
    matched();
    matched();
    expect(
      c.tutorialIndex,
      1,
      reason: 'Repeated results cannot skip Move Right',
    );
    await tester.pumpAndSettle();
    expect(find.text('Move Right'), findsOneWidget);

    c.back();
    await tester.pumpAndSettle();
    final afterManualNext = tester
        .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
        .onMatched!;
    await completeStep(c);
    afterManualNext();
    expect(c.tutorialIndex, 1);
    await tester.pumpAndSettle();

    c.replayTutorial(0);
    await tester.pumpAndSettle();
    final afterLeaving = tester
        .widget<GestureCameraGuide>(find.byType(GestureCameraGuide))
        .onMatched!;
    c.open(FlowPage.settings);
    afterLeaving();
    expect(c.page, FlowPage.settings);
    expect(c.tutorialIndex, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    c.dispose();
  });

  testWidgets(
    'settings pages save choices, discard drafts and preserve tutorial routes',
    (tester) async {
      tester.view.physicalSize = const Size(402, 874);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = GestureController(preferences, discovery: FakeDiscovery());
      c.openSettings();
      await tester.pumpWidget(GestureApp(controller: c));
      await tester.pumpAndSettle();
      Future<void> tap(String label) async {
        await tester.tap(find.text(label));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      await tap('Select default mode');
      await tap('Hand Gesture');
      expect(c.mode, GestureMode.hand);
      expect(preferences.getString('gesture.mode'), 'hand');
      c.back();
      await tester.pumpAndSettle();
      await tap('Edit reactions');
      await tester.tap(find.byKey(const ValueKey('emoji-1')));
      await tester.tap(find.byKey(const ValueKey('reaction-color-2')));
      await tester.tap(find.byKey(const ValueKey('background-white')));
      await tester.pumpAndSettle();
      final draft = tester.widget<SvgPicture>(
        find.byKey(const ValueKey('reaction-preview')),
      );
      expect(
        draft.colorFilter,
        const ColorFilter.mode(Color(0xffb0e2ff), BlendMode.srcIn),
      );
      expect(c.faceEmoji, 0);
      expect(preferences.getInt('gesture.faceEmoji'), isNull);
      c.back();
      await tester.pumpAndSettle();
      await tap('Edit reactions');
      expect(
        tester
            .widget<Image>(find.byKey(const ValueKey('reaction-preview')))
            .color,
        const Color(0xffbbcff9),
      );
      await tester.tap(find.byKey(const ValueKey('emoji-1')));
      await tester.tap(find.byKey(const ValueKey('reaction-color-2')));
      await tester.tap(find.byKey(const ValueKey('background-white')));
      await tester.pumpAndSettle();
      await tap('Save');
      expect(c.page, FlowPage.settings);
      final restored = GestureController(
        preferences,
        discovery: FakeDiscovery(),
      );
      expect(restored.mode, GestureMode.hand);
      expect(restored.faceEmoji, 1);
      expect(restored.faceColor, 0xffb0e2ff);
      expect(restored.faceBackground, 0xffffffff);
      await tap('Tutorial');
      await tap('Face Gesture Tutorial');
      expect(c.page, FlowPage.faceTutorial);
      c.back();
      await tester.pumpAndSettle();
      expect(c.page, FlowPage.tutorialMenu);
      await tap('Social Media Control Tutorial');
      expect(c.page, FlowPage.tutorial);
      expect(c.tutorialGroup, TutorialGroup.video);
      expect(find.text('Go to Previous Video'), findsOneWidget);
      await tester.ensureVisible(find.text('Skip'));
      await tap('Skip');
      expect(c.page, FlowPage.tutorial);
      expect(c.tutorialIndex, 1);
      c.back();
      c.back();
      await tester.pumpAndSettle();
      await tap('Hand Gesture Tutorial');
      expect(c.page, FlowPage.tutorial);
      expect(find.text('Fist'), findsOneWidget);
      await tester.ensureVisible(find.text('Skip'));
      await tap('Skip');
      expect(c.page, FlowPage.tutorial);
      expect(c.tutorialIndex, 1);
      c.back();
      c.back();
      await tester.pumpAndSettle();
      c.back();
      await tester.pumpAndSettle();
      await tap('About');
      expect(find.text('Software Version: 0.1.0+1'), findsOneWidget);
      expect(find.text('Firmware: 1.0.1'), findsOneWidget);
      c.back();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Log out'));
      await tester.pumpAndSettle();
      await tap('Cancel');
      expect(c.page, FlowPage.settings);
      await tester.pumpWidget(const SizedBox.shrink());
      restored.dispose();
      c.dispose();
    },
  );

  test('settings opened from Home returns to Home', () {
    final c = GestureController(preferences, discovery: FakeDiscovery());
    c.openSettings(returnTo: FlowPage.home);
    c.back();
    expect(c.page, FlowPage.home);
    c.dispose();
  });
}

class FakeDiscovery extends DeviceDiscovery {
  int starts = 0, stops = 0;
  @override
  bool get scanning => false;
  @override
  String? get error => null;
  @override
  List<DiscoveredDevice> get devices => [
    for (var index = 1; index <= 4; index++)
      DiscoveredDevice('IF01-124h83s83', 'A4:C1:38:00:00:0$index'),
  ];
  @override
  Future<void> restart() async {
    starts++;
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}
