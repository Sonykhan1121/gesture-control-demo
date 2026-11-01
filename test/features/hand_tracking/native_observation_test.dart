import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

// Recorded by the real Android/YUV test runner from official MediaPipe photos.
// These are test fixtures, never captures of the user's camera.
void main() {
  final raw =
      jsonDecode(
            File(
              'test/fixtures/native-gesture-observations.json',
            ).readAsStringSync(),
          )
          as Map;
  HandObservation sample(String name) =>
      HandObservation.fromMap(Map<Object?, Object?>.from(raw[name] as Map));
  test(
    'Real native scores are preserved without inflating them to pass 80 percent',
    () {
      for (final entry in {
        'fist.jpg': HandPose.fist,
        'victory.jpg': HandPose.victory,
      }.entries) {
        final observation = sample(entry.key);
        final score = (raw[entry.key]['scores'] as Map).values.first as num;
        expect(
          gestureMatch(observation, entry.value),
          closeTo(score.toDouble(), .000001),
        );
        expect(gestureMatch(observation, entry.value), lessThan(.8));
      }
    },
  );
  test(
    'Thumb landmarks qualify independently without altering model score',
    () {
      final observation = sample('thumb_up.jpg');
      expect(observation.scoreFor('Thumb_Up'), lessThan(.8));
      expect(
        gestureMatch(observation, HandPose.thumbUp),
        greaterThanOrEqualTo(.8),
      );
      expect(gestureMatch(observation, HandPose.thumbDown), 0);
    },
  );
  test(
    'Thumb geometry supports both hands and opposite vertical directions',
    () {
      for (final mirror in [false, true]) {
        for (final down in [false, true]) {
          final data = Map<Object?, Object?>.from(raw['thumb_up.jpg'] as Map);
          data['scores'] = <String, double>{};
          data['gesture'] = 'None';
          data['points'] = (data['points'] as List).map((point) {
            final values = point as List;
            var x = (values[0] as num).toDouble();
            var y = (values[1] as num).toDouble();
            if (down) {
              x = 1 - x;
              y = 1 - y;
            }
            if (mirror) x = 1 - x;
            return [x, y];
          }).toList();
          final observation = HandObservation.fromMap(data);
          expect(
            gestureMatch(
              observation,
              down ? HandPose.thumbDown : HandPose.thumbUp,
            ),
            greaterThanOrEqualTo(.8),
          );
          expect(
            gestureMatch(
              observation,
              down ? HandPose.thumbUp : HandPose.thumbDown,
            ),
            0,
          );
        }
      }
    },
  );
  test('Natural bent/foreshortened thumb does not need sideways spread', () {
    final data = Map<Object?, Object?>.from(raw['thumb_up.jpg'] as Map);
    data['scores'] = <String, double>{};
    data['gesture'] = 'None';
    final points = (data['points'] as List)
        .map((p) => List<num>.from(p as List))
        .toList();
    final width = (data['width'] as num).toDouble();
    final height = (data['height'] as num).toDouble();
    // ~150-degree joint, ~0.71 palm-width extension, tip above index knuckle:
    // reproduces the projection rejected by the previous device build.
    points[2] = [208 / width, 195 / height];
    points[3] = [201 / width, 160 / height];
    points[4] = [210 / width, 133 / height];
    data['points'] = points;
    final hand = HandObservation.fromMap(data);
    expect(gestureMatch(hand, HandPose.thumbUp), greaterThanOrEqualTo(.8));
    expect(gestureMatch(hand, HandPose.thumbDown), 0);
  });
  test('Sideways thumb and an extended index cannot pass thumb geometry', () {
    final data = Map<Object?, Object?>.from(raw['thumb_up.jpg'] as Map);
    data['scores'] = <String, double>{};
    data['gesture'] = 'None';
    data['points'] = (data['points'] as List).map((point) {
      final values = point as List;
      return [values[1], 1 - (values[0] as num).toDouble()];
    }).toList();
    final sideways = HandObservation.fromMap(data);
    expect(gestureMatch(sideways, HandPose.thumbUp), lessThan(.55));
    expect(gestureMatch(sideways, HandPose.thumbDown), lessThan(.55));
    expect(
      gestureMatch(sample('pointing_up.jpg'), HandPose.thumbUp),
      lessThan(.55),
    );
  });
  test('Real pointing landmarks match up and reject opposite directions', () {
    final observation = sample('pointing_up.jpg');
    expect(
      gestureMatch(observation, HandPose.pointUp),
      greaterThanOrEqualTo(.8),
    );
    expect(gestureMatch(observation, HandPose.pointDown), 0);
    expect(gestureMatch(observation, HandPose.pointLeft), 0);
    expect(gestureMatch(observation, HandPose.pointRight), 0);
  });
  test('Real back-of-hand photo matches Dorsal and rejects Open Palm', () {
    final observation = sample('right_hands.jpg');
    expect(
      gestureMatch(observation, HandPose.dorsal),
      greaterThanOrEqualTo(.8),
    );
    expect(gestureMatch(observation, HandPose.openPalm), 0);
  });
  test('real mirrored observations complete only for their physical hand', () {
    for (final entry in {
      'pointing_up.jpg': 'Right',
      'left_pointing_up.jpg': 'Left',
    }.entries) {
      final observation = sample(entry.key);
      expect(observation.mirrored, isTrue);
      expect(observation.physicalHand, entry.value);
      expect(observation.handScore, greaterThanOrEqualTo(.8));
      final start = DateTime(2026);
      for (final selected in ['Left', 'Right']) {
        final feedback = GestureFeedback(
          HandPose.pointUp,
          selectedHand: selected,
        );
        for (final ms in [0, 500, 1000, 1500, 2000]) {
          feedback.update(observation, start.add(Duration(milliseconds: ms)));
        }
        expect(
          feedback.ready,
          selected == entry.value,
          reason: '${entry.key}: only the selected physical hand qualifies',
        );
        expect(feedback.isMatching, selected == entry.value);
        if (selected != entry.value) expect(feedback.confidence, 0);
      }
    }
  });
  test('Real no-hand observations cannot match any tutorial pose', () {
    for (final pose in HandPose.values) {
      expect(gestureMatch(sample('cat.jpg'), pose), 0);
    }
  });
}
