import 'dart:ui';

/// Independent eyelid geometry plus the unmodified native classifier outputs.
class EyeMeasurement {
  const EyeMeasurement({
    required this.points,
    required this.imageSize,
    required this.rawLeft,
    required this.rawRight,
    required this.screenLeftFromRight,
    required this.leftAperture,
    required this.rightAperture,
  });
  final List<Offset> points;
  final Size imageSize;
  final double rawLeft, rawRight, leftAperture, rightAperture;
  final bool screenLeftFromRight;

  static EyeMeasurement? fromNative(Map<Object?, Object?> data, Size size) {
    final raw = data['eyeLandmarks'],
        left = data['eyeBlinkNativeLeft'],
        right = data['eyeBlinkNativeRight'];
    if (data['eyeDebugValid'] != true ||
        raw is! List ||
        raw.length != 8 ||
        left is! num ||
        right is! num ||
        !left.isFinite ||
        !right.isFinite ||
        left < 0 ||
        left > 1 ||
        right < 0 ||
        right > 1 ||
        data['screenLeftFromRight'] is! bool ||
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
    double? aperture(int base) {
      final a = p[base].dx < p[base + 1].dx ? p[base] : p[base + 1];
      final b = p[base].dx < p[base + 1].dx ? p[base + 1] : p[base];
      final width = (b - a).distance;
      if (width < 2) return null;
      final axis = (b - a) / width;
      final gap = p[base + 3] - p[base + 2];
      return ((-axis.dy * gap.dx + axis.dx * gap.dy) / width).clamp(0.0, 1.0);
    }

    final first = aperture(0), second = aperture(4);
    if (first == null || second == null) return null;
    final firstOnLeft = (p[0].dx + p[1].dx) < (p[4].dx + p[5].dx);
    return EyeMeasurement(
      points: List.unmodifiable(points),
      imageSize: size,
      rawLeft: left.toDouble(),
      rawRight: right.toDouble(),
      screenLeftFromRight: data['screenLeftFromRight'] as bool,
      leftAperture: firstOnLeft ? first : second,
      rightAperture: firstOnLeft ? second : first,
    );
  }
}

class EyeDebugSample {
  const EyeDebugSample({
    required this.measured,
    required this.screenLeft,
    required this.screenRight,
    required this.normalizedLeft,
    required this.normalizedRight,
    required this.leftClosed,
    required this.rightClosed,
    required this.latencyMs,
    this.usesLidGap = false,
  });
  final EyeMeasurement measured;
  final double screenLeft, screenRight, normalizedLeft, normalizedRight;
  final bool leftClosed, rightClosed;
  final bool usesLidGap;
  final int latencyMs;
}

enum EyeCheckPhase { normal, leftClosed, rightClosed, bothClosed }

/// One guided check; it measures the current behavior without changing it.
class EyeDiagnosticCheck {
  bool running = false;
  int _index = 0, invalid = 0;
  Duration? _readyAt, _started;
  final Map<String, List<double>> _values = {};
  int _leftClosed = 0, _rightClosed = 0, _rightMapping = 0;
  final Map<String, Map<String, Object>> history = {};
  EyeCheckPhase get phase => EyeCheckPhase.values[_index];
  int get step => _index + 1;
  bool get measuring => running && _started != null;
  bool get preparing => running && _readyAt != null;
  int get samples => _values['rawLeft']?.length ?? 0;
  String get instruction => switch (phase) {
    EyeCheckPhase.normal => 'Look normally at the camera',
    EyeCheckPhase.leftClosed => 'Close only YOUR LEFT eye',
    EyeCheckPhase.rightClosed => 'Close only YOUR RIGHT eye',
    EyeCheckPhase.bothClosed => 'Close both eyes for 5 seconds, then open',
  };
  int secondsLeft(Duration now) => preparing
      ? ((_readyAt! - now).inMilliseconds / 1000).ceil().clamp(0, 2)
      : _started == null
      ? 0
      : (3 - (now - _started!).inMilliseconds / 1000).ceil().clamp(0, 3);
  void start(Duration now) {
    running = true;
    _index = 0;
    history.clear();
    _readyAt = now + const Duration(seconds: 2);
    _started = null;
    _clear();
  }

  void _clear() {
    _values.clear();
    invalid = _leftClosed = _rightClosed = _rightMapping = 0;
  }

  void add(EyeDebugSample? sample) {
    if (!measuring) return;
    if (sample == null) {
      invalid++;
      return;
    }
    final values = {
      'rawLeft': sample.measured.rawLeft,
      'rawRight': sample.measured.rawRight,
      'screenLeft': sample.screenLeft,
      'screenRight': sample.screenRight,
      'normalizedLeft': sample.normalizedLeft,
      'normalizedRight': sample.normalizedRight,
      'apertureLeft': sample.measured.leftAperture,
      'apertureRight': sample.measured.rightAperture,
      'latencyMs': sample.latencyMs.toDouble(),
    };
    values.forEach((key, value) => (_values[key] ??= []).add(value));
    if (sample.leftClosed) _leftClosed++;
    if (sample.rightClosed) _rightClosed++;
    if (sample.measured.screenLeftFromRight) _rightMapping++;
  }

  bool tick(Duration now) {
    if (!running) return false;
    if (preparing && now >= _readyAt!) {
      _readyAt = null;
      _started = now;
      _clear();
    }
    if (!measuring || now - _started! < const Duration(seconds: 3)) {
      return false;
    }
    final count = samples;
    history[phase.name] = {
      'samples': count,
      'invalid': invalid,
      for (final entry in _values.entries) entry.key: _stats(entry.value),
      'leftClosedFraction': count == 0 ? 0 : _leftClosed / count,
      'rightClosedFraction': count == 0 ? 0 : _rightClosed / count,
      'screenLeftFromRightFraction': count == 0 ? 0 : _rightMapping / count,
    };
    _started = null;
    if (_index == 3) {
      running = false;
    } else {
      _index++;
      _readyAt = now + const Duration(seconds: 2);
    }
    return true;
  }

  Map<String, double> _stats(List<double> values) {
    final sorted = List<double>.of(values)..sort();
    double q(double fraction) {
      final at = (sorted.length - 1) * fraction;
      final lo = at.floor(), hi = at.ceil();
      return sorted[lo] + (sorted[hi] - sorted[lo]) * (at - lo);
    }

    return {
      'min': sorted.first,
      'p10': q(.1),
      'median': q(.5),
      'p90': q(.9),
      'max': sorted.last,
      'mean': sorted.reduce((a, b) => a + b) / sorted.length,
    };
  }

  void cancel() {
    running = false;
    _readyAt = _started = null;
  }
}
