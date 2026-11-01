import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

const settingsRasterAssets = [
  'assets/settings/icon-mode.png',
  'assets/settings/icon-camera.png',
  'assets/settings/icon-hand.png',
  'assets/settings/icon-reactions.png',
  'assets/settings/icon-tutorial.png',
  'assets/settings/icon-about.png',
  'assets/settings/icon-play.png',
  'assets/settings/logout.png',
  'assets/control/face.png',
];

/// Decode before navigation; the Image widgets can reuse a ready first frame.
Future<void> warmSettingsImages(BuildContext context) => Future.wait(
  settingsRasterAssets.map(
    (asset) => precacheImage(
      AssetImage(asset),
      context,
      onError: (Object error, StackTrace? stack) {
        debugPrint('Settings image preload failed: $error');
      },
    ),
  ),
);

/// Loads asynchronously while the existing app content stays visible.
class SettingsAssetWarmup extends StatefulWidget {
  const SettingsAssetWarmup({super.key, required this.child});
  final Widget child;
  @override
  State<SettingsAssetWarmup> createState() => _SettingsAssetWarmupState();
}

class _SettingsAssetWarmupState extends State<SettingsAssetWarmup> {
  double? _ratio;
  AssetBundle? _bundle;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final bundle = DefaultAssetBundle.of(context);
    if (_ratio == ratio && identical(_bundle, bundle)) return;
    _ratio = ratio;
    _bundle = bundle;
    unawaited(warmSettingsImages(context));
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      widget.child,
      // Keep decoded frames live, including after the ordinary LRU cache is cleared.
      // Offstage excludes these warmup copies from painting, input and semantics.
      Offstage(
        offstage: true,
        child: Wrap(
          children: [
            for (final asset in settingsRasterAssets)
              Image.asset(
                asset,
                width: 24,
                height: 24,
                excludeFromSemantics: true,
              ),
            SvgPicture.asset(
              'assets/settings/icon-language.svg',
              width: 32,
              height: 32,
              excludeFromSemantics: true,
            ),
            SvgPicture.asset(
              'assets/settings/face-happy.svg',
              width: 60,
              height: 30,
              excludeFromSemantics: true,
            ),
          ],
        ),
      ),
    ],
  );
}
