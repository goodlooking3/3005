import 'package:flutter/material.dart';

abstract final class WaselColors {
  static const navy = Color(0xFF101B3D);
  static const primary = Color(0xFF315CFF);
  static const primaryDark = Color(0xFF172554);
  static const canvas = Color(0xFFF6F8FB);
  static const surface = Colors.white;
  static const success = Color(0xFF079455);
  static const warning = Color(0xFFF79009);
  static const border = Color(0xFFE7EBF2);
  static const ink = Color(0xFF101828);
  static const muted = Color(0xFF667085);
}

abstract final class WaselMetrics {
  static const radiusCard = 18.0;
  static const radiusControl = 14.0;
  static const pagePadding = 24.0;
  static const compactBreakpoint = 760.0;
  static const wideBreakpoint = 1180.0;
}

ThemeData waselTheme() => ThemeData(
      useMaterial3: true,
      fontFamily: 'Amiri',
      scaffoldBackgroundColor: WaselColors.canvas,
      colorScheme: ColorScheme.fromSeed(seedColor: WaselColors.primary),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: WaselColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(WaselMetrics.radiusCard),
          side: const BorderSide(color: WaselColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WaselMetrics.radiusControl),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          side: const BorderSide(color: WaselColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WaselMetrics.radiusControl),
          ),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        filled: true,
        fillColor: WaselColors.surface,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(WaselMetrics.radiusControl),
          ),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(WaselMetrics.radiusControl),
          ),
          borderSide: BorderSide(color: WaselColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.all(
            Radius.circular(WaselMetrics.radiusControl),
          ),
          borderSide: BorderSide(color: WaselColors.primary, width: 1.4),
        ),
      ),
    );

BoxDecoration waselBox({Color color = WaselColors.surface}) => BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(WaselMetrics.radiusCard),
      border: Border.all(color: WaselColors.border),
    );
