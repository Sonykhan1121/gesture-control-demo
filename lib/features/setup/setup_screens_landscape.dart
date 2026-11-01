part of 'setup_screens.dart';

extension _SetupLandscape on _SetupScreensState {
  Widget _landscape(GestureController c) {
    final camera = widget.page == FlowPage.camera;
    return LandscapePage(
      key: ValueKey('landscape-${widget.page.name}'),
      title: camera ? 'Set position' : 'Choose hand',
      onBack: c.back,
      child: Row(
        children: [
          Expanded(
            flex: 6,
            child: camera
                ? LayoutBuilder(
                    builder: (context, box) {
                      void move(Offset point) => _update(() {
                        _position = Offset(
                          point.dx.clamp(24, box.maxWidth - 24) / box.maxWidth,
                          point.dy.clamp(24, box.maxHeight - 24) /
                              box.maxHeight,
                        );
                      });
                      return Semantics(
                        label: tr(context, 'Camera position area'),
                        child: GestureDetector(
                          key: const ValueKey('camera-position-area'),
                          onTapDown: (e) => move(e.localPosition),
                          onPanStart: (e) => move(e.localPosition),
                          onPanUpdate: (e) => move(e.localPosition),
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
                                  left: _position.dx * box.maxWidth - 24,
                                  top: _position.dy * box.maxHeight - 24,
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
                      );
                    },
                  )
                : Row(
                    children: [
                      Expanded(child: _landscapeHand('Left')),
                      const SizedBox(width: 16),
                      Expanded(child: _landscapeHand('Right')),
                    ],
                  ),
          ),
          const SizedBox(width: 32),
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LText(
                  camera
                      ? 'Set the camera to track you properly'
                      : 'Select Hand to control the gestures',
                  style: AppTypography.text(
                    17,
                    26,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 30),
                Row(
                  children: [
                    if (camera) ...[
                      Expanded(
                        child: landscapeAction(
                          'Restore',
                          () => _update(() => _position = _defaultPosition),
                          secondary: true,
                        ),
                      ),
                      const SizedBox(width: 14),
                    ],
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: _save(() async {
                          if (camera) {
                            await c.setCameraPosition(
                              _position.dx,
                              _position.dy,
                            );
                            c.finishCamera();
                          } else {
                            await c.setHand(_hand);
                            c.finishHand();
                          }
                        }),
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

  Widget _landscapeHand(String hand) => Semantics(
    label: tr(context, '$hand Hand'),
    button: true,
    selected: _hand == hand,
    child: InkWell(
      key: ValueKey('select-${hand.toLowerCase()}-hand'),
      onTap: () => _update(() => _hand = hand),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                _hand == hand
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 20,
                color: _hand == hand
                    ? AppColors.primary
                    : AppColors.textPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LText('$hand Hand', style: AppTypography.text(16, 24)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _hand == hand
                      ? AppColors.primary.withValues(alpha: .4)
                      : AppColors.transparent,
                ),
              ),
              child: Image.asset(
                'assets/devices/${hand.toLowerCase()}-hand.png',
                fit: BoxFit.contain,
                excludeFromSemantics: true,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
