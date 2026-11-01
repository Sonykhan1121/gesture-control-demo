import '../../helpers/camera_image.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_mouth.dart';
import 'package:hand_gesture/features/face_tracking/mouth_debug_panel.dart';
import 'package:hand_gesture/features/face_tracking/mouth_capture_store.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import 'mouth_motion_test.dart' show mouthFrame;
import 'mouth_calibration_test.dart' show calibrationFixture;
import 'eye_diagnostics_test.dart' show eyeFrame;

class _Frame implements CameraImage {
  @override
  ImageFormat get format => syntheticCameraImage().format;
  @override
  int get width => 400;
  @override
  int get height => 400;
  @override
  List<Plane> get planes => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CaptureStore extends MouthCaptureStore {
  _CaptureStore({this.initial});
  final Map<String, dynamic>? initial;
  final List<Map<String, Object?>> saved = [];
  @override
  Future<Map<String, dynamic>?> load() async => initial;
  @override
  Future<void> save(Map<String, Object?> snapshot) async {
    saved.add(snapshot);
  }
}

void main() {
  testWidgets(
    'Saved calibration loads at Home and survives mode changes without another check',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final store = _CaptureStore(
        initial: {'version': 1, 'captures': calibrationFixture()},
      );
      var ms = 0;
      var data = mouthFrame(gap: .03, width: .60, smile: .02);
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        FaceTracking.channel,
        (call) async => call.method == 'recognize' ? data : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(FaceTracking.channel, null),
      );
      Future<void> mount(bool enabled) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 312,
                height: 200,
                child: FaceTrackingEyes(
                  enabled: enabled,
                  happy: false,
                  color: Colors.lime,
                  captureStore: store,
                  timeSource: () => Duration(milliseconds: ms),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
      }

      Future<void> frame() async {
        tester
            .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
            .onFrame!(
          _Frame(),
          const CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 0,
          ),
          DeviceOrientation.portraitUp,
        );
        await tester.pump();
        await tester.pump();
      }

      await mount(true);
      await frame();
      var mouth = tester.widget<TrackedMouth>(find.byType(TrackedMouth));
      expect(mouth.openness, 0);
      expect(mouth.widthScale, 1);
      expect((store.saved.first['calibration'] as Map)['neutralWidth'], .60);
      await mount(false);
      await mount(true);
      ms = 100;
      data = mouthFrame(gap: .25, width: .50, smile: .02);
      await frame();
      mouth = tester.widget<TrackedMouth>(find.byType(TrackedMouth));
      expect(mouth.openness, inExclusiveRange(0, 1));
      expect(mouth.widthScale, lessThan(1));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets(
    'Normal, smile and talking share the eye frame; debugging preserves one camera and resets stale samples',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var ms = 0;
      final store = _CaptureStore();
      Map<Object?, Object?> data = mouthFrame();
      Completer<Map<Object?, Object?>>? pending;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        FaceTracking.channel,
        (call) async =>
            call.method == 'recognize' ? pending?.future ?? data : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(FaceTracking.channel, null),
      );
      Future<void> mount({bool debug = true, bool enabled = true}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 362,
                height: 580,
                child: FaceTrackingEyes(
                  enabled: enabled,
                  happy: false,
                  color: Colors.lime,
                  debugEnabled: debug,
                  timeSource: () => Duration(milliseconds: ms),
                  captureStore: store,
                  layoutBuilder: (context, face, diagnostics) => Column(
                    children: [
                      SizedBox(width: 312, height: 200, child: face),
                      SizedBox(width: 362, height: 250, child: diagnostics),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pump();
      }

      Future<void> frame(int time) async {
        ms = time;
        tester
            .widget<SetupCameraPreview>(
              find.byType(SetupCameraPreview, skipOffstage: false),
            )
            .onFrame!(
          _Frame(),
          const CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 0,
          ),
          DeviceOrientation.portraitUp,
        );
        await tester.pump();
        await tester.pump();
      }

      TrackedMouth mouth() => tester.widget(find.byType(TrackedMouth));
      await mount();
      await frame(0);
      expect(mouth().openness, 0);
      expect(mouth().smile, 0);
      expect(find.byType(SetupCameraPreview), findsOneWidget);
      data = {
        ...mouthFrame(smile: .8),
        ...eyeFrame(leftClosed: true, rightClosed: true),
      };
      await frame(60);
      expect(mouth().smile, 1);
      expect(mouth().openness, 0);
      expect(
        tester
            .widget<TweenAnimationBuilder<double>>(
              find.byKey(const ValueKey('blink-screen-left')),
            )
            .tween
            .end,
        1, // Real eyelid measurements no longer drive the avatar.
      );
      data = {
        ...mouthFrame(gap: .14),
        ...eyeFrame(),
        'y': .6,
        'blinkScreenLeft': .1,
        'blinkScreenRight': .1,
      };
      await frame(120);
      expect(mouth().openness, greaterThan(.5));
      expect(mouth().smile, 0);
      expect(
        tester
            .widget<TweenAnimationBuilder<double>>(
              find.byKey(const ValueKey('blink-screen-left')),
            )
            .tween
            .end,
        1,
      );
      await frame(150);
      await frame(180);
      await tester.pump(FaceFollowMotion.animationDuration);
      final movement = tester.widget<Transform>(
        find.byKey(const ValueKey('animated-face-position')),
      );
      expect(movement.transform.getTranslation().y, greaterThan(16));
      ms = 500;
      await tester.pump(const Duration(milliseconds: 500));
      expect(mouth().openness, 0);
      expect(mouth().smile, 0);
      expect(
        tester.widget<MouthDebugPanel>(find.byType(MouthDebugPanel)).measured,
        isNull,
      );
      expect(
        tester.widget<MouthDebugPanel>(find.byType(MouthDebugPanel)).status,
        contains('Stale frame'),
      );
      data = mouthFrame();
      await frame(600);
      await tester.tap(find.byKey(const ValueKey('mouth-check-start')));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        final begin = 2600 + i * 5000;
        ms = begin;
        await tester.pump(const Duration(seconds: 2));
        data = mouthFrame(gap: i == 2 ? .14 : 0, smile: i == 1 ? .8 : .05);
        await frame(begin + 50);
        await frame(begin + 100);
        ms = begin + 3000;
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
      }
      expect(find.text('Done — results saved'), findsOneWidget);
      expect(find.text('Saved on phone (3/3)'), findsOneWidget);
      expect(
        (store.saved.last['captures'] as Map).keys,
        containsAll(['normal', 'smile', 'talk']),
      );
      expect(store.saved.length, 3);
      final cameraState = tester.state(find.byType(SetupCameraPreview));
      await mount(debug: false);
      expect(
        tester.state(find.byType(SetupCameraPreview, skipOffstage: false)),
        same(cameraState),
      );
      expect(find.byType(MouthDebugPanel), findsNothing);
      expect(
        tester
            .widget<SetupCameraPreview>(
              find.byType(SetupCameraPreview, skipOffstage: false),
            )
            .showPreview,
        isFalse,
      );
      pending = Completer<Map<Object?, Object?>>();
      await frame(15700);
      await mount(debug: false, enabled: false);
      await mount(debug: false);
      pending.complete(data);
      await tester.pump();
      await tester.pump();
      expect(
        mouth().openness,
        0,
        reason: 'Old-session lips cannot animate the new session',
      );
      pending = null;
      await frame(15800);
      expect(mouth().openness, greaterThan(.5));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(mouth().openness, 0);
      expect(mouth().smile, 0);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      expect(tester.takeException(), isNull);
    },
  );
}
