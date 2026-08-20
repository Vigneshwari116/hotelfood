import 'package:flutter/material.dart';

/// Single Shilpa Enterprise palette (teal). Do not mix the old cream/maroon.
class BrandColors {
  static const Color teal = Color(0xFF0E5C56);
  static const Color canvas = Color(0xFFF3F6F5);
  static const Color onTeal = Colors.white;
}

ThemeData buildBrandTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: BrandColors.teal,
    primary: BrandColors.teal,
    surface: BrandColors.canvas,
    brightness: Brightness.light,
  ).copyWith(
    primary: BrandColors.teal,
    onPrimary: BrandColors.onTeal,
    secondary: BrandColors.teal,
    onSecondary: BrandColors.onTeal,
    tertiary: BrandColors.teal,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: BrandColors.canvas,
    appBarTheme: const AppBarTheme(
      backgroundColor: BrandColors.teal,
      foregroundColor: BrandColors.onTeal,
      elevation: 0,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: BrandColors.teal,
        foregroundColor: BrandColors.onTeal,
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: BrandColors.teal,
      foregroundColor: BrandColors.onTeal,
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: Colors.black,
      unselectedLabelColor: Colors.black54,
      indicatorColor: BrandColors.teal,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(),
    ),
    cardTheme: const CardThemeData(
      elevation: 1,
      color: Colors.white,
      margin: EdgeInsets.zero,
    ),
  );
}
