import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/face_tracking/mouth_tracking.dart';
import 'mouth_motion_test.dart' show measurement;

/// Synthetic summaries only; no captured face/person measurements are fixtures.
Map<String, dynamic> calibrationFixture() => {
  'normal': {
    'samples': 30,
    'invalid': 0,
    'smileSamples': 30,
    'gapP95': .03,
    'widthMedian': .60,
    'smileP90': .02,
  },
  'smile': {
    'samples': 30,
    'invalid': 0,
    'smileSamples': 30,
    'smileP10': .50,
    'smileMedian': .70,
  },
  'talk': {'samples': 30, 'invalid': 0, 'smileSamples': 30, 'gapP95': .30},
};

void main() {
  test(
    'Saved check sets an individual neutral point and preserves speech range',
    () {
      final profile = MouthCalibration.fromCaptures(calibrationFixture())!;
      expect(profile.gapRest, closeTo(.038, 1e-10));
      expect(profile.gapFull, closeTo(.31, 1e-10));
      expect(profile.neutralWidth, .60);
      expect(profile.smileOn, closeTo(.26, 1e-10));
      expect(profile.smileOff, lessThan(profile.smileOn));
      final state = MouthMotionState()..applyCalibration(profile);
      void update(double gap, double smile) => state.update(
        measurement(gap: gap, width: .60, smile: smile),
        jawOpen: .8,
        jawValid: true,
      );
      for (final gap in [.01, .02, .03, .037]) {
        update(gap, .02);
        expect(state.motion.atRest, isTrue);
      }
      update(.15, .02);
      final low = state.motion.openness;
      update(.24, .02);
      final mid = state.motion.openness;
      update(.29, .02);
      final high = state.motion.openness;
      expect(low, lessThan(mid));
      expect(mid, lessThan(high));
      expect(high, lessThan(1));
      update(.12, .70);
      expect(state.motion.smile, 1);
      update(.01, .02);
      expect(state.motion.atRest, isTrue);
      state.reset(forgetNeutral: true);
      expect(state.neutralWidthRatio, .60);
      expect(state.calibration, same(profile));
      state.relearnNeutral();
      expect(state.neutralWidthRatio, .60);
    },
  );
  test('Calibration rejects incomplete, noisy or indistinguishable checks', () {
    expect(MouthCalibration.fromCaptures({}), isNull);
    final edits = [
      ['normal', 'samples', 9],
      ['normal', 'invalid', 30],
      ['smile', 'smileSamples', 2],
      ['normal', 'gapP95', .2],
      ['normal', 'widthMedian', double.nan],
      ['smile', 'smileP10', .05],
      ['talk', 'gapP95', .05],
      ['talk', 'gapP95', double.infinity],
    ];
    for (final edit in edits) {
      final raw = calibrationFixture();
      (raw[edit[0]] as Map)[edit[1]] = edit[2];
      expect(MouthCalibration.fromCaptures(raw), isNull, reason: '$edit');
    }
  });
  test(
    'A validated saved profile survives incomplete replacement captures',
    () {
      final profile = MouthCalibration.fromCaptures(calibrationFixture())!;
      final decoded = MouthCalibration.fromMap(profile.toMap())!;
      expect(decoded.gapRest, profile.gapRest);
      expect(decoded.smileFull, profile.smileFull);
      expect(
        MouthCalibration.fromMap({...profile.toMap(), 'gapFull': 0}),
        isNull,
      );
      expect(
        MouthCalibration.fromMap({...profile.toMap(), 'smileOn': 1}),
        isNull,
      );
      expect(
        MouthCalibration.fromMap({...profile.toMap(), 'algorithmVersion': 2}),
        isNull,
      );
    },
  );
}
