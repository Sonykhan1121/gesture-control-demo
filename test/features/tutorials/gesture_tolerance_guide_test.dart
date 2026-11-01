import '../../helpers/camera_image.dart';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/gesture_camera_guide.dart';
import 'package:hand_gesture/features/tutorials/gesture_debug_overlay.dart';
import 'package:hand_gesture/features/tutorials/tutorial_outline_assets.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';

import '../../helpers/outline_test_helpers.dart';

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

class _Guide {
  _Guide(this.tester, {this.left = false}) {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(HandRecognition.channel, (call) async {
          if (call.method != 'recognize') return null;
          if (failRecognition) throw PlatformException(code: 'test-error');
          final physicalLeft = wrongHand ? !left : left;
          return {
            'points': points,
            'width': 362,
            'height': 536,
            'gesture': 'Closed_Fist',
            'scores': {'Closed_Fist': score},
            'hand': physicalLeft ? 'Right' : 'Left',
            'handScore': handScore,
            'mirrored': true,
          };
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(HandRecognition.channel, null),
    );
  }

  final WidgetTester tester;
  final bool left;
  int ms = 0, advances = 0;
  bool wrongHand = false;
  bool practiceEnabled = true, requireRelease = false;
  bool handPractice = false;
  bool failRecognition = false;
  double handScore = .75;
  double score = .45;
  List<List<double>> points = [];
  late Rect guide, panel;
  late String path;

  Future<void> mount(GestureTutorialStep step, String id) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 362,
              height: 536,
              child: GestureCameraGuide(
                showDebugOverlay: true,
                practiceEnabled: practiceEnabled,
                requireRelease: requireRelease,
                handPractice: handPractice,
                step: step,
                stepId: id,
                isLeftHand: left,
                timeSource: () =>
                    DateTime(2026).add(Duration(milliseconds: ms)),
                onMatched: () => advances++,
              ),
            ),
          ),
        ),
      ),
    );
    path = TutorialOutlineAssets.forPose(step.pose, isLeftHand: left);
    await settleOutline(tester, path);
    guide = tester.getRect(find.byKey(ValueKey('guide-$path')));
    panel = tester.getRect(find.byType(SetupCameraPreview));
    place([
      ...List.filled(17, const Offset(.5, .5)),
      const Offset(.25, .25),
      const Offset(.75, .25),
      const Offset(.25, .8),
      const Offset(.75, .8),
    ]);
  }

  void place(List<Offset> localPoints) {
    points = localPoints
        .map(
          (p) => [
            (guide.left + p.dx * guide.width - panel.left) / panel.width,
            (guide.top + p.dy * guide.height - panel.top) / panel.height,
          ],
        )
        .toList();
  }

  Future<void> elapse(int amount) async {
    ms += amount;
    await tester.pump(Duration(milliseconds: amount));
  }

  Future<void> frame(int at) async {
    await elapse(at - ms);
    tester.widget<SetupCameraPreview>(find.byType(SetupCameraPreview)).onFrame!(
      _Frame(),
      const CameraDescription(
        name: 'front',
        lensDirection: CameraLensDirection.front,
        sensorOrientation: 0,
      ),
      DeviceOrientation.portraitUp,
    );
    await tester.pump();
    await tester.pump(); // Paint the asynchronous recognition result.
  }

  Future<void> close() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }
}

Future<Offset> _bottomOfOutline(String path) async {
  final bytes = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final image = (await codec.getNextFrame()).image;
  try {
    final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    for (var y = image.height - 1; y >= 0; y--) {
      final xs = <int>[];
      for (var x = 0; x < image.width; x++) {
        if (rgba.getUint8((y * image.width + x) * 4 + 3) > 32) xs.add(x);
      }
      if (xs.isNotEmpty) {
        return Offset((xs.first + xs.last) / 2 / image.width, y / image.height);
      }
    }
    throw StateError('Empty outline');
  } finally {
    image.dispose();
    codec.dispose();
  }
}

void main() {
  for (final left in [false, true]) {
    testWidgets(
      '${left ? 'Left' : 'Right'} easier Hand profile allows relaxed alignment and an 800ms hold',
      (tester) async {
        final guide = _Guide(tester, left: left);
        await guide.mount(gestureTutorialSteps.first, 'easier-hand');
        final bottom = (await tester.runAsync(
          () => _bottomOfOutline(guide.path),
        ))!;
        final shifted = [
          ...List.filled(13, bottom + const Offset(0, .10)),
          ...List.filled(2, const Offset(.25, .25)),
          ...List.filled(2, const Offset(.75, .25)),
          ...List.filled(2, const Offset(.25, .8)),
          ...List.filled(2, const Offset(.75, .8)),
        ];
        GestureDebugOverlay debug() =>
            tester.widget(find.byType(GestureDebugOverlay));
        guide.place(shifted);
        await guide.frame(0);
        await guide.frame(200);
        expect(
          debug().checks.firstWhere((c) => c.id == 'outline').passed,
          isFalse,
        );

        guide.handPractice = true;
        await guide.mount(gestureTutorialSteps.first, 'easier-hand');
        guide.place(shifted);
        for (final ms in [400, 600, 800, 1000]) {
          await guide.frame(ms);
        }
        expect(guide.advances, 0);
        expect(
          debug().checks.firstWhere((c) => c.id == 'outline').passed,
          isTrue,
        );
        await guide.frame(1200);
        expect(debug().hold, '0.8 / 0.8 s');
        await guide.elapse(201);
        expect(guide.advances, 1);
        await guide.close();
      },
    );
    testWidgets(
      '${left ? 'Left' : 'Right'} easier Hand profile still resets for the opposite hand',
      (tester) async {
        final guide = _Guide(tester, left: left)..handPractice = true;
        await guide.mount(gestureTutorialSteps.first, 'easy-wrong-hand');
        await guide.frame(0);
        await guide.frame(400);
        guide.wrongHand = true;
        await guide.frame(600);
        guide.wrongHand = false;
        for (final ms in [800, 1000, 1200, 1400]) {
          await guide.frame(ms);
        }
        expect(guide.advances, 0);
        await guide.frame(1600);
        await guide.elapse(201);
        expect(guide.advances, 1);
        await guide.close();
      },
    );
  }
  for (final left in [false, true]) {
    testWidgets(
      'Wrong hand inline hint uses selected ${left ? 'Left' : 'Right'} hand and clears after correction',
      (tester) async {
        final guide = _Guide(tester, left: left)..wrongHand = true;
        await guide.mount(gestureTutorialSteps.first, 'wrong-hand');
        guide.handScore = .2;
        await guide.frame(0);
        final label = 'Please use your ${left ? 'Left' : 'Right'} hand';
        expect(find.text(label), findsNothing);
        guide.handScore = .9;
        await guide.frame(400);
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text(label), findsOneWidget);
        for (final ms in [
          800,
          1200,
          1600,
          2000,
          2400,
          2800,
          3200,
          3600,
          4000,
          4400,
          4800,
          5200,
        ]) {
          await guide.frame(ms);
        }
        await tester.pump(const Duration(milliseconds: 500));
        expect(
          find.text(label),
          findsOneWidget,
          reason: 'The hint remains under the hand until corrected',
        );
        expect(find.byType(SnackBar), findsNothing);
        guide.wrongHand = false;
        await guide.frame(5600);
        expect(find.text(label), findsNothing);
        expect(guide.advances, 0);
        await guide.close();
      },
    );
  }

  testWidgets(
    'Watch cannot earn progress; Your turn requires a fresh full hold',
    (tester) async {
      final guide = _Guide(tester)..practiceEnabled = false;
      await guide.mount(gestureTutorialSteps.first, 'watch');
      for (final ms in [0, 400, 800, 1200, 1600]) {
        await guide.frame(ms);
      }
      await guide.elapse(201);
      expect(guide.advances, 0);
      guide.practiceEnabled = true;
      await guide.mount(gestureTutorialSteps.first, 'watch');
      for (final ms in [2000, 2400, 2800]) {
        await guide.frame(ms);
      }
      expect(guide.advances, 0);
      await guide.frame(3200);
      await guide.elapse(201);
      expect(guide.advances, 1);
      await guide.close();
    },
  );
  for (final left in [false, true]) {
    testWidgets(
      '${left ? 'Left' : 'Right'} debug reports actual failed gates and clears stale readings',
      (tester) async {
        final guide = _Guide(tester, left: left);
        await guide.mount(gestureTutorialSteps.first, 'fist');
        GestureDebugOverlay debug() =>
            tester.widget(find.byType(GestureDebugOverlay));
        bool? passed(String id) =>
            debug().checks.firstWhere((check) => check.id == id).passed;
        final aligned = guide.points;
        await guide.frame(0);
        await guide.frame(200);
        expect(debug().checks.every((check) => check.passed == true), isTrue);
        expect(debug().hold, '0.2 / 1.2 s');
        expect(debug().status, 'All checks pass — keep holding');
        guide.wrongHand = true;
        await guide.frame(400);
        expect(passed('hand'), isFalse);
        expect(passed('pose'), isNull, reason: 'Wrong hand skips pose scoring');
        expect(debug().hold, '0.0 / 1.2 s');
        guide.wrongHand = false;
        guide.handScore = .74;
        await guide.frame(600);
        expect(passed('hand-confidence'), isFalse);
        guide.handScore = .75;
        guide.score = .44;
        await guide.frame(800);
        expect(passed('pose'), isFalse);
        expect(
          debug().checks.firstWhere((check) => check.id == 'pose').detail,
          '44.0% / need 45.0%',
        );
        guide.score = .45;
        guide.place([
          ...List.filled(20, const Offset(.5, .5)),
          const Offset(.51, .51),
        ]);
        await guide.frame(1000);
        expect(passed('pose'), isTrue);
        expect(passed('size'), isFalse);
        expect(debug().status, contains('Hand too small'));
        guide.points = [
          ...List.filled(17, <double>[.03, .5]),
          ...aligned.skip(17),
        ];
        await guide.frame(1200);
        expect(passed('outline'), isFalse);
        expect(debug().status, contains('Move your hand into the outline'));
        guide.points = [
          <double>[0, .5],
          ...aligned.skip(1),
        ];
        await guide.frame(1400);
        expect(passed('visibility'), isFalse);
        expect(passed('pose'), isNull);
        guide.points = [];
        await guide.frame(1600);
        expect(passed('tracking'), isFalse);
        expect(debug().nativeReading, isNull);
        guide.points = aligned;
        await guide.frame(1800);
        await guide.frame(2000);
        await tester.tap(find.byKey(const ValueKey('gesture-debug-toggle')));
        await tester.pump();
        expect(
          find.byKey(const ValueKey('gesture-debug-readings')),
          findsNothing,
        );
        await guide.frame(2200);
        expect(
          debug().hold,
          '0.4 / 1.2 s',
          reason: 'Collapsing must not reset detection',
        );
        await guide.elapse(601);
        expect(debug().status, contains('Detection stalled'));
        expect(debug().checks.every((check) => check.passed == null), isTrue);
        expect(debug().nativeReading, isNull);
        expect(debug().hold, '0.0 / 1.2 s');
        await guide.frame(3000);
        expect(passed('pose'), isTrue);
        guide.failRecognition = true;
        await guide.frame(3200);
        expect(debug().status, contains('Hand tracking unavailable'));
        expect(debug().checks.every((check) => check.passed == null), isTrue);
        expect(guide.advances, 0);
        expect(tester.takeException(), isNull);
        await guide.close();
      },
    );

    testWidgets(
      '${left ? 'Left' : 'Right'} placement wobble pauses without earning hold time',
      (tester) async {
        final guide = _Guide(tester, left: left);
        await guide.mount(gestureTutorialSteps.first, 'fist');
        final aligned = guide.points;
        for (final ms in [0, 200, 400]) {
          await guide.frame(ms);
        }
        guide.points = [
          ...List.filled(17, <double>[.03, .5]),
          ...aligned.skip(17),
        ];
        await guide.frame(600);
        guide.points = aligned;
        for (final ms in [750, 950, 1150, 1350, 1550]) {
          await guide.frame(ms);
        }
        expect(guide.advances, 0, reason: 'Paused time must not finish early');
        await guide.elapse(201);
        expect(
          guide.advances,
          1,
          reason: 'Short wobble retained earlier valid time',
        );
        await guide.close();
      },
    );

    testWidgets(
      '${left ? 'Left' : 'Right'} wrong-hand frame resets the final guide hold',
      (tester) async {
        final guide = _Guide(tester, left: left);
        await guide.mount(gestureTutorialSteps.first, 'fist');
        for (final ms in [0, 200, 400]) {
          await guide.frame(ms);
        }
        guide.wrongHand = true;
        await guide.frame(600);
        guide.wrongHand = false;
        for (final ms in [750, 950, 1150, 1350, 1550, 1750]) {
          await guide.frame(ms);
        }
        expect(
          guide.advances,
          0,
          reason: 'Wrong hand must lose the earlier progress',
        );
        await guide.frame(1950);
        await guide.elapse(201);
        expect(guide.advances, 1);
        await guide.close();
      },
    );

    testWidgets(
      '${left ? 'Left' : 'Right'} explicit release gate waits for an open hand',
      (tester) async {
        final guide = _Guide(tester, left: left)..score = .55;
        await guide.mount(
          videoTutorialSteps.firstWhere(
            (step) => step.socialAction == SocialTutorialAction.play,
          ),
          'play',
        );
        for (final ms in [0, 200, 400, 600, 800, 1000, 1200]) {
          await guide.frame(ms);
        }
        await guide.elapse(201);
        expect(guide.advances, 1);
        guide.requireRelease = true;
        await guide.mount(
          videoTutorialSteps.firstWhere(
            (step) => step.socialAction == SocialTutorialAction.pause,
          ),
          'pause',
        );
        for (final ms in [1600, 1800, 2000, 2200, 2400, 2600]) {
          await guide.frame(ms);
        }
        expect(guide.advances, 1);
        await guide.frame(2800);
        await guide.elapse(201);
        expect(guide.advances, 1, reason: 'A held punch cannot pass Pause');
        await guide.close();
      },
    );
  }

  testWidgets(
    'vertical outline margin accepts a small shift but rejects distant placement',
    (tester) async {
      final guide = _Guide(tester);
      await guide.mount(gestureTutorialSteps.first, 'fist');
      final bottom = (await tester.runAsync(
        () => _bottomOfOutline(guide.path),
      ))!;
      List<Offset> shifted(double offset) => [
        ...List.filled(13, bottom + Offset(0, offset)),
        ...List.filled(2, const Offset(.25, .25)),
        ...List.filled(2, const Offset(.75, .25)),
        ...List.filled(2, const Offset(.25, .8)),
        ...List.filled(2, const Offset(.75, .8)),
      ];
      guide.place(shifted(.12));
      for (final ms in [0, 300, 600, 900, 1200, 1500]) {
        await guide.frame(ms);
      }
      expect(guide.advances, 0);
      guide.place(shifted(.04));
      for (final ms in [1800, 2100, 2400, 2700, 3000]) {
        await guide.frame(ms);
      }
      await guide.elapse(201);
      expect(guide.advances, 1);
      await guide.close();
    },
  );
}
