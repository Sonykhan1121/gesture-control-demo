import 'package:hand_gesture/shared/logout_confirmation.dart';
import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/features/face_tracking/face_camera_overlay.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'package:hand_gesture/shared/app_toast.dart';
import 'package:hand_gesture/app/theme/app_typography.dart';
import 'package:hand_gesture/app/theme/app_theme.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:hand_gesture/app/flow/gesture_controller.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking_eyes.dart';
import 'package:hand_gesture/features/face_tracking/face_tracking.dart';
import 'package:hand_gesture/features/face_tracking/face_movement_debug.dart';
import 'package:hand_gesture/features/hand_tracking/hand_gesture_overlay.dart';

const _faceDebugDefault = bool.fromEnvironment('LAZIVOO_FACE_DEBUG');
const _handDebugDefault = bool.fromEnvironment('LAZIVOO_HAND_DEBUG');
const _movementDebugDefault = bool.fromEnvironment(
  'LAZIVOO_FACE_MOVEMENT_DEBUG',
);

class ControlScreen extends StatefulWidget {
  const ControlScreen({
    super.key,
    this.enableMouthDebug = false,
    this.enableEyeDebug = false,
    this.enableHandDebug = _handDebugDefault,
    this.showEyeStatus = false,
    this.enableFaceDebug = _faceDebugDefault,
    this.enableMovementDebug = _movementDebugDefault,
  });
  final bool enableMouthDebug;
  final bool enableEyeDebug;
  final bool enableHandDebug;
  final bool showEyeStatus;
  final bool enableFaceDebug;
  final bool enableMovementDebug;
  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  bool _showHandNotice = false;
  bool _showMouthDebug = true;
  bool _showEyeDebug = true;
  bool _showFaceDebug = true;
  bool _showMovementDebug = true;
  final _faceShift = ValueNotifier(Offset.zero);
  bool _landscapeDebugLeft = false;
  bool _portraitDebugTop = false;
  Timer? _noticeTimer;

  @override
  void initState() {
    super.initState();
    _showHandNotice =
        context.read<GestureController>().mode == GestureMode.hand;
    if (_showHandNotice) {
      _noticeTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _showHandNotice = false);
      });
    }
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    _faceShift.dispose();
    super.dispose();
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
        value: AppTheme.systemBars(background: Color(c.faceBackground)),
        child: Scaffold(
          backgroundColor: Color(c.faceBackground),
          body: MediaQuery.withClampedTextScaling(
            minScaleFactor: 1,
            child: LayoutBuilder(
              builder: (context, viewport) {
                if (viewport.maxWidth <= 0 || viewport.maxHeight <= 0) {
                  return const SizedBox.shrink();
                }
                final landscape = viewport.maxWidth > viewport.maxHeight;
                final referenceWidth = landscape ? 874.0 : 402.0;
                final referenceHeight = landscape ? 402.0 : 874.0;
                final scale = math.min(
                  viewport.maxWidth / referenceWidth,
                  viewport.maxHeight / referenceHeight,
                );
                final designWidth = viewport.maxWidth / scale;
                final designHeight = viewport.maxHeight / scale;
                return Align(
                  alignment: landscape ? Alignment.center : Alignment.topCenter,
                  child: SizedBox(
                    width: designWidth * scale,
                    height: designHeight * scale,
                    child: FittedBox(
                      fit: BoxFit.fill,
                      child: SizedBox(
                        key: ValueKey(
                          landscape ? 'home-horizontal' : 'home-vertical',
                        ),
                        width: designWidth,
                        height: designHeight,
                        child: Stack(
                          children: _content(
                            c,
                            landscape,
                            Size(designWidth, designHeight),
                            headerTop:
                                (MediaQuery.paddingOf(context).top + 8) / scale,
                            previewSafePadding:
                                MediaQuery.viewPaddingOf(context) / scale,
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
    );
  }

  List<Widget> _content(
    GestureController c,
    bool landscape,
    Size canvas, {
    required double headerTop,
    required EdgeInsets previewSafePadding,
  }) {
    final faceDebugVisible =
        widget.enableFaceDebug && _showFaceDebug && c.mode == GestureMode.face;
    final movementDebugEnabled =
        widget.enableMovementDebug && c.mode == GestureMode.face;
    final movementDebugScale = math.max(
      1.0,
      canvas.width / MediaQuery.sizeOf(context).width,
    );
    final movementLegendWidth = math.min(
      336 * movementDebugScale,
      canvas.width - 40,
    );
    final eyeStatusOnly =
        widget.showEyeStatus &&
        !faceDebugVisible &&
        !widget.enableEyeDebug &&
        !widget.enableMouthDebug;
    final cameraPreviewVisible =
        c.mode == GestureMode.face &&
        !faceDebugVisible &&
        !(widget.enableEyeDebug && _showEyeDebug) &&
        !(widget.enableMouthDebug && _showMouthDebug) &&
        !eyeStatusOnly;
    // Uniform sizing keeps the eyes, mouth and their spacing proportional.
    // Screen fractions can grow the artwork on larger displays as well as
    // shrink it for short landscape viewports; there is no fixed 1x cap.
    final faceScale = landscape || c.mode == GestureMode.face
        ? homeFaceSize(
                canvas,
                happy: c.faceEmoji == 1,
                following: c.mode == GestureMode.face,
              ).width /
              312
        : c.faceEmoji == 1
        ? math.min(1.4, (canvas.width - 36) / 312)
        : 1.0;
    final faceWidth = 312 * faceScale, faceHeight = 200 * faceScale;
    final faceLeft = (canvas.width - faceWidth) / 2;
    final faceTop = (canvas.height - faceHeight) / 2;
    final locationPanelWidth = landscape
        ? math.min(244.0, (canvas.width - faceWidth) / 2 - 40)
        : 362.0;
    final locationPanelLeft = landscape
        ? (_landscapeDebugLeft ? 20.0 : canvas.width - 20 - locationPanelWidth)
        : (canvas.width - 362) / 2;
    final locationPanelTop = landscape
        ? (_landscapeDebugLeft ? 219.0 : 175.0)
        : (_portraitDebugTop ? 226.0 : canvas.height - 188);
    // Derive each pair from the same nonnegative extent. Subtracting the
    // opposite edges independently can invert a zero-width range by rounding.
    final horizontalTravel = math.max(0.0, faceLeft - 18) / faceScale;
    final verticalTravel = math.max(0.0, faceTop - 18) / faceScale;
    final movementBounds = Rect.fromLTRB(
      -horizontalTravel,
      -verticalTravel,
      horizontalTravel,
      verticalTravel,
    );
    final screenMapping = FaceScreenMapping(
      viewport: canvas,
      avatar: Rect.fromLTWH(faceLeft, faceTop, faceWidth, faceHeight),
    );
    final movementGeometry = FaceMovementGeometry(
      mapping: screenMapping,
      limits: movementBounds,
      happy: c.faceEmoji != 0,
    );
    final children = <Widget>[
      Positioned(
        left: landscape ? 50 : 20,
        top: headerTop,
        width: 240,
        height: 46,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LText(
              'Hello!',
              style: AppTypography.text(
                12,
                18,
                color: AppColors.textOnBackground(Color(c.faceBackground)),
              ),
            ),
            Text(
              c.preferences.getBool('gesture.guestSession') == true
                  ? tr(context, 'Guest')
                  : c.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.text(
                20,
                28,
                weight: FontWeight.w500,
                color: AppColors.textOnBackground(Color(c.faceBackground)),
              ),
            ),
          ],
        ),
      ),
      Positioned(
        left: landscape ? 50 : 20,
        top: headerTop + 64,
        width: 226,
        height: 44,
        child: Align(
          alignment: Alignment.centerLeft,
          child: PopupMenuButton<GestureMode>(
            key: const ValueKey('home-mode-badge'),
            tooltip: tr(context, 'Change mode'),
            color: AppColors.surface,
            position: PopupMenuPosition.under,
            initialValue: c.mode,
            onSelected: c.setMode,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            itemBuilder: (context) => [
              for (final mode in GestureMode.values)
                PopupMenuItem(
                  key: ValueKey('home-mode-${mode.name}'),
                  value: mode,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _modeIcon(mode),
                        size: 18,
                        color: mode == c.mode
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: LText(
                          '${mode.label} mode',
                          style: AppTypography.text(
                            14,
                            21,
                            color: mode == c.mode
                                ? AppColors.primary
                                : AppColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (mode == c.mode)
                        const Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                    ],
                  ),
                ),
            ],
            child: Semantics(
              label: tr(context, 'Current mode: ${c.mode.label}. Change mode'),
              button: true,
              excludeSemantics: true,
              child: Container(
                constraints: const BoxConstraints(minHeight: 44),
                padding: const EdgeInsets.symmetric(
                  horizontal: 13,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_modeIcon(c.mode), size: 17, color: AppColors.primary),
                    const SizedBox(width: 9),
                    Flexible(
                      child: LText(
                        '${c.mode.label} mode',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.text(
                          13,
                          20,
                          weight: FontWeight.w500,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: canvas.width - (landscape ? 155 : 123),
        top: headerTop,
        width: 44,
        height: 44,
        child: IconButton(
          tooltip: tr(context, 'Settings'),
          padding: EdgeInsets.zero,
          onPressed: () => c.openSettings(),
          icon: Image.asset(
            'assets/devices/settings-button.png',
            width: 44,
            height: 44,
          ),
        ),
      ),
      Positioned(
        left: canvas.width - (landscape ? 95 : 63),
        top: headerTop,
        width: 44,
        height: 44,
        child: PopupMenuButton<String>(
          tooltip: tr(context, 'Profile'),
          color: AppColors.surface,
          padding: EdgeInsets.zero,
          onSelected: (value) {
            if (value == 'logout') confirmLogout(context, c);
          },
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Text(
                c.preferences.getBool('gesture.guestSession') == true
                    ? tr(context, 'Guest')
                    : c.name,
                style: AppTypography.text(16, 24),
              ),
            ),
            PopupMenuItem(
              value: 'logout',
              child: LText('Log out', style: AppTypography.text(14, 20)),
            ),
          ],
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              c.name.trim().isEmpty
                  ? 'G'
                  : c.name.trim().characters.first.toUpperCase(),
              style: AppTypography.text(24, 32),
            ),
          ),
        ),
      ),
      Positioned.fill(
        child: FaceTrackingEyes(
          enabled: c.mode == GestureMode.face,
          happy: c.faceEmoji != 0,
          color: Color(c.faceColor),
          key: const ValueKey('home-face-tracking'),
          showEyeStatus: widget.showEyeStatus,
          faceDebugEnabled: faceDebugVisible,
          showCameraPreview: cameraPreviewVisible,
          cameraPreviewBuilder: cameraPreviewVisible
              ? (context, size, preview) => Align(
                  alignment: Alignment.bottomLeft,
                  child: AspectRatio(
                    aspectRatio: size.aspectRatio,
                    child: DecoratedBox(
                      key: const ValueKey('home-face-camera-frame'),
                      position: DecorationPosition.foreground,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: preview,
                      ),
                    ),
                  ),
                )
              : null,
          movementBounds: movementBounds,
          screenMapping: screenMapping,
          savedStartPosition: c.mode == GestureMode.face
              ? Offset(c.cameraX, c.cameraY)
              : null,
          onPositionChanged: (shift) {
            if (movementDebugEnabled) _faceShift.value = shift;
            if (!faceDebugVisible) return;
            if (!landscape) {
              final y = canvas.height / 2 + shift.dy * faceScale;
              final threshold = (226 + 168 + canvas.height - 188) / 2;
              final dockTop = y > threshold + 8
                  ? true
                  : y < threshold - 8
                  ? false
                  : _portraitDebugTop;
              if (dockTop != _portraitDebugTop) {
                setState(() => _portraitDebugTop = dockTop);
              }
              return;
            }
            final x = shift.dx * faceScale;
            final dockLeft = x > 8
                ? true
                : x < -8
                ? false
                : _landscapeDebugLeft;
            if (dockLeft != _landscapeDebugLeft) {
              setState(() => _landscapeDebugLeft = dockLeft);
            }
          },
          debugEnabled:
              widget.enableMouthDebug &&
              c.mode == GestureMode.face &&
              _showMouthDebug,
          eyeDebugEnabled:
              widget.enableEyeDebug &&
              c.mode == GestureMode.face &&
              _showEyeDebug,
          layoutBuilder: (context, face, diagnostics) => Stack(
            children: [
              Positioned(
                left: faceLeft,
                top: faceTop,
                width: faceWidth,
                height: faceHeight,
                child: SizedBox(
                  key: const ValueKey('home-face'),
                  width: faceWidth,
                  height: faceHeight,
                  child: FittedBox(
                    child: SizedBox(width: 312, height: 200, child: face),
                  ),
                ),
              ),
              if (movementDebugEnabled && _showMovementDebug)
                Positioned.fill(
                  child: IgnorePointer(
                    child: ValueListenableBuilder<Offset>(
                      valueListenable: _faceShift,
                      builder: (context, shift, _) => CustomPaint(
                        key: const ValueKey('home-face-movement-limits'),
                        painter: FaceMovementLimitsPainter(
                          geometry: movementGeometry,
                          currentShift: shift,
                          uiScale: movementDebugScale,
                        ),
                      ),
                    ),
                  ),
                ),
              if (cameraPreviewVisible)
                Positioned(
                  key: const ValueKey('home-face-camera-preview'),
                  left: 20 + previewSafePadding.left,
                  bottom: 20 + previewSafePadding.bottom,
                  width: math.min(180, canvas.width * .26),
                  height: math.min(180, canvas.height * .26),
                  child: diagnostics,
                )
              else
                Positioned(
                  left: faceDebugVisible && landscape
                      ? locationPanelLeft
                      : eyeStatusOnly
                      ? (landscape ? 20 : 45)
                      : 20,
                  top: faceDebugVisible
                      ? locationPanelTop
                      : eyeStatusOnly
                      ? (landscape ? 175 : 594)
                      : (landscape ? 131 : 594),
                  width: faceDebugVisible && landscape
                      ? locationPanelWidth
                      : eyeStatusOnly
                      ? (landscape ? 236 : 312)
                      : (landscape ? 236 : 362),
                  height: faceDebugVisible
                      ? (landscape
                            ? canvas.height - locationPanelTop - 24
                            : 168)
                      : eyeStatusOnly
                      ? 54
                      : (landscape ? 247 : 250),
                  child: diagnostics,
                ),
            ],
          ),
        ),
      ),
      Positioned.fill(
        child: HandGestureOverlay(
          key: const ValueKey('home-hand-tracking'),
          enabled: c.mode == GestureMode.hand,
          selectedHand: c.hand,
          landscape: landscape,
          debugEnabled: widget.enableHandDebug,
        ),
      ),
      if (movementDebugEnabled)
        Positioned(
          left: landscape ? canvas.width - 20 - movementLegendWidth : 20,
          top: headerTop + (landscape ? 64 : 120),
          width: movementLegendWidth,
          child: FaceMovementDebugLegend(
            geometry: movementGeometry,
            visible: _showMovementDebug,
            uiScale: movementDebugScale,
            onToggle: () =>
                setState(() => _showMovementDebug = !_showMovementDebug),
          ),
        ),
      if (widget.enableEyeDebug && c.mode == GestureMode.face)
        Positioned(
          left: landscape ? 50 : 20,
          top: landscape ? 95 : 554,
          height: 32,
          child: TextButton.icon(
            key: const ValueKey('eye-debug-toggle'),
            onPressed: () => setState(() => _showEyeDebug = !_showEyeDebug),
            icon: const Icon(Icons.bug_report_outlined, size: 16),
            label: LText(_showEyeDebug ? 'Hide eye debug' : 'Eye debug'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textOnBackground(
                Color(c.faceBackground),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      if (widget.enableFaceDebug && c.mode == GestureMode.face)
        Positioned(
          left: landscape ? locationPanelLeft : 20,
          top: landscape ? (_landscapeDebugLeft ? 175 : 131) : 185,
          height: 32,
          child: TextButton.icon(
            key: const ValueKey('face-debug-toggle'),
            onPressed: () => setState(() => _showFaceDebug = !_showFaceDebug),
            icon: const Icon(Icons.bug_report_outlined, size: 16),
            label: LText(
              _showFaceDebug ? 'Hide location debug' : 'Location debug',
            ),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textOnBackground(
                Color(c.faceBackground),
              ),
            ),
          ),
        ),
      if (!widget.enableEyeDebug &&
          widget.enableMouthDebug &&
          c.mode == GestureMode.face)
        Positioned(
          left: landscape ? 50 : 20,
          top: landscape ? 95 : 554,
          height: 32,
          child: TextButton.icon(
            key: const ValueKey('mouth-debug-toggle'),
            onPressed: () => setState(() => _showMouthDebug = !_showMouthDebug),
            icon: const Icon(Icons.bug_report_outlined, size: 16),
            label: LText(_showMouthDebug ? 'Hide mouth debug' : 'Mouth debug'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textOnBackground(
                Color(c.faceBackground),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
          ),
        ),
      if (_showHandNotice)
        Positioned(
          left: 24,
          right: 24,
          bottom: 24,
          child: Center(
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: const AppToastCard(
                message: 'Hand gesture control enabled',
              ),
            ),
          ),
        ),
    ];
    // Keep Home controls reachable when the avatar travels across their area.
    return [...children.skip(4), ...children.take(4)];
  }

  IconData _modeIcon(GestureMode mode) => switch (mode) {
    GestureMode.face => Icons.face_outlined,
    GestureMode.hand => Icons.pan_tool_outlined,
    GestureMode.social => Icons.smartphone_outlined,
  };
}
