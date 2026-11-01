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
import 'package:hand_gesture/shared/camera/setup_camera_preview.dart';

part 'setup_screens_landscape.dart';

const _defaultPosition = Offset(.5, .5);

class SetupScreens extends StatefulWidget {
  const SetupScreens({super.key, required this.page});
  final FlowPage page;
  @override
  State<SetupScreens> createState() => _SetupScreensState();
}

class _SetupScreensState extends State<SetupScreens> {
  void _update(VoidCallback change) => setState(change);

  final _cameraKey = GlobalKey(debugLabel: 'setup-camera');
  late Offset _position;
  late String _hand;

  @override
  void initState() {
    super.initState();
    final c = context.read<GestureController>();
    _position = Offset(c.cameraX, c.cameraY);
    _hand = c.hand;
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

  List<Widget> _content(GestureController c) {
    final camera = widget.page == FlowPage.camera;
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
            camera ? 'Set position' : 'Choose hand',
            style: AppTypography.text(24, 32, weight: FontWeight.w700),
          ),
        ),
      ),
      Positioned(
        left: 20,
        right: 20,
        top: 134,
        height: 20,
        child: Center(
          child: LText(
            camera
                ? 'Set the camera to track you properly'
                : 'Select Hand to control the gestures',
            style: AppTypography.text(14, 20, color: AppColors.textSecondary),
          ),
        ),
      ),
      if (camera) ...[
        Positioned(
          left: 20,
          top: 164,
          width: 362,
          height: 594,
          child: LayoutBuilder(
            builder: (context, bounds) => Semantics(
              label: tr(context, 'Camera position area'),
              child: GestureDetector(
                key: const ValueKey('camera-position-area'),
                onTapDown: (event) =>
                    _moveMarker(event.localPosition, bounds.biggest),
                onPanStart: (event) =>
                    _moveMarker(event.localPosition, bounds.biggest),
                onPanUpdate: (event) =>
                    _moveMarker(event.localPosition, bounds.biggest),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: SetupCameraPreview(key: _cameraKey),
                      ),
                      Positioned(
                        left: _position.dx * bounds.maxWidth - 24,
                        top: _position.dy * bounds.maxHeight - 24,
                        child: Image.asset(
                          'assets/devices/face-position.png',
                          key: const ValueKey('face-position-marker'),
                          width: 48,
                          height: 48,
                          excludeFromSemantics: true,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 20,
          top: 807,
          width: 172,
          height: 44,
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              foregroundColor: _position == _defaultPosition
                  ? AppColors.disabledText
                  : AppColors.textPrimary,
              side: const BorderSide(color: AppColors.textPrimary),
              shape: const StadiumBorder(),
              textStyle: AppTypography.text(16, 24, weight: FontWeight.w500),
            ),
            onPressed: () => setState(() => _position = _defaultPosition),
            child: const LText('Restore'),
          ),
        ),
        Positioned(
          left: 212,
          top: 807,
          width: 170,
          height: 44,
          child: _save(() async {
            await c.setCameraPosition(_position.dx, _position.dy);
            c.finishCamera();
          }),
        ),
      ] else ...[
        _handOption('Left', 20, 'left-hand.png', 123),
        _handOption('Right', 209, 'right-hand.png', 124),
        Positioned(
          left: 19,
          top: 807,
          width: 362,
          height: 44,
          child: _save(() async {
            await c.setHand(_hand);
            c.finishHand();
          }),
        ),
      ],
    ];
  }

  void _moveMarker(Offset point, Size panel) => setState(() {
    _position = Offset(
      point.dx.clamp(24, panel.width - 24) / panel.width,
      point.dy.clamp(24, panel.height - 24) / panel.height,
    );
  });

  Widget _handOption(
    String hand,
    double left,
    String asset,
    double imageWidth,
  ) => Positioned(
    left: left,
    top: 202,
    width: 172,
    height: 261,
    child: Semantics(
      label: tr(context, '$hand Hand'),
      button: true,
      selected: _hand == hand,
      child: GestureDetector(
        key: ValueKey('select-${hand.toLowerCase()}-hand'),
        onTap: () => setState(() => _hand = hand),
        behavior: HitTestBehavior.opaque,
        child: Column(
          children: [
            SizedBox(
              height: 26,
              child: Row(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: RadioGroup<String>(
                      groupValue: _hand,
                      onChanged: (value) {
                        if (value != null) setState(() => _hand = value);
                      },
                      child: Radio<String>(
                        value: hand,
                        activeColor: AppColors.primary,
                        fillColor: WidgetStateProperty.resolveWith(
                          (states) => states.contains(WidgetState.selected)
                              ? AppColors.primary
                              : AppColors.textPrimary,
                        ),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: LText(
                      '$hand Hand',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.text(
                        18,
                        26,
                        weight: FontWeight.w500,
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: 172,
              height: 219,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Align(
                alignment: hand == 'Left'
                    ? Alignment.topLeft
                    : Alignment.center,
                child: Padding(
                  padding: hand == 'Left'
                      ? const EdgeInsets.only(left: 20, top: 21)
                      : EdgeInsets.zero,
                  child: Image.asset(
                    'assets/devices/$asset',
                    width: imageWidth,
                    height: 178,
                    fit: BoxFit.contain,
                    excludeFromSemantics: true,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _save(VoidCallback onTap) => FilledButton(
    onPressed: onTap,
    style: FilledButton.styleFrom(
      padding: EdgeInsets.zero,
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.black,
      shape: const StadiumBorder(),
      textStyle: AppTypography.text(16, 24, weight: FontWeight.w500),
    ),
    child: const LText('Save'),
  );
}
