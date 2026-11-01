import '../../helpers/camera_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_mouth.dart';
import 'package:hand_gesture/features/face_tracking/mouth_capture_store.dart';
import 'package:hand_gesture/features/face_tracking/eye_capture_store.dart';
import 'package:hand_gesture/features/face_tracking/eye_debug_panel.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import 'eye_diagnostics_test.dart' show eyeFrame;
import 'mouth_motion_test.dart' show mouthFrame;

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

class _MouthStore extends MouthCaptureStore {
  @override
  Future<Map<String, dynamic>?> load() async => null;
}

class _EyeStore extends EyeCaptureStore {
  final List<Map<String, Object?>> saved = [];
  @override
  Future<void> save(Map<String, Object?> snapshot) async {
    saved.add(snapshot);
  }
}

void main() {
  testWidgets(
    'One eye check captures actual outputs, retains the camera on hide and clears stale eye data',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      var ms = 0;
      var data = eyeFrame();
      final eyeStore = _EyeStore(), mouthStore = _MouthStore();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        FaceTracking.channel,
        (call) async => call.method == 'recognize'
            ? {...mouthFrame(gap: .10), ...data}
            : null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(FaceTracking.channel, null),
      );
      Future<void> mount({bool debug = true}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 362,
                height: 580,
                child: FaceTrackingEyes(
                  enabled: true,
                  happy: false,
                  color: Colors.lime,
                  eyeDebugEnabled: debug,
                  timeSource: () => Duration(milliseconds: ms),
                  captureStore: mouthStore,
                  eyeCaptureStore: eyeStore,
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

      Future<void> frame(int at) async {
        ms = at;
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

      await mount();
      await frame(0);
      expect(find.text('Camera left: OPEN'), findsOneWidget);
      expect(find.text('Camera right: OPEN'), findsOneWidget);
      expect(find.byType(SetupCameraPreview), findsOneWidget);
      final mouthOpen = tester
          .widget<TrackedMouth>(find.byType(TrackedMouth))
          .openness;
      await tester.tap(find.byKey(const ValueKey('eye-check-start')));
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        final start = 2000 + i * 5000;
        ms = start;
        await tester.pump(const Duration(seconds: 2));
        data = eyeFrame(
          leftClosed: i == 1 || i == 3,
          rightClosed: i == 2 || i == 3,
        );
        await frame(start + 50);
        await frame(start + 100);
        await frame(start + 150);
        final eye = tester
            .widget<EyeDebugPanel>(find.byType(EyeDebugPanel))
            .sample!;
        expect(eye.leftClosed, i == 1 || i == 3);
        expect(eye.rightClosed, i == 2 || i == 3);
        expect(
          tester.widget<TrackedMouth>(find.byType(TrackedMouth)).openness,
          mouthOpen,
        );
        ms = start + 3000;
        await tester.pump(const Duration(seconds: 3));
        await tester.pump();
      }
      expect(find.text('Done — eye check saved'), findsOneWidget);
      final captures = eyeStore.saved.last['captures'] as Map;
      expect(
        captures.keys,
        containsAll(['normal', 'leftClosed', 'rightClosed', 'bothClosed']),
      );
      expect(captures['leftClosed']['leftClosedFraction'], 1);
      expect(captures['leftClosed']['rightClosedFraction'], 0);
      expect(eyeStore.saved.length, 4);
      expect(
        tester.widget<EyeDebugPanel>(find.byType(EyeDebugPanel)).sample,
        isNull,
        reason: 'Stale inputs cannot remain displayed as current eye readings',
      );
      final camera = tester.state(find.byType(SetupCameraPreview));
      await mount(debug: false);
      expect(find.byType(EyeDebugPanel), findsNothing);
      expect(
        tester.state(find.byType(SetupCameraPreview, skipOffstage: false)),
        same(camera),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
