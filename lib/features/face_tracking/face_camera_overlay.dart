import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'face_tracking.dart';

/// Same contain transform as the visible, upright mirrored camera preview.
Offset faceOverlayPoint(Offset point, Size image, Size panel) {
  final scale = math.min(
    panel.width / image.width,
    panel.height / image.height,
  );
  return Offset(
    (panel.width - image.width * scale) / 2 + point.dx * image.width * scale,
    (panel.height - image.height * scale) / 2 + point.dy * image.height * scale,
  );
}

/// Shared artwork size, in the viewport's logical pixels. Active Face-mode
/// Home opts into following space; tutorial previews retain their sizing.
Size homeFaceSize(Size viewport, {bool happy = false, bool following = false}) {
  final landscape = viewport.width > viewport.height;
  final scale = landscape
      ? math.min(viewport.height * .56 / 200, viewport.width * .588 / 312)
      : math.min(viewport.width * .7 / 312, viewport.height * .392 / 200);
  var adjusted = happy
      ? math.min(scale * 1.4, (viewport.width - 36) / 312)
      : scale;
  if (following) {
    // Leave travel on both axes, including portrait's narrow width and
    // landscape's short height. The larger face must not consume its bounds.
    final fraction = happy ? .70 : .60;
    final availableWidth = math.max(1.0, viewport.width - 36);
    final availableHeight = math.max(1.0, viewport.height - 36);
    adjusted = math.min(
      adjusted,
      math.min(
        availableWidth * fraction / 312,
        availableHeight * fraction / 200,
      ),
    );
  }
  return Size(312 * adjusted, 200 * adjusted);
}

/// Reuses Home's artwork and size while anchoring it to the camera face.
class FaceCameraOverlay extends StatelessWidget {
  const FaceCameraOverlay({
    super.key,
    required this.face,
    required this.avatar,
    required this.viewport,
    this.happy = false,
  });
  final FaceObservation face;
  final Widget avatar;
  final Size viewport;
  final bool happy;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) {
      final center = faceOverlayPoint(
        face.center,
        face.imageSize,
        bounds.biggest,
      );
      final artwork = homeFaceSize(viewport, happy: happy);
      final eyes = face.eyeMeasurement?.points;
      var angle = 0.0;
      if (eyes != null && eyes.length == 8) {
        final a = faceOverlayPoint(
          (eyes[0] + eyes[1]) / 2,
          face.imageSize,
          bounds.biggest,
        );
        final b = faceOverlayPoint(
          (eyes[4] + eyes[5]) / 2,
          face.imageSize,
          bounds.biggest,
        );
        final axis = a.dx < b.dx ? b - a : a - b;
        angle = math.atan2(axis.dy, axis.dx);
      }
      return Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            left: center.dx - artwork.width / 2,
            top: center.dy - artwork.height / 2,
            width: artwork.width,
            height: artwork.height,
            child: Transform.rotate(
              angle: angle,
              child: FittedBox(
                child: SizedBox(width: 312, height: 200, child: avatar),
              ),
            ),
          ),
        ],
      );
    },
  );
}
