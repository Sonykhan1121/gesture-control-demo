import 'package:hand_gesture/shared/reaction_artwork.dart';
import 'package:hand_gesture/l10n/app_strings.dart';
import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';

import 'face_tracking.dart';
import 'face_camera_overlay.dart';
import 'face_tracking_mouth.dart';
import 'mouth_tracking.dart';
import 'mouth_diagnostics.dart';
import 'mouth_debug_panel.dart';
import 'mouth_capture_store.dart';
import 'eye_diagnostics.dart';
import 'eye_debug_panel.dart';
import 'eye_capture_store.dart';
import 'eye_status_strip.dart';
import 'face_debug_panel.dart';

/// Camera frames drive face/mouth movement; both eyes blink on their own timer.
class FaceTrackingEyes extends StatefulWidget {
  static const blinkInterval = Duration(seconds: 4);
  static const blinkClosedDuration = Duration(milliseconds: 120);
  // Accept a normal 30fps stream without the old 45ms gate discarding alternate
  // frames. The single-outstanding-call guard still prevents an inference queue.
  static const minFrameInterval = Duration(milliseconds: 30);
  const FaceTrackingEyes({
    super.key,
    required this.enabled,
    required this.happy,
    required this.color,
    this.debugEnabled = false,
    this.layoutBuilder,
    this.timeSource,
    this.captureStore,
    this.eyeDebugEnabled = false,
    this.eyeCaptureStore,
    this.showEyeStatus = false,
    this.faceDebugEnabled = false,
    this.movementBounds = const Rect.fromLTRB(-24, -32, 24, 32),
    this.onPositionChanged,
    this.screenMapping,
    this.savedStartPosition,
    this.onObservation,
    this.previewBuilder,
    this.cameraPreviewBuilder,
    this.showCameraPreview = false,
    this.overlayOnCamera = false,
  });

  final bool enabled;
  final bool happy;
  final Color color;
  final bool debugEnabled;
  final Widget Function(BuildContext context, Widget face, Widget diagnostics)?
  layoutBuilder;
  final Duration Function()? timeSource;
  final MouthCaptureStore? captureStore;
  final bool eyeDebugEnabled;
  final EyeCaptureStore? eyeCaptureStore;
  final bool showEyeStatus;
  final bool faceDebugEnabled;

  /// Translation limits supplied by the available Home layout, in design pixels.
  final Rect movementBounds;
  final ValueChanged<Offset>? onPositionChanged;
  final FaceScreenMapping? screenMapping;

  /// Settings' camera point is used before detection and after a face is lost.
  /// Live tracking uses the actual camera position, without a first-face offset.
  final Offset? savedStartPosition;

  /// Optional consumer of the same validated readings that animate the avatar.
  final void Function(
    FaceObservation? face,
    MouthMotion mouth,
    DeviceOrientation orientation,
  )?
  onObservation;

  /// Presents the live avatar and its camera permission/retry surface together.
  final Widget Function(BuildContext context, Widget face, Widget camera)?
  previewBuilder;
  final Widget Function(BuildContext, Size, Widget)? cameraPreviewBuilder;
  final bool showCameraPreview;
  final bool overlayOnCamera;

  @override
  State<FaceTrackingEyes> createState() => _FaceTrackingEyesState();
}

class _FaceTrackingEyesState extends State<FaceTrackingEyes>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final _tracking = FaceTracking();
  final _motion = FaceFollowMotion();
  final _stabilizer = FaceMotionStabilizer();
  Offset _requestedRatio = const Offset(.5, .5);
  final _blink = EyeBlinkState(useLidGap: true);
  final _mouth = MouthMotionState();
  final _capture = MouthDiagnosticCapture();
  final _guidedCheck = MouthGuidedCheck();
  late final _captureStore = widget.captureStore ?? MouthCaptureStore();
  late final _eyeStore = widget.eyeCaptureStore ?? EyeCaptureStore();
  final _eyeCheck = EyeDiagnosticCheck();
  final _cameraKey = GlobalKey();
  EyeDebugSample? _eyeSample;
  String _eyeStatus = 'Waiting for eyes',
      _eyeStorage = 'One check: normal, left, right, both';
  int _eyeRun = 0;
  final _clock = Stopwatch()..start();
  late final Timer _watchdog;
  Timer? _automaticBlinkTimer, _reopenEyesTimer;
  bool _automaticEyesClosed = false;
  Duration? _lastFrame, _lastFace;
  Duration? _lastResult;
  late final AnimationController _movementController;
  late final CurvedAnimation _movementCurve;
  Animation<Offset> _animatedShift = const AlwaysStoppedAnimation(Offset.zero);
  Offset _direction = Offset.zero;
  Offset _targetShift = Offset.zero;
  bool _positionReportQueued = false;
  DeviceOrientation? _orientation;
  bool _foreground = true, _processing = false;
  int _generation = 0;
  String? _error;
  FaceObservation? _debugFace;
  String _mouthStatus = 'Waiting for a face';
  int _latencyMs = 0;
  Duration? _lastMouthLog;
  final int _debugSession = DateTime.now().millisecondsSinceEpoch;
  String _captureStorage = 'Captures will be saved on phone';
  int _checkRuns = 0;
  Duration get _elapsed => widget.timeSource?.call() ?? _clock.elapsed;

  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _active => widget.enabled && _supported && _foreground;

  @override
  void initState() {
    super.initState();
    _movementController = AnimationController(
      vsync: this,
      duration: FaceFollowMotion.animationDuration,
    );
    _movementController.addListener(_reportPosition);
    _movementCurve = CurvedAnimation(
      parent: _movementController,
      curve: Curves.easeOut,
    );
    _requestedRatio = _restRatio;
    _direction = _restDirection;
    _targetShift = _targetFor(_direction);
    _animatedShift = AlwaysStoppedAnimation(_targetShift);
    _reportPosition();
    if (widget.enabled) unawaited(_loadSavedCalibration());
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _restartAutomaticBlink();
    _watchdog = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final now = _elapsed;
      _tickCapture(now);
      _tickEyeCheck(now);
      if ((_capture.active || _guidedCheck.running) && mounted) setState(() {});
      if (_eyeCheck.running && mounted) setState(() {});
      if (widget.faceDebugEnabled && _active && mounted) setState(() {});
      if (_lastFace != null &&
          now - _lastFace! > const Duration(milliseconds: 300) &&
          (_debugFace != null ||
              _blink.leftClosed ||
              _blink.rightClosed ||
              !_mouth.motion.atRest)) {
        setState(() {
          _blink.reset();
          _mouth.reset();
          _debugFace = null;
          _eyeSample = null;
          _eyeStatus = 'Stale eye frame';
          _mouthStatus = 'Stale frame — mouth reset';
        });
      }
      if (_lastFace != null &&
          now - _lastFace! > const Duration(milliseconds: 800)) {
        _lastFace = null;
        _motion.reset();
        _stabilizer.reset();
        _requestedRatio = _restRatio;
        _blink.reset();
        _mouth.reset();
        if (mounted) {
          setState(() {
            _moveTo(_restDirection);
          });
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant FaceTrackingEyes oldWidget) {
    super.didUpdateWidget(oldWidget);
    final startChanged =
        widget.savedStartPosition != oldWidget.savedStartPosition;
    if (startChanged) {
      _generation++;
      _stabilizer.reset();
      _requestedRatio = _restRatio;
    }
    final oldMapping = oldWidget.screenMapping,
        newMapping = widget.screenMapping;
    if (oldMapping != null && newMapping != null && oldMapping != newMapping) {
      final ratio = oldMapping.ratioForShift(_currentShift);
      final reprojected = newMapping.shiftForRatio(
        ratio,
        widget.movementBounds,
      );
      _movementController.stop();
      _animatedShift = AlwaysStoppedAnimation(reprojected);
      _targetShift = reprojected;
      _reportPosition();
    }
    if ((widget.screenMapping == null) != (oldWidget.screenMapping == null)) {
      _motion.reset();
      _stabilizer.reset();
      _moveTo(_restDirection);
    }
    if (widget.movementBounds != oldWidget.movementBounds ||
        widget.screenMapping != oldWidget.screenMapping) {
      _moveTo(startChanged ? _restDirection : _direction);
    }
    if (startChanged) _moveTo(_restDirection);
    if (widget.faceDebugEnabled && !oldWidget.faceDebugEnabled) {
      _reportPosition();
    }
    if (widget.enabled != oldWidget.enabled) {
      _reset();
      if (widget.enabled) unawaited(_loadSavedCalibration());
    }
    if (!widget.debugEnabled && oldWidget.debugEnabled) {
      _capture.cancel();
      _guidedCheck.cancel();
    }
    if (!widget.eyeDebugEnabled && oldWidget.eyeDebugEnabled) {
      _eyeCheck.cancel();
      _eyeRun++;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _restartAutomaticBlink();
    _reset();
  }

  void _restartAutomaticBlink() {
    _automaticBlinkTimer?.cancel();
    _reopenEyesTimer?.cancel();
    _automaticEyesClosed = false;
    if (!_foreground) return;
    _automaticBlinkTimer = Timer.periodic(FaceTrackingEyes.blinkInterval, (_) {
      if (!mounted || !_foreground) return;
      setState(() => _automaticEyesClosed = true);
      _reopenEyesTimer = Timer(FaceTrackingEyes.blinkClosedDuration, () {
        if (mounted) setState(() => _automaticEyesClosed = false);
      });
    });
  }

  void _reset({bool keepPosition = false}) {
    final retainedRatio = keepPosition
        ? widget.screenMapping?.ratioForShift(_currentShift)
        : null;
    _generation++;
    _lastFrame = _lastFace = null;
    _lastResult = null;
    _motion.reset();
    _stabilizer.reset();
    _requestedRatio = retainedRatio ?? _restRatio;
    _blink.reset();
    _mouth.reset(forgetNeutral: true);
    _debugFace = null;
    _capture.cancel();
    _guidedCheck.cancel();
    _lastMouthLog = null;
    _mouthStatus = 'Waiting for a face';
    _eyeCheck.cancel();
    _eyeRun++;
    _eyeSample = null;
    _eyeStatus = 'Waiting for eyes';
    _orientation = null;
    if (keepPosition) _lastFace = _elapsed;
    if (mounted) {
      setState(() {
        if (!keepPosition) _moveTo(_restDirection);
        _error = null;
      });
    }
    unawaited(_tracking.close());
  }

  void _frame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    if (_active && _orientation != null && _orientation != orientation) {
      _reset(keepPosition: widget.screenMapping != null);
    }
    _orientation = orientation;
    if (!_active) return;
    if (_error != null) return;
    if (_processing) return;
    if (_lastFrame != null &&
        _elapsed - _lastFrame! < FaceTrackingEyes.minFrameInterval) {
      return;
    }
    _processing = true;
    _lastFrame = _elapsed;
    unawaited(_recognize(image, camera, orientation, _generation));
  }

  Future<void> _recognize(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
    int generation,
  ) async {
    final started = _elapsed;
    try {
      final face = await _tracking.recognize(image, camera, orientation);
      if (!mounted || !_active || generation != _generation) return;
      _lastResult = _elapsed;
      _latencyMs = (_elapsed - started).inMilliseconds.clamp(0, 60000);
      _debugFace = face;
      _tickCapture(_elapsed);
      _capture.add(face?.mouthMeasurement, _latencyMs);
      if (face != null) {
        _lastFace = _elapsed;
        setState(() {
          final absolute = widget.screenMapping != null;
          // A centered face must target screen center regardless of where the
          // user first appeared. The saved setting only supplies the rest pose.
          _requestedRatio = face.center;
          final visibleRatio = widget.screenMapping?.ratioForShift(
            widget.screenMapping!.shiftForRatio(
              _requestedRatio,
              widget.movementBounds,
            ),
          );
          final input = absolute
              ? visibleRatio! * 2 - const Offset(1, 1)
              : _motion.update(face);
          _moveTo(_stabilizer.update(input, _elapsed, precise: absolute));
          // Retained developer diagnostics never drive the avatar's eyelids.
          if (widget.eyeDebugEnabled || widget.showEyeStatus) {
            _blink.update(face);
          }
          _eyeSample = widget.eyeDebugEnabled || widget.showEyeStatus
              ? _eyeReading(face)
              : null;
          _eyeStatus = _eyeSample == null
              ? 'Eye readings unavailable'
              : 'Reading both eyes';
          _mouth.update(
            face.mouthMeasurement,
            jawOpen: face.mouthOpen,
            jawValid: face.mouthValid,
          );
          _mouthStatus = '${_mouth.expression} · ${_mouth.source}';
          _error = null;
        });
      } else {
        setState(() {
          _blink.reset();
          _mouth.reset();
          _eyeSample = null;
          _eyeStatus = 'No face';
          _mouthStatus = 'No face — mouth reset';
          _error = null;
        });
      }
      _logMouthFrame(face);
      widget.onObservation?.call(face, _mouth.motion, orientation);
      _tickEyeCheck(_elapsed);
      _eyeCheck.add(_eyeSample);
    } catch (error) {
      if (!mounted || !_active || generation != _generation) return;
      setState(() {
        _moveTo(_restDirection);
        _blink.reset();
        _mouth.reset();
        _debugFace = null;
        _capture.cancel();
        _guidedCheck.cancel();
        _mouthStatus = 'Tracking error';
        _eyeCheck.cancel();
        _eyeRun++;
        _eyeSample = null;
        _eyeStatus = 'Eye tracking error';
        _error =
            'Face tracking unavailable. Leave this screen and return to retry.';
      });
      widget.onObservation?.call(null, const MouthMotion(), orientation);
    } finally {
      _processing = false;
    }
  }

  Offset get _currentShift => _animatedShift.value;
  Offset get _restRatio => widget.savedStartPosition ?? const Offset(.5, .5);
  Offset get _restDirection => widget.screenMapping == null
      ? Offset.zero
      : _restRatio * 2 - const Offset(1, 1);

  void _reportPosition() {
    if (widget.onPositionChanged == null) return;
    // Ticker updates can notify the layout before this frame is built. A range
    // change during parent build must defer its notification until afterwards.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_positionReportQueued) return;
      _positionReportQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _positionReportQueued = false;
        if (mounted) widget.onPositionChanged?.call(_currentShift);
      });
    } else {
      widget.onPositionChanged?.call(_currentShift);
    }
  }

  Offset _targetFor(Offset next) {
    final bounds = widget.movementBounds;
    return widget.screenMapping?.shiftForRatio(
          (next + const Offset(1, 1)) / 2,
          bounds,
        ) ??
        Offset(
          next.dx * (next.dx < 0 ? -bounds.left : bounds.right),
          next.dy * (next.dy < 0 ? -bounds.top : bounds.bottom),
        );
  }

  void _moveTo(Offset next) {
    final target = _targetFor(next);
    if (next == _direction && target == _targetShift) return;
    final current = _currentShift;
    _direction = next;
    _targetShift = target;
    _animatedShift = Tween<Offset>(
      begin: current,
      end: target,
    ).animate(_movementCurve);
    _movementController.forward(from: 0);
  }

  void _centerFace() {
    final face = _debugFace;
    if (face == null ||
        _lastFace == null ||
        _elapsed - _lastFace! > const Duration(milliseconds: 300)) {
      return;
    }
    setState(() {
      _motion.reset();
      _stabilizer.reset();
      _moveTo(_stabilizer.update(_motion.update(face), _elapsed));
    });
  }

  EyeDebugSample? _eyeReading(FaceObservation face) {
    final measured = face.eyeMeasurement;
    if (!face.blinkValid || measured == null) return null;
    final profile = _blink.profile;
    return EyeDebugSample(
      measured: measured,
      screenLeft: face.blinkScreenLeft,
      screenRight: face.blinkScreenRight,
      normalizedLeft: profile?.isValid == true
          ? profile!.normalized(face.blinkScreenLeft, left: true)
          : EyeGapTuning.closure(measured.leftAperture),
      normalizedRight: profile?.isValid == true
          ? profile!.normalized(face.blinkScreenRight, left: false)
          : EyeGapTuning.closure(measured.rightAperture),
      leftClosed: _blink.leftClosed,
      rightClosed: _blink.rightClosed,
      latencyMs: _latencyMs,
      usesLidGap: _blink.useLidGap,
    );
  }

  void _startEyeCheck() {
    if (!_active || !widget.eyeDebugEnabled || _eyeSample == null) return;
    setState(() {
      _eyeRun++;
      _eyeCheck.start(_elapsed);
      _eyeStorage = 'Results save automatically';
    });
  }

  void _tickEyeCheck(Duration now) {
    if (!_eyeCheck.tick(now)) return;
    final run = _eyeRun, count = _eyeCheck.history.length;
    final snapshot = <String, Object?>{
      'version': 1,
      'session': _debugSession,
      'run': run,
      'captures': Map.of(_eyeCheck.history),
      'profile': _blink.profile == null
          ? null
          : jsonDecode(_blink.profile!.encode()),
    };
    setState(() => _eyeStorage = 'Saving eye readings…');
    unawaited(
      _eyeStore
          .save(snapshot)
          .then((_) {
            if (mounted && run == _eyeRun) {
              setState(() => _eyeStorage = 'Saved on phone ($count/4)');
            }
          })
          .catchError((Object error) {
            if (mounted && run == _eyeRun) {
              setState(() => _eyeStorage = 'Save failed — please tell me');
            }
          }),
    );
    unawaited(HapticFeedback.lightImpact());
  }

  void _startCapture(MouthCapturePhase phase) {
    if (!_active || !widget.debugEnabled) return;
    setState(() {
      if (phase == MouthCapturePhase.normal) _mouth.relearnNeutral();
      _capture.start(phase, _elapsed);
      _lastMouthLog = null;
    });
  }

  void _startQuickCheck() {
    if (!_active ||
        !widget.debugEnabled ||
        _debugFace?.mouthMeasurement == null) {
      return;
    }
    setState(() {
      _checkRuns++;
      _capture.cancel();
      _capture.history.clear();
      _guidedCheck.start(_elapsed);
      _captureStorage = 'Results save automatically';
    });
  }

  void _applyCalibration(MouthCalibration calibration) {
    _mouth.applyCalibration(calibration);
    final face = _debugFace;
    if (face != null) {
      _mouth.update(
        face.mouthMeasurement,
        jawOpen: face.mouthOpen,
        jawValid: face.mouthValid,
      );
      _mouthStatus = '${_mouth.expression} · ${_mouth.source}';
    }
  }

  Future<void> _loadSavedCalibration() async {
    final checkRuns = _checkRuns;
    try {
      final saved = await _captureStore.load();
      if (!mounted || saved == null || checkRuns != _checkRuns) return;
      final tuning =
          MouthCalibration.fromCaptures(saved['captures']) ??
          MouthCalibration.fromMap(saved['calibration']);
      if (tuning == null) return;
      setState(() {
        _applyCalibration(tuning);
        _captureStorage = 'Using your saved mouth tuning';
      });
      await _captureStore.save({...saved, 'calibration': tuning.toMap()});
      if (kDebugMode && widget.debugEnabled) {
        debugPrint('MOUTH_TUNING ${jsonEncode(tuning.toMap())}');
      }
    } catch (error) {
      if (kDebugMode && widget.debugEnabled) {
        debugPrint('MOUTH_TUNING_LOAD_ERROR $error');
      }
    }
  }

  void _tickCapture(Duration now) {
    if (_guidedCheck.ready(now)) {
      _startCapture(_guidedCheck.phase);
      _guidedCheck.measuring();
    }
    if (_capture.finishIfDue(now)) {
      _logCaptureSummary();
      if (_guidedCheck.running) _guidedCheck.advance(now);
    }
  }

  void _logMouthFrame(FaceObservation? face) {
    if (!kDebugMode) return;
    final now = _elapsed;
    if (!_capture.active ||
        (_lastMouthLog != null &&
            now - _lastMouthLog! < const Duration(milliseconds: 250))) {
      return;
    }
    _lastMouthLog = now;
    final m = face?.mouthMeasurement;
    debugPrint(
      'MOUTH_FRAME ${jsonEncode({'session': _debugSession, 'atMs': now.inMilliseconds, 'phase': _capture.phase!.name, 'valid': m != null, 'gap': m?.gapRatio, 'width': m?.widthRatio, 'smile': m?.smileScore, 'smileValid': m?.smileValid, 'jaw': face?.mouthOpen, 'latencyMs': _latencyMs, 'outOpen': _mouth.motion.openness, 'outSmile': _mouth.motion.smile, 'outWidth': _mouth.motion.widthScale, 'refWidth': _mouth.neutralWidthRatio, 'source': _mouth.source})}',
    );
  }

  void _logCaptureSummary() {
    if (kDebugMode) {
      debugPrint(
        'MOUTH_SUMMARY ${jsonEncode({...?_capture.completed, 'session': _debugSession})}',
      );
    }
    final tuning = MouthCalibration.fromCaptures(_capture.history);
    if (tuning != null) _applyCalibration(tuning);
    final snapshot = <String, Object?>{
      'version': 1,
      'session': _debugSession,
      'captures': Map.of(_capture.history),
      'neutralReference': _mouth.neutralWidthRatio,
      'calibration': _mouth.calibration?.toMap(),
    };
    final savedCount = _capture.history.length;
    _captureStorage = 'Saving capture…';
    unawaited(
      _captureStore
          .save(snapshot)
          .then((_) {
            if (mounted) {
              setState(
                () => _captureStorage = 'Saved on phone ($savedCount/3)',
              );
            }
          })
          .catchError((Object error) {
            if (kDebugMode) debugPrint('MOUTH_SAVE_ERROR $error');
            if (mounted) {
              setState(
                () => _captureStorage = 'Capture save failed — please tell me',
              );
            }
          }),
    );
    if (mounted) setState(() {});
  }

  Widget _artwork() => reactionArtwork(
    widget.happy ? 'assets/settings/face-happy.png' : 'assets/control/face.png',
    filterQuality: widget.happy ? FilterQuality.none : FilterQuality.medium,
    color: widget.color,
    colorBlendMode: BlendMode.srcIn,
    width: 312,
    height: 200,
    fit: BoxFit.contain,
    excludeFromSemantics: true,
  );

  @override
  Widget build(BuildContext context) {
    // Source alpha gaps: normal eyes end at y=248/400, mouth starts at 368.
    // Happy is letterboxed: its eye/mouth gap falls at the canvas midpoint.
    final split = widget.happy ? .5 : .7;
    final avatar = Semantics(
      label: tr(context, 'Gesture control face'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          AnimatedBuilder(
            animation: _movementController,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                TrackedMouth(
                  key: const ValueKey('face-mouth'),
                  openness: _mouth.motion.openness,
                  smile: _mouth.motion.smile,
                  widthScale: _mouth.motion.widthScale,
                  followExpression: _active,
                  happy: widget.happy,
                  color: widget.color,
                ),
                _blinkingEye(split, left: true, closed: _automaticEyesClosed),
                _blinkingEye(split, left: false, closed: _automaticEyesClosed),
                if (widget.faceDebugEnabled)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: AvatarLocationMarkers(happy: widget.happy),
                      ),
                    ),
                  ),
              ],
            ),
            // A single transform/animation preserves eye-to-mouth spacing,
            // even mid-motion, on recentering and during the paired blink.
            builder: (context, child) => Transform.translate(
              key: const ValueKey('animated-face-position'),
              offset: _currentShift,
              child: child,
            ),
          ),
          if (_error != null)
            Positioned.fill(
              child: ColoredBox(
                color: AppColors.surface,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    LText(
                      _error!,
                      textAlign: TextAlign.center,
                      style: AppTypography.text(12, 18, color: AppColors.error),
                    ),
                    TextButton(onPressed: _reset, child: const LText('Retry')),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    final cameraPreview = widget.enabled && _supported
        ? SetupCameraPreview(
            key: _cameraKey,
            showPreview:
                widget.showCameraPreview ||
                widget.debugEnabled ||
                widget.eyeDebugEnabled ||
                widget.faceDebugEnabled,
            requireFrontCamera: true,
            // The small Home preview follows native preview dimensions, not a
            // previous recognition frame that can lag behind device rotation.
            orientedPreviewSize:
                widget.showCameraPreview && widget.cameraPreviewBuilder == null
                ? _debugFace?.imageSize
                : null,
            previewBuilder: widget.cameraPreviewBuilder,
            fit: widget.showCameraPreview ? BoxFit.contain : BoxFit.cover,
            resolutionPreset: ResolutionPreset.medium,
            onFrame: _frame,
          )
        : const SizedBox.shrink();
    final camera = widget.overlayOnCamera
        ? Stack(
            children: [
              Positioned.fill(child: cameraPreview),
              if (_error != null)
                Positioned.fill(
                  child: ColoredBox(
                    color: AppColors.surface,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          LText(
                            _error!,
                            textAlign: TextAlign.center,
                            style: AppTypography.text(
                              12,
                              18,
                              color: AppColors.error,
                            ),
                          ),
                          TextButton(
                            onPressed: _reset,
                            child: const LText('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_active &&
                  _debugFace != null &&
                  _lastFace != null &&
                  _elapsed - _lastFace! <= const Duration(milliseconds: 300))
                Positioned.fill(
                  child: IgnorePointer(
                    child: FaceCameraOverlay(
                      key: const ValueKey('face-camera-overlay'),
                      happy: widget.happy,
                      face: _debugFace!,
                      avatar: avatar,
                      viewport: MediaQuery.sizeOf(context),
                    ),
                  ),
                ),
            ],
          )
        : cameraPreview;
    if (widget.previewBuilder != null) {
      return widget.previewBuilder!(context, avatar, camera);
    }
    if (widget.layoutBuilder != null) {
      if (widget.faceDebugEnabled) {
        return widget.layoutBuilder!(
          context,
          avatar,
          AnimatedBuilder(
            animation: _movementController,
            child: camera,
            builder: (context, camera) => FaceLocationDebugPanel(
              camera: camera!,
              face: _debugFace,
              currentShift: _currentShift,
              targetShift: _targetShift,
              movementBounds: widget.movementBounds,
              screenMapping: widget.screenMapping,
              requestedRatio: _requestedRatio,
              savedStartRatio: widget.savedStartPosition,
              happy: widget.happy,
              onCenter: _debugFace == null || widget.screenMapping != null
                  ? null
                  : _centerFace,
              status:
                  _error ??
                  (_debugFace == null
                      ? (_lastResult == null
                            ? 'Waiting for camera'
                            : 'No recent face')
                      : 'Live'),
            ),
          ),
        );
      }
      if (widget.eyeDebugEnabled) {
        return widget.layoutBuilder!(
          context,
          avatar,
          EyeDebugPanel(
            camera: camera,
            sample: _eyeSample,
            check: _eyeCheck,
            now: _elapsed,
            storage: _eyeStorage,
            status: _eyeStatus,
            profile: _blink.profile,
            onStart: _startEyeCheck,
          ),
        );
      }
      if (widget.showEyeStatus && widget.enabled && !widget.debugEnabled) {
        return widget.layoutBuilder!(
          context,
          avatar,
          Stack(
            children: [
              Positioned.fill(child: camera),
              EyeStatusStrip(sample: _eyeSample),
            ],
          ),
        );
      }
      if (widget.showCameraPreview && !widget.debugEnabled) {
        return widget.layoutBuilder!(context, avatar, camera);
      }
      final diagnostics = Offstage(
        offstage: !widget.debugEnabled,
        child: MouthDebugPanel(
          camera: camera,
          status: _mouthStatus,
          motion: _mouth.motion,
          calibration: _mouth.calibration,
          measured: _debugFace?.mouthMeasurement,
          jaw: _debugFace?.mouthOpen ?? 0,
          latencyMs: _latencyMs,
          reference: _mouth.neutralWidthRatio,
          capture: _capture,
          guide: _guidedCheck,
          storage: _captureStorage,
          now: _elapsed,
          onStart: _startQuickCheck,
        ),
      );
      return widget.layoutBuilder!(context, avatar, diagnostics);
    }
    return Stack(
      children: [
        avatar,
        Positioned.fill(child: camera),
      ],
    );
  }

  Widget _blinkingEye(
    double split, {
    required bool left,
    required bool closed,
  }) => TweenAnimationBuilder<double>(
    key: ValueKey(left ? 'blink-screen-left' : 'blink-screen-right'),
    tween: Tween<double>(begin: 1, end: closed ? .06 : 1),
    duration: Duration(milliseconds: closed ? 40 : 70),
    curve: Curves.easeOut,
    child: ClipRect(
      clipper: _EyeHalfClipper(split, left: left),
      child: _artwork(),
    ),
    builder: (context, openness, child) => Transform.scale(
      scaleY: openness,
      // Scale about the eye centers, keeping the mouth outside this layer.
      alignment: Alignment(0, (widget.happy ? .279 : .31) * 2 - 1),
      child: child,
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _watchdog.cancel();
    _automaticBlinkTimer?.cancel();
    _reopenEyesTimer?.cancel();
    _clock.stop();
    _movementCurve.dispose();
    _movementController.dispose();
    unawaited(_tracking.close());
    super.dispose();
  }
}

class _EyeHalfClipper extends CustomClipper<Rect> {
  const _EyeHalfClipper(this.split, {required this.left});
  final double split;
  final bool left;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    left ? 0 : size.width / 2,
    0,
    left ? size.width / 2 : size.width,
    size.height * split,
  );

  @override
  bool shouldReclip(_EyeHalfClipper oldClipper) =>
      oldClipper.split != split || oldClipper.left != left;
}
