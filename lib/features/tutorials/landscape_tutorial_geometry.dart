import 'dart:math' as math;
import 'package:flutter/painting.dart';

/// Preserve the approved portrait guide's size in camera pixels when a tablet
/// widens the panel. The preview's cover crop and this guide use one scale.
Rect portraitTutorialOutlineRect({
  required Rect referenceOutline,
  required Size panelSize,
  required Size imageSize,
  required double referencePanelHeight,
}) {
  final referencePanel = Size(362, referencePanelHeight);
  final referenceScale = math.max(
    362 / imageSize.width,
    referencePanelHeight / imageSize.height,
  );
  final cameraScale = math.max(
    panelSize.width / imageSize.width,
    panelSize.height / imageSize.height,
  );
  final scale = cameraScale / referenceScale;
  return Rect.fromCenter(
    center:
        panelSize.center(Offset.zero) +
        (referenceOutline.center - referencePanel.center(Offset.zero)) * scale,
    width: referenceOutline.width * scale,
    height: referenceOutline.height * scale,
  );
}

/// Landscape uses the entire upright camera image. Both the visible guide and
/// detected landmarks share this fitted image rectangle, including its inset.
class LandscapeTutorialGeometry {
  LandscapeTutorialGeometry({
    required this.panelSize,
    required this.imageSize,
    required double portraitPanelHeight,
  }) : portraitPanelSize = Size(362, portraitPanelHeight);

  final Size panelSize;
  final Size imageSize;
  final Size portraitPanelSize;

  Rect get previewRect {
    final fitted = applyBoxFit(BoxFit.contain, imageSize, panelSize);
    return Alignment.center.inscribe(
      fitted.destination,
      Offset.zero & panelSize,
    );
  }

  Offset pointOnPreview(Offset normalized) => Offset(
    previewRect.left + normalized.dx * previewRect.width,
    previewRect.top + normalized.dy * previewRect.height,
  );

  /// Keep each approved pose the same size in camera pixels as in portrait.
  /// Scaling only by landscape panel height made tall poses ~25% too small.
  Rect outlineRect(Rect portraitOutline) {
    if (portraitOutline.isEmpty) return Rect.zero;
    final portraitImage = Size(imageSize.shortestSide, imageSize.longestSide);
    final portraitCameraScale = math.max(
      portraitPanelSize.width / portraitImage.width,
      portraitPanelSize.height / portraitImage.height,
    );
    final scale = previewRect.width / imageSize.width / portraitCameraScale;
    final center =
        previewRect.center +
        (portraitOutline.center - portraitPanelSize.center(Offset.zero)) *
            scale;
    return Rect.fromCenter(
      center: center,
      width: portraitOutline.width * scale,
      height: portraitOutline.height * scale,
    );
  }
}
