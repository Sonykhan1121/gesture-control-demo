import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import '../../app/flow/gesture_controller.dart';
import '../../app/theme/app_colors.dart';
import '../../l10n/app_strings.dart';
import '../hand_tracking/hand_gesture_icons.dart';
import 'gesture_border_icon.dart';
import 'tutorial_hand_hint.dart';
import 'gesture_camera_guide.dart';
import 'tutorial_steps.dart';
import 'tutorial_outline_assets.dart';

enum _PracticePhase { demo, tryGesture, response, success }

/// Offline YouTube practice. Demonstrations never count as a camera match.
class SocialTutorialScreen extends StatefulWidget {
  const SocialTutorialScreen({super.key});
  @override
  State<SocialTutorialScreen> createState() => _SocialTutorialScreenState();
}

class _SocialTutorialScreenState extends State<SocialTutorialScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const titles = [
    'A little curiosity',
    'Slow mornings, good coffee',
    'Ready for liftoff',
    'A moment in the garden',
  ];
  late final VideoPlayerController _player;
  late final AnimationController _motion;
  static const _effectDuration = Duration(seconds: 2);
  static const _successPause = Duration(seconds: 1);
  Timer? _demo, _advance;
  int? _session, _step;
  String? _hand, _cameraError, _videoError;
  bool _resultVisible = false;
  bool _debugOpen = const bool.fromEnvironment('LAZIVOO_SOCIAL_DEBUG');
  int _video = 1, _attempt = 0, _generation = 0;
  bool _liveActionShown = false;
  bool _matched = false, _resumePlayback = false;
  bool _foreground = true;
  bool _playing = false;
  _PracticePhase _phase = _PracticePhase.demo;
  bool get _isPracticing =>
      _phase == _PracticePhase.tryGesture || _phase == _PracticePhase.response;
  double _holdProgress = 0;
  String? _hint;
  bool _wrongHand = false;
  int _scene = 0;
  SocialTutorialAction _actionFor(int step) =>
      videoTutorialSteps[step].socialAction!;
  SocialTutorialAction get _action => _actionFor(_step ?? 0);
  double _volume = .5, _beforeVolume = .5;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _motion = AnimationController(vsync: this, duration: _effectDuration);
    _motion.addStatusListener((status) {
      if (mounted && status == AnimationStatus.completed) setState(() {});
    });
    _player = VideoPlayerController.asset('assets/social_practice/flower.mp4');
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      await _player.initialize();
      if (!mounted) return;
      await _player.setLooping(true);
      await _player.setVolume(_volume);
      if (mounted && _foreground && _playing) {
        await _player.play();
      }
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) {
        setState(
          () => _videoError =
              'Practice video unavailable. Please reopen the tutorial.',
        );
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      if (_resumePlayback && _player.value.isInitialized) _player.play();
      if (_step != null) _replay();
    } else {
      _demo?.cancel();
      _advance?.cancel();
      _generation++;
      _resumePlayback = _player.value.isPlaying;
      _player.pause();
      _motion.stop();
      if (mounted) {
        setState(() {
          _matched = false;
          _liveActionShown = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _demo?.cancel();
    _advance?.cancel();
    _motion.dispose();
    _player.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _reset(GestureController c) {
    _demo?.cancel();
    _advance?.cancel();
    _generation++;
    _session = c.tutorialSession;
    _step = c.tutorialIndex;
    _hand = c.hand;
    _matched = false;
    _phase = _PracticePhase.demo;
    _resetScene();
    _attempt++;
    final generation = _generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) _replay();
    });
  }

  void _resetScene() {
    _scene++;
    _video = _action.changesVideo ? 1 : 3;
    _playing = _action == SocialTutorialAction.pause || _action.changesVolume;
    _liveActionShown = false;
    _resultVisible = false;
    _volume = .5;
    _beforeVolume = .5;
    _holdProgress = 0;
    _wrongHand = false;
    _hint = null;
    _motion.value = 0;
    if (_player.value.isInitialized) {
      _player.setVolume(_volume);
      _player.seekTo(Duration.zero);
      if (_playing) {
        _player.play();
      } else {
        _player.pause();
      }
    }
  }

  void _effect(int step) {
    final action = _actionFor(step);
    _beforeVolume = _volume;
    _resultVisible = true;
    if (action.changesVideo) {
      _video = (_video + (action.previous ? -1 : 1)) % titles.length;
    }
    if (action == SocialTutorialAction.play) {
      _playing = true;
      _player.play();
    }
    if (action == SocialTutorialAction.pause) {
      _playing = false;
      _player.pause();
    }
    if (action.changesVolume) {
      _volume = (_volume + (action == SocialTutorialAction.volumeUp ? .2 : -.2))
          .clamp(0.0, 1.0);
      _player.setVolume(_volume);
    }
    if (action.changesVideo) {
      _playing = _video == 3;
    }
    if (action.changesVideo && _player.value.isInitialized) {
      if (_video == 3) {
        _player.play();
      } else {
        _player.pause();
      }
    }
  }

  void _startPractice(int generation) {
    if (!mounted || !_foreground || generation != _generation) return;
    _generation++;
    setState(() {
      _resetScene();
      _phase = _PracticePhase.tryGesture;
    });
  }

  void _replay() {
    if (!mounted || !_foreground || _matched || _step == null) return;
    _demo?.cancel();
    final generation = ++_generation, step = _step!;
    setState(() {
      _phase = _PracticePhase.demo;
      _resetScene();
    });
    _motion.forward(from: 0);
    _demo = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted || !_foreground || generation != _generation) return;
      setState(() => _effect(step));
      _demo = Timer(_effectDuration, () => _startPractice(generation));
    });
  }

  void _match(GestureController c, int session, int step, String hand) {
    if (!mounted ||
        !_foreground ||
        !_isPracticing ||
        _matched ||
        c.tutorialSession != session ||
        c.tutorialIndex != step ||
        c.hand != hand ||
        c.page != FlowPage.tutorial) {
      return;
    }
    if (!_liveActionShown) _beginLiveAction(step);
    _demo?.cancel();
    _generation++;
    final elapsed = (_motion.value * _effectDuration.inMilliseconds).round();
    _motion.stop();
    setState(() {
      _matched = true;
      _phase = _PracticePhase.success;
      _holdProgress = 1;
    });
    _advance?.cancel();
    // Keep success visible for one second and finish any remaining transition.
    final pause = Duration(
      milliseconds: math.max(
        _successPause.inMilliseconds,
        _effectDuration.inMilliseconds - elapsed,
      ),
    );
    _advance = Timer(pause, () {
      if (!mounted ||
          !_foreground ||
          !_matched ||
          c.page != FlowPage.tutorial ||
          c.tutorialSession != session ||
          c.tutorialIndex != step ||
          c.hand != hand) {
        return;
      }
      c.acceptTutorialMatch(
        TutorialGroup.video,
        step,
        hand: hand,
        session: session,
      );
    });
  }

  void _beginLiveAction(int step) {
    _demo?.cancel();
    _liveActionShown = true;
    _phase = _PracticePhase.response;
    _motion.forward(from: 0);
    _effect(step);
  }

  Widget _recognizer(GestureController c) {
    final session = c.tutorialSession, step = c.tutorialIndex, hand = c.hand;
    final generation = _generation;
    return ExcludeSemantics(
      excluding: !_debugOpen,
      child: IgnorePointer(
        ignoring: !_debugOpen,
        child: Opacity(
          opacity: _debugOpen ? 1 : 0,
          child: GestureCameraGuide(
            key: ValueKey('$session-$step-$_attempt-$hand'),
            step: c.tutorialSteps[step],
            stepId: 'youtube-$step-$_attempt',
            socialPractice: true,
            landscape:
                MediaQuery.orientationOf(context) == Orientation.landscape,
            practiceEnabled: _isPracticing,
            showDebugOverlay: _debugOpen,
            onCameraError: (error) {
              if (!mounted) return;
              setState(() {
                _cameraError = error;
              });
            },
            isLeftHand: hand == 'Left',
            onWrongHand: (wrong) {
              if (mounted &&
                  _foreground &&
                  generation == _generation &&
                  _isPracticing) {
                setState(() => _wrongHand = wrong);
              }
            },
            onReading: (reading) {
              if (!mounted ||
                  !_foreground ||
                  !_isPracticing ||
                  generation != _generation ||
                  _matched ||
                  c.page != FlowPage.tutorial ||
                  c.tutorialSession != session ||
                  c.tutorialIndex != step ||
                  c.hand != hand) {
                return;
              }
              setState(() {
                _holdProgress = reading.progress;
                _phase = reading.matching
                    ? _PracticePhase.response
                    : _PracticePhase.tryGesture;
                _hint = reading.matching
                    ? 'Hold steady'
                    : _friendlyHint(reading.status, hand);
                if (reading.matching && !_liveActionShown) {
                  _beginLiveAction(step);
                }
              });
            },
            onMatched: () {
              if (generation == _generation) _match(c, session, step, hand);
            },
          ),
        ),
      ),
    );
  }

  String? _friendlyHint(String status, String hand) {
    if (status.contains('whole hand')) return 'Keep your whole hand in view';
    if (status.contains('Show your') || status.contains('Use your')) {
      return 'Use your $hand hand';
    }
    return null;
  }

  Widget _phaseFeedback({required bool compact}) {
    final label = switch (_phase) {
      _PracticePhase.demo => 'Demo',
      _PracticePhase.tryGesture => 'Your turn',
      _PracticePhase.response => 'Response',
      _PracticePhase.success => 'Success',
    };
    final icon = switch (_phase) {
      _PracticePhase.demo => Icons.visibility_outlined,
      _PracticePhase.tryGesture => null,
      _PracticePhase.response => Icons.touch_app_outlined,
      _PracticePhase.success => Icons.check_circle,
    };
    final hint =
        _phase == _PracticePhase.tryGesture &&
            !_wrongHand &&
            _hint == 'Keep your whole hand in view'
        ? _hint
        : null;
    return Semantics(
      liveRegion: true,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 420),
          switchInCurve: Curves.easeOutCubic,
          // Keep one readable prompt while the new phase slides and scales in.
          layoutBuilder: (current, previous) =>
              current ?? const SizedBox.shrink(),
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, -.12),
                end: Offset.zero,
              ).animate(animation),
              child: ScaleTransition(
                scale: Tween(begin: .94, end: 1.0).animate(animation),
                child: child,
              ),
            ),
          ),
          child: Container(
            key: ValueKey('phase-${_phase.name}-$_resultVisible-$hint'),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 12 : 18,
              vertical: compact ? 10 : 12,
            ),
            decoration: BoxDecoration(
              color: const Color(0xeb101419),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: _matched ? 1 : .5),
              ),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 12,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_phase == _PracticePhase.response)
                      SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          key: const ValueKey('social-hold-progress'),
                          value: _holdProgress,
                          strokeWidth: 3,
                          color: AppColors.primary,
                          backgroundColor: Colors.white24,
                        ),
                      )
                    else if (_phase == _PracticePhase.tryGesture)
                      GestureBorderIcon(
                        key: const ValueKey('social-try-gesture'),
                        assetPath: HandGestureIcons.forPose(
                          videoTutorialSteps[_step ?? 0].pose,
                          isLeftHand: _hand == 'Left',
                        ),
                        color: AppColors.primary,
                      )
                    else
                      Icon(icon, size: 30, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        tr(context, label),
                        key: const ValueKey('social-phase-label'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: compact ? 22 : 28,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_resultVisible) ...[
                  const SizedBox(height: 8),
                  _actionBadge(),
                ] else if (hint != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    tr(context, hint),
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Colors.white),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _movingHand(int step) => AnimatedBuilder(
    animation: _motion,
    builder: (context, _) {
      final amount = math.sin(_motion.value * math.pi);
      final offset = switch (_actionFor(step)) {
        SocialTutorialAction.previousVideo => const Offset(-64, 0),
        SocialTutorialAction.nextVideo => const Offset(46, 0),
        SocialTutorialAction.previousShort => const Offset(0, -80),
        SocialTutorialAction.nextShort => const Offset(0, 54),
        SocialTutorialAction.volumeUp => const Offset(0, -30),
        SocialTutorialAction.volumeDown => const Offset(0, 30),
        _ => Offset.zero,
      };
      final asset = TutorialOutlineAssets.forPose(
        videoTutorialSteps[step].pose,
        isLeftHand: _hand == 'Left',
      );
      return Transform.translate(
        offset: offset * amount,
        child: Transform.scale(
          scale:
              _actionFor(step) == SocialTutorialAction.play ||
                  _actionFor(step) == SocialTutorialAction.pause
              ? 1 + amount * .18
              : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Transform.translate(
                offset: const Offset(1.5, 1.5),
                child: Image.asset(
                  asset,
                  fit: BoxFit.contain,
                  color: Colors.black54,
                  colorBlendMode: BlendMode.srcIn,
                  excludeFromSemantics: true,
                ),
              ),
              Image.asset(
                asset,
                fit: BoxFit.contain,
                color: _matched ? AppColors.primary : AppColors.textPrimary,
                colorBlendMode: BlendMode.srcIn,
                key: const ValueKey('youtube-hand-guide'),
              ),
              if (!_matched && _isPracticing && _holdProgress > 0)
                ClipRect(
                  clipper: _HandProgressClipper(_holdProgress),
                  child: Image.asset(
                    asset,
                    fit: BoxFit.contain,
                    color: AppColors.primary,
                    colorBlendMode: BlendMode.srcIn,
                    excludeFromSemantics: true,
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
  Widget _media(int step) {
    if ((_video == 3) && _player.value.isInitialized) {
      return ColoredBox(
        key: ValueKey('video-$_video'),
        color: Colors.black,
        child: Center(
          child: AspectRatio(
            aspectRatio: _player.value.aspectRatio,
            child: VideoPlayer(_player),
          ),
        ),
      );
    }
    if (_video == 3) return const ColoredBox(color: Colors.black);
    return Image.asset(
      'assets/social_practice/${['cat.png', 'coffee.png', 'rocket.jpg'][_video % 3]}',
      key: ValueKey(_video),
      fit: BoxFit.cover,
      width: double.infinity,
      height: double.infinity,
    );
  }

  Widget _volumeHud() => Container(
    key: const ValueKey('youtube-volume-feedback'),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.black87,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(
          _action == SocialTutorialAction.volumeDown
              ? Icons.volume_down
              : Icons.volume_up,
          color: Colors.white,
          size: 22,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TweenAnimationBuilder<double>(
            key: ValueKey('volume-$_volume'),
            tween: Tween(begin: _beforeVolume, end: _volume),
            duration: _effectDuration,
            curve: Curves.easeInOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 7,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _actionBadge() {
    final (label, icon) = switch (_action) {
      SocialTutorialAction.play => ('Playing', Icons.play_arrow),
      SocialTutorialAction.pause => ('Paused', Icons.pause),
      SocialTutorialAction.nextVideo => ('Next video', Icons.arrow_forward),
      SocialTutorialAction.previousVideo => (
        'Previous video',
        Icons.arrow_back,
      ),
      SocialTutorialAction.nextShort => ('Next Short', Icons.arrow_downward),
      SocialTutorialAction.previousShort => (
        'Previous Short',
        Icons.arrow_upward,
      ),
      SocialTutorialAction.volumeUp => ('Volume up', Icons.volume_up),
      SocialTutorialAction.volumeDown => ('Volume down', Icons.volume_down),
    };
    final color = _matched ? AppColors.primary : Colors.white;
    return Semantics(
      liveRegion: true,
      child: Container(
        key: const ValueKey('youtube-action-feedback'),
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '${tr(context, label)}${_action.changesVolume ? ' · ${(_volume * 100).round()}%' : ''}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: color,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ytText(
    String text, {
    double size = 13,
    Color color = Colors.black,
    int lines = 2,
  }) => Text(
    text,
    maxLines: lines,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(fontFamily: 'Roboto', fontSize: size, color: color),
  );

  Widget _phoneNavigation(bool shorts) {
    final color = shorts ? Colors.white : Colors.black;
    return Container(
      key: const ValueKey('youtube-phone-navigation'),
      height: 58,
      color: shorts ? const Color(0xff0f0f0f) : Colors.white,
      child: Row(
        children: [
          for (final item in [
            (Icons.home_outlined, 'Home'),
            (Icons.video_collection, 'Shorts'),
            (Icons.add_circle_outline, ''),
            (Icons.subscriptions_outlined, 'Subscriptions'),
            (Icons.account_circle_outlined, 'You'),
          ])
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(item.$1, color: color, size: item.$2.isEmpty ? 30 : 23),
                  if (item.$2.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    _ytText(item.$2, size: 10, color: color, lines: 1),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _watchDetails() => Padding(
    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ytText(titles[_video], size: 18),
        const SizedBox(height: 5),
        _ytText(
          [
            '18K views · 1 day ago  ...more',
            '24K views · 2 days ago  ...more',
            '42K views · 3 days ago  ...more',
            '12K views · 4 days ago  ...more',
          ][_video],
          size: 11,
          color: Colors.black54,
          lines: 1,
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: Color(0xffe9e5db),
              child: Text(
                ['M', 'C', 'S', 'G'][_video],
                style: const TextStyle(color: Colors.black),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ytText(
                [
                  'Maya & moments',
                  'The Coffee Corner',
                  'Space journal',
                  'Garden stories',
                ][_video],
                size: 13,
                lines: 1,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(24),
              ),
              child: _ytText(
                'Subscribe',
                color: Colors.white,
                size: 12,
                lines: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 7,
          runSpacing: 6,
          children: [
            for (final action in [
              (Icons.thumb_up_outlined, '2.4K'),
              (Icons.share_outlined, 'Share'),
              (Icons.download_outlined, 'Download'),
            ])
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xfff0f0f0),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(action.$1, size: 16, color: Colors.black),
                    const SizedBox(width: 6),
                    _ytText(action.$2, size: 12, lines: 1),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xfff2f2f2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ytText('Comments  ${[86, 128, 240, 64][_video]}', size: 13),
              const SizedBox(height: 6),
              _ytText(
                'A little moment worth watching.',
                size: 12,
                color: Colors.black54,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ytText('Playlist · ${_video + 1} / 4', size: 13),
      ],
    ),
  );

  Widget _feed(GestureController c, int step, double height, double width) {
    final shorts = _actionFor(step).isShort;
    // Reserve room for readable correction text even on short landscape screens.
    final handAreaHeight = _wrongHand && !_matched
        ? math.min(height, math.max(104.0, height * .48))
        : height * .48;
    final handAreaTop = math.min(height * .26, height - handAreaHeight);
    final videoHeight = shorts
        ? height - 58
        : math.min(width * 9 / 16, height * .55);
    return ClipRRect(
      key: const ValueKey('youtube-preview'),
      borderRadius: BorderRadius.circular(12),
      child: ColoredBox(
        color: shorts ? Colors.black : Colors.white,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: videoHeight,
              child: ColoredBox(
                color: Colors.black,
                child: AnimatedSwitcher(
                  key: ValueKey('scene-$_scene'),
                  duration: _effectDuration,
                  switchInCurve: Curves.easeInOutCubic,
                  switchOutCurve: Curves.easeInOutCubic,
                  transitionBuilder: (child, a) {
                    // Scroll Up enters from below; Scroll Down enters above.
                    // Watch-video navigation retains its horizontal direction.
                    final incomingDirection = shorts
                        ? (_actionFor(step).previous ? 1.0 : -1.0)
                        : (_actionFor(step).previous ? -1.0 : 1.0);
                    final currentMediaKey = _video == 3
                        ? ValueKey('video-$_video')
                        : ValueKey(_video);
                    final direction =
                        incomingDirection *
                        (child.key == currentMediaKey ? 1 : -1);
                    return SlideTransition(
                      key: ValueKey('youtube-slide-${child.key}'),
                      position: Tween(
                        begin: shorts
                            ? Offset(0, direction)
                            : Offset(direction, 0),
                        end: Offset.zero,
                      ).animate(a),
                      child: child,
                    );
                  },
                  child: _media(step),
                ),
              ),
            ),
            if (!shorts) ...[
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Row(
                  children: [
                    const Icon(
                      Icons.keyboard_arrow_down,
                      color: Colors.white,
                      size: 26,
                    ),
                    const Spacer(),
                    for (final icon in [
                      Icons.cast,
                      Icons.closed_caption_outlined,
                      Icons.settings_outlined,
                    ])
                      Padding(
                        padding: const EdgeInsets.only(left: 18),
                        child: Icon(icon, color: Colors.white, size: 22),
                      ),
                  ],
                ),
              ),
              Positioned(
                top: videoHeight / 2 - 20,
                left: 0,
                right: 0,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _player,
                  builder: (context, value, _) => Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.skip_previous,
                        color: Colors.white,
                        size: 30,
                      ),
                      const SizedBox(width: 40),
                      AnimatedSwitcher(
                        key: const ValueKey('youtube-playback-control'),
                        duration: const Duration(milliseconds: 250),
                        layoutBuilder: (current, previous) =>
                            current ?? const SizedBox.shrink(),
                        transitionBuilder: (child, animation) =>
                            ScaleTransition(scale: animation, child: child),
                        child: Semantics(
                          key: ValueKey(_playing),
                          label: tr(context, _playing ? 'Pause' : 'Play'),
                          child: Icon(
                            _playing ? Icons.pause : Icons.play_arrow,
                            color: Colors.white,
                            size: 44,
                          ),
                        ),
                      ),
                      const SizedBox(width: 40),
                      const Icon(
                        Icons.skip_next,
                        color: Colors.white,
                        size: 30,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: videoHeight - 28,
                left: 12,
                right: 12,
                child: ValueListenableBuilder<VideoPlayerValue>(
                  valueListenable: _player,
                  builder: (context, value, _) => Row(
                    children: [
                      _ytText(
                        '${value.position.inMinutes}:${(value.position.inSeconds % 60).toString().padLeft(2, '0')} / 0:05',
                        color: Colors.white,
                        size: 11,
                      ),
                      const Spacer(),
                      const Icon(
                        Icons.fullscreen,
                        color: Colors.white,
                        size: 22,
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                top: videoHeight - 3,
                left: 0,
                right: 0,
                child: const LinearProgressIndicator(
                  value: .18,
                  minHeight: 3,
                  color: Color(0xffff0033),
                  backgroundColor: Colors.white30,
                ),
              ),
              Positioned(
                top: videoHeight,
                left: 0,
                right: 0,
                bottom: 58,
                child: SingleChildScrollView(
                  child: AnimatedSwitcher(
                    key: ValueKey('details-scene-$_scene'),
                    duration: const Duration(milliseconds: 300),
                    layoutBuilder: (current, previous) =>
                        current ?? const SizedBox.shrink(),
                    switchInCurve: Curves.easeInOutCubic,
                    switchOutCurve: Curves.easeInOutCubic,
                    child: KeyedSubtree(
                      key: ValueKey('details-$_video'),
                      child: _watchDetails(),
                    ),
                  ),
                ),
              ),
            ] else ...[
              Positioned(
                top: 16,
                left: 12,
                right: 12,
                child: Row(
                  children: [
                    const Icon(Icons.arrow_back, color: Colors.white, size: 23),
                    const Spacer(),
                    const Icon(Icons.search, color: Colors.white, size: 26),
                    const SizedBox(width: 18),
                    const Icon(Icons.more_horiz, color: Colors.white, size: 26),
                  ],
                ),
              ),
              Positioned(
                right: 12,
                bottom: height < 400 ? 80 : 160,
                child: Column(
                  children: [
                    for (final item in [
                      (Icons.favorite_border, '1.7K'),
                      (Icons.chat_bubble_outline, '53'),
                      if (height >= 400) (Icons.bookmark_border, 'Save'),
                      (Icons.share_outlined, 'Share'),
                      if (height >= 400) (Icons.repeat, 'Remix'),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Column(
                          children: [
                            Icon(item.$1, color: Colors.white, size: 27),
                            const SizedBox(height: 3),
                            _ytText(item.$2, color: Colors.white, size: 11),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Positioned(
                left: 12,
                right: 54,
                bottom: 70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 13,
                          backgroundColor: Colors.white24,
                          child: Text(
                            ['M', 'C', 'S', 'G'][_video],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: _ytText(
                            [
                              '@mayas.moments',
                              '@thecoffeecorner',
                              '@spacejournal',
                              '@gardenstories',
                            ][_video],
                            color: Colors.white,
                            size: 13,
                            lines: 1,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: _ytText('Subscribe', size: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _ytText(
                      '${titles[_video]} #shorts',
                      color: Colors.white,
                      size: 13,
                    ),
                    const SizedBox(height: 8),
                    _ytText(
                      '▶ Original sound · ${['Maya & moments', 'The Coffee Corner', 'Space journal', 'Garden stories'][_video]}',
                      color: Colors.white,
                      size: 11,
                    ),
                  ],
                ),
              ),
            ],
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: _phoneNavigation(shorts),
            ),
            Positioned(
              key: const ValueKey('youtube-hand-position'),
              left: width * .18,
              top: handAreaTop,
              width: width * .64,
              height: handAreaHeight,
              child: IgnorePointer(
                child: Column(
                  children: [
                    Expanded(
                      child: AnimatedOpacity(
                        key: const ValueKey('youtube-hand-visibility'),
                        duration: const Duration(milliseconds: 250),
                        opacity: _matched || _phase == _PracticePhase.demo
                            ? 1
                            : .65,
                        child: _movingHand(step),
                      ),
                    ),
                    if (_wrongHand && !_matched)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: TutorialHandHint(
                          hand: c.hand,
                          textKey: const ValueKey('social-wrong-hand-hint'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (_resultVisible && _actionFor(step).changesVolume)
              Positioned(
                top: math.max(8, videoHeight - 60),
                right: 12,
                width: math.min(240, width * .45),
                child: _volumeHud(),
              ),
            Positioned(
              key: const ValueKey('social-screen-feedback'),
              top: height < 260 ? 8 : 44,
              left: 12,
              right: 12,
              child: IgnorePointer(
                child: Align(
                  alignment: height < 260 && width > 600
                      ? Alignment.topLeft
                      : Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: height < 260 && width > 600 ? 260 : 420,
                    ),
                    child: _phaseFeedback(compact: height < 260),
                  ),
                ),
              ),
            ),
            Positioned(
              key: const ValueKey('social-debug-camera'),
              left: _debugOpen ? 8 : 0,
              top: _debugOpen ? 8 : 0,
              width: _debugOpen ? math.min(420, width - 16) : width,
              height: _debugOpen ? math.min(560, height - 16) : height,
              child: Material(
                color: _debugOpen
                    ? const Color(0xff101419)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                clipBehavior: Clip.hardEdge,
                child: Column(
                  children: [
                    if (_debugOpen)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text(
                              'Social control · live camera',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              'Action: ${_liveActionShown ? "triggered" : "waiting"} · Hold: ${_matched ? "confirmed" : "not confirmed"} · Next: ${_advance?.isActive == true ? "queued" : "waiting"}',
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Expanded(child: _recognizer(c)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GestureController>();
    if (_session != c.tutorialSession ||
        _step != c.tutorialIndex ||
        _hand != c.hand) {
      _reset(c);
    }
    final step = c.tutorialIndex;
    final instruction = switch (_action) {
      SocialTutorialAction.play => 'Make a punch to play the video.',
      SocialTutorialAction.pause => 'Make a punch to pause the video.',
      SocialTutorialAction.nextVideo => 'Point right to play the next video.',
      SocialTutorialAction.previousVideo =>
        'Point left to play the previous video.',
      SocialTutorialAction.nextShort =>
        'Point down to scroll to the next Short.',
      SocialTutorialAction.previousShort =>
        'Point up to scroll to the previous Short.',
      SocialTutorialAction.volumeUp =>
        'Give a thumbs up to increase the volume.',
      SocialTutorialAction.volumeDown =>
        'Give a thumbs down to decrease the volume.',
    };
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 40,
                      height: 44,
                      child: IconButton(
                        onPressed: c.back,
                        icon: const Icon(Icons.chevron_left),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        tr(context, 'Tutorial'),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      height: 44,
                      child: IconButton(
                        key: const ValueKey('social-debug-toggle'),
                        tooltip: _debugOpen
                            ? 'Hide camera debug'
                            : 'Show camera debug',
                        onPressed: () =>
                            setState(() => _debugOpen = !_debugOpen),
                        icon: Icon(
                          Icons.bug_report_outlined,
                          color: _debugOpen
                              ? AppColors.primary
                              : Colors.white54,
                          size: 21,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  key: const ValueKey('social-tutorial-stages'),
                  children: [
                    for (final label in [
                      'Face Gesture',
                      'Hand Gesture',
                      'Social Media',
                    ])
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 1),
                          child: Column(
                            children: [
                              Text(
                                tr(context, label),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tr(context, c.tutorialSteps[step].title),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tr(
                    context,
                    _cameraError ??
                        _videoError ??
                        '${tr(context, 'Use your ${c.hand} hand')}. ${tr(context, instruction)}',
                  ),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) =>
                        _feed(c, step, box.maxHeight, box.maxWidth),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _matched ? null : _replay,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: Text(tr(context, 'Replay demo')),
                ),
                if (_cameraError != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _attempt++;
                            _cameraError = null;
                          });
                        },
                        child: Text(tr(context, 'Retry')),
                      ),
                      TextButton(
                        onPressed: openAppSettings,
                        child: Text(tr(context, 'Open Settings')),
                      ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        key: const ValueKey('social-skip'),
                        onPressed: c.skipTutorial,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: Text(tr(context, 'Skip')),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('social-next'),
                        onPressed: _matched
                            ? () => c.acceptTutorialMatch(
                                TutorialGroup.video,
                                step,
                                hand: c.hand,
                                session: c.tutorialSession,
                              )
                            : null,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(44),
                        ),
                        child: Text(tr(context, 'Next')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HandProgressClipper extends CustomClipper<Rect> {
  const _HandProgressClipper(this.progress);
  final double progress;
  @override
  Rect getClip(Size size) => Rect.fromLTRB(
    0,
    size.height * (1 - progress.clamp(0, 1)),
    size.width,
    size.height,
  );
  @override
  bool shouldReclip(_HandProgressClipper old) => old.progress != progress;
}
