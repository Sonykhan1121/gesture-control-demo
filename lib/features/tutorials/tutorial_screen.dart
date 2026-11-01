import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/shared/layout/responsive_canvas.dart';
import 'package:hand_gesture/shared/layout/landscape_layout.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:hand_gesture/features/tutorials/gesture_camera_guide.dart';

import 'social_tutorial_screen.dart';

part 'tutorial_screen_landscape.dart';

class TutorialScreen extends StatefulWidget {
  const TutorialScreen({super.key});
  @override
  State<TutorialScreen> createState() => _TutorialScreenState();
}

class _TutorialScreenState extends State<TutorialScreen> {
  GlobalKey _guideKey = GlobalKey();
  int? _guideSession;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GestureController>();
    if (c.tutorialGroup == TutorialGroup.video && c.page == FlowPage.tutorial) {
      return SocialTutorialScreen(key: ValueKey(c.tutorialSession));
    }
    if (_guideSession != c.tutorialSession) {
      _guideSession = c.tutorialSession;
      _guideKey = GlobalKey(debugLabel: 'tutorial-camera-${c.tutorialSession}');
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) c.back();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: AppTheme.systemBars(),
        child: Scaffold(
          backgroundColor: AppColors.background,
          body: Theme(
            data: AppTheme.screen,
            child: MediaQuery.withClampedTextScaling(
              minScaleFactor: 1,
              child: LayoutBuilder(
                builder: (context, viewport) {
                  if (landscapeLayout(context)) {
                    return ResponsiveLandscape(builder: (_) => _landscape(c));
                  }
                  final width = portraitCanvasWidth(context, viewport);
                  final scale = portraitCanvasScale(context, viewport);
                  final canvasWidth = width / scale;
                  final height = math.max(874.0, viewport.maxHeight / scale);
                  return Center(
                    child: SizedBox(
                      width: width,
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        child: SizedBox(
                          height: height * scale,
                          child: FittedBox(
                            fit: BoxFit.fill,
                            alignment: Alignment.topCenter,
                            child: SizedBox(
                              width: canvasWidth,
                              height: height,
                              child: Stack(
                                children: portraitCanvasChildren(
                                  _content(c),
                                  canvasWidth,
                                  topOffset: portraitHeaderOffset(
                                    context,
                                    scale,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
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

  Widget _cameraGuide(GestureController c, {bool landscape = false}) {
    final group = c.tutorialGroup, index = c.tutorialIndex;
    final hand = c.hand, session = c.tutorialSession;
    return GestureCameraGuide(
      key: _guideKey,
      step: c.tutorialSteps[index],
      stepId: '${group.name}-$index',
      isLeftHand: hand == 'Left',
      landscape: landscape,
      handPractice: group == TutorialGroup.hand,
      onMatched: () {
        if (c.hand != hand) return;
        c.acceptTutorialMatch(group, index, hand: hand, session: session);
      },
    );
  }

  List<Widget> _content(GestureController c) {
    final group = c.tutorialGroup;
    final index = c.tutorialIndex;
    final steps = c.tutorialSteps;
    final step = steps[index];
    final completed = c.page == FlowPage.tutorialCompleted;
    return [
      Positioned(
        left: 20,
        top: 62,
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: tr(context, 'Back'),
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
            backgroundColor: AppColors.surface,
            shape: const CircleBorder(),
          ),
          onPressed: c.back,
          icon: const Icon(
            CupertinoIcons.chevron_back,
            color: AppColors.textPrimary,
            size: 20,
          ),
        ),
      ),
      Positioned(
        left: 76,
        right: 76,
        top: 68,
        height: 32,
        child: Center(
          child: LText(
            'Tutorial',
            style: AppTypography.text(24, 32, weight: FontWeight.w700),
          ),
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        top: 124,
        height: 22,
        child: Row(
          children: [
            _stage('Face Gesture', true),
            const SizedBox(width: 2),
            _stage('Hand Gesture', true),
            const SizedBox(width: 2),
            _stage('Social Media', group == TutorialGroup.video),
          ],
        ),
      ),
      if (completed) ..._completed(c),
      if (!completed) ...[
        Positioned(
          left: 20,
          right: 20,
          top: 158,
          height: 32,
          child: Center(
            child: LText(
              step.title,
              style: AppTypography.text(
                24,
                32,
                color: AppColors.primary,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          right: 20,
          top: 198,
          height: step.panelTop - 218,
          child: LText(
            step.instruction,
            textAlign: TextAlign.center,
            style: AppTypography.text(14, 19, color: AppColors.textSecondary),
          ),
        ),
        Positioned(
          left: 20,
          top: step.panelTop,
          width: 362,
          height: step.panelHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _cameraGuide(c),
          ),
        ),
        Positioned(
          left: 20,
          top: 807,
          width: 172,
          height: 44,
          child: OutlinedButton(
            onPressed: c.skipTutorial,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              foregroundColor: AppColors.skipText,
              side: const BorderSide(color: AppColors.textPrimary),
              shape: const StadiumBorder(),
              textStyle: AppTypography.text(16, 24, weight: FontWeight.w500),
            ),
            child: const LText('Skip'),
          ),
        ),
        Positioned(
          left: 212,
          top: 807,
          width: 170,
          height: 44,
          child: FilledButton(
            onPressed: c.canAdvanceTutorial ? c.nextTutorial : null,
            style: FilledButton.styleFrom(
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              backgroundColor: AppColors.primary,
              disabledBackgroundColor: AppColors.primary.withValues(alpha: .35),
              disabledForegroundColor: AppColors.textSecondary,
              foregroundColor: AppColors.black,
              shape: const StadiumBorder(),
              textStyle: AppTypography.text(16, 24, weight: FontWeight.w500),
            ),
            child: LText(
              c.tutorialIndex == steps.length - 1
                  ? 'Continue'
                  : 'Next (${(index + 1).toString().padLeft(2, '0')}/${steps.length.toString().padLeft(2, '0')})',
            ),
          ),
        ),
      ],
    ];
  }

  List<Widget> _completed(GestureController c) => [
    Positioned(
      left: 32,
      right: 32,
      top: 317,
      height: 324,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(28),
        ),
        padding: const EdgeInsets.fromLTRB(16, 26, 16, 16),
        child: Column(
          children: [
            Container(
              width: 100,
              height: 100,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const CustomPaint(painter: _CompletionCheck()),
            ),
            const SizedBox(height: 26),
            SizedBox(
              height: 32,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: LText(
                  c.tutorialGroup == TutorialGroup.video &&
                          c.hasSkippedSocialExercises
                      ? 'Practice complete'
                      : 'Congratulations',
                  maxLines: 1,
                  style: AppTypography.text(
                    24,
                    32,
                    color: AppColors.primary,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            LText(
              c.tutorialGroup == TutorialGroup.video &&
                      c.hasSkippedSocialExercises
                  ? 'You can practice skipped exercises again anytime.'
                  : 'You completed the training successfully',
              textAlign: TextAlign.center,
              style: AppTypography.text(14, 20, color: AppColors.textSecondary),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 44,
              child: OutlinedButton(
                onPressed: c.tutorialGroup == TutorialGroup.video
                    ? c.finishSocialTutorial
                    : c.continueAfterTutorial,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.textPrimary),
                  shape: const StadiumBorder(),
                ),
                child: LText(
                  c.tutorialGroup == TutorialGroup.video ? 'Finish' : 'Next',
                  style: AppTypography.text(
                    16,
                    24,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  ];

  Widget _stage(String label, bool highlighted, {bool compact = false}) =>
      Expanded(
        child: Column(
          children: [
            LText(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.text(
                compact ? 10 : 12,
                compact ? 15 : 18,
                color: highlighted
                    ? AppColors.primary
                    : AppColors.textSecondary,
              ),
            ),
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: highlighted ? AppColors.primary : AppColors.textPrimary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ],
        ),
      );
}

class _CompletionCheck extends CustomPainter {
  const _CompletionCheck();
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(size.width * .31, size.height * .53)
      ..lineTo(size.width * .43, size.height * .65)
      ..lineTo(size.width * .70, size.height * .37);
    canvas.drawPath(
      path,
      Paint()
        ..color = AppColors.background
        ..style = PaintingStyle.stroke
        ..strokeWidth = size.width * .07
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_CompletionCheck oldDelegate) => false;
}
