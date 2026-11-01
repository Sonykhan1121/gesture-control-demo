import 'dart:math' as math;
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/tutorials/landscape_tutorial_geometry.dart';

void main() {
  test('tablet guide retains its approved size relative to preview pixels', () {
    const image = Size(480, 640);
    const outline = Rect.fromLTWH(80, 130, 200, 260);
    const source = Size(362, 536);
    for (final panel in [source, const Size(472, 536), const Size(620, 760)]) {
      final painted = portraitTutorialOutlineRect(
        referenceOutline: outline,
        panelSize: panel,
        imageSize: image,
        referencePanelHeight: source.height,
      );
      final referenceScale = math.max(
        source.width / image.width,
        source.height / image.height,
      );
      final scale = math.max(
        panel.width / image.width,
        panel.height / image.height,
      );
      expect(
        painted.width / scale,
        closeTo(outline.width / referenceScale, .00001),
      );
      expect(
        painted.height / scale,
        closeTo(outline.height / referenceScale, .00001),
      );
      if (panel == source) expect(painted, outline);
    }
  });
}
