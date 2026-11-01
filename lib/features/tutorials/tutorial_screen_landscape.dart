part of 'tutorial_screen.dart';

extension _TutorialLandscape on _TutorialScreenState {
  Widget _landscape(GestureController c) {
    final step = c.tutorialSteps[c.tutorialIndex];
    final stages = Row(
      children: [
        _stage('Face Gesture', true, compact: true),
        const SizedBox(width: 3),
        _stage('Hand Gesture', true, compact: true),
        const SizedBox(width: 3),
        _stage(
          'Social Media',
          c.tutorialGroup == TutorialGroup.video,
          compact: true,
        ),
      ],
    );
    return LandscapePage(
      key: const ValueKey('landscape-tutorial'),
      title: 'Tutorial',
      onBack: c.back,
      child: c.page == FlowPage.tutorialCompleted
          ? Column(
              children: [
                SizedBox(width: 380, child: stages),
                Expanded(
                  child: Center(
                    child: SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 570),
                        child: Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 76,
                                height: 76,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const CustomPaint(
                                  painter: _CompletionCheck(),
                                ),
                              ),
                              const SizedBox(width: 24),
                              Expanded(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    LText(
                                      c.tutorialGroup == TutorialGroup.video &&
                                              c.hasSkippedSocialExercises
                                          ? 'Practice complete'
                                          : 'Congratulations',
                                      style: AppTypography.text(
                                        24,
                                        32,
                                        color: AppColors.primary,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    LText(
                                      c.tutorialGroup == TutorialGroup.video &&
                                              c.hasSkippedSocialExercises
                                          ? 'You can practice skipped exercises again anytime.'
                                          : 'You completed the training successfully',
                                      style: AppTypography.text(
                                        14,
                                        20,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    landscapeAction(
                                      c.tutorialGroup == TutorialGroup.video
                                          ? 'Finish'
                                          : 'Next',
                                      c.tutorialGroup == TutorialGroup.video
                                          ? c.finishSocialTutorial
                                          : c.continueAfterTutorial,
                                      secondary: true,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 6,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: ColoredBox(
                      color: AppColors.surface,
                      child: _cameraGuide(c, landscape: true),
                    ),
                  ),
                ),
                const SizedBox(width: 30),
                Expanded(
                  flex: 5,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      stages,
                      Expanded(
                        child: Center(
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LText(
                                  step.title,
                                  style: AppTypography.text(
                                    24,
                                    32,
                                    color: AppColors.primary,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                LText(
                                  step.instruction,
                                  style: AppTypography.text(
                                    14,
                                    21,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: landscapeAction(
                              'Skip',
                              c.skipTutorial,
                              secondary: true,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: landscapeAction(
                              c.tutorialIndex == c.tutorialSteps.length - 1
                                  ? 'Continue'
                                  : 'Next (${(c.tutorialIndex + 1).toString().padLeft(2, '0')}/${c.tutorialSteps.length.toString().padLeft(2, '0')})',
                              c.canAdvanceTutorial ? c.nextTutorial : null,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
