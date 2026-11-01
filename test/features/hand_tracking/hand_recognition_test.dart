import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';

void main() {
  HandObservation fist(double score) => HandObservation(
    points: List.filled(21, const Offset(.5, .5)),
    imageSize: const Size(480, 640),
    fistScore: score,
    gesture: 'Closed_Fist',
  );
  test(
    'Fist readiness requires fresh consecutive confident camera matches',
    () {
      final feedback = FistFeedback();
      final start = DateTime(2026);
      expect(feedback.update(fist(.9), start), 'Hold your fist steady');
      expect(feedback.ready, isFalse);
      feedback.update(fist(.91), start.add(const Duration(milliseconds: 500)));
      expect(
        feedback.update(fist(.92), start.add(const Duration(seconds: 1))),
        'Fist detected',
      );
      expect(feedback.ready, isTrue);
      expect(
        feedback.update(
          const HandObservation(),
          start.add(const Duration(milliseconds: 1200)),
        ),
        'Show your hand to the camera',
      );
      expect(feedback.ready, isFalse);
      feedback.update(fist(.9), start.add(const Duration(seconds: 2)));
      feedback.update(fist(.9), start.add(const Duration(seconds: 4)));
      expect(
        feedback.ready,
        isFalse,
        reason: 'A missing-frame gap cannot count as holding the pose',
      );
      feedback.update(fist(.6), start.add(const Duration(milliseconds: 4200)));
      expect(feedback.ready, isFalse);
    },
  );
  test('Fist readiness needs at least 80 percent for a full steady second', () {
    final feedback = FistFeedback();
    final start = DateTime(2026);
    for (final milliseconds in [0, 500, 1000]) {
      feedback.update(
        fist(.7999),
        start.add(Duration(milliseconds: milliseconds)),
      );
      expect(feedback.ready, isFalse);
    }
    for (final milliseconds in [1100, 1600, 2099]) {
      feedback.update(
        fist(.8),
        start.add(Duration(milliseconds: milliseconds)),
      );
      expect(feedback.ready, isFalse);
    }
    feedback.update(fist(.8), start.add(const Duration(milliseconds: 2100)));
    expect(feedback.ready, isTrue);
    feedback.update(fist(.79), start.add(const Duration(milliseconds: 2200)));
    expect(feedback.ready, isFalse);
    feedback.update(fist(.9), start.add(const Duration(milliseconds: 2300)));
    feedback.update(fist(.9), start.add(const Duration(milliseconds: 2800)));
    expect(
      feedback.ready,
      isFalse,
      reason: 'A confidence dip restarts the hold',
    );
    feedback.update(fist(.9), start.add(const Duration(milliseconds: 3300)));
    expect(feedback.ready, isTrue);
  });
  test('Hand landmarks align with the camera center cover crop', () {
    expect(
      handPointOnPreview(
        const Offset(.5, .5),
        const Size(480, 640),
        const Size(362, 358),
      ),
      const Offset(181, 179),
    );
    final left = handPointOnPreview(
      const Offset(0, .5),
      const Size(480, 640),
      const Size(362, 358),
    );
    expect(left.dx, closeTo(0, .001));
    final top = handPointOnPreview(
      const Offset(.5, 0),
      const Size(480, 640),
      const Size(362, 358),
    );
    expect(
      top.dy,
      lessThan(0),
      reason: 'Cover crops the top and bottom, not the overlay scale',
    );
  });
  test(
    'native mirror metadata resolves the physical hand without changing geometry labels',
    () {
      for (final mirrored in [false, true]) {
        for (final rawHand in ['Left', 'Right']) {
          final observation = HandObservation.fromMap({
            'points': List.generate(21, (_) => [.2, .3, 0]),
            'width': 480,
            'height': 640,
            'hand': rawHand,
            'handScore': .97,
            'mirrored': mirrored,
          });
          expect(observation.hand, rawHand);
          expect(observation.handScore, .97);
          expect(
            observation.physicalHand,
            mirrored ? (rawHand == 'Left' ? 'Right' : 'Left') : rawHand,
          );
        }
      }
      expect(
        const HandObservation(hand: 'Unknown', mirrored: true).physicalHand,
        '',
      );
      expect(const HandObservation().handScore, 0);
    },
  );

  test(
    'Native observations preserve real confidence and missing-hand state',
    () {
      final observation = HandObservation.fromMap({
        'points': List.generate(21, (_) => [.2, .3, 0]),
        'width': 480,
        'height': 640,
        'fistScore': .87,
        'gesture': 'Closed_Fist',
      });
      expect(observation.hasHand, isTrue);
      expect(observation.fistScore, .87);
      expect(observation.points.first, const Offset(.2, .3));
      expect(const HandObservation().hasHand, isFalse);
    },
  );
}
