import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture/shared/camera/recognition_frame.dart';
import 'eye_calibration.dart';
import 'mouth_tracking.dart';
import 'eye_diagnostics.dart';

/// Position of a detected face in the upright, mirrored front-camera frame.
class FaceObservation {
  const FaceObservation({
    required this.center,
    required this.confidence,
    required this.faceHeight,
    required this.imageSize,
    this.blinkScreenLeft = 0,
    this.blinkScreenRight = 0,
    this.blinkValid = true,
    this.mouthOpen = 0,
    this.mouthValid = false,
    this.mouthMeasurement,
    this.eyeMeasurement,
  });

  static FaceObservation? fromMap(Map<Object?, Object?>? data) {
    if (data == null || data['detected'] != true) return null;
    final x = (data['x'] as num?)?.toDouble();
    final y = (data['y'] as num?)?.toDouble();
    final score = (data['confidence'] as num?)?.toDouble();
    final faceHeight = (data['faceHeight'] as num?)?.toDouble();
    final width = (data['width'] as num?)?.toDouble();
    final height = (data['height'] as num?)?.toDouble();
    double blinkScore(Object? value) {
      final score = value is num ? value.toDouble() : 0.0;
      return score.isFinite && score >= 0 && score <= 1 ? score : 0.0;
    }

    if (x == null ||
        y == null ||
        score == null ||
        !x.isFinite ||
        !y.isFinite ||
        !score.isFinite ||
        x < 0 ||
        x > 1 ||
        y < 0 ||
        y > 1 ||
        score < .6 ||
        score > 1 ||
        faceHeight == null ||
        !faceHeight.isFinite ||
        faceHeight <= 0 ||
        faceHeight > 1 ||
        width == null ||
        !width.isFinite ||
        width <= 0 ||
        height == null ||
        !height.isFinite ||
        height <= 0) {
      return null;
    }
    return FaceObservation(
      center: Offset(x, y),
      confidence: score,
      faceHeight: faceHeight,
      imageSize: Size(width, height),
      blinkScreenLeft: blinkScore(data['blinkScreenLeft']),
      blinkScreenRight: blinkScore(data['blinkScreenRight']),
      blinkValid:
          data['blinkValid'] == true &&
          [
            data['blinkScreenLeft'],
            data['blinkScreenRight'],
          ].every((v) => v is num && v.isFinite && v >= 0 && v <= 1),
      mouthOpen: blinkScore(data['mouthOpen']),
      mouthValid:
          data['mouthValid'] == true &&
          data['mouthOpen'] is num &&
          (data['mouthOpen'] as num).isFinite &&
          (data['mouthOpen'] as num) >= 0 &&
          (data['mouthOpen'] as num) <= 1,
      mouthMeasurement: MouthMeasurement.fromNative(data, Size(width, height)),
      eyeMeasurement: EyeMeasurement.fromNative(data, Size(width, height)),
    );
  }

  final Offset center;
  final double confidence;
  final double faceHeight;
  final Size imageSize;
  final double blinkScreenLeft, blinkScreenRight;
  final bool blinkValid;
  final double mouthOpen;
  final bool mouthValid;
  final MouthMeasurement? mouthMeasurement;
  final EyeMeasurement? eyeMeasurement;

  /// Bounded eye direction. Center of the camera frame is neutral.
  Offset get direction => Offset(
    ((center.dx - .5) * 2).clamp(-1.0, 1.0),
    ((center.dy - .5) * 2).clamp(-1.0, 1.0),
  );
}

/// Continuous measured jaw opening. The small dead zone suppresses resting
/// expression noise; rendering eases between samples instead of inventing speech.
class MouthOpenState {
  double openness = 0;

  void update(FaceObservation face) {
    final score = face.mouthOpen;
    openness = face.mouthValid && score.isFinite && score >= 0 && score <= 1
        ? ((score - .04) / (.55 - .04)).clamp(0.0, 1.0)
        : 0;
  }

  void reset() => openness = 0;
}

/// Hysteresis keeps near-threshold noise from fluttering the eyelids.
/// Legacy camera blink classifier for diagnostics; Home uses a separate timer.
abstract final class EyeGapTuning {
  // Lid separation / eye-corner width, independent of camera scale. The user's
  // illustrated 3.5% opening remains OPEN; these are initial camera tolerances.
  static const closed = .022;
  static const reopen = .030;

  static double closure(double aperture) =>
      ((reopen - aperture) / (reopen - closed)).clamp(0.0, 1.0);
}

class EyeBlinkState {
  EyeBlinkState({this.useLidGap = false});
  final bool useLidGap;
  EyeBlinkProfile? profile;
  bool leftClosed = false, rightClosed = false;

  void update(FaceObservation face) {
    if (!face.blinkValid) {
      reset();
      return;
    }
    if (useLidGap) {
      final eyes = face.eyeMeasurement;
      if (eyes == null ||
          !eyes.leftAperture.isFinite ||
          !eyes.rightAperture.isFinite ||
          eyes.leftAperture < 0 ||
          eyes.leftAperture > 1 ||
          eyes.rightAperture < 0 ||
          eyes.rightAperture > 1) {
        reset();
        return;
      }
      leftClosed = _gapClosed(eyes.leftAperture, leftClosed);
      rightClosed = _gapClosed(eyes.rightAperture, rightClosed);
      return;
    }
    leftClosed = _closed(face.blinkScreenLeft, leftClosed, left: true);
    rightClosed = _closed(face.blinkScreenRight, rightClosed, left: false);
  }

  bool _gapClosed(double aperture, bool wasClosed) =>
      aperture <= EyeGapTuning.closed ||
      (wasClosed && aperture < EyeGapTuning.reopen);

  bool _closed(double score, bool wasClosed, {required bool left}) {
    final personal = profile;
    if (personal != null && personal.isValid) {
      final relative = personal.normalized(score, left: left);
      return relative >= .60 || (wasClosed && relative > .30);
    }
    return score >= .55 || (wasClosed && score > .30);
  }

  void reset() {
    leftClosed = rightClosed = false;
  }
}

/// Both axes use the first face as their neutral position and the same travel
/// in image pixels. Tiny detection changes do not continually retarget animation.
class FaceFollowMotion {
  Offset? _neutral;
  double? _initialHeight;
  Offset _direction = Offset.zero;
  Offset rawDirection = Offset.zero;
  Offset? get neutral => _neutral;

  static const animationDuration = Duration(milliseconds: 80);
  // Default range for standalone embeddings; Home supplies layout-based bounds.
  static const maxShift = Offset(24, 32);

  Offset update(FaceObservation face) {
    _neutral ??= face.center;
    _initialHeight ??= face.faceHeight;
    final travel = math.max(.04, _initialHeight! * .35);
    rawDirection = Offset(
      ((face.center.dx - _neutral!.dx) *
              face.imageSize.width /
              face.imageSize.height /
              travel)
          .clamp(-1.0, 1.0),
      ((face.center.dy - _neutral!.dy) / travel).clamp(-1.0, 1.0),
    );
    double stable(double next, double previous) {
      if (next.abs() < .025) return 0;
      return (next - previous).abs() < .02 ? previous : next;
    }

    _direction = Offset(
      stable(rawDirection.dx, _direction.dx),
      stable(rawDirection.dy, _direction.dy),
    );
    return _direction;
  }

  void reset() {
    _neutral = null;
    _initialHeight = null;
    _direction = rawDirection = Offset.zero;
  }
}

/// Map camera 0–1 coordinates to the same percentage of the full Home viewport.
/// Avatar-local coordinates remain 312 × 200 while Home may scale that artwork.
class FaceScreenMapping {
  const FaceScreenMapping({required this.viewport, required this.avatar});
  final Size viewport;
  final Rect avatar;
  double get scale => avatar.width / 312;

  Offset screenPoint(Offset local) => avatar.topLeft + local * scale;

  Offset ratioForShift(Offset shift) {
    final center = screenPoint(const Offset(156, 100) + shift);
    return Offset(center.dx / viewport.width, center.dy / viewport.height);
  }

  Offset shiftForRatio(Offset ratio, Rect limits) {
    final shift =
        (Offset(ratio.dx * viewport.width, ratio.dy * viewport.height) -
            avatar.center) /
        scale;
    double bounded(double value, double lower, double upper) =>
        lower <= upper ? value.clamp(lower, upper) : (lower + upper) / 2;
    // A collapsed axis stays centered even if a caller's rounding inverts its
    // limits. Never pass an inverted interval to double.clamp.
    return Offset(
      bounded(shift.dx, limits.left, limits.right),
      bounded(shift.dy, limits.top, limits.bottom),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FaceScreenMapping &&
      other.viewport == viewport &&
      other.avatar == avatar;
  @override
  int get hashCode => Object.hash(viewport, avatar);
}

/// Reject isolated detector jumps and damp small noise before applying the
/// screen-sized movement gain. Larger deliberate changes settle more quickly.
class FaceMotionStabilizer {
  final _samples = <Offset>[];
  Offset _filtered = Offset.zero, _output = Offset.zero;
  Duration? _lastTime;
  Duration _fastUntil = Duration.zero;

  Offset update(Offset input, Duration now, {bool precise = false}) {
    if (_lastTime == null) {
      _lastTime = now;
      _samples.addAll([input, input, input]);
      return _output = _filtered = input;
    }
    final dt = ((now - _lastTime!).inMicroseconds / 1000000).clamp(
      1 / 120,
      .12,
    );
    _lastTime = now;
    _samples.add(input);
    if (_samples.length > 3) _samples.removeAt(0);
    double median(bool x) {
      final values = _samples.map((p) => x ? p.dx : p.dy).toList()..sort();
      return values[values.length ~/ 2];
    }

    final measured = Offset(median(true), median(false));
    if ((measured - _filtered).distance > .12) {
      _fastUntil = now + const Duration(milliseconds: 250);
    }
    final tau = now < _fastUntil ? .045 : .18;
    final alpha = 1 - math.exp(-dt / tau);
    _filtered = Offset.lerp(_filtered, measured, alpha)!;
    if (precise) {
      // Absolute placement must settle to the requested percentage, with no
      // neutral dead zone or persistent hold error around the middle of screen.
      if ((_filtered - measured).distance < .0005) _filtered = measured;
      return _output = _filtered;
    }
    double stable(double filtered, double measured, double previous) {
      if (filtered.abs() < .045) return 0;
      if (measured.abs() >= .999 && filtered.abs() > .985) return measured.sign;
      return (filtered - previous).abs() < .018 ? previous : filtered;
    }

    return _output = Offset(
      stable(_filtered.dx, measured.dx, _output.dx),
      stable(_filtered.dy, measured.dy, _output.dy),
    );
  }

  void reset() {
    _samples.clear();
    _filtered = _output = Offset.zero;
    _lastTime = null;
    _fastUntil = Duration.zero;
  }
}

/// Match the hidden/diagnostic preview's centered BoxFit.cover crop.
Offset facePointOnPreview(FaceObservation face, Size canvas) {
  final scale = math.max(
    canvas.width / face.imageSize.width,
    canvas.height / face.imageSize.height,
  );
  return Offset(
    face.center.dx * face.imageSize.width * scale +
        (canvas.width - face.imageSize.width * scale) / 2,
    face.center.dy * face.imageSize.height * scale +
        (canvas.height - face.imageSize.height * scale) / 2,
  );
}

class FaceTracking {
  static const channel = MethodChannel('lazivoo/face_tracking');

  Future<FaceObservation?> recognize(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) async {
    return FaceObservation.fromMap(
      await channel.invokeMapMethod<Object?, Object?>(
        'recognize',
        recognitionFrame(image, camera, orientation),
      ),
    );
  }

  Future<void> close() async {
    try {
      await channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // Android is the only implemented native host.
    } on PlatformException {
      // A closing activity may already have released its native engine.
    }
  }
}
