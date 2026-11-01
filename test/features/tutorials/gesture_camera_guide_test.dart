import '../../helpers/camera_image.dart';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/tutorials/gesture_camera_guide.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import 'package:hand_gesture/features/tutorials/tutorial_outline_assets.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

import '../../helpers/outline_test_helpers.dart';

// Recognition is mocked at the native boundary; this test exercises the real
// PNG placement mask, 1.2-second hold, lifecycle reset and delayed callback.
class _Frame implements CameraImage {
  @override
  ImageFormat get format => syntheticCameraImage().format;
  @override
  int get width => 362;
  @override
  int get height => 536;
  @override
  List<Plane> get planes => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  for (final isLeft in [true, false]) {
    for (final reopen in [false, true]) {
      testWidgets(
        'pending ${isLeft ? 'Left' : 'Right'} fist advance recovers after ${reopen ? 'exit and re-entry' : 'backgrounding'}',
        (tester) async {
          var now = DateTime(2026);
          var advances = 0;
          var requests = 0;
          var points = <List<double>>[];
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(HandRecognition.channel, (call) async {
                if (call.method != 'recognize') return null;
                requests++;
                return {
                  'points': points,
                  'width': 362,
                  'height': 536,
                  'gesture': 'Closed_Fist',
                  'fistScore': .6,
                  'scores': {'Closed_Fist': .6},
                  'hand': isLeft ? 'Right' : 'Left',
                  'handScore': .99,
                  'mirrored': true,
                };
              });
          addTearDown(
            () => TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger
                .setMockMethodCallHandler(HandRecognition.channel, null),
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          Widget guideWidget() => MaterialApp(
            home: Center(
              child: SizedBox(
                width: 362,
                height: 536,
                child: GestureCameraGuide(
                  step: gestureTutorialSteps.first,
                  stepId: 'hand-0',
                  isLeftHand: isLeft,
                  timeSource: () => now,
                  onMatched: () => advances++,
                ),
              ),
            ),
          );
          await tester.pumpWidget(guideWidget());
          final path = TutorialOutlineAssets.forPose(
            HandPose.fist,
            isLeftHand: isLeft,
          );
          await settleOutline(tester, path);
          final guide = tester.getRect(find.byKey(ValueKey('guide-$path')));
          final panel = tester.getRect(find.byType(SetupCameraPreview));
          // Known inside-palm points plus a large enough bounding box. The mocked
          // native classifier supplies the pose; placement uses the real asset.
          final localPoints = [
            ...List.filled(17, const Offset(.5, .5)),
            const Offset(.25, .25),
            const Offset(.75, .25),
            const Offset(.25, .8),
            const Offset(.75, .8),
          ];
          points = localPoints
              .map(
                (p) => [
                  (guide.left + p.dx * guide.width - panel.left) / panel.width,
                  (guide.top + p.dy * guide.height - panel.top) / panel.height,
                  0.0,
                ],
              )
              .toList();
          var lastMs = 0;
          Future<void> frame(int ms) async {
            now = DateTime(2026).add(Duration(milliseconds: ms));
            await tester.pump(Duration(milliseconds: ms - lastMs));
            lastMs = ms;
            tester
                .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
                .onFrame!(
              _Frame(),
              const CameraDescription(
                name: 'test',
                lensDirection: CameraLensDirection.front,
                sensorOrientation: 0,
              ),
              DeviceOrientation.portraitUp,
            );
            await tester.pump();
          }

          for (final ms in [0, 400, 800, 1200]) {
            await frame(ms);
          }
          expect(advances, 0, reason: 'The 200ms advancement is still pending');
          expect(find.byKey(ValueKey('progress-$path')), findsOneWidget);
          if (reopen) {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump(const Duration(milliseconds: 250));
            await tester.pumpWidget(guideWidget());
            await settleOutline(tester, path);
          } else {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.inactive,
            );
            await tester.pump(const Duration(milliseconds: 250));
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            await tester.pump();
          }
          expect(advances, 0, reason: 'Leaving cancels the pending callback');
          final firstPassRequests = requests;
          for (final ms in [2000, 2400, 2800, 3200]) {
            await frame(ms);
          }
          expect(
            requests,
            greaterThan(firstPassRequests),
            reason: 'Recognition must restart after resuming',
          );
          expect(advances, 0);
          await tester.pump(const Duration(milliseconds: 201));
          expect(advances, 1);
          await tester.pump(const Duration(milliseconds: 300));
          expect(advances, 1, reason: 'Completion is delivered once');
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  test('Fist and Pointing Right use all four approved, separate files', () {
    expect(
      TutorialOutlineAssets.forPose(HandPose.fist, isLeftHand: true),
      'assets/tutorials/fist-left-outline.png',
    );
    expect(
      TutorialOutlineAssets.forPose(HandPose.fist, isLeftHand: false),
      'assets/tutorials/fist-right-outline.png',
    );
    expect(
      TutorialOutlineAssets.forPose(HandPose.pointRight, isLeftHand: true),
      'assets/tutorials/point-right-left-outline.png',
    );
    expect(
      TutorialOutlineAssets.forPose(HandPose.pointRight, isLeftHand: false),
      'assets/tutorials/point-right-right-outline.png',
    );
  });
}
