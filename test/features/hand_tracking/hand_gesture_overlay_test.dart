import 'dart:async';

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    as platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_gesture_overlay.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/hand_tracking/hand_debug_panel.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import '../../helpers/camera_image.dart';
import '../../helpers/gesture_pose_fixture.dart' show poseFixture;
import '../../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;
import '../../app/gesture_flow_test.dart' show FakeDiscovery;

class _Recognizer extends HandRecognition {
  HandObservation observation = poseFixture(HandPose.fist);
  Completer<HandObservation>? gate;
  int calls = 0, closes = 0;
  bool fail = false;
  @override
  Future<HandObservation> recognize(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) async {
    calls++;
    if (fail) throw StateError('Synthetic failure');
    return gate == null ? observation : await gate!.future;
  }

  @override
  Future<void> close() async {
    closes++;
  }
}

void main() {
  testWidgets(
    'slow native results survive watchdog ticks and show the selected hand',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final original = platform.CameraPlatform.instance;
      platform.CameraPlatform.instance = FakeCameraPlatform();
      addTearDown(() => platform.CameraPlatform.instance = original);
      final recognizer = _Recognizer();
      var ms = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HandGestureOverlay(
            enabled: true,
            selectedHand: 'Right',
            landscape: false,
            recognition: recognizer,
            timeSource: () => Duration(milliseconds: ms),
          ),
        ),
      );
      await tester.pump();
      final preview = tester.widget<SetupCameraPreview>(
        find.byType(SetupCameraPreview),
      );
      expect(preview.resolutionPreset, ResolutionPreset.medium);
      Future<void> resultAt(int at) async {
        recognizer.gate = Completer<HandObservation>();
        preview.onFrame!(
          syntheticCameraImage(),
          const CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 90,
          ),
          DeviceOrientation.portraitUp,
        );
        ms = at;
        await tester.pump(const Duration(milliseconds: 500));
        recognizer.gate!.complete(poseFixture(HandPose.fist));
        await tester.pump();
        await tester.pump();
      }

      await resultAt(500);
      expect(find.byKey(const ValueKey('home-detected-gesture')), findsNothing);
      await resultAt(1000);
      expect(find.byKey(const ValueKey('detected-fist-Right')), findsOneWidget);
      ms = 1400;
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('home-detected-gesture')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'Hand debug uses the same camera, reports actual failed hand gate and clears stale readings',
    (tester) async {
      final original = platform.CameraPlatform.instance;
      platform.CameraPlatform.instance = FakeCameraPlatform();
      addTearDown(() => platform.CameraPlatform.instance = original);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(402, 874);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final recognizer = _Recognizer()
        ..observation = poseFixture(HandPose.fist, hand: 'Left');
      var ms = 0;
      Future<void> mount(bool debug) async {
        await tester.pumpWidget(
          MaterialApp(
            home: HandGestureOverlay(
              enabled: true,
              selectedHand: 'Right',
              landscape: false,
              debugEnabled: debug,
              recognition: recognizer,
              timeSource: () => Duration(milliseconds: ms),
            ),
          ),
        );
        await tester.pump();
      }

      await mount(true);
      await tester.pumpAndSettle();
      final camera = tester.state(find.byType(SetupCameraPreview));
      expect(
        tester
            .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
            .showPreview,
        isTrue,
      );
      expect(find.text('No camera frames yet'), findsOneWidget);
      tester
          .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
          .onFrame!(
        syntheticCameraImage(),
        const CameraDescription(
          name: 'front',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 90,
        ),
        DeviceOrientation.portraitUp,
      );
      await tester.pump();
      await tester.pump();
      final panel = tester.widget<HandDebugPanel>(find.byType(HandDebugPanel));
      expect(
        panel.status,
        contains('Wrong hand: detected Left, selected Right'),
      );
      expect(panel.frames, 1);
      expect(panel.submitted, 1);
      expect(panel.results, 1);
      expect(panel.observation?.physicalHand, 'Left');
      expect(find.byKey(const ValueKey('home-detected-gesture')), findsNothing);
      ms = 500;
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.widget<HandDebugPanel>(find.byType(HandDebugPanel)).observation,
        isNull,
      );
      await mount(false);
      expect(find.byType(HandDebugPanel), findsNothing);
      expect(tester.state(find.byType(SetupCameraPreview)), same(camera));
      expect(
        tester
            .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
            .showPreview,
        isFalse,
      );
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home Face/Hand switching serializes camera shutdown before reacquisition and releases on exit',
    (tester) async {
      final original = platform.CameraPlatform.instance;
      final camera = FakeCameraPlatform();
      platform.CameraPlatform.instance = camera;
      addTearDown(() => platform.CameraPlatform.instance = original);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        HandRecognition.channel,
        (call) async =>
            call.method == 'recognize' ? {'width': 320, 'height': 240} : null,
      );
      messenger.setMockMethodCallHandler(
        FaceTracking.channel,
        (call) async => call.method == 'recognize' ? {'detected': false} : null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(HandRecognition.channel, null);
        messenger.setMockMethodCallHandler(FaceTracking.channel, null);
      });
      SharedPreferences.setMockInitialValues({});
      final c = GestureController(
        await SharedPreferences.getInstance(),
        discovery: FakeDiscovery(),
      );
      c.mode = GestureMode.face;
      c.open(FlowPage.control);
      await tester.pumpWidget(GestureApp(controller: c));
      await tester.pumpAndSettle();
      expect(camera.frames[1]!.hasListener, isTrue);
      for (final mode in [
        GestureMode.hand,
        GestureMode.face,
        GestureMode.hand,
        GestureMode.face,
      ]) {
        final old = camera.nextId;
        await c.setMode(mode);
        await tester.pumpAndSettle();
        final next = camera.nextId;
        expect(next, old + 1);
        expect(
          camera.events.indexOf('stop:$old'),
          lessThan(camera.events.indexOf('create:$next')),
        );
        expect(
          camera.events.indexOf('dispose:$old'),
          lessThan(camera.events.indexOf('create:$next')),
        );
        expect(camera.frames[old]!.hasListener, isFalse);
        expect(camera.frames[next]!.hasListener, isTrue);
        expect(
          find.byType(SetupCameraPreview, skipOffstage: false),
          findsOneWidget,
        );
      }
      await c.setMode(GestureMode.hand);
      await tester.pumpAndSettle();
      final last = camera.nextId;
      c.openSettings();
      await tester.pumpAndSettle();
      expect(camera.frames[last]!.hasListener, isFalse);
      c.back();
      await tester.pumpAndSettle();
      expect(camera.frames[camera.nextId]!.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(camera.frames[camera.nextId]!.hasListener, isFalse);
      c.dispose();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );

  testWidgets(
    'Bottom-center icon tracks selected hand and clears on pause, stale frames, hand/mode changes and errors',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final recognizer = _Recognizer();
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      var ms = 0;
      Future<void> mount({
        bool enabled = true,
        String hand = 'Right',
        bool landscape = false,
      }) async {
        tester.view.physicalSize = landscape
            ? const Size(874, 402)
            : const Size(402, 874);
        await tester.pumpWidget(
          MaterialApp(
            home: SizedBox(
              width: landscape ? 874 : 402,
              height: landscape ? 402 : 874,
              child: HandGestureOverlay(
                enabled: enabled,
                selectedHand: hand,
                landscape: landscape,
                recognition: recognizer,
                timeSource: () => Duration(milliseconds: ms),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      Future<void> frame(
        int at, {
        DeviceOrientation orientation = DeviceOrientation.portraitUp,
      }) async {
        ms = at;
        tester
            .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
            .onFrame!(
          syntheticCameraImage(),
          const CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 90,
          ),
          orientation,
        );
        await tester.pump();
        await tester.pump();
      }

      final icon = find.byKey(const ValueKey('home-detected-gesture'));
      await mount();
      expect(
        tester
            .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
            .showPreview,
        isFalse,
      );
      await frame(0);
      await frame(200);
      expect(find.byKey(const ValueKey('detected-fist-Right')), findsOneWidget);
      final rightIcon = tester.widget<Image>(
        find.byKey(const ValueKey('detected-fist-Right')),
      );
      expect(
        (rightIcon.image as AssetImage).assetName,
        'assets/gestures/fist-right-filled.png',
      );
      expect(
        rightIcon.color,
        isNull,
        reason: 'Skin artwork must not receive the old lime tint',
      );

      expect(
        tester.getCenter(icon).dx,
        closeTo(tester.view.physicalSize.width / 2, .1),
      );
      expect(
        tester.getBottomRight(icon).dy,
        closeTo(tester.view.physicalSize.height - 44, .1),
      );
      ms = 600;
      await tester.pump(const Duration(milliseconds: 400));
      expect(icon, findsNothing);
      await frame(700);
      await frame(900);
      expect(icon, findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(icon, findsNothing);
      final pausedCalls = recognizer.calls;
      await frame(1000);
      expect(recognizer.calls, pausedCalls);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await frame(1100);
      await frame(1300);
      expect(icon, findsOneWidget);
      await mount(hand: 'Left');
      expect(icon, findsNothing);
      await frame(1400);
      await frame(1600);
      expect(icon, findsNothing);
      recognizer.observation = poseFixture(HandPose.thumbUp, hand: 'Left');
      await frame(1700);
      await frame(1900);
      expect(
        find.byKey(const ValueKey('detected-thumbUp-Left')),
        findsOneWidget,
      );
      final leftIcon = tester.widget<Image>(
        find.byKey(const ValueKey('detected-thumbUp-Left')),
      );
      expect(
        (leftIcon.image as AssetImage).assetName,
        'assets/gestures/thumb-up-left-filled.png',
      );
      expect(leftIcon.color, isNull);
      recognizer.gate = Completer<HandObservation>();
      ms = 2000;
      final callback = tester
          .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
          .onFrame!;
      callback(
        syntheticCameraImage(),
        const CameraDescription(
          name: 'front',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 0,
        ),
        DeviceOrientation.portraitUp,
      );
      await mount(enabled: false);
      expect(find.byType(SetupCameraPreview), findsNothing);
      recognizer.gate!.complete(poseFixture(HandPose.fist, hand: 'Left'));
      await tester.pump();
      expect(icon, findsNothing);
      recognizer.gate = null;
      await mount(hand: 'Left', landscape: true);
      await frame(2100);
      await frame(2300);
      expect(icon, findsOneWidget);
      expect(
        tester.getBottomRight(icon).dy,
        closeTo(tester.view.physicalSize.height - 16, .1),
      );
      await frame(2400, orientation: DeviceOrientation.landscapeLeft);
      expect(icon, findsNothing);
      recognizer.fail = true;
      await frame(2500, orientation: DeviceOrientation.landscapeLeft);
      expect(find.text('Retry'), findsOneWidget);
      expect(icon, findsNothing);
      recognizer.fail = false;
      await tester.tap(find.text('Retry'));
      await tester.pump();
      await frame(2600);
      await frame(2800);
      expect(icon, findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(recognizer.closes, greaterThan(0));
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
