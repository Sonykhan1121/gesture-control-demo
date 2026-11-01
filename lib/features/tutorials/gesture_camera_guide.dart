import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hand_gesture/features/hand_tracking/hand_recognition.dart';
import 'package:hand_gesture/features/tutorials/gesture_feedback.dart';
import 'package:hand_gesture/features/tutorials/gesture_debug_overlay.dart';
import 'package:hand_gesture/features/tutorials/gesture_diagnostics.dart';
import 'package:hand_gesture/features/tutorials/gesture_hold.dart';
import 'package:hand_gesture/features/tutorials/gesture_tolerance.dart';
import 'package:hand_gesture/features/tutorials/tutorial_outline_assets.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'tutorial_hand_hint.dart';
import 'package:hand_gesture/features/tutorials/landscape_tutorial_geometry.dart';
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';

/// Reusable camera guide for all 13 hand poses and the 8 video tutorial steps.
///
/// 1. Shows the separately approved left or right PNG (no mirroring).
/// 2. Reads that SAME PNG's transparent-alpha outline as a placement footprint.
/// 3. Requires the correct physical hand, suitable gesture score, enough size,
///    and the pose-specific placement/hold from GestureTolerance.
/// 4. Reveals the lime progress overlay and calls onMatched exactly once.
///
/// Note: the placement footprint uses leftmost and rightmost visible outline
/// pixels per PNG row. It is an approximate silhouette, NOT a pixel-perfect
/// camera-hand-versus-PNG image comparison.
///
/// Social practice skips all outline placement and size requirements, using
/// scale-normalized pose geometry anywhere inside the camera frame instead.
/// For Hand practice, a missing outline prevents completion. Neither mode can
/// bypass the selected physical hand, recognition confidence or steady hold.
class GestureCameraGuide extends StatefulWidget {
  const GestureCameraGuide({
    super.key,
    required this.step,
    required this.stepId,
    this.isLeftHand = false,
    this.landscape = false,
    this.showDebugOverlay = false,
    this.socialPractice = false,
    this.handPractice = false,
    this.practiceEnabled = true,
    this.requireRelease = false,
    this.onReading,
    this.onWrongHand,
    this.onCameraError,
    this.onMatched,
    this.timeSource,
  });

  final GestureTutorialStep step;
  final String stepId;
  final bool isLeftHand;
  final bool landscape;

  /// Opt-in diagnostics for development; normal tutorials keep this off.
  final bool showDebugOverlay;
  final bool socialPractice;

  /// Easier alignment and shorter holds, enabled only by Hand tutorial screens.
  final bool handPractice;
  final bool practiceEnabled;
  final bool requireRelease;
  final ValueChanged<String?>? onCameraError;
  final ValueChanged<bool>? onWrongHand;
  final ValueChanged<({double progress, String status, bool matching})>?
  onReading;
  final VoidCallback? onMatched;

  /// Optional clock for deterministic camera-hold and lifecycle tests.
  final DateTime Function()? timeSource;

  @override
  State<GestureCameraGuide> createState() => _GestureCameraGuideState();
}

class _GestureCameraGuideState extends State<GestureCameraGuide>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final HandRecognition _recognition = HandRecognition();
  late GestureFeedback _feedback;
  late GestureHold _placementHold;
  late final AnimationController _outlineProgress;
  late final Timer _watchdog;
  Timer? _advanceTimer;

  static const Color _outlineWhite = AppColors.textPrimary;
  static const Color _outlinePrimary = AppColors.primary;
  static const double _whiteOutlineOpacity = 0.40;

  // Fist defines the STANDARD visual size. Other pose assets are scaled to
  // match its visible alpha bounds plus approximate silhouette coverage,
  // not merely the PNG canvas or a shared BoxFit.contain container.
  static const String _sizeReferenceAsset =
      'assets/tutorials/fist-left-outline.png';
  static const double _fistStandardBoxWidthFactor = 0.65;
  static const double _fistStandardBoxHeightFactor = 0.58;

  // Very wide or tall hand poses should never be clipped by the camera panel.
  static const double _maxIconPanelWidthFactor = 0.90;
  static const double _maxIconPanelHeightFactor = 0.72;

  // Pointing hands contain less hand mass than a closed fist, even when their
  // visible bounding rectangles have the same area. Blend a gentle silhouette
  // coverage adjustment into the visual scale to balance their visual weight.
  static const double _silhouetteWeightExponent = 0.25;

  static _OutlineFootprint? _referenceFootprint;

  GestureTolerance get _tolerance => _feedback.tolerance;

  Size? _panelSize;
  Size? _landscapeImageSize;
  Size? _portraitImageSize;
  DeviceOrientation? _frameOrientation;
  HandObservation? _visibleHand;
  String? _cameraError;
  bool get _wrongHand {
    final hand = _visibleHand;
    return widget.practiceEnabled &&
        !_ready &&
        hand != null &&
        hand.hasHand &&
        hand.handScore.isFinite &&
        hand.handScore >= _tolerance.handConfidence &&
        hand.handScore <= 1 &&
        hand.physicalHand.isNotEmpty &&
        hand.physicalHand != (widget.isLeftHand ? 'Left' : 'Right');
  }

  String? _outlineError;
  DateTime? _lastResult;
  String _debugMessage = 'Waiting for camera frames';
  String? _debugNative;
  List<GestureCheck> _debugChecks = const [];
  Map<String, double> _debugComponents = const {};
  final List<GestureCheck> _placementChecks = [];
  String _placementMessage = 'Waiting for outline';

  List<GestureCheck> get _visibleChecks {
    final readings = {for (final check in _debugChecks) check.id: check};
    return [
      for (final entry in const {
        'tracking': 'Tracking',
        'hand': 'Physical hand',
        'hand-confidence': 'Hand confidence',
        'visibility': 'Whole hand',
        'pose': 'Pose score',
        'size': 'Size (long / short)',
        'outline': 'Outline',
      }.entries)
        if (!widget.socialPractice ||
            (entry.key != 'size' && entry.key != 'outline'))
          readings[entry.key] ??
              GestureCheck(
                entry.key,
                entry.value,
                _lastResult == null
                    ? 'Waiting for fresh detection'
                    : entry.key == 'size' || entry.key == 'outline'
                    ? 'Waiting for valid hand and loaded outline'
                    : 'Waiting for earlier checks',
                null,
              ),
      if (readings['release'] != null) readings['release']!,
    ];
  }

  bool _processing = false;
  bool _advanced = false;
  bool _active = true;
  bool _ready = false;
  int _generation = 0;
  int _assetGeneration = 0;
  DateTime _lastFrame = DateTime.fromMillisecondsSinceEpoch(0);

  _OutlineFootprint? _outlineFootprint;
  _OutlineFootprint? _fistReferenceFootprint;
  String? _loadedOutlinePath;

  DateTime _now() => widget.timeSource?.call() ?? DateTime.now();

  String get _outlinePath => TutorialOutlineAssets.forPose(
    widget.step.pose,
    isLeftHand: widget.isLeftHand,
  );

  @override
  void initState() {
    super.initState();
    _feedback = GestureFeedback(
      widget.step.pose,
      selectedHand: widget.isLeftHand ? 'Left' : 'Right',
      freePlacement: widget.socialPractice,
      handPractice: widget.handPractice,
      requireRelease: widget.requireRelease,
    );
    _placementHold = GestureHold(
      _tolerance.holdDuration,
      wobbleGrace: _tolerance.holdWobbleGrace,
    );
    _outlineProgress = AnimationController(
      vsync: this,
      duration: _tolerance.holdDuration,
    );

    WidgetsBinding.instance.addObserver(this);
    _loadOutlineAsset();
    _watchdog = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!_active || (_advanced && !widget.socialPractice)) return;
      final now = _now();
      if (_lastResult != null &&
          now.difference(_lastResult!) > GestureTolerance.maxResultGap) {
        setState(() {
          _clearObservation();
          _debugMessage = 'Detection stalled — waiting for a fresh result';
        });
        widget.onWrongHand?.call(false);
        widget.onReading?.call((
          progress: 0,
          matching: false,
          status: _debugMessage,
        ));
      } else if (_placementHold.expire(now)) {
        setState(() {
          _clearObservation(preserveDiagnostics: true);
          _debugMessage =
              'Hold reset — ${_debugMessage.replaceFirst('Paused — ', '')}';
        });
        widget.onWrongHand?.call(false);
        widget.onReading?.call((
          progress: 0,
          matching: false,
          status: _debugMessage,
        ));
      }
    });
  }

  @override
  void didUpdateWidget(covariant GestureCameraGuide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.practiceEnabled != widget.practiceEnabled ||
        oldWidget.requireRelease != widget.requireRelease ||
        oldWidget.socialPractice != widget.socialPractice ||
        oldWidget.handPractice != widget.handPractice) {
      _generation++;
      _clearObservation();
      _feedback = GestureFeedback(
        widget.step.pose,
        selectedHand: widget.isLeftHand ? 'Left' : 'Right',
        freePlacement: widget.socialPractice,
        handPractice: widget.handPractice,
        requireRelease: widget.requireRelease,
      );
      _placementHold = GestureHold(
        _tolerance.holdDuration,
        wobbleGrace: _tolerance.holdWobbleGrace,
      );
      _outlineProgress.duration = _tolerance.holdDuration;
    }
    if (oldWidget.socialPractice != widget.socialPractice) _loadOutlineAsset();
    if (oldWidget.landscape != widget.landscape) {
      // A pending result/advance belongs to the old preview coordinates.
      _generation++;
      _clearObservation();
      _landscapeImageSize = null;
      _frameOrientation = null;
    }
    if (oldWidget.stepId == widget.stepId &&
        oldWidget.isLeftHand == widget.isLeftHand &&
        oldWidget.step.pose == widget.step.pose) {
      return;
    }

    _generation++;
    _clearObservation();
    _cameraError = null;

    _feedback = GestureFeedback(
      widget.step.pose,
      selectedHand: widget.isLeftHand ? 'Left' : 'Right',
      freePlacement: widget.socialPractice,
      handPractice: widget.handPractice,
      requireRelease:
          widget.requireRelease ||
          (widget.step.pose != HandPose.punch &&
              oldWidget.isLeftHand == widget.isLeftHand &&
              oldWidget.step.pose == widget.step.pose),
    );
    _placementHold = GestureHold(
      _tolerance.holdDuration,
      wobbleGrace: _tolerance.holdWobbleGrace,
    );
    _outlineProgress.duration = _tolerance.holdDuration;
    _loadOutlineAsset();
  }

  void _loadOutlineAsset() {
    if (widget.socialPractice) {
      // The Social illustration is instructional, never a detection mask.
      _assetGeneration++;
      _loadedOutlinePath = null;
      _outlineFootprint = null;
      _fistReferenceFootprint = null;
      _outlineError = null;
      return;
    }
    final requestedPath = _outlinePath;
    if (requestedPath == _loadedOutlinePath && _outlineFootprint != null) {
      return;
    }

    final loadGeneration = ++_assetGeneration;
    _loadedOutlinePath = requestedPath;
    _outlineFootprint = null;
    _outlineError = null;

    // Cache the approved Fist mask as the visual-size reference across steps.
    // Load the selected hand and the standard simultaneously; the reference
    // is loaded once, so later tutorial steps do not repeatedly decode it.
    final referenceFuture = _referenceFootprint != null
        ? Future.value(_referenceFootprint!)
        : _OutlineFootprint.fromAsset(_sizeReferenceAsset).then((footprint) {
            _referenceFootprint = footprint;
            return footprint;
          });
    final selectedFuture = requestedPath == _sizeReferenceAsset
        ? referenceFuture
        : _OutlineFootprint.fromAsset(requestedPath);
    unawaited(
      Future.wait([selectedFuture, referenceFuture])
          .then((masks) {
            if (!mounted || loadGeneration != _assetGeneration) return;
            setState(() {
              _outlineFootprint = masks[0];
              _fistReferenceFootprint = masks[1];
              _outlineError = null;
            });
          })
          .catchError((Object error) {
            if (!mounted || loadGeneration != _assetGeneration) return;
            setState(() {
              _outlineFootprint = null;
              _fistReferenceFootprint = null;
              _outlineError =
                  'Outline or size reference missing: ${requestedPath.split('/').last}';
            });
          }),
    );
  }

  void _clearObservation({bool preserveDiagnostics = false}) {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _advanced = false;
    _visibleHand = null;
    _feedback.reset();
    _placementHold.reset();
    _outlineProgress.reset();
    _ready = false;
    if (!preserveDiagnostics) {
      _placementChecks.clear();
      _lastResult = null;
      _debugChecks = const [];
      _debugComponents = const {};
      _debugNative = null;
      _debugMessage = 'Waiting for camera frames';
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _active = state == AppLifecycleState.resumed;
    _generation++;
    setState(() {
      _clearObservation();
      if (!_active) _debugMessage = 'App paused — detection stopped';
    });
    if (!_active) unawaited(_recognition.close());
  }

  void _onFrame(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
  ) {
    final now = _now();
    final landscapeFrame =
        orientation == DeviceOrientation.landscapeLeft ||
        orientation == DeviceOrientation.landscapeRight;
    if (widget.landscape != landscapeFrame) return;
    if (_frameOrientation != null && _frameOrientation != orientation) {
      _generation++;
      _clearObservation();
      _landscapeImageSize = null;
    }
    _frameOrientation = orientation;
    if (!_active ||
        (_advanced && !widget.socialPractice) ||
        _processing ||
        now.difference(_lastFrame).inMilliseconds < 150) {
      return;
    }

    _lastFrame = now;
    _processing = true;
    if (_lastResult == null) {
      setState(() => _debugMessage = 'Camera frame received — detecting');
    }
    unawaited(_recognize(image, camera, orientation, _generation));
  }

  Future<void> _recognize(
    CameraImage image,
    CameraDescription camera,
    DeviceOrientation orientation,
    int generation,
  ) async {
    final panelAtCapture = _panelSize;
    try {
      final observation = await _recognition.recognize(
        image,
        camera,
        orientation,
      );
      if (!mounted ||
          !_active ||
          generation != _generation ||
          panelAtCapture != _panelSize) {
        return;
      }

      if (widget.landscape) {
        // AVFoundation can deliver the last portrait buffer after its device
        // orientation event. Never align it to the new landscape preview.
        if (!observation.imageSize.width.isFinite ||
            !observation.imageSize.height.isFinite ||
            observation.imageSize.height <= 0 ||
            observation.imageSize.width <= observation.imageSize.height) {
          return;
        }
        if (_landscapeImageSize != null &&
            _landscapeImageSize != observation.imageSize) {
          _clearObservation();
        }
        _landscapeImageSize = observation.imageSize;
      } else if (observation.imageSize.width.isFinite &&
          observation.imageSize.height.isFinite &&
          observation.imageSize.width > 0 &&
          observation.imageSize.height > observation.imageSize.width) {
        _portraitImageSize = observation.imageSize;
      }

      final now = _now();
      final resultMessage = _feedback.update(observation, now);

      // The same profile gates both pose feedback and final placement hold.
      // The Watch phase can display the camera but cannot earn hold progress.
      final posePassed = widget.practiceEnabled && _feedback.isMatching;

      final placementPassed =
          widget.socialPractice ||
          (_panelSize != null && _matchesOutline(observation, _panelSize!));

      // A short wobble freezes earned progress. Social can also pause a brief
      // tracking interruption; a wrong hand resets. Paused time earns no credit.
      _placementHold.update(
        now,
        matches: posePassed && placementPassed,
        allowPause: widget.practiceEnabled && _feedback.canPause,
      );
      _outlineProgress.value = _placementHold.progress;
      _ready = _placementHold.ready;
      setState(() {
        _visibleHand = observation;
        _lastResult = now;
        _cameraError = null;
        _debugChecks = [..._feedback.checks, ..._placementChecks];
        _debugComponents = Map.of(_feedback.components);
        _debugNative = observation.hasHand
            ? 'Model: ${observation.gesture.replaceAll('_', ' ')} '
                  '${gesturePercent(observation.scoreFor(observation.gesture))} · '
                  '3D points: ${observation.worldPoints.length}/21'
            : null;
        _debugMessage = _ready
            ? 'Complete — gesture accepted'
            : posePassed && placementPassed
            ? 'All checks pass — keep holding'
            : '${_placementHold.progress > 0 ? 'Paused — ' : ''}'
                  '${!posePassed ? resultMessage : _placementMessage}';
      });

      widget.onWrongHand?.call(_wrongHand);
      widget.onReading?.call((
        progress: _placementHold.progress,
        matching: posePassed && placementPassed,
        status: _debugMessage,
      ));
      if (_ready && !_advanced && widget.onMatched != null) {
        _advanced = true;
        final callback = widget.onMatched!;
        _advanceTimer?.cancel();
        _advanceTimer = Timer(const Duration(milliseconds: 200), () {
          _advanceTimer = null;
          if (mounted && _active && generation == _generation) callback();
        });
      }
    } on MissingPluginException {
      if (mounted && generation == _generation) {
        _clearObservation();
        setState(() {
          _cameraError = 'Hand tracking is unavailable on this device.';
        });
      }
    } catch (error) {
      assert(() {
        debugPrint('Hand tracking error: $error');
        return true;
      }());
      if (mounted && generation == _generation) {
        _clearObservation();
        setState(() {
          _cameraError =
              'Hand tracking unavailable. Reopen this page to retry.';
        });
      }
    } finally {
      _processing = false;
    }
  }

  /// The transparent stroke bounds, not the overall PNG canvas, determine
  /// visual size. Portrait Fist, wide pointing hands, and thumbs-up can
  /// therefore have comparable visible presence without being stretched.
  ///
  /// Fist stays exactly the size it was with widthFactor=.65/heightFactor=.58.
  /// Other outlines first match the visible bounding-box area, then receive
  /// a mild adjustment for approximate hand-silhouette density (a pointing
  /// hand is naturally slimmer). Every image keeps its original aspect ratio.
  /// The displayed image and placement detector MUST share this exact Rect.
  Rect _paintedOutlineRect(Size panelSize) {
    if (!widget.landscape) {
      return portraitTutorialOutlineRect(
        referenceOutline: _sizedOutlineRect(Size(362, widget.step.panelHeight)),
        panelSize: panelSize,
        imageSize: _portraitImageSize ?? const Size(480, 640),
        referencePanelHeight: widget.step.panelHeight,
      );
    }
    final geometry = _landscapeGeometry(panelSize);
    return geometry.outlineRect(_sizedOutlineRect(geometry.portraitPanelSize));
  }

  LandscapeTutorialGeometry _landscapeGeometry(Size panelSize) =>
      LandscapeTutorialGeometry(
        panelSize: panelSize,
        imageSize: _landscapeImageSize ?? const Size(640, 480),
        portraitPanelHeight: widget.step.panelHeight,
      );

  Rect _sizedOutlineRect(Size panelSize) {
    final mask = _outlineFootprint;
    final reference = _fistReferenceFootprint;
    if (mask == null ||
        reference == null ||
        panelSize.width <= 0 ||
        panelSize.height <= 0 ||
        mask.visibleBounds.isEmpty ||
        reference.visibleBounds.isEmpty) {
      return Rect.zero;
    }

    final fistScale = math.min(
      panelSize.width * _fistStandardBoxWidthFactor / reference.width,
      panelSize.height *
          (panelSize.width > panelSize.height
              ? .85
              : _fistStandardBoxHeightFactor) /
          reference.height,
    );
    final fistVisibleArea =
        reference.visibleBounds.width *
        reference.visibleBounds.height *
        fistScale *
        fistScale;
    final currentVisibleArea =
        mask.visibleBounds.width * mask.visibleBounds.height;
    if (fistVisibleArea <= 0 || currentVisibleArea <= 0) {
      return Rect.zero;
    }

    // Match visible area and gently correct for slimmer silhouettes.
    // Row-span coverage is measured from the same PNG mask, so inconsistent
    // transparent margins or original PNG resolution do not alter sizing.
    final densityRatio = reference.silhouetteDensity / mask.silhouetteDensity;
    final silhouetteBoost = math
        .pow(densityRatio.clamp(.25, 4.0), _silhouetteWeightExponent)
        .toDouble();
    final visualScale =
        math.sqrt(fistVisibleArea / currentVisibleArea) * silhouetteBoost;
    final widthFit = panelSize.width * _maxIconPanelWidthFactor / mask.width;
    final heightFit =
        panelSize.height * _maxIconPanelHeightFactor / mask.height;
    final scale = math.min(visualScale, math.min(widthFit, heightFit));

    // Center the *visible hand*, not an arbitrary transparent PNG canvas.
    final imageCenter = Offset(
      panelSize.width / 2 +
          (mask.width / 2 - mask.visibleBounds.center.dx) * scale,
      panelSize.height / 2 +
          (mask.height / 2 - mask.visibleBounds.center.dy) * scale,
    );
    return Rect.fromCenter(
      center: imageCenter,
      width: mask.width * scale,
      height: mask.height * scale,
    );
  }

  bool _matchesOutline(HandObservation observation, Size panelSize) {
    _placementChecks.clear();
    _placementMessage = 'Waiting for valid hand and outline';
    final outline = _outlineFootprint;
    if (outline == null ||
        !observation.hasHand ||
        observation.points.length < 21 ||
        !observation.imageSize.width.isFinite ||
        !observation.imageSize.height.isFinite ||
        observation.imageSize.width <= 0 ||
        observation.imageSize.height <= 0 ||
        observation.points.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      _placementChecks.add(
        const GestureCheck(
          'placement',
          'Placement',
          'Needs valid landmarks and loaded outline',
          null,
        ),
      );
      return false;
    }

    final points = observation.points
        .map(
          (p) => widget.landscape
              ? _landscapeGeometry(panelSize).pointOnPreview(p)
              : handPointOnPreview(p, observation.imageSize, panelSize),
        )
        .toList();
    if (points.any((p) => !p.dx.isFinite || !p.dy.isFinite)) {
      return false;
    }

    // Exactly the same bounds used by the rendered guide PNG.
    final painted = _paintedOutlineRect(panelSize);
    if (painted.isEmpty) return false;

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;
    for (final p in points) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }

    // Compare size against the VISIBLE guide silhouette, so unrelated
    // transparent margins in different PNGs cannot change sensitivity.
    final guideVisibleWidth =
        painted.width * outline.visibleBounds.width / outline.width;
    final guideVisibleHeight =
        painted.height * outline.visibleBounds.height / outline.height;
    final widthRatio = (maxX - minX) / guideVisibleWidth;
    final heightRatio = (maxY - minY) / guideVisibleHeight;
    final longRatio = math.max(widthRatio, heightRatio);
    final shortRatio = math.min(widthRatio, heightRatio);
    final sizePassed =
        longRatio >= _tolerance.minLongAxisRatio &&
        shortRatio >= _tolerance.minShortAxisRatio;
    _placementChecks.add(
      GestureCheck(
        'size',
        'Size (long / short)',
        '${gesturePercent(longRatio)} / ${gesturePercent(shortRatio)}; '
            'need ${gesturePercent(_tolerance.minLongAxisRatio)} / ${gesturePercent(_tolerance.minShortAxisRatio)}',
        sizePassed,
      ),
    );

    final insideCount = points.where((p) {
      final normalized = Offset(
        (p.dx - painted.left) / painted.width,
        (p.dy - painted.top) / painted.height,
      );
      return outline.containsNormalized(
        normalized,
        xSlack: _tolerance.outlineSlackX,
        ySlack: _tolerance.outlineSlackY,
      );
    }).length;

    final insidePassed = insideCount / points.length >= _tolerance.insideRatio;
    _placementChecks.add(
      GestureCheck(
        'outline',
        'Outline',
        '$insideCount/${points.length} points inside; '
            'need ${(_tolerance.insideRatio * points.length).ceil()}/${points.length}',
        insidePassed,
      ),
    );
    _placementMessage = !sizePassed
        ? 'Hand too small — move closer to the camera'
        : 'Move your hand into the outline';
    return sizePassed && insidePassed;
  }

  Widget _outlineArtwork(Color color, {bool progressLayer = false}) {
    return Image.asset(
      _outlinePath,
      key: ValueKey('${progressLayer ? 'progress' : 'guide'}-$_outlinePath'),
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      color: color,
      colorBlendMode: BlendMode.srcIn,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontFamily: AppTypography.bodyFont),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(
          builder: (context, constraints) {
            _panelSize = Size(constraints.maxWidth, constraints.maxHeight);
            final painted = _paintedOutlineRect(_panelSize!);
            return Stack(
              fit: StackFit.expand,
              children: [
                SetupCameraPreview(
                  onFrame: _onFrame,
                  onError: widget.onCameraError,
                  fit: widget.landscape ? BoxFit.contain : BoxFit.cover,
                  orientedPreviewSize: widget.landscape
                      ? _landscapeImageSize
                      : null,
                ),
                if (widget.socialPractice && _visibleHand?.hasHand == true)
                  IgnorePointer(
                    child: CustomPaint(
                      painter: _SocialLandmarks(_visibleHand!),
                    ),
                  ),
                if (widget.socialPractice && !widget.showDebugOverlay)
                  Positioned(
                    left: 8,
                    right: 8,
                    bottom: 6,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      color: Colors.black54,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _cameraError ??
                                (_ready ? "Gesture matched" : _debugMessage),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          LinearProgressIndicator(
                            value: _placementHold.progress,
                            color: AppColors.primary,
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!widget.socialPractice && !painted.isEmpty)
                  Positioned.fromRect(
                    rect: painted,
                    child: IgnorePointer(
                      child: Semantics(
                        label: tr(
                          context,
                          '${widget.isLeftHand ? 'Left' : 'Right'} hand ${widget.step.title} placement outline',
                        ),
                        image: true,
                        child: AnimatedBuilder(
                          animation: _outlineProgress,
                          builder: (context, child) {
                            final reveal = (_advanced || _ready)
                                ? 1.0
                                : _outlineProgress.value.clamp(0.0, 0.95);
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                Opacity(
                                  opacity: _whiteOutlineOpacity,
                                  child: _outlineArtwork(_outlineWhite),
                                ),
                                if (reveal > 0)
                                  ClipPath(
                                    clipper: _OutlineSweepClipper(reveal),
                                    child: _outlineArtwork(
                                      _outlinePrimary,
                                      progressLayer: true,
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                if (!widget.socialPractice && _wrongHand && !painted.isEmpty)
                  Positioned(
                    top: math.min(
                      painted.bottom + 6,
                      math.max(0, constraints.maxHeight - 66),
                    ),
                    left: 12,
                    right: 12,
                    child: Center(
                      child: TutorialHandHint(
                        hand: widget.isLeftHand ? 'Left' : 'Right',
                        textKey: const ValueKey('tutorial-wrong-hand-hint'),
                      ),
                    ),
                  ),
                if (widget.showDebugOverlay)
                  Positioned(
                    top: 8,
                    left: 8,
                    right: 8,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxHeight: constraints.maxHeight * .46,
                      ),
                      child: GestureDebugOverlay(
                        target:
                            '${widget.isLeftHand ? 'Left' : 'Right'} · ${widget.step.title}',
                        status: _cameraError ?? _outlineError ?? _debugMessage,
                        checks: _visibleChecks,
                        hold:
                            '${(_placementHold.progress * _tolerance.holdDuration.inMilliseconds / 1000).toStringAsFixed(1)}'
                            ' / ${(_tolerance.holdDuration.inMilliseconds / 1000).toStringAsFixed(1)} s',
                        matching: _placementHold.isMatching,
                        complete: _ready,
                        nativeReading: _debugNative,
                        components: _debugComponents,
                      ),
                    ),
                  ),
                if (!widget.showDebugOverlay &&
                    (_cameraError != null || _outlineError != null))
                  Positioned(
                    top: 12,
                    left: 12,
                    right: 12,
                    child: LText(
                      _cameraError ?? _outlineError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontSize: 12,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  void dispose() {
    _generation++;
    _assetGeneration++;
    _watchdog.cancel();
    _advanceTimer?.cancel();
    _outlineProgress.dispose();
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_recognition.close());
    super.dispose();
  }
}

class _RowSpan {
  const _RowSpan(this.first, this.last);
  final int first;
  final int last;
}

/// A scanline approximation of the silhouette enclosed by a transparent
/// outline PNG; see _matchesOutline for its use.
/// IMPORTANT: all future hand assets must have truly transparent backgrounds.
class _OutlineFootprint {
  const _OutlineFootprint(
    this.width,
    this.height,
    this.rows,
    this.visibleBounds,
    this.rowSpanPixels,
  );

  final int width;
  final int height;
  final List<_RowSpan?> rows;
  final Rect visibleBounds;
  final int rowSpanPixels;

  double get silhouetteDensity =>
      rowSpanPixels / (visibleBounds.width * visibleBounds.height);

  static Future<_OutlineFootprint> fromAsset(String assetPath) async {
    final bytes = await rootBundle.load(assetPath);
    final codec = await ui.instantiateImageCodec(
      bytes.buffer.asUint8List(),
      targetWidth: 320,
    );

    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;

      try {
        final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (rgba == null) {
          throw StateError('Cannot decode outline: $assetPath');
        }

        final raw = rgba.buffer.asUint8List();
        final rows = List<_RowSpan?>.filled(image.height, null);
        var nonemptyRowCount = 0;
        var visiblePixelCount = 0;
        var rowSpanPixels = 0;
        var minVisibleX = image.width;
        var maxVisibleX = -1;
        var minVisibleY = image.height;
        var maxVisibleY = -1;

        for (var y = 0; y < image.height; y++) {
          int? first;
          int? last;
          for (var x = 0; x < image.width; x++) {
            final alpha = raw[(y * image.width + x) * 4 + 3];
            if (alpha > 12) {
              visiblePixelCount++;
              first ??= x;
              last = x;
            }
          }
          if (first != null && last != null) {
            rows[y] = _RowSpan(first, last);
            nonemptyRowCount++;
            rowSpanPixels += last - first + 1;
            minVisibleX = math.min(minVisibleX, first);
            maxVisibleX = math.max(maxVisibleX, last);
            minVisibleY = math.min(minVisibleY, y);
            maxVisibleY = math.max(maxVisibleY, y);
          }
        }

        if (visiblePixelCount > image.width * image.height * .45) {
          throw StateError(
            'The PNG must have a transparent background and no solid hand fill: $assetPath',
          );
        }
        if (nonemptyRowCount < 12) {
          throw StateError('Outline has no usable shape: $assetPath');
        }

        return _OutlineFootprint(
          image.width,
          image.height,
          rows,
          Rect.fromLTRB(
            minVisibleX.toDouble(),
            minVisibleY.toDouble(),
            (maxVisibleX + 1).toDouble(),
            (maxVisibleY + 1).toDouble(),
          ),
          rowSpanPixels,
        );
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  }

  bool containsNormalized(
    Offset point, {
    double xSlack = .04,
    double ySlack = .02,
  }) {
    if (point.dx < -xSlack ||
        point.dx > 1 + xSlack ||
        point.dy < -ySlack ||
        point.dy > 1 + ySlack) {
      return false;
    }

    final y = point.dy * (height - 1);
    final x = point.dx * (width - 1);
    final slackX = math.max(6, (width * xSlack).round());
    final slackY = (height * ySlack).ceil();
    final firstRow = (y.floor() - slackY).clamp(0, height - 1);
    final lastRow = (y.ceil() + slackY).clamp(0, height - 1);
    // Expand the footprint in both axes. Merely allowing y beyond the PNG's
    // canvas still rejected every point on a transparent row near the hand.
    for (var rowIndex = firstRow; rowIndex <= lastRow; rowIndex++) {
      final row = rows[rowIndex];
      if (row != null && x >= row.first - slackX && x <= row.last + slackX) {
        return true;
      }
    }
    return false;
  }
}

/// The lime layer gradually sweeps across existing white outline strokes.
/// This is an angular sweep, not per-SVG-stroke tracing.
class _OutlineSweepClipper extends CustomClipper<Path> {
  const _OutlineSweepClipper(this.progress);
  final double progress;

  @override
  Path getClip(Size size) {
    final amount = progress.clamp(0.0, 1.0);
    if (amount <= 0) return Path();
    if (amount >= 1) return Path()..addRect(Offset.zero & size);

    final center = Offset(size.width / 2, size.height / 2);
    final radius =
        math.sqrt(size.width * size.width + size.height * size.height) / 2 + 1;
    final circle = Rect.fromCircle(center: center, radius: radius);
    return Path()
      ..moveTo(center.dx, center.dy)
      ..lineTo(center.dx, center.dy - radius)
      ..arcTo(circle, -math.pi / 2, 2 * math.pi * amount, false)
      ..close();
  }

  @override
  bool shouldReclip(_OutlineSweepClipper old) => old.progress != progress;
}

class _SocialLandmarks extends CustomPainter {
  _SocialLandmarks(this.hand);
  final HandObservation hand;
  @override
  void paint(Canvas canvas, Size size) {
    final fitted = applyBoxFit(BoxFit.cover, hand.imageSize, size);
    final source = Alignment.center.inscribe(
      fitted.source,
      Offset.zero & hand.imageSize,
    );
    final target = Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & size,
    );
    Offset point(int i) => Offset(
      target.left +
          (hand.points[i].dx * hand.imageSize.width - source.left) /
              source.width *
              target.width,
      target.top +
          (hand.points[i].dy * hand.imageSize.height - source.top) /
              source.height *
              target.height,
    );
    final stroke = Paint()
      ..color = Colors.white
      ..strokeWidth = 1.5;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final chain in const [
      [0, 1, 2, 3, 4],
      [0, 5, 6, 7, 8],
      [5, 9, 10, 11, 12],
      [9, 13, 14, 15, 16],
      [13, 17, 18, 19, 20],
      [0, 17],
    ]) {
      for (var i = 1; i < chain.length; i++) {
        canvas.drawLine(point(chain[i - 1]), point(chain[i]), stroke);
      }
    }
    for (var i = 0; i < 21; i++) {
      canvas.drawCircle(point(i), 2.5, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SocialLandmarks oldDelegate) =>
      oldDelegate.hand != hand;
}
