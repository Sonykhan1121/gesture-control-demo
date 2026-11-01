import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';

void main() {
  for (final happy in [false, true]) {
    testWidgets(
      'Timed blinking is paired, camera independent and lifecycle safe (happy=$happy)',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        final messenger = tester.binding.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          FaceTracking.channel,
          (_) async => null,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(FaceTracking.channel, null),
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Center(
              child: SizedBox(
                width: 312,
                height: 200,
                child: FaceTrackingEyes(
                  enabled: false,
                  happy: happy,
                  color: Colors.lime,
                ),
              ),
            ),
          ),
        );
        void expectBoth(bool closed) {
          for (final side in ['left', 'right']) {
            final eye = tester.widget<TweenAnimationBuilder<double>>(
              find.byKey(ValueKey('blink-screen-$side')),
            );
            expect(eye.tween.end, closed ? .06 : 1);
          }
        }

        expect(find.byType(SetupCameraPreview), findsNothing);
        expectBoth(false);
        await tester.pump(const Duration(milliseconds: 3999));
        expectBoth(false);
        await tester.pump(const Duration(milliseconds: 1));
        expectBoth(true);
        await tester.pump(const Duration(milliseconds: 119));
        expectBoth(true);
        await tester.pump(const Duration(milliseconds: 1));
        expectBoth(false);
        await tester.pump(const Duration(milliseconds: 3880));
        expectBoth(true);

        // Leaving during closure cancels the reopen timer and the repeating timer.
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        await tester.pump();
        expectBoth(false);
        await tester.pump(const Duration(seconds: 10));
        expectBoth(false);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 3999));
        expectBoth(false);
        await tester.pump(const Duration(milliseconds: 1));
        expectBoth(true);
        // Disposing during closure must cancel both timers.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 10));
        expect(tester.takeException(), isNull);
      },
      variant: TargetPlatformVariant({
        TargetPlatform.android,
        TargetPlatform.iOS,
      }),
    );
  }
}
