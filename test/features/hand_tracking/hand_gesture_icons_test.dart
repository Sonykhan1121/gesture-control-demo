import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/features/hand_tracking/hand_gesture_icons.dart';
import 'package:hand_gesture/features/tutorials/tutorial_outline_assets.dart';
import 'package:hand_gesture/features/tutorials/tutorial_steps.dart';
import 'package:image/image.dart' as img;

void main() {
  test(
    'every pose has separate transparent, filled skin-colored hand artwork',
    () {
      expect(HandGestureIcons.byPose.keys, unorderedEquals(HandPose.values));
      final assets = <String>{};
      for (final pose in HandPose.values) {
        for (final left in [true, false]) {
          final path = HandGestureIcons.forPose(pose, isLeftHand: left);
          expect(
            assets.add(path),
            isTrue,
            reason: 'Do not reuse another pose/hand icon',
          );
          expect(
            path,
            isNot(TutorialOutlineAssets.forPose(pose, isLeftHand: left)),
          );
          final file = File(path);
          expect(file.existsSync(), isTrue, reason: path);
          final image = img.decodePng(file.readAsBytesSync())!;
          expect(image.width, 384);
          expect(image.height, 384);
          expect(image.getPixel(0, 0).a, 0);
          expect(image.getPixel(383, 383).a, 0);
          var opaque = 0, skin = 0;
          for (final p in image) {
            if (p.a < 230) continue;
            opaque++;
            if (p.r > 150 && p.r > p.b + 20 && p.g > p.b + 5 && p.r > p.g) {
              skin++;
            }
          }
          expect(
            opaque,
            greaterThan(12000),
            reason: '$path must contain a filled hand, not just contour lines',
          );
          expect(
            skin / opaque,
            greaterThan(.75),
            reason: '$path must retain the skin palette',
          );
        }
        final pair = HandGestureIcons.byPose[pose]!;
        expect(
          File(pair.left).readAsBytesSync(),
          isNot(orderedEquals(File(pair.right).readAsBytesSync())),
          reason: '$pose must have distinct left/right artwork',
        );
      }
      expect(assets.length, 26);
    },
  );
}
