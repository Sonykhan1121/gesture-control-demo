import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hand_gesture/shared/settings_asset_warmup.dart';

void main() {
  testWidgets(
    'warmup leaves content visible and icons have a synchronous first frame',
    (tester) async {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      late BuildContext screen;
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsAssetWarmup(
            child: Builder(
              builder: (context) {
                screen = context;
                return const Text('Ready');
              },
            ),
          ),
        ),
      );
      expect(find.text('Ready'), findsOneWidget);
      await tester.runAsync(() => warmSettingsImages(screen));
      PaintingBinding.instance.imageCache.clear(); // Simulate cache pressure.
      final firstFrames = <String, bool>{};
      await tester.pumpWidget(
        MaterialApp(
          home: SettingsAssetWarmup(
            child: Column(
              children: [
                for (final asset in settingsRasterAssets)
                  Image.asset(
                    asset,
                    width: 24,
                    height: 24,
                    frameBuilder: (context, child, frame, sync) {
                      firstFrames.putIfAbsent(asset, () => sync);
                      return child;
                    },
                  ),
              ],
            ),
          ),
        ),
      );
      expect(firstFrames.keys, containsAll(settingsRasterAssets));
      expect(firstFrames.values, everyElement(isTrue));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    },
  );
}
