import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/tutorials/gesture_hold.dart';

void main() {
  final start = DateTime(2026);
  DateTime at(int ms) => start.add(Duration(milliseconds: ms));

  for (final duration in [800, 1000, 1200]) {
    test(
      '$duration ms requires matching frames through the exact hold boundary',
      () {
        final hold = GestureHold(Duration(milliseconds: duration));
        for (var ms = 0; ms < duration; ms += 200) {
          hold.update(at(ms), matches: true);
          expect(hold.ready, isFalse);
        }
        hold.update(at(duration - 1), matches: true);
        expect(hold.ready, isFalse);
        hold.update(at(duration), matches: true);
        expect(hold.ready, isTrue);
      },
    );

    test(
      '$duration ms pauses a short wobble without counting failed or recovery time',
      () {
        final hold = GestureHold(Duration(milliseconds: duration));
        for (final ms in [0, 200, 400]) {
          hold.update(at(ms), matches: true);
        }
        final earned = hold.progress;
        hold.update(at(550), matches: false);
        expect(hold.progress, earned);
        expect(hold.ready, isFalse);
        hold.update(at(700), matches: true);
        expect(
          hold.progress,
          earned,
          reason: 'Recovery interval earns no time',
        );
        for (var ms = 900; ms <= duration + 100; ms += 200) {
          hold.update(at(ms), matches: true);
          expect(hold.ready, isFalse);
        }
        hold.update(at(duration + 300), matches: true);
        expect(
          hold.ready,
          isTrue,
          reason: 'The 300ms interruption was excluded',
        );
      },
    );
  }

  test(
    'Hand practice keeps progress through a 300ms wobble without counting it',
    () {
      final hold = GestureHold(
        const Duration(milliseconds: 800),
        wobbleGrace: const Duration(milliseconds: 350),
      );
      hold.update(at(0), matches: true);
      hold.update(at(400), matches: true);
      hold.update(at(500), matches: false);
      expect(hold.expire(at(800)), isFalse);
      hold.update(at(800), matches: true);
      expect(hold.progress, .5);
      hold.update(at(1199), matches: true);
      expect(hold.ready, isFalse);
      hold.update(at(1200), matches: true);
      expect(hold.ready, isTrue);
    },
  );

  test('Wobble timeout resets even without another camera frame', () {
    final hold = GestureHold(const Duration(seconds: 1));
    hold.update(at(0), matches: true);
    hold.update(at(400), matches: true);
    hold.update(at(500), matches: false);
    expect(hold.expire(at(700)), isFalse);
    expect(hold.expire(at(701)), isTrue);
    expect(hold.progress, 0);
    hold.update(at(702), matches: true);
    expect(hold.progress, 0);
    expect(hold.ready, isFalse);
  });

  test(
    'Wrong/missing hand immediately cancels progress instead of pausing',
    () {
      final hold = GestureHold(const Duration(seconds: 1));
      hold.update(at(0), matches: true);
      hold.update(at(500), matches: true);
      hold.update(at(600), matches: false, allowPause: false);
      expect(hold.progress, 0);
      hold.update(at(700), matches: true);
      expect(hold.progress, 0);
      expect(hold.ready, isFalse);
    },
  );

  test('Repeated mismatches cannot extend the grace or complete a hold', () {
    final hold = GestureHold(const Duration(seconds: 1));
    hold.update(at(0), matches: true);
    hold.update(at(500), matches: true);
    for (var ms = 600; ms <= 1600; ms += 100) {
      hold.update(at(ms), matches: false);
      expect(hold.ready, isFalse);
    }
    expect(hold.progress, 0);
  });

  test('Stale observations or a reversed clock cannot add hold time', () {
    for (final next in [1001, 399]) {
      final hold = GestureHold(const Duration(seconds: 1));
      hold.update(at(0), matches: true);
      hold.update(at(400), matches: true);
      hold.update(at(next), matches: true);
      expect(hold.progress, 0);
      expect(hold.ready, isFalse);
    }
  });
}
