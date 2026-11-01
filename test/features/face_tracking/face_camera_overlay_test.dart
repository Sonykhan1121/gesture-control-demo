import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/face_camera_overlay.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';

void main() {
  for (final viewport in [
    const Size(402, 874),
    const Size(874, 402),
    const Size(800, 1333),
    const Size(1333, 800),
  ]) {
    testWidgets(
      'overlay retains Home size as face depth changes at $viewport',
      (t) async {
        t.view.physicalSize = viewport;
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        for (final height in [.2, .6]) {
          await t.pumpWidget(
            MaterialApp(
              home: Center(
                child: SizedBox(
                  width: 300,
                  height: 300,
                  child: FaceCameraOverlay(
                    face: FaceObservation(
                      center: const Offset(.5, .5),
                      confidence: .9,
                      faceHeight: height,
                      imageSize: const Size(480, 640),
                    ),
                    viewport: viewport,
                    avatar: const ColoredBox(color: Colors.blue),
                  ),
                ),
              ),
            ),
          );
          final positioned = t.widget<Positioned>(
            find.descendant(
              of: find.byType(FaceCameraOverlay),
              matching: find.byType(Positioned),
            ),
          );
          expect(positioned.width, homeFaceSize(viewport).width);
          expect(positioned.height, homeFaceSize(viewport).height);
          expect(positioned.left! + positioned.width! / 2, 150);
          expect(positioned.top! + positioned.height! / 2, 150);
        }
      },
    );
  }
  test('both faces preserve proportions and reserve two-axis travel', () {
    for (final viewport in [
      const Size(402, 874),
      const Size(874, 402),
      const Size(800, 1333),
      const Size(1333, 800),
    ]) {
      final original = homeFaceSize(viewport, following: true);
      final second = homeFaceSize(viewport, happy: true, following: true);
      expect(second.width, greaterThan(original.width));
      expect(
        second.width,
        lessThanOrEqualTo((viewport.width - 36) * .7 + .001),
      );
      expect(
        second.height,
        lessThanOrEqualTo((viewport.height - 36) * .7 + .001),
      );
      expect(
        original.width,
        lessThanOrEqualTo((viewport.width - 36) * .6 + .001),
      );
      expect(
        original.height,
        lessThanOrEqualTo((viewport.height - 36) * .6 + .001),
      );
      expect(second.width / second.height, closeTo(312 / 200, .001));
      expect(homeFaceSize(viewport, happy: false, following: true), original);
    }
    expect(
      homeFaceSize(const Size(402, 874), following: true).width,
      closeTo(219.6, .001),
    );
    expect(
      homeFaceSize(const Size(402, 874), happy: true, following: true).width,
      closeTo(256.2, .001),
    );
  });
  test('non-following Home modes retain their existing artwork size', () {
    expect(
      homeFaceSize(const Size(402, 874), following: false).width,
      closeTo(281.4, .001),
    );
    expect(
      homeFaceSize(const Size(402, 874), happy: true, following: false).width,
      closeTo(366, .001),
    );
    expect(
      homeFaceSize(const Size(874, 402), following: false).width,
      closeTo(351.1872, .001),
    );
    expect(
      homeFaceSize(const Size(874, 402), happy: true, following: false).width,
      closeTo(491.66208, .001),
    );
  });
  test(
    'landmark projection shares camera contain letterboxing in both orientations',
    () {
      const image = Size(480, 640);
      expect(
        faceOverlayPoint(const Offset(.5, .5), image, const Size(400, 400)),
        const Offset(200, 200),
      );
      expect(
        faceOverlayPoint(Offset.zero, image, const Size(400, 400)),
        const Offset(50, 0),
      );
      expect(
        faceOverlayPoint(const Offset(1, 1), image, const Size(400, 400)),
        const Offset(350, 400),
      );
      expect(
        faceOverlayPoint(
          Offset.zero,
          const Size(640, 480),
          const Size(400, 400),
        ),
        const Offset(0, 50),
      );
      expect(
        faceOverlayPoint(
          const Offset(1, 1),
          const Size(640, 480),
          const Size(400, 400),
        ),
        const Offset(400, 350),
      );
    },
  );
}
