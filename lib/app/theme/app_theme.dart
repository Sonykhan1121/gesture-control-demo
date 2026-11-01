import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_typography.dart';

/// Material component defaults and system bars. Palette lives in AppColors.
abstract final class AppTheme {
  static ThemeData get app => screen.copyWith(
    appBarTheme: const AppBarTheme(
      centerTitle: true,
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  static ThemeData get screen => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    fontFamily: AppTypography.bodyFont,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      primary: AppColors.primary,
      onPrimary: AppColors.background,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.error,
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.primary.withValues(alpha: 1 / 3),
      selectionHandleColor: AppColors.primary,
    ),
  );

  /// Auth uses the canvas as its surface and pure-white form text.
  static ThemeData get auth => screen.copyWith(
    colorScheme: screen.colorScheme.copyWith(
      surface: AppColors.background,
      onSurface: AppColors.white,
    ),
  );

  static SystemUiOverlayStyle systemBars({Color? background}) =>
      SystemUiOverlayStyle.light.copyWith(
        statusBarColor: AppColors.transparent,
        systemNavigationBarColor: background ?? AppColors.background,
        systemNavigationBarIconBrightness:
            ThemeData.estimateBrightnessForColor(
                  background ?? AppColors.background,
                ) ==
                Brightness.light
            ? Brightness.dark
            : Brightness.light,
      );
}
