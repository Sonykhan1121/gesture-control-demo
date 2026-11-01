import 'package:flutter_svg/flutter_svg.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_debug_panel.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
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
  testWidgets(
    'Location debug follows actual animated face and mouth positions, clears stale input and retains the camera',
    (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      final oldCamera = CameraPlatform.instance;
      CameraPlatform.instance = FakeCameraPlatform();
      var ms = 0, calls = 0;
      final reportedPositions = <Offset>[];
      var orientation = DeviceOrientation.portraitUp;
      var data = mouthFrame(gap: .14, smile: .8);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(FaceTracking.channel, (call) async {
        if (call.method != 'recognize') return null;
        calls++;
        return data;
      });
      addTearDown(() {
        CameraPlatform.instance = oldCamera;
        messenger.setMockMethodCallHandler(FaceTracking.channel, null);
      });
      Future<void> mount({
        bool debug = true,
        bool compact = false,
        bool happy = false,
        FaceScreenMapping? mapping,
        Rect movementBounds = const Rect.fromLTRB(-24, -32, 24, 32),
      }) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: mapping?.viewport.width ?? 362,
                height: mapping?.viewport.height ?? 460,
                child: FaceTrackingEyes(
                  enabled: true,
                  happy: happy,
                  color: Colors.lime,
                  faceDebugEnabled: debug,
                  movementBounds: movementBounds,
                  screenMapping: mapping,
                  onPositionChanged: reportedPositions.add,
                  captureStore: _NoCalibration(),
                  timeSource: () => Duration(milliseconds: ms),
                  layoutBuilder: (context, face, diagnostics) => mapping != null
                      ? Stack(
                          children: [
                            Positioned.fromRect(
                              rect: mapping.avatar,
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
                        )
                      : Column(
                          children: [
                            SizedBox(width: 312, height: 200, child: face),
                            SizedBox(
                              width: compact ? 244 : 362,
                              height: compact ? 203 : 168,
                              child: diagnostics,
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> frame({int delta = 100}) async {
        ms += delta;
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
          orientation,
        );
        await tester.pump();
        await tester.pump();
      }

      await mount();
      final camera = tester.state(find.byType(SetupCameraPreview));
      expect(
        tester
            .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
            .showPreview,
        isTrue,
      );
      expect(find.text('Start eye check'), findsNothing);
      expect(find.textContaining('Your left eye'), findsNothing);
      await frame();
      var panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(panel.face, isNotNull);
      expect(calls, 1);
      expect(panel.currentShift, Offset.zero);
      expect(
        tester.widget<TrackedMouth>(find.byType(TrackedMouth)).openness,
        greaterThan(.5),
      );
      expect(find.textContaining('Mouth gap'), findsNothing);
      expect(find.textContaining('Smile input'), findsNothing);
      expect(find.textContaining('Inference'), findsNothing);
      final origin = tester.getTopLeft(find.byType(TrackedMouth));
      data = {...data, 'x': .65, 'y': .64};
      await frame(delta: 33);
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(
        calls,
        2,
        reason:
            'A 30fps camera frame should not be skipped when inference is ready',
      );
      expect(
        panel.targetShift,
        Offset.zero,
        reason: 'One isolated detector jump must not move the face',
      );
      await frame(delta: 33);
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(panel.targetShift.dx, greaterThan(0));
      expect(panel.targetShift.dy, greaterThan(0));
      await tester.pump(const Duration(milliseconds: 20));
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(panel.currentShift.dx, inExclusiveRange(0, panel.targetShift.dx));
      expect(panel.currentShift.dy, inExclusiveRange(0, panel.targetShift.dy));
      expect(
        (reportedPositions.last - panel.currentShift).distance,
        lessThan(.001),
      );
      void expectRenderedLocations() {
        final current = tester.widget<FaceLocationDebugPanel>(
          find.byType(FaceLocationDebugPanel),
        );
        final actualShift =
            tester.getTopLeft(find.byType(TrackedMouth)) - origin;
        expect((current.currentShift - actualShift).distance, lessThan(.001));
        final mouthBase = AvatarLocationMarkers.mouth(current.happy);
        expect(
          (current.mouthAnchor - actualShift - mouthBase).distance,
          lessThan(.001),
        );
        expect(
          (current.faceCenter - actualShift - const Offset(156, 100)).distance,
          lessThan(.001),
        );
        final image = tester.renderObject<RenderBox>(
          find.descendant(
            of: find.byKey(const ValueKey('blink-screen-left')),
            matching: find.byWidgetPredicate(
              (widget) => widget is Image || widget is SvgPicture,
            ),
          ),
        );
        final eyePosition =
            image.localToGlobal(AvatarLocationMarkers.leftEye(current.happy)) -
            origin;
        expect((current.leftEye - eyePosition).distance, lessThan(.001));
      }

      expectRenderedLocations();
      await tester.pump(const Duration(milliseconds: 60));
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(panel.currentShift, panel.targetShift);
      expectRenderedLocations();
      // Reopening debug while the avatar is stationary must report its current
      // side immediately, so docking cannot stay on the occupied side.
      await mount(debug: false);
      reportedPositions.clear();
      await mount();
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(reportedPositions, isNotEmpty);
      expect(reportedPositions.last, panel.currentShift);
      await frame(delta: 10);
      expect(calls, 3);
      // Recenter only the shared position: expressions/camera stay active.
      await tester.tap(find.byKey(const ValueKey('face-debug-center')));
      await tester.pump();
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(panel.targetShift, Offset.zero);
      expect(
        tester.widget<TrackedMouth>(find.byType(TrackedMouth)).openness,
        greaterThan(.5),
      );
      await tester.pump(const Duration(milliseconds: 80));
      expectRenderedLocations();
      expect(tester.state(find.byType(SetupCameraPreview)), same(camera));
      await mount(compact: true);
      expect(tester.takeException(), isNull);
      ms += 500;
      await tester.pump(const Duration(milliseconds: 400));
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(panel.face, isNull);
      expect(
        tester.widget<TrackedMouth>(find.byType(TrackedMouth)).openness,
        0,
      );
      ms += 1000;
      await tester.pump(const Duration(milliseconds: 400));
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(find.textContaining("No recent face"), findsWidgets);
      expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('face-debug-center')))
            .onPressed,
        isNull,
      );
      await mount(debug: false);
      expect(find.byType(FaceLocationDebugPanel), findsNothing);
      expect(
        tester.state(find.byType(SetupCameraPreview, skipOffstage: false)),
        same(camera),
      );
      expect(
        tester
            .widget<SetupCameraPreview>(
              find.byType(SetupCameraPreview, skipOffstage: false),
            )
            .showPreview,
        isFalse,
      );
      await mount(happy: true);
      await frame();
      expectRenderedLocations();
      expect(
        tester
            .widget<FaceLocationDebugPanel>(find.byType(FaceLocationDebugPanel))
            .face,
        isNotNull,
      );
      await mount(
        happy: true,
        movementBounds: const Rect.fromLTRB(-24, -111, 24, 137),
      );
      await tester.tap(find.byKey(const ValueKey('face-debug-center')));
      await tester.pumpAndSettle();
      data = {...data, 'y': .95};
      for (var i = 0; i < 12; i++) {
        await frame(delta: 33);
      }
      await tester.pump(FaceFollowMotion.animationDuration);
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(panel.currentShift.dy, 137);
      expectRenderedLocations();
      data = {...data, 'y': .1};
      for (var i = 0; i < 12; i++) {
        await frame(delta: 33);
      }
      await tester.pump(FaceFollowMotion.animationDuration);
      panel = tester.widget<FaceLocationDebugPanel>(
        find.byType(FaceLocationDebugPanel),
      );
      expect(panel.currentShift.dy, -111);
      expectRenderedLocations();
      // Repeated live rotation must establish neutral in the new camera axes
      // and continue following in both vertical directions without reopening.
      for (final nextOrientation in [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
        DeviceOrientation.portraitUp,
      ]) {
        orientation = nextOrientation;
        await mount(
          happy: true,
          compact: true,
          movementBounds: nextOrientation == DeviceOrientation.portraitUp
              ? const Rect.fromLTRB(-24, -120, 24, 120)
              : const Rect.fromLTRB(-360, -120, 360, 120),
        );
        data = mouthFrame(gap: .14, size: const Size(640, 480));
        await frame();
        await tester.pump(FaceFollowMotion.animationDuration);
        panel = tester.widget<FaceLocationDebugPanel>(
          find.byType(FaceLocationDebugPanel),
        );
        expect(panel.currentShift, Offset.zero);
        for (final y in [.8, .2]) {
          data = {...data, 'y': y};
          for (var i = 0; i < 12; i++) {
            await frame(delta: 33);
          }
          await tester.pump(FaceFollowMotion.animationDuration);
          panel = tester.widget<FaceLocationDebugPanel>(
            find.byType(FaceLocationDebugPanel),
          );
          expect(panel.currentShift.dy, y > .5 ? 120 : -120);
          expectRenderedLocations();
        }
        if (nextOrientation != DeviceOrientation.portraitUp) {
          for (final x in [.9, .1]) {
            data = {...data, 'x': x, 'y': .5};
            for (var i = 0; i < 12; i++) {
              await frame(delta: 33);
            }
            await tester.pump(FaceFollowMotion.animationDuration);
            panel = tester.widget<FaceLocationDebugPanel>(
              find.byType(FaceLocationDebugPanel),
            );
            expect(panel.currentShift.dx, x > .5 ? 360 : -360);
            expectRenderedLocations();
          }
        }
        expect(tester.state(find.byType(SetupCameraPreview)), same(camera));
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      Offset? previousRatio;
      for (final viewport in [
        const Size(402, 874),
        const Size(874, 402),
        const Size(492, 874),
      ]) {
        tester.view.physicalSize = viewport;
        orientation = viewport.width > viewport.height
            ? DeviceOrientation.landscapeLeft
            : DeviceOrientation.portraitUp;
        final width = viewport.width > viewport.height
            ? 250.0
            : viewport.width * .5;
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
        await mount(mapping: mapping, movementBounds: limits);
        if (previousRatio != null) {
          final actual = tester
              .renderObject<RenderBox>(find.byType(TrackedMouth))
              .localToGlobal(const Offset(156, 100));
          expect(actual.dx / viewport.width, closeTo(previousRatio.dx, .001));
          expect(actual.dy / viewport.height, closeTo(previousRatio.dy, .001));
        }
        expect(find.byKey(const ValueKey('face-debug-center')), findsNothing);
        for (final ratio in [
          const Offset(.3, .7),
          const Offset(.49, .51),
          const Offset(.7, .3),
        ]) {
          data = {
            ...mouthFrame(gap: .14),
            'x': ratio.dx,
            'y': ratio.dy,
            'faceHeight': .12,
          };
          for (var i = 0; i < 40; i++) {
            await frame(delta: 33);
          }
          await tester.pump(FaceFollowMotion.animationDuration);
          final renderedMouth = tester.renderObject<RenderBox>(
            find.byType(TrackedMouth),
          );
          final actualCenter = renderedMouth.localToGlobal(
            const Offset(156, 100),
          );
          expect(actualCenter.dx / viewport.width, closeTo(ratio.dx, .001));
          expect(actualCenter.dy / viewport.height, closeTo(ratio.dy, .001));
          // Changing distance/face size must not alter the same X/Y percentage.
          data = {...data, 'faceHeight': .7};
          await frame();
          await tester.pump(FaceFollowMotion.animationDuration);
          expect(
            (renderedMouth.localToGlobal(const Offset(156, 100)) - actualCenter)
                .distance,
            lessThan(.01),
          );
          expect(
            tester.widget<TrackedMouth>(find.byType(TrackedMouth)).openness,
            greaterThan(.5),
          );
        }
        expect(tester.state(find.byType(SetupCameraPreview)), same(camera));
        expect(tester.takeException(), isNull);
        previousRatio = const Offset(.7, .3);
      }
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
