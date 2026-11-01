import 'dart:ui';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/mouth_tracking.dart';

enum FaceLesson { findFace, horizontal, vertical, smile, talk }

/// Tutorial-only evidence; never modifies the live tracking/calibration rules.
class FaceTutorialProgress {
  FaceTutorialProgress(this.lesson);
  final FaceLesson lesson;
  static const staleAfter = Duration(milliseconds: 800);
  Duration? _last, _heldSince, _directionSince, _talkSince;
  Offset? _anchor;
  bool firstDirection = false, secondDirection = false, matched = false;
  double progress = 0;
  double? _mouthExtreme;
  int _mouthDirection = 0, _reversals = 0;
  bool get hasFace => _last != null;

  void reset() {
    _last = _heldSince = _directionSince = _talkSince = null;
    _anchor = null;
    firstDirection = secondDirection = matched = false;
    progress = 0;
    _mouthExtreme = null;
    _mouthDirection = _reversals = 0;
  }

  void expire(Duration now) {
    if (!matched && _last != null && now - _last! > staleAfter) reset();
  }

  void update(FaceObservation? face, MouthMotion mouth, Duration now) {
    if (matched) return;
    expire(now);
    if (face == null) {
      reset();
      return;
    }
    _last = now;
    switch (lesson) {
      case FaceLesson.findFace:
        _hold(true, now, const Duration(milliseconds: 1500));
      case FaceLesson.horizontal:
      case FaceLesson.vertical:
        _anchor ??= face.center;
        final delta = lesson == FaceLesson.horizontal
            ? face.center.dx - _anchor!.dx
            : face.center.dy - _anchor!.dy;
        // Both directions relative to the first comfortable position.
        final reached = firstDirection ? delta >= .045 : delta <= -.045;
        if (!reached) {
          _directionSince = null;
        } else {
          _directionSince ??= now;
          if (now - _directionSince! >= const Duration(milliseconds: 150)) {
            if (!firstDirection) {
              firstDirection = true;
              _directionSince = null;
            } else {
              secondDirection = true;
              matched = true;
            }
          }
        }
        progress = matched
            ? 1
            : firstDirection
            ? .5
            : 0;
      case FaceLesson.smile:
        _hold(
          face.mouthMeasurement != null && mouth.smile >= .25,
          now,
          const Duration(milliseconds: 700),
        );
      case FaceLesson.talk:
        if (face.mouthMeasurement == null && !face.mouthValid) {
          _talkSince = null;
          _mouthExtreme = null;
          _mouthDirection = _reversals = 0;
          progress = 0;
          return;
        }
        _talkSince ??= now;
        _mouthExtreme ??= mouth.openness;
        final delta = mouth.openness - _mouthExtreme!;
        // Track repeated changes, rather than accepting a held-open mouth.
        if (_mouthDirection == 0 && delta.abs() >= .08) {
          _mouthDirection = delta.sign.toInt();
          _mouthExtreme = mouth.openness;
        } else if (_mouthDirection != 0) {
          if (delta * _mouthDirection >= 0) {
            _mouthExtreme = mouth.openness;
          } else if (delta.abs() >= .08) {
            _reversals++;
            _mouthDirection = -_mouthDirection;
            _mouthExtreme = mouth.openness;
          }
        }
        progress = (_reversals / 3).clamp(0, 1);
        matched =
            _reversals >= 3 && now - _talkSince! >= const Duration(seconds: 1);
        if (!matched) progress = progress.clamp(0, .9);
    }
  }

  void _hold(bool valid, Duration now, Duration required) {
    if (!valid) {
      _heldSince = null;
      progress = 0;
      return;
    }
    _heldSince ??= now;
    progress = ((now - _heldSince!).inMilliseconds / required.inMilliseconds)
        .clamp(0, 1);
    matched = progress >= 1;
  }
}
