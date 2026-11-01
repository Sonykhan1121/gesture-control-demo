import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/face_tracking/face_debug_panel.dart';
import 'package:hand_gesture/features/face_tracking/face_movement_debug.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_mouth.dart';
import 'package:hand_gesture/features/home/control_screen.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../app/gesture_flow_test.dart' show FakeDiscovery;
import '../../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;
import '../../helpers/camera_image.dart';
import 'mouth_motion_test.dart' show mouthFrame;

void main() {
  test('Eye reference X coordinates follow the PNG and SVG artwork', () {
    expect(AvatarLocationMarkers.leftEye(false).dx, 100 / 2);
    expect(AvatarLocationMarkers.rightEye(false).dx, 524 / 2);
    expect(AvatarLocationMarkers.leftEye(true).dx, 16 * 312 / 120);
    expect(AvatarLocationMarkers.rightEye(true).dx, 104 * 312 / 120);
  });

  testWidgets(
    'Movement boxes match live artwork transforms and hide without restarting the camera',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final previousCamera = CameraPlatform.instance;
      CameraPlatform.instance = FakeCameraPlatform();
      addTearDown(() => CameraPlatform.instance = previousCamera);
      t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        FaceTracking.channel,
        (call) async => call.method == 'recognize'
            ? {...mouthFrame(), 'x': .5, 'y': .5}
            : null,
      );
      addTearDown(
        () => t.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          FaceTracking.channel,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({});
      final c = GestureController(
        await SharedPreferences.getInstance(),
        discovery: FakeDiscovery(),
      );
      c.cameraX = .6;
      c.cameraY = .4;
      for (final happy in [false, true]) {
        for (final size in [
          const Size(320, 568),
          const Size(568, 320),
          const Size(402, 874),
          const Size(874, 402),
          const Size(800, 1333),
          const Size(1333, 800),
        ]) {
          t.view.physicalSize = size;
          c.mode = GestureMode.face;
          c.faceEmoji = happy ? 1 : 0;
          await t.pumpWidget(
            ChangeNotifierProvider.value(
              value: c,
              child: MaterialApp(
                key: UniqueKey(),
                home: const ControlScreen(enableMovementDebug: true),
              ),
            ),
          );
          await t.pumpAndSettle();
          final overlay = find.byKey(
            const ValueKey('home-face-movement-limits'),
          );
          final cameraOwner = t.state(find.byType(SetupCameraPreview));
          void checkLiveGeometry() {
            final painter =
                t.widget<CustomPaint>(overlay).painter!
                    as FaceMovementLimitsPainter;
            final geometry = painter.geometry;
            final box = t.renderObject<RenderBox>(overlay);
            final mouth = t.renderObject<RenderBox>(find.byType(TrackedMouth));
            final renderedMouthAnchor = mouth.localToGlobal(
              AvatarLocationMarkers.mouth(happy),
            );
            final debugMouthAnchor = box.localToGlobal(
              geometry.position(2, painter.currentShift),
            );
            expect(
              (renderedMouthAnchor - debugMouthAnchor).distance,
              lessThan(.001),
            );
            for (var i = 0; i < 3; i++) {
              final range = geometry.range(i);
              for (final extreme in [
                geometry.limits.topLeft,
                geometry.limits.topRight,
                geometry.limits.bottomLeft,
                geometry.limits.bottomRight,
              ]) {
                expect(
                  range.inflate(.00001).contains(geometry.position(i, extreme)),
                  isTrue,
                );
              }
              expect(range.left, greaterThan(0));
              expect(range.top, greaterThan(0));
              expect(range.right, lessThan(geometry.mapping.viewport.width));
              expect(range.bottom, lessThan(geometry.mapping.viewport.height));
            }
          }

          checkLiveGeometry();
          t
              .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
              .onFrame!(
            syntheticCameraImage(),
            const CameraDescription(
              name: 'front',
              lensDirection: CameraLensDirection.front,
              sensorOrientation: 0,
            ),
            size.width > size.height
                ? DeviceOrientation.landscapeLeft
                : DeviceOrientation.portraitUp,
          );
          await t.pump();
          await t.pump(const Duration(milliseconds: 20));
          checkLiveGeometry();
          await t.pump(FaceFollowMotion.animationDuration);
          checkLiveGeometry();
          final toggle = find.byKey(
            const ValueKey('face-movement-debug-toggle'),
          );
          await t.tap(toggle);
          await t.pumpAndSettle();
          expect(overlay, findsNothing);
          expect(t.state(find.byType(SetupCameraPreview)), same(cameraOwner));
          expect(
            find.byKey(const ValueKey('home-face-camera-frame')),
            findsOneWidget,
          );
          await t.tap(toggle);
          await t.pumpAndSettle();
          checkLiveGeometry();
          expect(t.state(find.byType(SetupCameraPreview)), same(cameraOwner));
          for (final mode in [GestureMode.hand, GestureMode.social]) {
            c.setMode(mode);
            await t.pumpAndSettle();
            expect(overlay, findsNothing);
            expect(find.byType(FaceMovementDebugLegend), findsNothing);
          }
          expect(t.takeException(), isNull, reason: '$size happy=$happy');
        }
      }
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      c.dispose();
    },
  );
}
