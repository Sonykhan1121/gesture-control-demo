import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/gesture_app.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gesture_flow_test.dart' show FakeDiscovery;
import '../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;

void main() {
  testWidgets(
    'Home preview follows native camera ratio and rotation only in Face mode',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final previousCamera = CameraPlatform.instance;
      addTearDown(() => CameraPlatform.instance = previousCamera);
      for (final nativeSize in [const Size(640, 480), const Size(1280, 720)]) {
        final camera = FakeCameraPlatform()..previewSize = nativeSize;
        CameraPlatform.instance = camera;
        SharedPreferences.setMockInitialValues({});
        final c = GestureController(
          await SharedPreferences.getInstance(),
          discovery: FakeDiscovery(),
        );
        c.mode = GestureMode.face;
        c.open(FlowPage.control);
        await t.pumpWidget(GestureApp(controller: c));
        await t.pumpAndSettle();
        for (final viewport in [
          const Size(320, 568),
          const Size(568, 320),
          const Size(800, 1333),
          const Size(1333, 800),
        ]) {
          t.view.physicalSize = viewport;
          t.view.viewPadding = const FakeViewPadding(left: 12, bottom: 24);
          await t.pumpAndSettle();
          final landscape = viewport.width > viewport.height;
          for (final orientation
              in landscape
                  ? [
                      DeviceOrientation.landscapeLeft,
                      DeviceOrientation.landscapeRight,
                    ]
                  : [
                      DeviceOrientation.portraitUp,
                      DeviceOrientation.portraitDown,
                    ]) {
            camera.orientation.add(DeviceOrientationChangedEvent(orientation));
            await t.pumpAndSettle();
            final frame = t.getRect(
              find.byKey(const ValueKey('home-face-camera-frame')),
            );
            expect(
              frame.width / frame.height,
              closeTo(
                landscape ? nativeSize.aspectRatio : 1 / nativeSize.aspectRatio,
                .00001,
              ),
            );
            expect(frame.left, greaterThan(12));
            expect(frame.bottom, lessThan(viewport.height - 24));
            expect(frame.right, lessThan(viewport.width / 2));
            expect(frame.top, greaterThan(viewport.height / 2));
            expect(frame.width, lessThanOrEqualTo(viewport.width * .26 + .001));
            expect(
              frame.height,
              lessThanOrEqualTo(viewport.height * .26 + .001),
            );
            expect(t.takeException(), isNull);
            expect(camera.frames.values.where((s) => s.hasListener).length, 1);
          }
        }
        for (final mode in [GestureMode.hand, GestureMode.social]) {
          c.setMode(mode);
          await t.pumpAndSettle();
          expect(
            find.byKey(const ValueKey('home-face-camera-preview')),
            findsNothing,
          );
        }
        expect(camera.frames.values.any((s) => s.hasListener), isFalse);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        c.dispose();
      }
    },
  );

  testWidgets(
    'both Home faces can travel proportionally on phones and tablets',
    (t) async {
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final previousCamera = CameraPlatform.instance;
      CameraPlatform.instance = FakeCameraPlatform();
      addTearDown(() => CameraPlatform.instance = previousCamera);
      SharedPreferences.setMockInitialValues({});
      final c = GestureController(
        await SharedPreferences.getInstance(),
        discovery: FakeDiscovery(),
      );
      c.mode = GestureMode.face;
      c.open(FlowPage.control);
      for (final portrait in [
        const Size(320, 568),
        const Size(360, 640),
        const Size(360, 800),
        const Size(393, 852),
        const Size(402, 874),
        const Size(768, 1024),
        const Size(800, 1333),
        const Size(800, 1333.333333),
        const Size(1024, 1366),
      ]) {
        for (final viewport in [
          portrait,
          Size(portrait.height, portrait.width),
        ]) {
          t.view.physicalSize = viewport;
          Size? original;
          for (final happy in [false, true]) {
            c.faceEmoji = happy ? 1 : 0;
            await t.pumpWidget(GestureApp(key: UniqueKey(), controller: c));
            await t.pumpAndSettle();
            expect(t.takeException(), isNull, reason: '$viewport happy=$happy');
            final tracker = t.widget<FaceTrackingEyes>(
              find.byKey(const ValueKey('home-face-tracking')),
            );
            final mapping = tracker.screenMapping!;
            final bounds = tracker.movementBounds;
            expect(bounds.left, lessThan(0));
            expect(bounds.right, greaterThan(0));
            expect(bounds.top, lessThan(0));
            expect(bounds.bottom, greaterThan(0));
            expect(
              mapping.avatar.width / mapping.avatar.height,
              closeTo(312 / 200, .00001),
            );
            if (!happy) {
              original = mapping.avatar.size;
            } else {
              expect(mapping.avatar.width, greaterThan(original!.width));
            }
            // A ten-percentage-point movement in either direction must stay
            // proportional, instead of clamping both sides to the center.
            for (final point in [const Offset(.4, .4), const Offset(.6, .6)]) {
              final shift = mapping.shiftForRatio(point, bounds);
              expect(
                (mapping.ratioForShift(shift) - point).distance,
                lessThan(.00001),
              );
            }
            for (final point in [
              Offset.zero,
              const Offset(1, 1),
              const Offset(0, 1),
              const Offset(1, 0),
            ]) {
              final shift =
                  mapping.shiftForRatio(point, bounds) * mapping.scale;
              final moved = mapping.avatar.shift(shift);
              expect(moved.left, greaterThanOrEqualTo(18 - .00001));
              expect(moved.top, greaterThanOrEqualTo(18 - .00001));
              expect(
                moved.right,
                lessThanOrEqualTo(mapping.viewport.width - 18 + .00001),
              );
              expect(
                moved.bottom,
                lessThanOrEqualTo(mapping.viewport.height - 18 + .00001),
              );
            }
          }
        }
      }
      await t.pumpWidget(const SizedBox());
      await t.pumpAndSettle();
      c.dispose();
    },
  );
}
