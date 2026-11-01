import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/gesture_camera_guide.dart';
import 'package:hand_gesture/features/tutorials/landscape_tutorial_geometry.dart';
import 'package:hand_gesture/features/tutorials/tutorial_outline_assets.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';

import '../../helpers/camera_image.dart';
import '../../helpers/outline_test_helpers.dart';
import '../../shared/camera/setup_camera_preview_test.dart'
    show FakeCameraPlatform;

Future<Rect> _visibleBounds(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(
    data.buffer.asUint8List(),
    targetWidth: 320,
  );
  final image = (await codec.getNextFrame()).image;
  try {
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    int x0 = image.width, y0 = image.height, x1 = 0, y1 = 0;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (rgba.getUint8((y * image.width + x) * 4 + 3) > 12) {
          x0 = math.min(x0, x);
          y0 = math.min(y0, y);
          x1 = math.max(x1, x + 1);
          y1 = math.max(y1, y + 1);
        }
      }
    }
    return Rect.fromLTRB(
      x0 / image.width,
      y0 / image.height,
      x1 / image.width,
      y1 / image.height,
    );
  } finally {
    image.dispose();
    codec.dispose();
  }
}

class _Frame implements CameraImage {
  _Frame(this.size);
  final Size size;
  @override
  int get width => size.width.toInt();
  @override
  int get height => size.height.toInt();
  @override
  ImageFormat get format => syntheticCameraImage(ios: true).format;
  @override
  List<Plane> get planes => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Guide {
  _Guide(this.tester, {this.left = false});
  final WidgetTester tester;
  final bool left;
  bool landscape = false;
  Size panelSize = const Size(362, 536);
  Size imageSize = const Size(480, 640);
  int ms = 0, advances = 0;
  String get path => TutorialOutlineAssets.forPose(step.pose, isLeftHand: left);
  GestureTutorialStep step = gestureTutorialSteps.first;
  bool wrongHand = false;
  List<List<double>> points = [];
  Completer<Map<String, Object>>? pending;

  Map<String, Object> result() => {
    'width': imageSize.width,
    'height': imageSize.height,
    'points': points,
    'scores': {'Closed_Fist': .99},
    'gesture': 'Closed_Fist',
    'hand': (wrongHand ? !left : left) ? 'Right' : 'Left',
    'handScore': .99,
    'mirrored': true,
  };

  Future<void> mount() async {
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: panelSize.width,
            height: panelSize.height,
            child: GestureCameraGuide(
              step: step,
              stepId: step.title,
              isLeftHand: left,
              landscape: landscape,
              timeSource: () => DateTime(2026).add(Duration(milliseconds: ms)),
              onMatched: () => advances++,
            ),
          ),
        ),
      ),
    );
    await settleOutline(tester, path);
  }

  Rect get panel => tester.getRect(find.byType(SetupCameraPreview));
  Rect get outline => tester.getRect(find.byKey(ValueKey('guide-$path')));

  void align() {
    final scale = landscape
        ? math.min(
            panel.width / imageSize.width,
            panel.height / imageSize.height,
          )
        : math.max(
            panel.width / imageSize.width,
            panel.height / imageSize.height,
          );
    final cameraRect = Rect.fromCenter(
      center: panel.center,
      width: imageSize.width * scale,
      height: imageSize.height * scale,
    );
    points =
        [
              ...List.filled(17, const Offset(.5, .5)),
              const Offset(.25, .25),
              const Offset(.75, .25),
              const Offset(.25, .8),
              const Offset(.75, .8),
            ]
            .map(
              (p) => <double>[
                (outline.left + p.dx * outline.width - cameraRect.left) /
                    cameraRect.width,
                (outline.top + p.dy * outline.height - cameraRect.top) /
                    cameraRect.height,
              ],
            )
            .toList();
  }

  Future<void> frame(DeviceOrientation orientation, {int elapsed = 200}) async {
    ms += elapsed;
    await tester.pump(Duration(milliseconds: elapsed));
    tester.widget<SetupCameraPreview>(find.byType(SetupCameraPreview)).onFrame!(
      _Frame(imageSize),
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
}

void main() {
  late CameraPlatform original;
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    original = CameraPlatform.instance;
    CameraPlatform.instance = FakeCameraPlatform();
  });
  tearDown(() {
    CameraPlatform.instance = original;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HandRecognition.channel, null);
  });

  for (final left in [true, false]) {
    testWidgets(
      'all 20 ${left ? 'Left' : 'Right'} outlines keep portrait camera scale in landscape',
      (tester) async {
        final g = _Guide(tester, left: left);
        for (final step in [...gestureTutorialSteps, ...videoTutorialSteps]) {
          g.step = step;
          g.landscape = false;
          g.panelSize = Size(362, step.panelHeight);
          await g.mount();
          final portrait = g.outline.shift(-g.panel.topLeft);
          final alphaBounds = (await tester.runAsync(
            () => _visibleBounds(g.path),
          ))!;
          final portraitScale = math.max(362 / 480, step.panelHeight / 640);
          final beforeCamera = tester.widget<SetupCameraPreview>(
            find.byType(SetupCameraPreview),
          );
          expect(beforeCamera.fit, BoxFit.cover);
          expect(beforeCamera.orientedPreviewSize, isNull);
          for (final size in [const Size(400, 306), const Size(220, 233)]) {
            g.landscape = true;
            g.panelSize = size;
            await g.mount();
            final geometry = LandscapeTutorialGeometry(
              panelSize: size,
              imageSize: const Size(640, 480),
              portraitPanelHeight: step.panelHeight,
            );
            final current = g.outline.shift(-g.panel.topLeft);
            final scale = math.min(size.width / 640, size.height / 480);
            expect(
              current.width / scale,
              closeTo(portrait.width / portraitScale, .0001),
              reason: step.title,
            );
            expect(
              current.height / scale,
              closeTo(portrait.height / portraitScale, .0001),
              reason: step.title,
            );
            expect(
              current,
              rectMoreOrLessEquals(geometry.outlineRect(portrait)),
            );
            final visible = Rect.fromLTRB(
              current.left + alphaBounds.left * current.width,
              current.top + alphaBounds.top * current.height,
              current.left + alphaBounds.right * current.width,
              current.top + alphaBounds.bottom * current.height,
            );
            expect(
              geometry.previewRect.inflate(.01).contains(visible.topLeft),
              isTrue,
              reason: step.title,
            );
            expect(
              geometry.previewRect.inflate(.01).contains(visible.bottomRight),
              isTrue,
              reason: step.title,
            );
          }
          g.landscape = false;
          g.panelSize = Size(362, step.panelHeight);
          await g.mount();
          expect(
            g.outline.shift(-g.panel.topLeft),
            portrait,
            reason: 'Returning to portrait must preserve its exact outline',
          );
        }
        await tester.pumpWidget(const SizedBox());
      },
    );

    for (final orientation in [
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]) {
      testWidgets(
        '${left ? 'Left' : 'Right'} Fist aligns and completes in $orientation with camera insets',
        (tester) async {
          final g = _Guide(tester, left: left)
            ..landscape = orientation != DeviceOrientation.portraitUp
            ..panelSize = orientation == DeviceOrientation.portraitUp
                ? const Size(472, 536)
                : const Size(400, 250)
            ..imageSize = orientation == DeviceOrientation.portraitUp
                ? const Size(480, 640)
                : const Size(640, 480);
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(
                HandRecognition.channel,
                (call) async => call.method == 'recognize' ? g.result() : null,
              );
          await g.mount();
          g.align();
          g.wrongHand = true;
          for (var i = 0; i < 8; i++) {
            await g.frame(orientation);
          }
          expect(g.advances, 0);
          g.wrongHand = false;
          g.points = g.points.map((p) => [p[0] + .65, p[1]]).toList();
          for (var i = 0; i < 8; i++) {
            await g.frame(orientation);
          }
          expect(
            g.advances,
            0,
            reason: 'Outside the visible outline must fail',
          );
          g.align();
          for (var i = 0; i < 6; i++) {
            await g.frame(orientation);
          }
          expect(g.advances, 0, reason: 'Must earn the full existing hold');
          await g.frame(orientation);
          await tester.pump(const Duration(milliseconds: 201));
          expect(g.advances, 1);
          final preview = tester.widget<SetupCameraPreview>(
            find.byType(SetupCameraPreview),
          );
          if (!g.landscape) {
            expect(preview.fit, BoxFit.cover);
            expect(preview.orientedPreviewSize, isNull);
            await tester.pumpWidget(const SizedBox());
            return;
          }
          expect(preview.fit, BoxFit.contain);
          expect(preview.orientedPreviewSize, const Size(640, 480));
          final cameraRect = tester.getRect(find.byType(CameraPreview));
          final expected = LandscapeTutorialGeometry(
            panelSize: g.panelSize,
            imageSize: g.imageSize,
            portraitPanelHeight: g.step.panelHeight,
          ).previewRect.shift(g.panel.topLeft);
          expect(
            cameraRect,
            rectMoreOrLessEquals(expected),
            reason: 'Rendered preview and landmark mapping share the inset',
          );
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'rotation discards old results, pending completion and the old hold',
    (tester) async {
      final g = _Guide(tester);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HandRecognition.channel, (call) async {
            if (call.method != 'recognize') return null;
            return g.pending?.future ?? Future.value(g.result());
          });
      await g.mount();
      final state = tester.state(find.byType(GestureCameraGuide));
      g.align();
      for (var i = 0; i < 6; i++) {
        await g.frame(DeviceOrientation.portraitUp);
      }
      final oldResult = g.result();
      g.pending = Completer();
      await g.frame(DeviceOrientation.portraitUp);
      g.landscape = true;
      g.panelSize = const Size(400, 250);
      await g.mount();
      expect(tester.state(find.byType(GestureCameraGuide)), same(state));
      g.pending!.complete(oldResult);
      g.pending = null;
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 201));
      expect(g.advances, 0);
      // Late portrait-sized iOS buffers are ignored even after the sensor event.
      for (var i = 0; i < 8; i++) {
        await g.frame(DeviceOrientation.landscapeLeft);
      }
      expect(g.advances, 0);
      expect(find.byKey(ValueKey('progress-${g.path}')), findsNothing);
      g.imageSize = const Size(640, 480);
      g.align();
      for (var i = 0; i < 7; i++) {
        await g.frame(DeviceOrientation.landscapeLeft);
      }
      expect(g.advances, 0); // The completion callback is still pending.
      await g.frame(DeviceOrientation.landscapeRight, elapsed: 150);
      await tester.pump(const Duration(milliseconds: 60));
      expect(
        g.advances,
        0,
        reason: 'Opposite landscape rotation cancels pending completion',
      );
      for (var i = 0; i < 6; i++) {
        await g.frame(DeviceOrientation.landscapeRight);
      }
      await tester.pump(const Duration(milliseconds: 201));
      expect(g.advances, 1);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
