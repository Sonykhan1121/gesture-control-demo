import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture/shared/camera/recognition_frame.dart';

/// Metric-space landmark from MediaPipe, preserving depth for foreshortened poses.
class HandPoint3D {
  const HandPoint3D(this.x, this.y, this.z);
  final double x, y, z;
  bool get isFinite => x.isFinite && y.isFinite && z.isFinite;
  HandPoint3D operator -(HandPoint3D other) =>
      HandPoint3D(x - other.x, y - other.y, z - other.z);
  double get length => math.sqrt(x * x + y * y + z * z);
  double dot(HandPoint3D other) => x * other.x + y * other.y + z * other.z;
}

class HandObservation {
  const HandObservation({
    this.points = const [],
    this.worldPoints = const [],
    this.imageSize = const Size(1, 1),
    this.fistScore = 0,
    this.gesture = 'None',
    this.scores = const {},
    this.hand = '',
    this.handScore = 0,
    this.mirrored = false,
  });

  factory HandObservation.fromMap(Map<Object?, Object?> data) =>
      HandObservation(
        points: ((data['points'] as List?) ?? []).map((point) {
          final values = point as List;
          return Offset(
            (values[0] as num).toDouble(),
            (values[1] as num).toDouble(),
          );
        }).toList(),
        worldPoints: ((data['worldPoints'] as List?) ?? []).map((point) {
          final values = point as List;
          return HandPoint3D(
            (values[0] as num).toDouble(),
            (values[1] as num).toDouble(),
            (values[2] as num).toDouble(),
          );
        }).toList(),
        imageSize: Size(
          (data['width'] as num).toDouble(),
          (data['height'] as num).toDouble(),
        ),
        fistScore: ((data['fistScore'] as num?)?.toDouble() ?? 0).clamp(
          0.0,
          1.0,
        ),
        gesture: data['gesture'] as String? ?? 'None',
        scores: ((data['scores'] as Map?) ?? {}).map(
          (key, value) => MapEntry(key.toString(), (value as num).toDouble()),
        ),
        hand: data['hand'] as String? ?? '',
        handScore: (data['handScore'] as num?)?.toDouble() ?? 0,
        mirrored: data['mirrored'] == true,
      );

  final List<Offset> points;
  final List<HandPoint3D> worldPoints;
  final Size imageSize;
  final double fistScore;
  final String gesture;
  final Map<String, double> scores;
  final String hand;
  final double handScore;
  final bool mirrored;

  /// Tasks Vision labels the hand in its input image. The native bridge
  /// mirrors front-camera images, so undo that swap for the user's own hand.
  /// Keep [hand] unchanged for image-space palm/dorsal geometry.
  String get physicalHand => switch (hand) {
    'Left' => mirrored ? 'Right' : 'Left',
    'Right' => mirrored ? 'Left' : 'Right',
    _ => '',
  };
  bool get hasHand =>
      points.length == 21 &&
      points.every((point) => point.dx.isFinite && point.dy.isFinite);

  double scoreFor(String category) {
    final value =
        scores[category] ?? (category == 'Closed_Fist' ? fistScore : 0.0);
    return value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
  }
}

class HandRecognition {
  static const channel = MethodChannel('hand_gesture/recognizer');

  Future<HandObservation> recognize(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) async {
    final data = await channel.invokeMapMethod<Object?, Object?>(
      'recognize',
      recognitionFrame(image, camera, orientation),
    );
    if (data == null) throw StateError('No hand recognition result');
    return HandObservation.fromMap(data);
  }

  Future<void> close() async {
    try {
      await channel.invokeMethod<void>('close');
    } on MissingPluginException {
      // No native recognizer on unsupported platforms or widget tests.
    }
  }
}

/// Require consecutive recent matches, not a timer independent of the camera.
class FistFeedback {
  static const minimumConfidence = .8;

  DateTime? _matchingSince;
  DateTime? _lastResult;
  bool ready = false;

  void reset() {
    _matchingSince = null;
    _lastResult = null;
    ready = false;
  }

  String update(HandObservation observation, DateTime now) {
    if (_lastResult != null &&
        now.difference(_lastResult!) > const Duration(milliseconds: 600)) {
      _matchingSince = null;
    }
    _lastResult = now;
    if (!observation.hasHand) {
      _matchingSince = null;
      ready = false;
      return 'Show your hand to the camera';
    }
    if (observation.points.any(
      (p) => p.dx < .01 || p.dx > .99 || p.dy < .01 || p.dy > .99,
    )) {
      _matchingSince = null;
      ready = false;
      return 'Keep your whole hand in view';
    }
    if (observation.gesture == 'Closed_Fist' &&
        observation.fistScore >= minimumConfidence) {
      _matchingSince ??= now;
      ready = now.difference(_matchingSince!) >= const Duration(seconds: 1);
      return ready ? 'Fist detected' : 'Hold your fist steady';
    }
    _matchingSince = null;
    ready = false;
    final wrist = observation.points[0];
    final extended = [
      for (final pair in [
        [8, 6],
        [12, 10],
        [16, 14],
        [20, 18],
      ])
        if ((observation.points[pair[0]] - wrist).distance >
            (observation.points[pair[1]] - wrist).distance * 1.08)
          pair,
    ].length;
    return extended > 0
        ? 'Curl your fingers into your palm'
        : 'Turn your fist toward the camera';
  }
}

/// Match the exact centered cover crop used by the mirrored camera preview.
Offset handPointOnPreview(Offset normalized, Size imageSize, Size canvasSize) {
  final scale = math.max(
    canvasSize.width / imageSize.width,
    canvasSize.height / imageSize.height,
  );
  return Offset(
    normalized.dx * imageSize.width * scale +
        (canvasSize.width - imageSize.width * scale) / 2,
    normalized.dy * imageSize.height * scale +
        (canvasSize.height - imageSize.height * scale) / 2,
  );
}
