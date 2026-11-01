part of 'settings_screens.dart';

extension _SettingsLandscape on _SettingsScreensState {
  Widget _settingsIcon(String icon, double size) => icon == 'language'
      ? SvgPicture.asset(
          'assets/settings/icon-language.svg',
          width: size,
          height: size,
          excludeFromSemantics: true,
        )
      : Image.asset(
          'assets/settings/icon-$icon.png',
          width: size,
          height: size,
          excludeFromSemantics: true,
        );

  Widget _settingsTile(
    String text,
    String icon,
    VoidCallback? action, {
    bool vertical = false,
    bool landscape = false,
  }) => Semantics(
    button: true,
    enabled: action != null,
    child: Opacity(
      opacity: vertical && action == null ? .45 : 1,
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: action,
          child: Padding(
            padding: EdgeInsets.all(vertical ? 20 : 10),
            child: vertical
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _settingsIcon(icon, 32),
                      const SizedBox(height: 20),
                      LText(
                        text,
                        style: AppTypography.text(
                          14,
                          22,
                          weight: FontWeight.w500,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      _settingsIcon(icon, 24),
                      const SizedBox(width: 16),
                      Expanded(
                        child: LText(
                          text,
                          maxLines: landscape ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.text(
                            landscape ? 14 : 16,
                            landscape ? 20 : 24,
                            weight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _landscape(GestureController c) {
    final title = switch (widget.page) {
      FlowPage.settings => 'Settings',
      FlowPage.selectMode => 'Select mode',
      FlowPage.reactions => 'Edit reactions',
      FlowPage.tutorialMenu => 'Tutorial',
      _ => 'About',
    };
    Widget body;
    switch (widget.page) {
      case FlowPage.settings:
        final entries = <(String, String, VoidCallback)>[
          ('Select default mode', 'mode', () => c.open(FlowPage.selectMode)),
          ('Change camera point position', 'camera', c.editCamera),
          ('Change hand', 'hand', c.editHand),
          ('Edit reactions', 'reactions', () => c.open(FlowPage.reactions)),
          ('Tutorial', 'tutorial', () => c.open(FlowPage.tutorialMenu)),
          ('Language', 'language', _openLanguage),
          ('About', 'about', () => c.open(FlowPage.about)),
        ];
        body = GridView.count(
          padding: EdgeInsets.zero,
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 18,
          mainAxisExtent: 64,
          children: [
            for (final (label, icon, action) in entries)
              _settingsTile(label, icon, action, landscape: true),
          ],
        );
      case FlowPage.selectMode:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              'Choose default mode',
              style: AppTypography.text(16, 24, weight: FontWeight.w500),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: RadioGroup<GestureMode>(
                groupValue: c.mode,
                onChanged: (value) {
                  if (value != null) c.setMode(value);
                },
                child: Row(
                  children: [
                    for (final mode in GestureMode.values) ...[
                      if (mode != GestureMode.face) const SizedBox(width: 16),
                      Expanded(
                        child: Material(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: mode == c.mode
                                  ? AppColors.primary
                                  : AppColors.border,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => c.setMode(mode),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Image.asset(
                                        'assets/settings/icon-${mode == GestureMode.face
                                            ? 'mode'
                                            : mode == GestureMode.hand
                                            ? 'hand'
                                            : 'play'}.png',
                                        width: 30,
                                        height: 30,
                                      ),
                                      const Spacer(),
                                      SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: _radio(mode),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  LText(switch (mode) {
                                    GestureMode.face =>
                                      'Face Gesture (Default)',
                                    GestureMode.hand => 'Hand Gesture',
                                    GestureMode.social =>
                                      'Social Media Control',
                                  }, style: AppTypography.text(13, 20)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      case FlowPage.tutorialMenu:
        body = Row(
          children: [
            Expanded(
              child: _settingsTile(
                'Face Gesture Tutorial',
                'play',
                () => c.open(FlowPage.faceTutorial),
                vertical: true,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _settingsTile(
                'Hand Gesture Tutorial',
                'play',
                () => c.replayTutorial(0, returnTo: FlowPage.tutorialMenu),
                vertical: true,
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: _settingsTile(
                'Social Media Control Tutorial',
                'play',
                () => c.replayTutorial(
                  0,
                  group: TutorialGroup.video,
                  returnTo: FlowPage.tutorialMenu,
                ),
                vertical: true,
              ),
            ),
          ],
        );
      case FlowPage.reactions:
        body = _landscapeReactions(c);
      default:
        body = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 6,
              child: SingleChildScrollView(
                child: LText(
                  _aboutDescription,
                  style: AppTypography.text(
                    13,
                    21,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 40),
            Expanded(
              flex: 4,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SoftwareVersionText(
                    style: AppTypography.text(
                      16,
                      24,
                      color: AppColors.textSecondary,
                      weight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 24),
                  LText(
                    'Firmware: 1.0.1',
                    style: AppTypography.text(
                      16,
                      24,
                      color: AppColors.textSecondary,
                      weight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
    }
    return LandscapePage(
      key: ValueKey('landscape-${widget.page.name}'),
      title: title,
      subtitle: widget.page == FlowPage.settings ? _deviceSubtitle(c) : null,
      onBack: c.back,
      action: widget.page == FlowPage.settings
          ? IconButton(
              tooltip: tr(context, 'Log out'),
              onPressed: () => confirmLogout(context, c),
              icon: Image.asset('assets/settings/logout.png'),
            )
          : null,
      child: body,
    );
  }

  Widget _landscapeReactions(GestureController c) => Row(
    children: [
      Expanded(
        child: ColoredBox(
          color: Color(_faceBackground),
          child: Center(
            child: FractionallySizedBox(
              widthFactor: .85,
              heightFactor: .8,
              child: reactionArtwork(
                _emoji == 0
                    ? 'assets/control/face.png'
                    : 'assets/settings/face-happy.png',
                filterQuality: _emoji != 0
                    ? FilterQuality.none
                    : FilterQuality.medium,
                key: const ValueKey('reaction-preview'),
                color: Color(_faceColor),
                colorBlendMode: BlendMode.srcIn,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 36),
      Expanded(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              LText('Change Emoji', style: AppTypography.text(14, 21)),
              const SizedBox(height: 8),
              RadioGroup<int>(
                groupValue: _emoji,
                onChanged: (value) {
                  if (value != null) _update(() => _emoji = value);
                },
                child: Row(
                  children: [
                    for (var i = 0; i < 2; i++)
                      InkWell(
                        key: ValueKey('emoji-$i'),
                        onTap: () => _update(() => _emoji = i),
                        child: Row(
                          children: [
                            SizedBox(width: 30, height: 30, child: _radio(i)),
                            reactionArtwork(
                              i == 0
                                  ? 'assets/control/face.png'
                                  : 'assets/settings/face-happy.png',
                              filterQuality: i != 0
                                  ? FilterQuality.none
                                  : FilterQuality.medium,
                              width: 50,
                              height: 30,
                              color: AppColors.avatarSurface,
                              colorBlendMode: BlendMode.srcIn,
                            ),
                            const SizedBox(width: 18),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          'Change reaction Color',
                          style: AppTypography.text(12, 18),
                        ),
                        const SizedBox(height: 8),
                        _colorPalette(true),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LText(
                          'Change Background Color',
                          style: AppTypography.text(12, 18),
                        ),
                        const SizedBox(height: 8),
                        _colorPalette(false),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              landscapeAction(
                'Save',
                _saving
                    ? null
                    : () async {
                        _update(() => _saving = true);
                        await c.saveAppearance(
                          emoji: _emoji,
                          color: _faceColor,
                          background: _faceBackground,
                        );
                        if (mounted) c.open(FlowPage.settings);
                      },
              ),
            ],
          ),
        ),
      ),
    ],
  );
}
