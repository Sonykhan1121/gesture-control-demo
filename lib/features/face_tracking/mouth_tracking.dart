import 'dart:math' as math;
import 'dart:ui';

/// Landmarks ordered as 61,291,13,14,0,17,33,263 in the upright mirrored image.
/// Distances are measured in pixels and in the mouth's own axes, so camera
/// aspect ratio, scale and head roll do not masquerade as opening/width changes.
class MouthMeasurement {
  const MouthMeasurement({
    required this.points,
    required this.imageSize,
    required this.gapRatio,
    required this.widthRatio,
    required this.smileScore,
    required this.smileValid,
  });
  final List<Offset> points;
  final Size imageSize;
  final double gapRatio, widthRatio, smileScore;
  final bool smileValid;

  static MouthMeasurement? fromNative(Map<Object?, Object?> data, Size size) {
    final raw = data['mouthLandmarks'];
    if (data['mouthGeometryValid'] != true ||
        raw is! List ||
        raw.length != 8 ||
        !size.width.isFinite ||
        !size.height.isFinite ||
        size.isEmpty) {
      return null;
    }
    final points = <Offset>[];
    for (final entry in raw) {
      if (entry is! List ||
          entry.length != 2 ||
          entry.any((v) => v is! num || !v.isFinite || v < 0 || v > 1)) {
        return null;
      }
      points.add(
        Offset((entry[0] as num).toDouble(), (entry[1] as num).toDouble()),
      );
    }
    final p = points
        .map((v) => Offset(v.dx * size.width, v.dy * size.height))
        .toList();
    final left = p[0].dx < p[1].dx ? p[0] : p[1];
    final right = p[0].dx < p[1].dx ? p[1] : p[0];
    final mouthWidth = (right - left).distance;
    final eyeWidth = (p[7] - p[6]).distance;
    if (mouthWidth < 2 || eyeWidth < 2) return null;
    final axis = (right - left) / mouthWidth;
    final down = Offset(-axis.dy, axis.dx);
    final lipGap = p[3] - p[2];
    final gap =
        math.max(0.0, lipGap.dx * down.dx + lipGap.dy * down.dy) / mouthWidth;
    final width = mouthWidth / eyeWidth;
    if (gap > 1 || width < .1 || width > 1.5) return null;
    final smile = data['mouthSmile'];
    final smileValid =
        data['mouthSmileValid'] == true &&
        smile is num &&
        smile.isFinite &&
        smile >= 0 &&
        smile <= 1;
    return MouthMeasurement(
      points: List.unmodifiable(points),
      imageSize: size,
      gapRatio: gap,
      widthRatio: width,
      smileScore: smileValid ? smile.toDouble() : 0,
      smileValid: smileValid,
    );
  }
}

class MouthMotion {
  const MouthMotion({this.openness = 0, this.smile = 0, this.widthScale = 1});
  final double openness, smile, widthScale;
  bool get atRest => openness == 0 && smile == 0 && widthScale == 1;
  static MouthMotion lerp(MouthMotion a, MouthMotion b, double t) =>
      MouthMotion(
        openness: lerpDouble(a.openness, b.openness, t)!,
        smile: lerpDouble(a.smile, b.smile, t)!,
        widthScale: lerpDouble(a.widthScale, b.widthScale, t)!,
      );
}

/// Initial tuning values are visible in diagnostics and require live testing.
abstract final class MouthTuning {
  static const smileOn = .45, smileOff = .28;
  static const gapRest = .008, gapFull = .22;
  static const defaultWidthRatio = .65;
}

/// Per-user tuning derived from a completed, explicit Normal/Smile/Talk check.
/// Retaining the original summaries makes every derived threshold inspectable.
class MouthCalibration {
  const MouthCalibration({
    required this.gapRest,
    required this.gapFull,
    required this.neutralWidth,
    required this.smileOn,
    required this.smileOff,
    required this.smileFull,
  });
  final double gapRest, gapFull, neutralWidth, smileOn, smileOff, smileFull;

  static MouthCalibration? fromMap(Object? raw) {
    if (raw is! Map || raw['algorithmVersion'] != 1) return null;
    const keys = [
      'gapRest',
      'gapFull',
      'neutralWidth',
      'smileOn',
      'smileOff',
      'smileFull',
    ];
    if (keys.any((key) => raw[key] is! num || !(raw[key] as num).isFinite)) {
      return null;
    }
    double get(String key) => (raw[key] as num).toDouble();
    final rest = get('gapRest'),
        full = get('gapFull'),
        width = get('neutralWidth'),
        on = get('smileOn'),
        off = get('smileOff'),
        smileFull = get('smileFull');
    if (rest < 0 ||
        full > 1 ||
        full - rest < .04 ||
        width < .1 ||
        width > 1.5 ||
        off < 0 ||
        on <= off ||
        smileFull <= on ||
        smileFull > 1) {
      return null;
    }
    return MouthCalibration(
      gapRest: rest,
      gapFull: full,
      neutralWidth: width,
      smileOn: on,
      smileOff: off,
      smileFull: smileFull,
    );
  }

  static MouthCalibration? fromCaptures(Object? raw) {
    if (raw is! Map) return null;
    final rows = <String, Map>{};
    for (final phase in ['normal', 'smile', 'talk']) {
      final row = raw[phase];
      if (row is! Map) return null;
      final count = row['samples'],
          invalid = row['invalid'],
          smileCount = row['smileSamples'];
      if (count is! num ||
          !count.isFinite ||
          count < 10 ||
          invalid is! num ||
          !invalid.isFinite ||
          invalid < 0 ||
          invalid / (count + invalid) > .25 ||
          smileCount is! num ||
          !smileCount.isFinite ||
          smileCount < 10 ||
          smileCount > count) {
        return null;
      }
      rows[phase] = row;
    }
    double? value(String phase, String key) {
      final v = rows[phase]![key];
      return v is num && v.isFinite && v >= 0 && v <= 1.5 ? v.toDouble() : null;
    }

    final rest = value('normal', 'gapP95'),
        full = value('talk', 'gapP95'),
        width = value('normal', 'widthMedian'),
        neutralSmile = value('normal', 'smileP90'),
        smiling = value('smile', 'smileP10'),
        smileFull = value('smile', 'smileMedian');
    if (rest == null ||
        full == null ||
        width == null ||
        neutralSmile == null ||
        smiling == null ||
        smileFull == null ||
        rest > .12 ||
        width < .1 ||
        neutralSmile > .25 ||
        smiling - neutralSmile < .10 ||
        full < rest + .06 ||
        smileFull < smiling ||
        smileFull > 1 ||
        full > .8) {
      return null;
    }
    final on = (neutralSmile + smiling) / 2;
    final off = neutralSmile + (on - neutralSmile) * .45;
    return MouthCalibration(
      gapRest: rest + .008,
      gapFull: full + .01,
      neutralWidth: width,
      smileOn: on,
      smileOff: off,
      smileFull: smileFull,
    );
  }

  Map<String, Object> toMap() => {
    'algorithmVersion': 1,
    'gapRest': gapRest,
    'gapFull': gapFull,
    'neutralWidth': neutralWidth,
    'smileOn': smileOn,
    'smileOff': smileOff,
    'smileFull': smileFull,
  };
}

class MouthMotionState {
  MouthMotion motion = const MouthMotion();
  double neutralWidthRatio = MouthTuning.defaultWidthRatio;
  int neutralSamples = 0;
  bool _smiling = false;
  MouthCalibration? calibration;
  String source = 'Waiting';
  String get expression => motion.smile > 0
      ? (motion.openness > .04 ? 'Smile + open' : 'Smiling')
      : (motion.openness > .04 ? 'Open / moving' : 'Normal');

  void update(
    MouthMeasurement? measured, {
    required double jawOpen,
    required bool jawValid,
  }) {
    if (measured == null) {
      _smiling = false;
      final valid =
          jawValid && jawOpen.isFinite && jawOpen >= 0 && jawOpen <= 1;
      motion = MouthMotion(
        openness: valid ? ((jawOpen - .04) / .51).clamp(0.0, 1.0) : 0,
      );
      source = valid
          ? 'Jaw fallback (lip landmarks missing)'
          : 'Mouth unavailable';
      return;
    }
    // Learn only clearly closed, neutral frames, never speech or a smile.
    if (calibration == null &&
        neutralSamples < 12 &&
        measured.gapRatio <= MouthTuning.gapRest &&
        measured.smileValid &&
        measured.smileScore < .20) {
      final total = neutralWidthRatio * neutralSamples + measured.widthRatio;
      neutralSamples++;
      neutralWidthRatio = total / neutralSamples;
    }
    final on = calibration?.smileOn ?? MouthTuning.smileOn;
    final off = calibration?.smileOff ?? MouthTuning.smileOff;
    final smileLow = calibration?.smileOff ?? .20;
    final smileHigh = calibration?.smileFull ?? .65;
    _smiling =
        measured.smileValid &&
        (measured.smileScore >= on || (_smiling && measured.smileScore > off));
    final smile = _smiling
        ? ((measured.smileScore - smileLow) / (smileHigh - smileLow)).clamp(
            0.0,
            1.0,
          )
        : 0.0;
    var width = (measured.widthRatio / neutralWidthRatio).clamp(.68, 1.28);
    if ((width - 1).abs() < .04) width = 1;
    motion = MouthMotion(
      openness:
          ((measured.gapRatio - (calibration?.gapRest ?? MouthTuning.gapRest)) /
                  ((calibration?.gapFull ?? MouthTuning.gapFull) -
                      (calibration?.gapRest ?? MouthTuning.gapRest)))
              .clamp(0.0, 1.0),
      smile: smile,
      widthScale: width,
    );
    source = calibration == null
        ? 'Lip landmarks'
        : 'Lip landmarks · saved tuning';
  }

  void applyCalibration(MouthCalibration value) {
    calibration = value;
    reset(forgetNeutral: true);
  }

  void relearnNeutral() {
    neutralSamples = calibration == null ? 0 : 12;
    neutralWidthRatio =
        calibration?.neutralWidth ?? MouthTuning.defaultWidthRatio;
  }

  void reset({bool forgetNeutral = false}) {
    motion = const MouthMotion();
    _smiling = false;
    source = 'Waiting';
    if (forgetNeutral) relearnNeutral();
  }
}
