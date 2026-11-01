import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_mouth.dart';
import 'package:hand_gesture/features/face_tracking/mouth_capture_store.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import '../../helpers/camera_image.dart';
import '../../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;
import 'eye_diagnostics_test.dart' show eyeFrame;
import 'mouth_motion_test.dart' show mouthFrame;

class _NoMouthCapture extends MouthCaptureStore {
  @override
  Future<Map<String, dynamic>?> load() async => null;
}

void main() {
  testWidgets(
    'Optional camera eye labels never drive timer blinking; missing data clears them',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final oldCamera = CameraPlatform.instance;
      CameraPlatform.instance = FakeCameraPlatform();
      final messenger = tester.binding.defaultBinaryMessenger;
      Map<Object?, Object?> data = {};
      var ms = 0;
      messenger.setMockMethodCallHandler(
        FaceTracking.channel,
        (call) async => call.method == 'recognize' ? data : null,
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(FaceTracking.channel, null);
        CameraPlatform.instance = oldCamera;
      });
      Future<void> mount({bool enabled = true, bool status = true}) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 312,
                height: 280,
                child: FaceTrackingEyes(
                  enabled: enabled,
                  happy: false,
                  color: Colors.lime,
                  showEyeStatus: status,
                  captureStore: _NoMouthCapture(),
                  timeSource: () => Duration(milliseconds: ms),
                  layoutBuilder: (context, face, diagnostics) => Column(
                    children: [
                      SizedBox(width: 312, height: 200, child: face),
                      SizedBox(width: 312, height: 54, child: diagnostics),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> frame({
        double left = .035,
        double right = .035,
        bool missing = false,
      }) async {
        ms += 100;
        data = missing
            ? {'detected': false}
            : {
                ...mouthFrame(gap: .14),
                ...eyeFrame(leftAperture: left, rightAperture: right),
                'blinkScreenLeft': .99,
                'blinkScreenRight': .99,
              };
        tester
            .widget<SetupCameraPreview>(
              find.byType(SetupCameraPreview, skipOffstage: false),
            )
            .onFrame!(
          syntheticCameraImage(
            ios: defaultTargetPlatform == TargetPlatform.iOS,
          ),
          const CameraDescription(
            name: 'front',
            lensDirection: CameraLensDirection.front,
            sensorOrientation: 0,
          ),
          DeviceOrientation.portraitUp,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
      }

      void expectEye(bool left, String status) {
        expect(
          find.text('Your ${left ? "left" : "right"} eye\n$status'),
          findsOneWidget,
        );
        final animation = tester.widget<TweenAnimationBuilder<double>>(
          find.byKey(
            ValueKey(left ? 'blink-screen-left' : 'blink-screen-right'),
          ),
        );
        // Camera closure is diagnostic only. All these frames precede the
        // first timed blink, so neither eye should close with a real wink.
        expect(animation.tween.end, 1);
      }

      await mount();
      expect(find.text('Start eye check'), findsNothing);
      expectEye(true, 'NO READING');
      await frame();
      expectEye(true, 'OPEN');
      expectEye(false, 'OPEN');
      expect(
        tester.widget<TrackedMouth>(find.byType(TrackedMouth)).openness,
        greaterThan(.5),
      );
      await frame(left: .005);
      expectEye(true, 'CLOSED');
      expectEye(false, 'OPEN');
      await frame(right: .005);
      expectEye(true, 'OPEN');
      expectEye(false, 'CLOSED');
      await frame(left: .005, right: .005);
      expectEye(true, 'CLOSED');
      expectEye(false, 'CLOSED');
      ms += 400;
      await tester.pump(const Duration(milliseconds: 400));
      expectEye(true, 'NO READING');
      expectEye(false, 'NO READING');
      await frame();
      final camera = tester.state(find.byType(SetupCameraPreview));
      await mount(status: false);
      expect(
        tester.state(find.byType(SetupCameraPreview, skipOffstage: false)),
        same(camera),
      );
      await mount();
      await frame(missing: true);
      expectEye(true, 'NO READING');
      await mount(enabled: false);
      expect(find.byKey(const ValueKey('live-eye-left')), findsNothing);
      await mount();
      await frame();
      expectEye(true, 'OPEN');
      expectEye(false, 'OPEN');
      expect(find.text('Start eye check'), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
