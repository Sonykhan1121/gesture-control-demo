import 'package:flutter_svg/flutter_svg.dart';
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
import 'mouth_motion_test.dart' show mouthFrame;
import 'eye_diagnostics_test.dart' show eyeFrame;

class _NoCalibration extends MouthCaptureStore {
  @override
  Future<Map<String, dynamic>?> load() async => null;
}

void main() {
  for (final happy in [false, true]) {
    testWidgets(
      'Eyes and mouth keep their spacing through motion, blinking and reset (happy=$happy)',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final oldCamera = CameraPlatform.instance;
        CameraPlatform.instance = FakeCameraPlatform();
        var ms = 0;
        Map<Object?, Object?> data = mouthFrame();
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          FaceTracking.channel,
          (call) async => call.method == 'recognize' ? data : null,
        );
        addTearDown(() {
          CameraPlatform.instance = oldCamera;
          messenger.setMockMethodCallHandler(FaceTracking.channel, null);
        });

        Future<void> mount({bool enabled = true}) async {
          await tester.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 312,
                  height: 200,
                  child: FaceTrackingEyes(
                    enabled: enabled,
                    happy: happy,
                    color: Colors.lime,
                    captureStore: _NoCalibration(),
                    timeSource: () => Duration(milliseconds: ms),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        Future<void> frame(Map<Object?, Object?> next) async {
          data = next;
          ms += 100;
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
            DeviceOrientation.portraitUp,
          );
          await tester.pump();
          await tester.pump();
        }

        Offset mouthAnchor() => tester
            .renderObject<RenderBox>(
              find.descendant(
                of: find.byType(TrackedMouth),
                matching: find.byType(CustomPaint),
              ),
            )
            .localToGlobal(Offset(156, happy ? 145 : 192));

        Offset eyeAnchor(bool left) => tester
            .renderObject<RenderBox>(
              find.descendant(
                of: find.byKey(
                  ValueKey(left ? 'blink-screen-left' : 'blink-screen-right'),
                ),
                matching: find.byWidgetPredicate(
                  (widget) => widget is Image || widget is SvgPicture,
                ),
              ),
            )
            .localToGlobal(Offset(left ? 78 : 234, 200 * (happy ? .279 : .31)));

        TrackedMouth mouth() => tester.widget(find.byType(TrackedMouth));
        await mount(enabled: false);
        final idlePainter = tester
            .widget<CustomPaint>(
              find.descendant(
                of: find.byType(TrackedMouth),
                matching: find.byType(CustomPaint),
              ),
            )
            .painter;
        expect(
          idlePainter,
          isNotNull,
          reason: 'Inactive modes also draw the resting smile',
        );
        await mount();
        await frame({
          ...mouthFrame(),
          ...eyeFrame(),
          'blinkScreenLeft': .1,
          'blinkScreenRight': .1,
        });
        await tester.pump(const Duration(milliseconds: 150));
        final origin = mouthAnchor();
        final leftGap = origin - eyeAnchor(true);
        final rightGap = origin - eyeAnchor(false);
        void expectSpacing() {
          expect(
            (mouthAnchor() - eyeAnchor(true) - leftGap).distance,
            lessThan(.001),
          );
          expect(
            (mouthAnchor() - eyeAnchor(false) - rightGap).distance,
            lessThan(.001),
          );
        }

        for (final y in [.64, .36]) {
          for (var sample = 0; sample < 3; sample++) {
            await frame({
              ...mouthFrame(gap: .14, smile: .8),
              ...eyeFrame(leftClosed: true),
              'x': y,
              'y': y,
              'blinkScreenLeft': .95,
              'blinkScreenRight': .1,
            });
          }
          // Check mid-animation as well as the final position; separate easing
          // on mouth/eyes must not change their spacing.
          for (final delay in [20, 50, 80]) {
            await tester.pump(Duration(milliseconds: delay));
            expectSpacing();
          }
          expect(mouth().openness, greaterThan(.5));
          expect(mouth().smile, 1);
          expect(
            mouthAnchor().dy - origin.dy,
            y > .5 ? greaterThan(0) : lessThan(0),
          );
          expect(
            mouthAnchor().dx - origin.dx,
            y > .5 ? greaterThan(0) : lessThan(0),
          );
          expect(
            tester
                .widget<TweenAnimationBuilder<double>>(
                  find.byKey(const ValueKey('blink-screen-left')),
                )
                .tween
                .end,
            1, // A real wink must not override the automatic blink timer.
          );
          expect(
            tester
                .widget<TweenAnimationBuilder<double>>(
                  find.byKey(const ValueKey('blink-screen-right')),
                )
                .tween
                .end,
            1,
          );
        }

        ms += 1000;
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 70));
        expectSpacing();
        await tester.pump(const Duration(milliseconds: 100));
        expect((mouthAnchor() - origin).distance, lessThan(.001));
        expect(mouth().openness, 0);
        expect(mouth().smile, 0);

        await frame({...mouthFrame(gap: .14), 'y': .5});
        await frame({...mouthFrame(gap: .14), 'y': .65});
        await tester.pump(const Duration(milliseconds: 150));
        await mount(enabled: false);
        expectSpacing();
        expect((mouthAnchor() - origin).distance, lessThan(.001));
        expect(mouth().followExpression, isFalse);
        expect(find.byType(SetupCameraPreview), findsNothing);
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
