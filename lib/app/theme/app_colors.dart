import 'package:flutter/material.dart';

/// Shared UI palette. Change these tokens instead of individual screens.
abstract final class AppColors {
  static const background = Color(0xff14161b);
  static const dialogSurface = Color(0xff20232b);
  static const surface = Color(0xff1a1d24);
  static const primary = Color(0xffbfed03);
  static const textPrimary = Color(0xfff9fde6);
  static const textSecondary = Color(0xffbfbfbf);
  static const error = Color(0xffffb4ab);
  static const border = Color(0xff595959);
  static const disabledText = Color(0xff808080);
  static const skipText = Color(0xff737373);
  static const subtleText = Color(0xffa6a792);
  static const noticeSurface = Color(0xff222222);
  static const avatarSurface = Color(0xffe9effd);

  // Fixed contrast/artwork colors are intentionally distinct from the canvas.
  static const white = Colors.white;
  static const black = Colors.black;
  static const transparent = Colors.transparent;
  static const darkText = Color(0xff14161b);

  // Persisted appearance choices use ARGB integers. Preserve existing values.
  static const defaultReactionColor = 0xffbbcff9;
  static const whiteBackgroundValue = 0xffffffff;
  static const reactionColors = [
    defaultReactionColor,
    0xffebf9b1,
    0xffb0e2ff,
    whiteBackgroundValue,
  ];

  /// Home supports user-selected backgrounds in addition to the app default.
  static Color textOnBackground(Color color) =>
      ThemeData.estimateBrightnessForColor(color) == Brightness.light
      ? darkText
      : textPrimary;
}
