import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_camera_overlay.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_mouth.dart';
import 'package:hand_gesture/features/face_tracking/mouth_capture_store.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import '../../helpers/camera_image.dart';
import '../../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;
import 'mouth_motion_test.dart' show mouthFrame;

class _NoCalibration extends MouthCaptureStore {
  @override
  Future<Map<String, dynamic>?> load() async => null;
}

void main() {
  for (final happy in [false, true]) {
    for (final portrait in [const Size(402, 874), const Size(800, 1333)]) {
      testWidgets(
        'Saved point is the rest pose; live position stays absolute through rotation, loss and restart (happy=$happy, $portrait)',
        (tester) async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetPhysicalSize);
          final oldCamera = CameraPlatform.instance;
          CameraPlatform.instance = FakeCameraPlatform();
          final messenger = tester.binding.defaultBinaryMessenger;
          Map<Object?, Object?> data = mouthFrame(gap: .14);
          var ms = 0;
          var orientation = DeviceOrientation.portraitUp;
          messenger.setMockMethodCallHandler(
            FaceTracking.channel,
            (call) async => call.method == 'recognize' ? data : null,
          );
          addTearDown(() {
            messenger.setMockMethodCallHandler(FaceTracking.channel, null);
            CameraPlatform.instance = oldCamera;
          });
          var viewport = portrait;
          var saved = const Offset(.4, .6);
          Future<void> mount({bool settle = true}) async {
            tester.view.physicalSize = viewport;
            final width = homeFaceSize(
              viewport,
              happy: happy,
              following: true,
            ).width;
            final scale = width / 312;
            final rect = Rect.fromCenter(
              center: Offset(viewport.width / 2, viewport.height / 2),
              width: width,
              height: 200 * scale,
            );
            final mapping = FaceScreenMapping(viewport: viewport, avatar: rect);
            final limits = Rect.fromLTRB(
              (18 - rect.left) / scale,
              (18 - rect.top) / scale,
              (viewport.width - 18 - rect.right) / scale,
              (viewport.height - 18 - rect.bottom) / scale,
            );
            await tester.pumpWidget(
              MaterialApp(
                home: SizedBox.expand(
                  child: FaceTrackingEyes(
                    enabled: true,
                    happy: happy,
                    color: Colors.lime,
                    faceDebugEnabled: true,
                    screenMapping: mapping,
                    savedStartPosition: saved,
                    movementBounds: limits,
                    captureStore: _NoCalibration(),
                    timeSource: () => Duration(milliseconds: ms),
                    layoutBuilder: (context, face, diagnostics) => Stack(
                      children: [
                        Positioned.fromRect(
                          rect: rect,
                          child: FittedBox(
                            child: SizedBox(
                              width: 312,
                              height: 200,
                              child: face,
                            ),
                          ),
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          width: 362,
                          height: 168,
                          child: diagnostics,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
            if (settle) await tester.pumpAndSettle();
          }

          void expectRatio(Offset ratio) {
            final mouth = tester.renderObject<RenderBox>(
              find.byType(TrackedMouth),
            );
            final center = mouth.localToGlobal(const Offset(156, 100));
            expect(center.dx / viewport.width, closeTo(ratio.dx, .001));
            expect(center.dy / viewport.height, closeTo(ratio.dy, .001));
          }

          void expectCameraRatio(Offset ratio) {
            final tracker = tester.widget<FaceTrackingEyes>(
              find.byType(FaceTrackingEyes),
            );
            final mapping = tracker.screenMapping!;
            expectRatio(
              mapping.ratioForShift(
                mapping.shiftForRatio(ratio, tracker.movementBounds),
              ),
            );
          }

          Future<void> frames({int count = 1}) async {
            for (var i = 0; i < count; i++) {
              ms += 33;
              tester
                  .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
                  .onFrame!(
                syntheticCameraImage(
                  ios: defaultTargetPlatform == TargetPlatform.iOS,
                ),
                const CameraDescription(
                  name: 'front',
                  lensDirection: CameraLensDirection.front,
                  sensorOrientation: 0,
                ),
                orientation,
              );
              await tester.pump();
              await tester.pump(const Duration(milliseconds: 33));
            }
            await tester.pump(FaceFollowMotion.animationDuration);
          }

          await mount(settle: false);
          expectRatio(
            saved,
          ); // Initial rendered frame, before any camera observation.
          await tester.pumpAndSettle();
          final owner = tester.state(find.byType(SetupCameraPreview));
          // Reproduce the tablet bug: the first face was at x=27%, then the user
          // moved to center. This must not retain a +23% horizontal offset.
          data = {...mouthFrame(gap: .14), 'x': .27, 'y': .46};
          await frames();
          expectCameraRatio(const Offset(.27, .46));
          data = {...data, 'x': .5, 'y': .5};
          await frames(count: 40);
          expectRatio(const Offset(.5, .5));

          for (final point in [
            const Offset(.4, .5),
            const Offset(.6, .5),
            const Offset(.5, .4),
            const Offset(.5, .6),
          ]) {
            data = {...data, 'x': point.dx, 'y': point.dy};
            await frames(count: 40);
            expectRatio(point);
          }

          viewport = Size(portrait.height, portrait.width);
          orientation = DeviceOrientation.landscapeLeft;
          await mount();
          expectRatio(const Offset(.5, .6));
          data = {...data, 'x': .6, 'y': .4};
          await frames();
          expectRatio(const Offset(.6, .4));
          data = {...data, 'x': .5, 'y': .5};
          await frames(count: 40);
          expectRatio(const Offset(.5, .5));

          viewport = portrait;
          orientation = DeviceOrientation.portraitUp;
          await mount();
          expectRatio(const Offset(.5, .5));
          data = {...data, 'x': .4, 'y': .6};
          await frames();
          expectRatio(const Offset(.4, .6));

          saved = const Offset(.45, .55);
          await mount();
          expectRatio(saved);
          data = {...data, 'x': .5, 'y': .5};
          await frames(count: 40);
          expectRatio(const Offset(.5, .5));
          expect(
            tester.widget<TrackedMouth>(find.byType(TrackedMouth)).openness,
            greaterThan(.5),
          );
          expect(tester.state(find.byType(SetupCameraPreview)), same(owner));

          data = {'detected': false};
          await frames();
          ms += 1000;
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pump(FaceFollowMotion.animationDuration);
          expectRatio(saved);
          data = {...mouthFrame(gap: .14), 'x': .6, 'y': .4};
          await frames();
          expectRatio(const Offset(.6, .4));
          data = {...data, 'x': .5, 'y': .5};
          await frames(count: 40);
          expectRatio(const Offset(.5, .5));
          // A fresh Home state uses the setting only until its first live frame.
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpAndSettle();
          await mount();
          expectRatio(saved);
          await frames();
          expectRatio(const Offset(.5, .5));
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
  }
}
