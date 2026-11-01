import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/gesture_camera_guide.dart';
import 'package:hand_gesture/features/tutorials/gesture_debug_overlay.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import '../../helpers/camera_image.dart';
import '../../helpers/gesture_pose_fixture.dart';

void main() {
  for (final hand in ['Left', 'Right']) {
    for (final shake in [false, true]) {
      for (final size in [const Size(362, 536), const Size(650, 280)]) {
        testWidgets(
          'Social $hand gestures ignore position and size in $size; shake=$shake',
          (tester) async {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
            final landscape = size.width > size.height;
            final cameraSize = landscape
                ? const Size(1000, 600)
                : const Size(600, 1000);
            HandObservation cameraPose(
              HandPose pose, {
              double handScore = .99,
            }) {
              final source = poseFixture(
                pose,
                hand: hand,
                handScore: handScore,
              );
              final shortest = math.min(cameraSize.width, cameraSize.height);
              return HandObservation(
                points: source.points
                    .map(
                      (p) => Offset(
                        .5 + (p.dx - .5) * shortest / cameraSize.width,
                        .5 + (p.dy - .5) * shortest / cameraSize.height,
                      ),
                    )
                    .toList(),
                imageSize: cameraSize,
                hand: source.hand,
                handScore: source.handScore,
                gesture: source.gesture,
                scores: source.scores,
              );
            }

            var observation = const HandObservation();
            var now = DateTime(2026);
            var advances = 0;
            double progress = 0;
            bool matching = false;
            final messenger = TestDefaultBinaryMessengerBinding
                .instance
                .defaultBinaryMessenger;
            messenger.setMockMethodCallHandler(HandRecognition.channel, (
              call,
            ) async {
              if (call.method != 'recognize') return null;
              return {
                'points': observation.points.map((p) => [p.dx, p.dy]).toList(),
                'width': observation.imageSize.width,
                'height': observation.imageSize.height,
                'hand': observation.hand,
                'handScore': observation.handScore,
                'gesture': observation.gesture,
                'scores': observation.scores,
              };
            });
            addTearDown(
              () => messenger.setMockMethodCallHandler(
                HandRecognition.channel,
                null,
              ),
            );
            Future<void> frame(HandObservation sample) async {
              observation = sample;
              now = now.add(const Duration(milliseconds: 200));
              await tester.pump(const Duration(milliseconds: 200));
              tester
                  .widget<SetupCameraPreview>(find.byType(SetupCameraPreview))
                  .onFrame!(
                syntheticCameraImage(),
                const CameraDescription(
                  name: 'front',
                  lensDirection: CameraLensDirection.front,
                  sensorOrientation: 0,
                ),
                landscape
                    ? DeviceOrientation.landscapeLeft
                    : DeviceOrientation.portraitUp,
              );
              await tester.pump();
              await tester.pump();
            }

            for (final step in videoTutorialSteps) {
              await tester.pumpWidget(
                MaterialApp(
                  home: Scaffold(
                    body: Center(
                      child: SizedBox(
                        width: size.width,
                        height: size.height,
                        child: GestureCameraGuide(
                          key: ValueKey(step.socialAction),
                          step: step,
                          stepId: step.title,
                          socialPractice: true,
                          landscape: landscape,
                          showDebugOverlay: true,
                          isLeftHand: hand == 'Left',
                          timeSource: () => now,
                          onMatched: () => advances++,
                          onReading: (reading) {
                            progress = reading.progress;
                            matching = reading.matching;
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              );
              final before = advances;
              // Play and Pause must accept the punch directly; no open-hand
              // observation is sent between these consecutive lessons.
              final placements = [
                (const Offset(.025, .025), .04),
                (const Offset(.975, .025), .04),
                (const Offset(.5, .5), .85),
                (const Offset(.025, .975), .04),
                (const Offset(.975, .975), .04),
                (const Offset(.5, .5), .12),
                (const Offset(.5, .5), .85),
              ];
              if (shake) placements.add(placements.last);
              for (var i = 0; i < placements.length; i++) {
                final placement = placements[i];
                if (shake && i == 3) {
                  final earned = progress;
                  expect(earned, greaterThan(0));
                  await frame(HandObservation(imageSize: cameraSize));
                  expect(progress, earned);
                  expect(matching, isFalse);
                  await frame(cameraPose(step.pose, handScore: .5));
                  expect(progress, earned);
                  expect(matching, isFalse);
                  expect(advances, before);
                }
                await frame(
                  placePose(
                    cameraPose(step.pose),
                    center: placement.$1,
                    extent: placement.$2,
                  ),
                );
              }
              final debug = tester.widget<GestureDebugOverlay>(
                find.byType(GestureDebugOverlay),
              );
              expect(
                debug.complete,
                isTrue,
                reason: '${step.title}: ${debug.status} ${debug.hold}',
              );
              expect(
                debug.checks.any(
                  (check) => check.id == 'size' || check.id == 'outline',
                ),
                isFalse,
              );
              await tester.pump(const Duration(milliseconds: 201));
              expect(
                advances,
                before + 1,
                reason: '${step.title} completes once',
              );
              expect(tester.takeException(), isNull);
            }
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }
}
