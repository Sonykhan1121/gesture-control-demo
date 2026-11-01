import 'dart:math' as math;
import 'mouth_tracking.dart';

enum MouthCapturePhase { normal, smile, talk }

/// One button runs all three phases: 2s to prepare, then 3s to measure each.
class MouthGuidedCheck {
  int _index = 0;
  bool running = false;
  Duration? readyAt;
  MouthCapturePhase get phase => MouthCapturePhase.values[_index];
  String get instruction => switch (phase) {
    MouthCapturePhase.normal => 'Relax your mouth',
    MouthCapturePhase.smile => 'Smile naturally',
    MouthCapturePhase.talk => 'Say: hello, how are you?',
  };
  int get step => _index + 1;
  void start(Duration now) {
    _index = 0;
    running = true;
    readyAt = now + const Duration(seconds: 2);
  }

  bool ready(Duration now) => running && readyAt != null && now >= readyAt!;
  int prepareSeconds(Duration now) => readyAt == null
      ? 0
      : ((readyAt! - now).inMilliseconds / 1000).ceil().clamp(0, 2);
  void measuring() {
    readyAt = null;
  }

  void advance(Duration now) {
    if (_index == 2) {
      running = false;
      readyAt = null;
      return;
    }
    _index++;
    readyAt = now + const Duration(seconds: 2);
  }

  void cancel() {
    running = false;
    readyAt = null;
  }
}

/// Records measurements only, in memory. No camera images or audio are stored.
class MouthDiagnosticCapture {
  MouthCapturePhase? phase;
  Duration? started;
  int count = 0, invalid = 0;
  double _gapSum = 0, _widthSum = 0, _smileSum = 0, _latencySum = 0;
  double _gapMin = double.infinity, _gapMax = 0;
  String summary = 'Capture Normal, then Smile, then Talk (3s each).';
  Map<String, Object>? completed;
  final Map<String, Map<String, Object>> history = {};
  final List<double> _gaps = [], _widths = [], _smiles = [];
  bool get active => phase != null;
  double secondsLeft(Duration now) => started == null
      ? 0
      : (3 - (now - started!).inMilliseconds / 1000).clamp(0.0, 3.0);

  void start(MouthCapturePhase value, Duration now) {
    phase = value;
    started = now;
    count = invalid = 0;
    _gapSum = _widthSum = _smileSum = _latencySum = _gapMax = 0;
    _gapMin = double.infinity;
    completed = null;
    _gaps.clear();
    _widths.clear();
    _smiles.clear();
    summary =
        'Hold ${value.name == 'talk' ? 'a conversation' : value.name} for 3 seconds.';
  }

  void add(MouthMeasurement? sample, int latencyMs) {
    if (!active) return;
    if (sample == null) {
      invalid++;
      return;
    }
    count++;
    _gapSum += sample.gapRatio;
    _widthSum += sample.widthRatio;
    _gaps.add(sample.gapRatio);
    _widths.add(sample.widthRatio);
    if (sample.smileValid) {
      _smiles.add(sample.smileScore);
      _smileSum += sample.smileScore;
    }
    _latencySum += latencyMs;
    _gapMin = math.min(_gapMin, sample.gapRatio);
    _gapMax = math.max(_gapMax, sample.gapRatio);
  }

  bool finishIfDue(Duration now) {
    if (!active || secondsLeft(now) > 0) return false;
    final label = phase!.name;
    completed = {
      'phase': label,
      'samples': count,
      'invalid': invalid,
      'gapMin': count == 0 ? 0 : _gapMin,
      'gapMax': _gapMax,
      'gapMean': count == 0 ? 0 : _gapSum / count,
      'widthMean': count == 0 ? 0 : _widthSum / count,
      'smileMean': _smiles.isEmpty ? 0 : _smileSum / _smiles.length,
      'latencyMeanMs': count == 0 ? 0 : _latencySum / count,
      'smileSamples': _smiles.length,
      'gapP10': _quantile(_gaps, .10),
      'gapMedian': _quantile(_gaps, .50),
      'gapP90': _quantile(_gaps, .90),
      'gapP95': _quantile(_gaps, .95),
      'widthMedian': _quantile(_widths, .50),
      'smileP10': _quantile(_smiles, .10),
      'smileMedian': _quantile(_smiles, .50),
      'smileP90': _quantile(_smiles, .90),
    };
    history[label] = Map.of(completed!);
    summary = count == 0
        ? '$label: no valid mouth samples. Try again.'
        : '$label: $count samples · gap ${_gapMin.toStringAsFixed(3)}–${_gapMax.toStringAsFixed(3)}';
    phase = null;
    started = null;
    return true;
  }

  double _quantile(List<double> values, double percentile) {
    if (values.isEmpty) return 0;
    final sorted = List<double>.of(values)..sort();
    final at = (sorted.length - 1) * percentile;
    final lo = at.floor(), hi = at.ceil();
    return sorted[lo] + (sorted[hi] - sorted[lo]) * (at - lo);
  }

  void cancel() {
    if (active) summary = 'Capture cancelled: tracking restarted.';
    phase = null;
    started = null;
    completed = null;
  }
}
