import 'package:hand_gesture/l10n/app_strings.dart';
import 'package:hand_gesture/app/theme/app_colors.dart';
import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Owns a camera only while its screen is visible and foregrounded.
class SetupCameraPreview extends StatefulWidget {
  const SetupCameraPreview({
    super.key,
    this.onFrame,
    this.onError,
    this.showPreview = true,
    this.requireFrontCamera = false,
    this.resolutionPreset = ResolutionPreset.medium,
    this.fit = BoxFit.cover,
    this.orientedPreviewSize,
    this.previewBuilder,
  });

  final ValueChanged<String?>? onError;
  final bool showPreview;
  final bool requireFrontCamera;
  final ResolutionPreset resolutionPreset;

  /// Landscape tutorials show the whole image and use the actual upright
  /// recognition dimensions. Other callers retain the existing cover preview.
  final BoxFit fit;
  final Size? orientedPreviewSize;

  /// Builds a frame around the initialized preview using its upright dimensions.
  /// Rebuilds when the native camera orientation changes, even without a face.
  final Widget Function(BuildContext, Size, Widget)? previewBuilder;

  final void Function(CameraImage, CameraDescription, DeviceOrientation)?
  onFrame;

  @override
  State<SetupCameraPreview> createState() => _SetupCameraPreviewState();
}

class _SetupCameraPreviewState extends State<SetupCameraPreview>
    with WidgetsBindingObserver {
  CameraController? _controller;
  // Serialize ownership across screens, not only within one widget instance.
  static Future<void>? _queue;
  static _SetupCameraPreviewState? _owner;
  bool _foreground = true;
  int _generation = 0;
  String? _error;
  bool _accessDenied = false;

  bool get _hasAppSettings =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  void _retryCamera() {
    // Only a deliberate retry can ask again after a denied permission.
    _accessDenied = false;
    _updateCamera();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _updateCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground = state == AppLifecycleState.resumed;
    if (foreground == _foreground) return;
    _foreground = foreground;
    _updateCamera();
  }

  @override
  void didUpdateWidget(covariant SetupCameraPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.resolutionPreset != widget.resolutionPreset ||
        oldWidget.requireFrontCamera != widget.requireFrontCamera ||
        (oldWidget.onFrame == null) != (widget.onFrame == null)) {
      _updateCamera();
    }
  }

  void _updateCamera() {
    // Serialize initialization/disposal, including camera permission dialogs.
    // Invalidate frames immediately. Even a quick inactive -> resumed pair
    // must replace the interrupted controller rather than reuse it.
    final generation = ++_generation;
    final operation = (_queue ?? Future<void>.value()).then(
      (_) => _reconcile(generation),
    );
    _queue = operation;
    unawaited(
      operation.then((_) {
        if (identical(_queue, operation)) _queue = null;
      }),
    );
  }

  bool _isCurrent(int generation) =>
      mounted && _foreground && generation == _generation;

  Future<void> _disposeController(CameraController controller) async {
    // camera 0.10.x dispose() does not cancel its image-stream subscription.
    // Await cancellation BEFORE disposing or creating the next camera: the
    // platform's image stream is shared between controller instances.
    try {
      if (controller.value.isStreamingImages) {
        await controller.stopImageStream();
      }
    } catch (error) {
      debugPrint('Camera stream cleanup failed: $error');
    } finally {
      try {
        await controller.dispose();
      } catch (error) {
        // A camera already closed by the OS must not poison the shared queue
        // and prevent every subsequent tutorial/face screen from initializing.
        debugPrint('Camera disposal failed: $error');
      }
    }
  }

  Future<void> _release() async {
    final controller = _controller;
    _controller = null;
    if (identical(_owner, this)) _owner = null;
    if (mounted) setState(() {});
    if (controller != null) await _disposeController(controller);
  }

  Future<void> _reconcile(int generation) async {
    CameraController? candidate;
    try {
      if (generation != _generation) return;
      await _release();
      if (!_isCurrent(generation)) return;
      // A new route can initialize before the previous route is disposed.
      // Release the old camera before requesting another native controller.
      if (_owner != null && !identical(_owner, this)) {
        await _owner!._release();
      }
      if (!_isCurrent(generation)) return;
      if (_accessDenied && _hasAppSettings) {
        // Permission dialogs themselves produce inactive/resumed events. A
        // queued resume must retain the denial, rather than open another dialog.
        // A grant made in Settings can recover without a second user action.
        final permission = await Permission.camera.status;
        if (!_isCurrent(generation)) return;
        if (!permission.isGranted) return;
        _accessDenied = false;
      }
      setState(() => _error = null);
      final cameras = await availableCameras();
      if (!_isCurrent(generation)) return;
      if (cameras.isEmpty) {
        setState(() => _error = 'No camera available on this device.');
        return;
      }
      if (widget.requireFrontCamera &&
          !cameras.any((c) => c.lensDirection == CameraLensDirection.front)) {
        setState(() => _error = 'Face tracking requires a front camera.');
        return;
      }
      final camera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      candidate = CameraController(
        camera,
        widget.resolutionPreset,
        enableAudio: false,
        imageFormatGroup: defaultTargetPlatform == TargetPlatform.iOS
            ? ImageFormatGroup.bgra8888
            : ImageFormatGroup.yuv420,
      );
      await candidate.initialize();
      if (!_isCurrent(generation)) return;
      final initialized = candidate;
      if (widget.onFrame != null) {
        await initialized.startImageStream((image) {
          if (_isCurrent(generation) && identical(_controller, initialized)) {
            widget.onFrame?.call(
              image,
              camera,
              initialized.value.deviceOrientation,
            );
          }
        });
      }
      if (!_isCurrent(generation)) return;
      setState(() {
        _controller = initialized;
        _owner = this;
      });
      candidate = null; // Ownership transferred; finally only cleans failures.
    } on CameraException catch (error) {
      final denied = error.code.startsWith('CameraAccess');
      // Do not discard a permission decision merely because its dialog changed
      // the lifecycle generation. The next queued attempt needs that decision.
      if (!mounted || (!denied && !_isCurrent(generation))) return;
      setState(() {
        _accessDenied = denied;
        _error = denied
            ? 'Allow camera access in phone Settings, then return.'
            : 'Camera unavailable. Please try again.';
      });
    } on MissingPluginException {
      if (_isCurrent(generation)) {
        setState(() => _error = 'Camera unavailable on this device.');
      }
    } catch (_) {
      if (_isCurrent(generation)) {
        setState(() => _error = 'Camera unavailable. Please try again.');
      }
    } finally {
      if (mounted && (_isCurrent(generation) || _accessDenied)) {
        widget.onError?.call(_error);
      }
      if (candidate != null) await _disposeController(candidate);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foreground = false;
    // An in-flight initialization finishes before its resources are released.
    _updateCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      if (!widget.showPreview) return const SizedBox.expand();
      return ValueListenableBuilder<CameraValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final landscape =
              value.deviceOrientation == DeviceOrientation.landscapeLeft ||
              value.deviceOrientation == DeviceOrientation.landscapeRight;
          final size = value.previewSize!;
          final oriented =
              widget.orientedPreviewSize ??
              Size(
                landscape ? size.width : size.height,
                landscape ? size.height : size.width,
              );
          final preview = ClipRect(
            child: SizedBox.expand(
              child: FittedBox(
                fit: widget.fit,
                child: SizedBox(
                  width: oriented.width,
                  height: oriented.height,
                  child: CameraPreview(controller),
                ),
              ),
            ),
          );
          return widget.previewBuilder?.call(context, oriented, preview) ??
              preview;
        },
      );
    }
    if (_error == null) return const SizedBox.expand();
    return Align(
      alignment: Alignment.bottomCenter,
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LText(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                ),
              ),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                children: [
                  TextButton(
                    onPressed: _retryCamera,
                    child: const LText('Retry'),
                  ),
                  if (_accessDenied && _hasAppSettings)
                    TextButton(
                      onPressed: () async {
                        await openAppSettings();
                      },
                      child: const LText('Open Settings'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
