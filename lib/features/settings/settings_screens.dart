import 'package:hand_gesture/shared/app_dialog.dart';
import 'package:hand_gesture/shared/software_version_text.dart';
import 'package:hand_gesture/shared/logout_confirmation.dart';
import 'package:hand_gesture/shared/reaction_artwork.dart';
import 'package:hand_gesture/l10n/app_strings.dart';
import 'language_screen.dart';
import 'custom_color_picker.dart';
import 'package:hand_gesture/shared/layout/responsive_canvas.dart';
import 'package:hand_gesture/shared/layout/landscape_layout.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';

part 'settings_screens_landscape.dart';

const _aboutDescription =
    'lazivoo brings your device setup, gesture preferences and reactions together. Choose a camera position, select your hand, and follow the gesture tutorials. Select Face Gesture, Hand Gesture or Social Media Control from Settings. Personalize the on-screen face with your preferred emoji, reaction color and background, and revisit your setup and tutorials whenever you need.';

class SettingsScreens extends StatefulWidget {
  const SettingsScreens({super.key, required this.page});
  final FlowPage page;
  @override
  State<SettingsScreens> createState() => _SettingsScreensState();
}

class _SettingsScreensState extends State<SettingsScreens> {
  void _update(VoidCallback change) => setState(change);

  late int _emoji, _faceColor, _faceBackground;
  bool _saving = false;
  static const _customPickerEnabled = bool.fromEnvironment(
    'LAZIVOO_CUSTOM_COLORS',
  );
  int? _customReaction, _customBackground;

  @override
  void initState() {
    super.initState();
    final c = context.read<GestureController>();
    _emoji = c.faceEmoji;
    _faceColor = c.faceColor;
    _faceBackground = c.faceBackground;
    if (!AppColors.reactionColors.contains(_faceColor)) {
      _customReaction = _faceColor;
    }
    if (_faceBackground != AppColors.background.toARGB32() &&
        _faceBackground != AppColors.whiteBackgroundValue) {
      _customBackground = _faceBackground;
    }
  }

  Future<void> _pickColor(bool reaction) async {
    final original = reaction ? _faceColor : _faceBackground;
    final result = await showDialog<int>(
      context: context,
      builder: (_) => CustomColorPicker(
        color: Color(_faceColor),
        background: Color(_faceBackground),
        reaction: reaction,
        emoji: _emoji,
        onChanged: (color) {
          if (mounted) {
            setState(() {
              if (reaction) {
                _faceColor = color.toARGB32();
              } else {
                _faceBackground = color.toARGB32();
              }
            });
          }
        },
      ),
    );
    if (!mounted) return;
    setState(() {
      if (reaction) {
        _faceColor = result ?? original;
        if (result != null && !AppColors.reactionColors.contains(result)) {
          _customReaction = result;
        }
      } else {
        _faceBackground = result ?? original;
        if (result != null &&
            result != AppColors.background.toARGB32() &&
            result != AppColors.whiteBackgroundValue) {
          _customBackground = result;
        }
      }
    });
  }

  Widget _colorPalette(bool reaction) {
    final custom = reaction ? _customReaction : _customBackground;
    final values = reaction
        ? AppColors.reactionColors
        : [AppColors.background.toARGB32(), AppColors.whiteBackgroundValue];
    Widget swatch(int color, String label, Key key) => SizedBox(
      width: 44,
      height: 44,
      child: _swatchBody(
        Color(color),
        (reaction ? _faceColor : _faceBackground) == color,
        label,
        key,
        () => setState(() {
          if (reaction) {
            _faceColor = color;
          } else {
            _faceBackground = color;
          }
        }),
      ),
    );
    final selected = reaction ? _faceColor : _faceBackground;
    final entries = <(int, String, Key)>[
      for (var i = 0; i < values.length; i++)
        (
          values[i],
          reaction
              ? 'Reaction color ${['Blue', 'Pale green', 'Sky blue', 'White'][i]}'
              : (i == 0 ? 'Dark background' : 'White background'),
          ValueKey(
            reaction
                ? 'reaction-color-$i'
                : (i == 0 ? 'background-dark' : 'background-white'),
          ),
        ),
      if (custom != null)
        (
          custom,
          reaction ? 'Custom reaction color' : 'Custom background color',
          ValueKey(
            reaction ? 'custom-reaction-swatch' : 'custom-background-swatch',
          ),
        ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final entry in [
          ...entries.where((entry) => entry.$1 == selected),
          ...entries.where((entry) => entry.$1 != selected),
        ])
          swatch(entry.$1, entry.$2, entry.$3),
        if (_customPickerEnabled)
          SizedBox(
            width: 44,
            height: 44,
            child: IconButton(
              key: ValueKey(
                reaction ? 'add-reaction-color' : 'add-background-color',
              ),
              tooltip: tr(
                context,
                reaction ? 'Custom reaction color' : 'Custom background color',
              ),
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                side: const BorderSide(color: AppColors.border),
                shape: const CircleBorder(),
              ),
              onPressed: () => _pickColor(reaction),
              icon: const Icon(Icons.add, size: 24),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GestureController>();
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

  List<Widget> _content(GestureController c) {
    final title = switch (widget.page) {
      FlowPage.settings => 'Settings',
      FlowPage.selectMode => 'Select mode',
      FlowPage.reactions => 'Edit reactions',
      FlowPage.tutorialMenu => 'Tutorial',
      _ => 'About',
    };
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
            title,
            style: AppTypography.text(24, 32, weight: FontWeight.w700),
          ),
        ),
      ),
      if (widget.page == FlowPage.settings) ...[
        Positioned(
          left: 76,
          right: 76,
          top: 106,
          height: 24,
          child: _deviceSubtitle(c),
        ),
        Positioned(
          left: 338,
          top: 62,
          width: 44,
          height: 44,
          child: IconButton(
            tooltip: tr(context, 'Log out'),
            padding: EdgeInsets.zero,
            onPressed: () => confirmLogout(context, c),
            icon: Image.asset('assets/settings/logout.png'),
          ),
        ),
        _row(
          141,
          'Select default mode',
          'mode',
          () => c.open(FlowPage.selectMode),
        ),
        _row(213, 'Change camera point position', 'camera', c.editCamera),
        _row(285, 'Change hand', 'hand', c.editHand),
        _row(
          357,
          'Edit reactions',
          'reactions',
          () => c.open(FlowPage.reactions),
        ),
        _row(429, 'Tutorial', 'tutorial', () => c.open(FlowPage.tutorialMenu)),
        _row(501, 'Language', 'language', _openLanguage),
        _row(573, 'About', 'about', () => c.open(FlowPage.about)),
      ],
      if (widget.page == FlowPage.selectMode) ...[
        Positioned(
          left: 20,
          top: 141,
          child: LText(
            'Choose default mode',
            style: AppTypography.text(16, 24, weight: FontWeight.w500),
          ),
        ),
        Positioned(
          left: 36,
          top: 177,
          right: 20,
          child: RadioGroup<GestureMode>(
            groupValue: c.mode,
            onChanged: (value) {
              if (value != null) c.setMode(value);
            },
            child: Column(
              children: [
                for (final mode in GestureMode.values)
                  SizedBox(
                    height: 32,
                    child: InkWell(
                      onTap: () => c.setMode(mode),
                      child: Row(
                        children: [
                          SizedBox(width: 24, height: 24, child: _radio(mode)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: LText(
                              switch (mode) {
                                GestureMode.face => 'Face Gesture (Default)',
                                GestureMode.hand => 'Hand Gesture',
                                GestureMode.social => 'Social Media Control',
                              },
                              style: AppTypography.text(
                                12,
                                18,
                                color: c.mode == mode
                                    ? AppColors.white
                                    : AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
      if (widget.page == FlowPage.reactions) ..._reactions(c),
      if (widget.page == FlowPage.tutorialMenu) ...[
        _row(
          141,
          'Face Gesture Tutorial',
          'play',
          () => c.open(FlowPage.faceTutorial),
        ),
        _row(
          213,
          'Hand Gesture Tutorial',
          'play',
          () => c.replayTutorial(0, returnTo: FlowPage.tutorialMenu),
        ),
        _row(
          285,
          'Social Media Control Tutorial',
          'play',
          () => c.replayTutorial(
            0,
            group: TutorialGroup.video,
            returnTo: FlowPage.tutorialMenu,
          ),
        ),
      ],
      if (widget.page == FlowPage.about)
        Positioned(
          left: 20,
          right: 20,
          top: 141,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(
                _aboutDescription,
                style: AppTypography.text(
                  12,
                  18,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 32),
              SoftwareVersionText(
                style: AppTypography.text(
                  16,
                  24,
                  color: AppColors.textSecondary,
                  weight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 16),
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
    ];
  }

  Widget _row(double top, String text, String icon, VoidCallback? action) =>
      Positioned(
        left: 20,
        right: 20,
        top: top,
        height: 56,
        child: _settingsTile(text, icon, action),
      );

  void _openLanguage() => Navigator.of(
    context,
  ).push<void>(MaterialPageRoute(builder: (_) => const LanguageScreen()));

  Widget _deviceSubtitle(GestureController c) {
    final name = c.device?.trim();
    final label = name == null || name.isEmpty
        ? tr(context, 'No device selected')
        : name;
    return Semantics(
      label: tr(context, 'Device: $label'),
      child: InkWell(
        key: const ValueKey('settings-device-name'),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => AppDialog(
            title: 'Device',
            icon: Icons.bluetooth_rounded,
            content: Text(
              label,
              textAlign: TextAlign.center,
              style: AppTypography.text(15, 24, color: AppColors.textSecondary),
            ),
            actions: [appDialogAction('Close', () => Navigator.pop(context))],
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bluetooth, size: 14, color: AppColors.primary),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.text(
                  12,
                  18,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radio<T>(T value) => Radio<T>(
    value: value,
    side: WidgetStateBorderSide.resolveWith(
      (_) => const BorderSide(color: AppColors.textPrimary, width: 1.5),
    ),
    innerRadius: const WidgetStatePropertyAll(6),
    fillColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.selected)
          ? AppColors.primary
          : AppColors.textPrimary,
    ),
    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
  );

  List<Widget> _reactions(GestureController c) => [
    Positioned(
      left: 45,
      top: 175,
      width: 312,
      height: 200,
      child: ColoredBox(
        color: Color(_faceBackground),
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
    Positioned(
      left: 20,
      top: 477,
      child: LText(
        'Change Emoji',
        style: AppTypography.text(16, 24, weight: FontWeight.w500),
      ),
    ),
    Positioned(
      left: 20,
      top: 511,
      height: 40,
      child: RadioGroup<int>(
        groupValue: _emoji,
        onChanged: (value) {
          if (value != null) setState(() => _emoji = value);
        },
        child: Row(
          children: [
            for (var index = 0; index < 2; index++)
              SizedBox(
                width: 102,
                child: InkWell(
                  key: ValueKey('emoji-$index'),
                  onTap: () => setState(() => _emoji = index),
                  child: Row(
                    children: [
                      SizedBox(width: 24, height: 24, child: _radio(index)),
                      const SizedBox(width: 8),
                      reactionArtwork(
                        index == 0
                            ? 'assets/control/face.png'
                            : 'assets/settings/face-happy.png',
                        filterQuality: index != 0
                            ? FilterQuality.none
                            : FilterQuality.medium,
                        width: index == 0 ? 44 : 60,
                        height: 30,
                        fit: BoxFit.contain,
                        color: AppColors.avatarSurface,
                        colorBlendMode: BlendMode.srcIn,
                        excludeFromSemantics: true,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
    Positioned(
      left: 20,
      top: 583,
      child: LText(
        'Change reaction Color',
        style: AppTypography.text(16, 24, weight: FontWeight.w500),
      ),
    ),
    Positioned(left: 20, top: 621, width: 362, child: _colorPalette(true)),
    Positioned(
      left: 20,
      top: 693,
      child: LText(
        'Change Background Color',
        style: AppTypography.text(16, 24, weight: FontWeight.w500),
      ),
    ),
    Positioned(left: 20, top: 731, width: 362, child: _colorPalette(false)),
    Positioned(
      left: 20,
      top: 807,
      width: 362,
      height: 44,
      child: FilledButton(
        onPressed: _saving
            ? null
            : () async {
                setState(() => _saving = true);
                await c.saveAppearance(
                  emoji: _emoji,
                  color: _faceColor,
                  background: _faceBackground,
                );
                if (mounted) c.open(FlowPage.settings);
              },
        style: FilledButton.styleFrom(
          padding: EdgeInsets.zero,
          minimumSize: Size.zero,
          shape: const StadiumBorder(),
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.black,
          textStyle: AppTypography.text(16, 24, weight: FontWeight.w500),
        ),
        child: const LText('Save'),
      ),
    ),
  ];

  Widget _swatchBody(
    Color color,
    bool selected,
    String label,
    Key key,
    VoidCallback action,
  ) => Semantics(
    label: tr(context, label),
    button: true,
    selected: selected,
    child: InkWell(
      key: key,
      onTap: action,
      customBorder: const CircleBorder(),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.transparent,
          ),
        ),
        child: Center(
          child: selected
              ? Icon(
                  Icons.check,
                  size: 22,
                  color: AppColors.textOnBackground(color),
                )
              : null,
        ),
      ),
    ),
  );
}
