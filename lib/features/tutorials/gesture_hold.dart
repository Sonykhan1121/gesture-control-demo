import 'gesture_tolerance.dart';

/// Counts time only between consecutive matching frames. Short pose/placement
/// wobbles retain earned progress but contribute no time, including recovery.
class GestureHold {
  GestureHold(this.duration, {this.wobbleGrace = GestureTolerance.wobbleGrace});

  final Duration duration;
  final Duration wobbleGrace;
  Duration _elapsed = Duration.zero;
  DateTime? _lastSample;
  DateTime? _pausedSince;
  bool _matching = false;

  bool get isMatching => _matching;
  bool get ready => _matching && _elapsed >= duration;
  double get progress =>
      (_elapsed.inMicroseconds / duration.inMicroseconds).clamp(0.0, 1.0);

  void reset() {
    _elapsed = Duration.zero;
    _lastSample = _pausedSince = null;
    _matching = false;
  }

  /// Also called by the guide's watchdog, so a paused outline cannot remain
  /// filled indefinitely if the camera stops delivering frames.
  bool expire(DateTime now) {
    final last = _lastSample;
    if (last == null) return false;
    final gap = now.difference(last);
    if (gap.isNegative ||
        gap > GestureTolerance.maxResultGap ||
        (_pausedSince != null && now.difference(_pausedSince!) > wobbleGrace)) {
      reset();
      return true;
    }
    return false;
  }

  void update(DateTime now, {required bool matches, bool allowPause = true}) {
    if (!allowPause) {
      reset();
      return;
    }
    expire(now);
    if (matches) {
      if (_matching && _lastSample != null) {
        _elapsed += now.difference(_lastSample!);
      }
      _pausedSince = null;
      _matching = true;
      _lastSample = now;
    } else if (_lastSample != null) {
      _pausedSince ??= now;
      _matching = false;
      _lastSample = now;
    }
  }
}
