import 'dart:convert';

/// Personal expression-score range, not eyelid size or a biometric identity.
class EyeBlinkProfile {
  /// Last user-measured profile, explicitly requested as the fixed app default.
  /// Bundled in code so a clean reinstall does not request calibration again.
  static const lastMeasured = EyeBlinkProfile(
    0.5174492001533508,
    0.699134886264801,
    0.6775257587432861,
    0.822638988494873,
  );

  const EyeBlinkProfile(
    this.leftOpen,
    this.leftClosed,
    this.rightOpen,
    this.rightClosed,
  );
  final double leftOpen, leftClosed, rightOpen, rightClosed;

  bool get isValid =>
      [
        leftOpen,
        leftClosed,
        rightOpen,
        rightClosed,
      ].every((v) => v.isFinite && v >= 0 && v <= 1) &&
      leftClosed - leftOpen >= .12 &&
      rightClosed - rightOpen >= .12;

  double normalized(double value, {required bool left}) {
    final open = left ? leftOpen : rightOpen;
    final closed = left ? leftClosed : rightClosed;
    return ((value - open) / (closed - open)).clamp(0.0, 1.0);
  }

  String encode() => jsonEncode({
    'version': 1,
    'values': [leftOpen, leftClosed, rightOpen, rightClosed],
  });

  static EyeBlinkProfile? decode(String? source) {
    try {
      final data = jsonDecode(source!);
      if (data is! Map || data['version'] != 1) return null;
      final values = data['values'];
      if (values is! List ||
          values.length != 4 ||
          values.any((v) => v is! num)) {
        return null;
      }
      final p = EyeBlinkProfile(
        (values[0] as num).toDouble(),
        (values[1] as num).toDouble(),
        (values[2] as num).toDouble(),
        (values[3] as num).toDouble(),
      );
      return p.isValid ? p : null;
    } catch (_) {
      return null;
    }
  }
}

enum EyeCalibrationStage {
  introduction,
  open,
  closePrompt,
  closed,
  failed,
  complete,
}

/// Only continuous valid observations count. Normal blinks are filtered from
/// open samples by the lower quartile; closed samples use the upper quartile.
class EyeCalibration {
  EyeCalibrationStage stage = EyeCalibrationStage.introduction;
  final _left = <double>[], _right = <double>[];
  Duration? _started, _last;
  double? _leftOpen, _rightOpen;
  EyeBlinkProfile? profile;
  double progress = 0;

  void startOpen() {
    stage = EyeCalibrationStage.open;
    _clear();
  }

  void startClosed() {
    stage = EyeCalibrationStage.closed;
    _clear();
  }

  void _clear() {
    _left.clear();
    _right.clear();
    _started = _last = null;
    progress = 0;
  }

  void interrupt() {
    if (stage == EyeCalibrationStage.open ||
        stage == EyeCalibrationStage.closed) {
      _clear();
    }
  }

  void sample(double left, double right, Duration now, {required bool valid}) {
    if (stage != EyeCalibrationStage.open &&
        stage != EyeCalibrationStage.closed) {
      return;
    }
    if (!valid ||
        !left.isFinite ||
        !right.isFinite ||
        left < 0 ||
        left > 1 ||
        right < 0 ||
        right > 1) {
      interrupt();
      return;
    }
    if (_last != null && now - _last! > const Duration(milliseconds: 500)) {
      _clear();
    }
    _started ??= now;
    _last = now;
    final elapsed = now - _started!;
    // Time to react to the prompt before collecting the two-second sample.
    const settling = Duration(milliseconds: 700);
    if (elapsed < settling) return;
    _left.add(left);
    _right.add(right);
    progress = ((elapsed - settling).inMilliseconds / 2000).clamp(0.0, 1.0);
    if (progress < 1 || _left.length < 8) return;
    if (stage == EyeCalibrationStage.open) {
      _leftOpen = _quantile(_left, .25);
      _rightOpen = _quantile(_right, .25);
      stage = EyeCalibrationStage.closePrompt;
    } else {
      final result = EyeBlinkProfile(
        _leftOpen!,
        _quantile(_left, .75),
        _rightOpen!,
        _quantile(_right, .75),
      );
      profile = result.isValid ? result : null;
      stage = profile != null
          ? EyeCalibrationStage.complete
          : EyeCalibrationStage.failed;
    }
  }

  double _quantile(List<double> values, double fraction) {
    final sorted = [...values]..sort();
    return sorted[((sorted.length - 1) * fraction).round()];
  }
}
