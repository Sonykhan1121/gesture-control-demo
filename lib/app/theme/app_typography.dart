import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Shared font family and Figma line-height conversion, preserving layout sizes.
abstract final class AppTypography {
  static const bodyFont = 'Manrope';
  static const detailFont = 'Poppins';

  static TextStyle text(
    double size,
    double lineHeight, {
    Color color = AppColors.textPrimary,
    FontWeight weight = FontWeight.w400,
    String family = bodyFont,
  }) => TextStyle(
    fontFamily: family,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    letterSpacing: 0,
    color: color,
  );
}
