import 'package:hand_gesture/l10n/app_strings.dart';
import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';
import 'hand_recognition.dart';
import 'live_hand_gesture.dart';
import 'hand_debug_panel.dart';

const _compactDebug = bool.fromEnvironment('LAZIVOO_HAND_COMPACT_DEBUG');
const _traceEnabled = bool.fromEnvironment('LAZIVOO_HAND_TRACE');

/// Foreground Home hand mode. Shares the existing camera ownership queue with
/// Face mode and tutorials; it does not start a second camera/native session.
class HandGestureOverlay extends StatefulWidget {
  const HandGestureOverlay({
    super.key,
    required this.enabled,
    required this.selectedHand,
    required this.landscape,
    this.timeSource,
    this.recognition,
    this.debugEnabled = false,
  });
  final bool enabled, landscape;
  final String selectedHand;
  final Duration Function()? timeSource;
  final HandRecognition? recognition;
  final bool debugEnabled;

  @override
  State<HandGestureOverlay> createState() => _HandGestureOverlayState();
}

class _HandGestureOverlayState extends State<HandGestureOverlay>
    with WidgetsBindingObserver {
  late final _recognition = widget.recognition ?? HandRecognition();
  final _live = LiveHandGestureState();
  final _clock = Stopwatch()..start();
  late final Timer _watchdog;
  bool _foreground = true, _processing = false;
  int _generation = 0;
  Duration? _lastFrame;
  DeviceOrientation? _orientation;
  String? _error;
  final _cameraKey = GlobalKey();
  int _framesReceived = 0,
      _framesSubmitted = 0,
      _resultsReceived = 0,
      _latencyMs = 0;
  Duration? _lastCameraFrame, _lastResultAt, _lastDebugRefresh;
  HandObservation? _observation;
  String? _nativeError;
  String _resetReason = 'Hand mode opened';
  Duration? _lastTrace;

  void _trace() {
    if (!kDebugMode || !_traceEnabled) return;
    if (_lastTrace != null && _now - _lastTrace! < const Duration(seconds: 1)) {
      return;
    }
    _lastTrace = _now;
    debugPrint(
      'LAZIVOO_HAND_TRACE ${jsonEncode({'elapsedMs': _now.inMilliseconds, 'active': _active, 'selected': widget.selectedHand, 'detected': _observation?.physicalHand, 'points': _observation?.points.length ?? 0, 'confidence': _observation?.handScore, 'native': _observation?.gesture, 'status': _live.status, 'shown': _live.current?.label, 'score': _live.current?.score, 'frames': _framesReceived, 'submitted': _framesSubmitted, 'results': _resultsReceived, 'latencyMs': _latencyMs, 'resultAgeMs': _lastResultAt == null ? null : (_now - _lastResultAt!).inMilliseconds, 'processing': _processing, 'error': _error})}',
    );
  }

  Duration get _now => widget.timeSource?.call() ?? _clock.elapsed;
  bool get _supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _active => widget.enabled && _supported && _foreground;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _watchdog = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_active || !mounted) return;
      _trace();
      var changed = _live.expire(_now);
      if (_observation != null &&
          _lastResultAt != null &&
          _now - _lastResultAt! > LiveHandGestureState.staleTime) {
        _observation = null;
        changed = true;
      }
      if (widget.debugEnabled &&
          (_lastDebugRefresh == null ||
              _now - _lastDebugRefresh! >= const Duration(milliseconds: 200))) {
        _lastDebugRefresh = _now;
        changed = true;
      }
      if (changed) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant HandGestureOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled != widget.enabled ||
        oldWidget.selectedHand != widget.selectedHand) {
      _reset(reason: 'Mode or selected hand changed');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _reset(reason: _foreground ? 'App resumed' : 'App paused');
  }

  Future<void> _closeRecognizer() async {
    try {
      await _recognition.close();
    } catch (_) {
      /* Cleanup must not block retry. */
    }
  }

  void _reset({String reason = 'Tracking restarted'}) {
    ++_generation;
    _live.reset();
    _lastFrame = null;
    _orientation = null;
    _error = null;
    _resetReason = reason;
    _observation = null;
    _nativeError = null;
    _framesReceived = _framesSubmitted = _resultsReceived = _latencyMs = 0;
    _lastCameraFrame = _lastResultAt = _lastDebugRefresh = null;
    unawaited(_closeRecognizer());
    if (mounted) setState(() {});
  }

  void _frame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    if (!_active) return;
    if (_orientation != null && _orientation != orientation) {
      _reset(reason: 'Camera orientation changed');
    }
    _orientation = orientation;
    ++_framesReceived;
    _lastCameraFrame = _now;
    if (_processing ||
        _error != null ||
        (_lastFrame != null &&
            _now - _lastFrame! < const Duration(milliseconds: 80))) {
      return;
    }
    _lastFrame = _now;
    _processing = true;
    ++_framesSubmitted;
    unawaited(_recognize(image, camera, orientation, _generation));
  }

  Future<void> _recognize(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
    int generation,
  ) async {
    final started = _now;
    try {
      final observation = await _recognition.recognize(
        image,
        camera,
        orientation,
      );
      if (!mounted || !_active || generation != _generation) return;
      ++_resultsReceived;
      _lastResultAt = _now;
      _latencyMs = (_now - started).inMilliseconds;
      _observation = observation;
      final previous = _live.current;
      _live.update(observation, _now, selectedHand: widget.selectedHand);
      if (widget.debugEnabled ||
          previous?.pose != _live.current?.pose ||
          previous?.hand != _live.current?.hand) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted || !_active || generation != _generation) return;
      debugPrint('LAZIVOO_HAND_FAILURE $error');
      _live.reset();
      _observation = null;
      _nativeError = error.toString();
      setState(() => _error = 'Hand tracking unavailable. Please try again.');
    } finally {
      _processing = false;
    }
  }

  @override
  void dispose() {
    ++_generation;
    WidgetsBinding.instance.removeObserver(this);
    _watchdog.cancel();
    _clock.stop();
    unawaited(_closeRecognizer());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || !_supported) return const SizedBox.shrink();
    final detected = _active ? _live.current : null;
    final size = widget.landscape ? 48.0 : 72.0;
    final camera = SetupCameraPreview(
      key: _cameraKey,
      showPreview: widget.debugEnabled && !_compactDebug,
      requireFrontCamera: true,
      resolutionPreset: ResolutionPreset.medium,
      onFrame: _frame,
    );
    return Stack(
      children: [
        if (widget.debugEnabled && _compactDebug)
          Positioned(
            left: 20,
            right: widget.landscape ? null : 20,
            top: widget.landscape ? 130 : 185,
            width: widget.landscape ? 260 : null,
            child: IgnorePointer(
              child: Container(
                key: const ValueKey('home-hand-compact-debug'),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: .92),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: DefaultTextStyle(
                  style: AppTypography.text(11, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      LText(
                        'Hand debug · ${_error ?? _live.status}',
                        style: AppTypography.text(
                          12,
                          18,
                          color: AppColors.primary,
                        ),
                      ),
                      LText(
                        'Selected ${widget.selectedHand} · Detected ${_observation?.physicalHand ?? 'none'} · ${_observation?.points.length ?? 0}/21 points',
                      ),
                      LText(
                        'Confidence ${_observation?.handScore.toStringAsFixed(2) ?? '—'} · Native ${_observation?.gesture ?? 'none'}',
                      ),
                      LText(
                        'Shown ${detected?.label ?? 'none'} · Fit ${detected?.score.toStringAsFixed(2) ?? '—'}',
                      ),
                      LText(
                        '${_latencyMs}ms · Frames $_framesReceived · Results $_resultsReceived',
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (widget.debugEnabled && !_compactDebug)
          Positioned(
            left: 20,
            right: widget.landscape ? null : 20,
            top: widget.landscape ? 175 : 185,
            width: widget.landscape ? 240 : null,
            height: widget.landscape ? 150 : 480,
            child: HandDebugPanel(
              camera: camera,
              selectedHand: widget.selectedHand,
              status:
                  _error ??
                  (_framesReceived == 0
                      ? 'No camera frames yet'
                      : _processing && _resultsReceived == 0
                      ? 'Waiting for first recognition result'
                      : _live.status),
              frames: _framesReceived,
              submitted: _framesSubmitted,
              results: _resultsReceived,
              processing: _processing,
              latencyMs: _latencyMs,
              now: _now,
              lastFrame: _lastCameraFrame,
              lastResult: _lastResultAt,
              resetReason: _resetReason,
              observation: _observation,
              nativeError: _nativeError,
            ),
          )
        else
          Positioned.fill(child: camera),
        if (detected != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: widget.landscape ? 16 : 44,
            child: Center(
              child: Semantics(
                image: true,
                label: tr(context, '${detected.hand} hand: ${detected.label}'),
                child: Tooltip(
                  message: detected.label,
                  child: Container(
                    key: const ValueKey('home-detected-gesture'),
                    width: size,
                    height: size,
                    padding: EdgeInsets.all(widget.landscape ? 6 : 9),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Image.asset(
                      detected.asset,
                      key: ValueKey(
                        'detected-${detected.pose.name}-${detected.hand}',
                      ),
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (_error != null && _active)
          Positioned(
            left: 20,
            right: 20,
            bottom: 24,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
          ),
      ],
    );
  }
}
