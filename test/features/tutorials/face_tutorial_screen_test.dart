import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart'
    show CameraPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/tutorials/face_tutorial_screen.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/features/face_tracking/mouth_tracking.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import '../../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;
import '../../helpers/camera_image.dart';
import 'face_tutorial_progress_test.dart' show observation;

void main() {
  late FakeCameraPlatform camera;
  late CameraPlatform oldCamera;
  late GestureController c;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    c = GestureController(await SharedPreferences.getInstance());
    oldCamera = CameraPlatform.instance;
    camera = FakeCameraPlatform();
    CameraPlatform.instance = camera;
  });
  tearDown(() {
    c.dispose();
    CameraPlatform.instance = oldCamera;
  });
  Future<void> settle(WidgetTester t) async {
    for (var i = 0; i < 5; i++) {
      await t.pump(const Duration(milliseconds: 50));
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
    }
  }

  testWidgets(
    'all detected steps save completion and keep short-screen actions visible',
    (t) async {
      t.view.physicalSize = const Size(320, 568);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var ms = 0;
      c.open(FlowPage.faceTutorial);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: c,
          child: MaterialApp(
            home: FaceTutorialScreen(
              timeSource: () => Duration(milliseconds: ms),
            ),
          ),
        ),
      );
      await settle(t);
      void sample({
        double x = .5,
        double y = .5,
        double smile = 0,
        double open = 0,
      }) {
        t
            .widget<FaceTrackingEyes>(find.byType(FaceTrackingEyes))
            .onObservation!(
          observation(x: x, y: y),
          MouthMotion(smile: smile, openness: open),
          DeviceOrientation.portraitUp,
        );
        ms += 200;
      }

      for (var step = 0; step < 5; step++) {
        for (var frame = 0; frame < 12; frame++) {
          sample(
            x: step == 1
                ? (frame < 2
                      ? .5
                      : frame < 6
                      ? .4
                      : .6)
                : .5,
            y: step == 2
                ? (frame < 2
                      ? .5
                      : frame < 6
                      ? .4
                      : .6)
                : .5,
            smile: step == 3 ? .5 : 0,
            open: step == 4 ? (frame.isEven ? .4 : 0) : 0,
          );
        }
        await t.pump();
        final next = find.widgetWithText(FilledButton, 'Next');
        expect(t.getBottomRight(next).dy, lessThanOrEqualTo(568));
        expect(t.widget<FilledButton>(next).onPressed, isNotNull);
        await t.pump(const Duration(milliseconds: 500));
        await settle(t);
      }
      expect(find.text('Tutorial completed'), findsOneWidget);
      await t.tap(find.text('Go to Home'));
      await settle(t);
      expect(c.preferences.getBool('gesture.faceTutorialCompleted'), true);
      expect(c.page, FlowPage.control);
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('menu opens live camera, releases on exit and reopens fresh', (
    t,
  ) async {
    t.view.physicalSize = const Size(402, 874);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    c.open(FlowPage.tutorialMenu);
    await t.pumpWidget(GestureApp(controller: c));
    await settle(t);
    await t.tap(find.text('Face Gesture Tutorial'));
    await settle(t);
    expect(c.page, FlowPage.faceTutorial);
    expect(
      t.widget<SetupCameraPreview>(find.byType(SetupCameraPreview)).showPreview,
      true,
    );
    expect(
      t.widget<FaceTrackingEyes>(find.byType(FaceTrackingEyes)).overlayOnCamera,
      true,
    );
    expect(find.text('Your animated face'), findsNothing);
    final firstId = camera.nextId;
    c.back();
    await settle(t);
    expect(camera.events, contains('stopped:$firstId'));
    expect(camera.events, contains('dispose:$firstId'));
    await t.tap(find.text('Face Gesture Tutorial'));
    await settle(t);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(camera.nextId, greaterThan(firstId));
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNull,
    );
    await t.pumpWidget(const SizedBox());
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('backgrounding cancels an accepted step waiting to advance', (
    t,
  ) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    var ms = 0;
    c.open(FlowPage.faceTutorial);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
          home: FaceTutorialScreen(
            timeSource: () => Duration(milliseconds: ms),
          ),
        ),
      ),
    );
    await settle(t);
    for (ms = 0; ms <= 1600; ms += 200) {
      t.widget<FaceTrackingEyes>(find.byType(FaceTrackingEyes)).onObservation!(
        observation(),
        const MouthMotion(),
        DeviceOrientation.portraitUp,
      );
    }
    await t.pump();
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNotNull,
    );
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await t.pump(const Duration(seconds: 1));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
    expect(find.text('Step 1 of 5'), findsOneWidget);
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNull,
    );
    await t.pumpWidget(const SizedBox());
    await settle(t);
    expect(t.takeException(), isNull);
  });

  testWidgets('same camera drives progress, rotation, skip and completion', (
    t,
  ) async {
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    t.view.physicalSize = const Size(402, 874);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var ms = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      FaceTracking.channel,
      (call) async => call.method == 'recognize'
          ? {
              'detected': true,
              'x': .5,
              'y': .5,
              'confidence': .95,
              'faceHeight': .3,
              'width': 480,
              'height': 640,
            }
          : null,
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(FaceTracking.channel, null),
    );
    c.open(FlowPage.faceTutorial);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: c,
        child: MaterialApp(
          home: FaceTutorialScreen(
            timeSource: () => Duration(milliseconds: ms),
          ),
        ),
      ),
    );
    await settle(t);
    final tracker = t.state(find.byType(FaceTrackingEyes));
    for (ms = 0; ms <= 1600; ms += 200) {
      t.widget<SetupCameraPreview>(find.byType(SetupCameraPreview)).onFrame!(
        syntheticCameraImage(),
        const CameraDescription(
          name: 'front',
          lensDirection: CameraLensDirection.front,
          sensorOrientation: 0,
        ),
        DeviceOrientation.portraitUp,
      );
      await t.pump();
      await t.pump();
    }
    expect(
      t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'Next'))
          .onPressed,
      isNotNull,
    );
    await t.tap(find.text('Next'));
    await t.pump();
    expect(find.text('Move left and right'), findsOneWidget);
    expect(t.state(find.byType(FaceTrackingEyes)), same(tracker));
    void sample(double x, DeviceOrientation o) {
      t.widget<FaceTrackingEyes>(find.byType(FaceTrackingEyes)).onObservation!(
        observation(x: x),
        const MouthMotion(),
        o,
      );
    }

    sample(.5, DeviceOrientation.portraitUp);
    ms += 200;
    sample(.4, DeviceOrientation.portraitUp);
    ms += 200;
    sample(.4, DeviceOrientation.portraitUp);
    await t.pump();
    expect(find.text('Now move right'), findsOneWidget);
    t.view.physicalSize = const Size(874, 402);
    await settle(t);
    sample(.6, DeviceOrientation.landscapeLeft);
    await t.pump();
    expect(find.text('Move left first'), findsOneWidget);
    expect(t.state(find.byType(FaceTrackingEyes)), same(tracker));
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(t);
    expect(camera.events.where((s) => s.startsWith('stopped:')), isNotEmpty);
    t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(t);
    for (var i = 0; i < 4; i++) {
      await t.tap(find.text('Skip'));
      await settle(t);
    }
    expect(find.text('Practice finished'), findsOneWidget);
    expect(find.text('1 of 5 exercises practiced'), findsOneWidget);
    expect(find.byType(SetupCameraPreview), findsNothing);
    await t.tap(find.text('Go to Home'));
    await settle(t);
    expect(c.mode, GestureMode.face);
    expect(c.page, FlowPage.control);
    expect(c.preferences.getBool('gesture.faceTutorialCompleted'), isNull);
    await t.pumpWidget(const SizedBox());
    await settle(t);
    expect(t.takeException(), isNull);
  });
}
