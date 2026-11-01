import 'package:hand_gesture/l10n/app_strings.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/features/face_tracking/mouth_tracking.dart';
import 'face_tutorial_progress.dart';

class FaceTutorialScreen extends StatefulWidget {
  const FaceTutorialScreen({super.key, this.timeSource});
  final Duration Function()? timeSource;
  @override
  State<FaceTutorialScreen> createState() => _FaceTutorialScreenState();
}

class _FaceTutorialScreenState extends State<FaceTutorialScreen>
    with WidgetsBindingObserver {
  final _clock = Stopwatch()..start();
  late final Timer _watchdog;
  Timer? _advanceTimer;
  int _index = 0;
  bool _completed = false, _leaving = false;
  final _passed = <FaceLesson>{};
  FaceTutorialProgress _progress = FaceTutorialProgress(FaceLesson.findFace);
  DeviceOrientation? _orientation;
  bool _foreground = true;
  Duration get _now => widget.timeSource?.call() ?? _clock.elapsed;
  FaceLesson get _lesson => FaceLesson.values[_index];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _watchdog = Timer.periodic(const Duration(milliseconds: 200), (_) {
      if (!_completed && _foreground) {
        final hadFace = _progress.hasFace;
        _progress.expire(_now);
        if (hadFace != _progress.hasFace) setState(() {});
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    _foreground = state == AppLifecycleState.resumed;
    if (!_completed) setState(_progress.reset);
    _orientation = null;
  }

  void _observe(
    FaceObservation? face,
    MouthMotion mouth,
    DeviceOrientation orientation,
  ) {
    if (!mounted || _completed || !_foreground) return;
    setState(() {
      if (_orientation != null &&
          _orientation != orientation &&
          !_progress.matched) {
        _progress.reset();
      }
      _orientation = orientation;
      _progress.update(face, mouth, _now);
    });
    if (_progress.matched && _advanceTimer == null) {
      final progress = _progress;
      _advanceTimer = Timer(const Duration(milliseconds: 500), () {
        _advanceTimer = null;
        if (mounted &&
            _foreground &&
            !_completed &&
            identical(progress, _progress) &&
            context.read<GestureController>().page == FlowPage.faceTutorial) {
          _next();
        }
      });
    }
  }

  void _next({bool skip = false}) {
    if (_completed || (!skip && !_progress.matched)) return;
    _advanceTimer?.cancel();
    _advanceTimer = null;
    setState(() {
      if (_progress.matched) _passed.add(_lesson);
      if (_index == FaceLesson.values.length - 1) {
        _completed = true;
      } else {
        _index++;
        _progress = FaceTutorialProgress(_lesson);
      }
    });
  }

  void _back() {
    _advanceTimer?.cancel();
    _advanceTimer = null;
    if (_completed) {
      setState(() {
        _completed = false;
        _progress = FaceTutorialProgress(_lesson);
      });
    } else if (_index > 0) {
      setState(() {
        _index--;
        _progress = FaceTutorialProgress(_lesson);
      });
    } else {
      context.read<GestureController>().back();
    }
  }

  Future<void> _home() async {
    if (_leaving) return;
    setState(() => _leaving = true);
    final c = context.read<GestureController>();
    // Completion means all exercises were detected; skipped steps stay optional.
    if (_passed.length == FaceLesson.values.length) {
      await c.preferences.setBool('gesture.faceTutorialCompleted', true);
    }
    await c.setMode(GestureMode.face);
    if (mounted && c.page == FlowPage.faceTutorial) c.open(FlowPage.control);
  }

  String get _title => switch (_lesson) {
    FaceLesson.findFace => 'Face the camera',
    FaceLesson.horizontal => 'Move left and right',
    FaceLesson.vertical => 'Move up and down',
    FaceLesson.smile => 'Give a smile',
    FaceLesson.talk => 'Say a few words',
  };
  String get _instruction => switch (_lesson) {
    FaceLesson.findFace =>
      'Look toward the front camera and hold comfortably for a moment.',
    FaceLesson.horizontal =>
      'Move your whole face to your left, then right. Watch the eyes and mouth follow.',
    FaceLesson.vertical =>
      'Move your whole face up, then down. Keep looking toward the camera.',
    FaceLesson.smile => 'Smile naturally and watch the mouth smile with you.',
    FaceLesson.talk =>
      'Say a short sentence. Watch the mouth move as you speak.',
  };
  String get _feedback {
    if (_progress.matched) return 'Well done! Moving to the next step…';
    if (!_progress.hasFace) return 'Keep your face visible to the camera';
    return switch (_lesson) {
      FaceLesson.findFace => 'Face found · hold comfortably',
      FaceLesson.horizontal =>
        _progress.firstDirection ? 'Now move right' : 'Move left first',
      FaceLesson.vertical =>
        _progress.firstDirection ? 'Now move down' : 'Move up first',
      FaceLesson.smile => 'Hold a natural smile',
      FaceLesson.talk => 'Keep speaking naturally',
    };
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GestureController>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars(),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Theme(
            data: AppTheme.screen,
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, bounds) {
                  final landscape = bounds.maxWidth > bounds.maxHeight;
                  return SizedBox(
                    height: bounds.maxHeight,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              IconButton(
                                tooltip: tr(context, 'Back'),
                                onPressed: _back,
                                icon: const Icon(Icons.chevron_left),
                                style: IconButton.styleFrom(
                                  backgroundColor: AppColors.surface,
                                ),
                              ),
                              Expanded(
                                child: LText(
                                  'Face Gesture Tutorial',
                                  textAlign: TextAlign.center,
                                  style: AppTypography.text(
                                    20,
                                    28,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 48),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, bodyBounds) => SingleChildScrollView(
                                child: SizedBox(
                                  height: math.max(
                                    bodyBounds.maxHeight,
                                    landscape ? 160 : 470,
                                  ),
                                  child: _completed
                                      ? _success()
                                      : FaceTrackingEyes(
                                          key: const ValueKey(
                                            'face-tutorial-tracker',
                                          ),
                                          enabled: true,
                                          showCameraPreview: true,
                                          overlayOnCamera: true,
                                          happy: c.faceEmoji != 0,
                                          color: Color(c.faceColor),
                                          movementBounds: Rect.zero,
                                          onObservation: _observe,
                                          timeSource: widget.timeSource,
                                          previewBuilder: (context, avatar, camera) {
                                            final stage = _stage(
                                              avatar,
                                              camera,
                                              Color(c.faceBackground),
                                              landscape,
                                            );
                                            final instructions =
                                                _instructions();
                                            return landscape
                                                ? Row(
                                                    children: [
                                                      Expanded(
                                                        flex: 6,
                                                        child: stage,
                                                      ),
                                                      const SizedBox(width: 24),
                                                      Expanded(
                                                        flex: 5,
                                                        child:
                                                            SingleChildScrollView(
                                                              child:
                                                                  instructions,
                                                            ),
                                                      ),
                                                    ],
                                                  )
                                                : Column(
                                                    children: [
                                                      instructions,
                                                      const SizedBox(
                                                        height: 16,
                                                      ),
                                                      Expanded(child: stage),
                                                    ],
                                                  );
                                          },
                                        ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: _leaving
                                      ? null
                                      : _completed
                                      ? () => setState(() {
                                          _index = 0;
                                          _completed = false;
                                          _passed.clear();
                                          _progress = FaceTutorialProgress(
                                            _lesson,
                                          );
                                        })
                                      : () => _next(skip: true),
                                  child: LText(
                                    _completed ? 'Practice again' : 'Skip',
                                  ),
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: FilledButton(
                                  onPressed: _leaving
                                      ? null
                                      : _completed
                                      ? _home
                                      : _progress.matched
                                      ? () => _next()
                                      : null,
                                  child: LText(
                                    _completed ? 'Go to Home' : 'Next',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _instructions() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      LText(
        'Step ${_index + 1} of ${FaceLesson.values.length}',
        style: AppTypography.text(12, 18, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 8),
      LText(
        _title,
        textAlign: TextAlign.center,
        style: AppTypography.text(
          24,
          32,
          color: AppColors.primary,
          weight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 8),
      LText(
        _instruction,
        textAlign: TextAlign.center,
        style: AppTypography.text(14, 20, color: AppColors.textSecondary),
      ),
      const SizedBox(height: 14),
      LinearProgressIndicator(
        value: _progress.progress,
        color: AppColors.primary,
        backgroundColor: AppColors.surface,
        minHeight: 4,
      ),
      const SizedBox(height: 8),
      LText(
        _feedback,
        textAlign: TextAlign.center,
        style: AppTypography.text(
          12,
          18,
          color: _progress.matched
              ? AppColors.primary
              : AppColors.textSecondary,
        ),
      ),
    ],
  );

  Widget _stage(
    Widget avatar,
    Widget camera,
    Color background,
    bool landscape,
  ) => ClipRRect(
    borderRadius: BorderRadius.circular(12),
    child: ColoredBox(
      color: AppColors.surface,
      child: SizedBox.expand(child: camera),
    ),
  );

  Widget _success() => Center(
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            color: AppColors.primary,
            size: 64,
          ),
          const SizedBox(height: 16),
          LText(
            _passed.length == 5 ? 'Tutorial completed' : 'Practice finished',
            textAlign: TextAlign.center,
            style: AppTypography.text(24, 32, weight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          LText(
            '${_passed.length} of 5 exercises practiced',
            style: AppTypography.text(14, 20, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          LText(
            _passed.length == 5
                ? 'Your face is ready to follow you on Home.'
                : 'You can practice skipped exercises again anytime.',
            textAlign: TextAlign.center,
            style: AppTypography.text(14, 20, color: AppColors.textSecondary),
          ),
        ],
      ),
    ),
  );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _watchdog.cancel();
    _advanceTimer?.cancel();
    _clock.stop();
    super.dispose();
  }
}
