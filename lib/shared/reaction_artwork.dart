import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The pixel face uses vector rectangles so its edges stay crisp at any size.
Widget reactionArtwork(
  String asset, {
  Key? key,
  Color? color,
  BlendMode? colorBlendMode,
  FilterQuality filterQuality = FilterQuality.medium,
  double? width,
  double? height,
  BoxFit? fit,
  bool excludeFromSemantics = false,
}) {
  if (asset == 'assets/settings/face-happy.png') {
    return SizedBox(
      width: width,
      height: height,
      child: SvgPicture.asset(
        'assets/settings/face-happy.svg',
        key: key,
        width: width,
        height: height,
        fit: fit ?? BoxFit.contain,
        colorFilter: color == null
            ? null
            : ColorFilter.mode(color, colorBlendMode ?? BlendMode.srcIn),
        excludeFromSemantics: excludeFromSemantics,
      ),
    );
  }
  return Image.asset(
    asset,
    key: key,
    color: color,
    colorBlendMode: colorBlendMode,
    filterQuality: filterQuality,
    width: width,
    height: height,
    fit: fit,
    excludeFromSemantics: excludeFromSemantics,
  );
}
