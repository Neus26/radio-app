import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

/// Temas claro/oscuro de la app. Fuente UI = Manrope; display = Bebas Neue.
class AppTheme {
  AppTheme._();

  static ThemeData get dark => _build(Brightness.dark);
  static ThemeData get light => _build(Brightness.light);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.bgDark : AppColors.bgLight;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final onBg = isDark ? Colors.white : AppColors.ink;

    final base = ThemeData(brightness: brightness, useMaterial3: true);
    final textTheme = GoogleFonts.manropeTextTheme(base.textTheme)
        .apply(bodyColor: onBg, displayColor: onBg);

    return base.copyWith(
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.brand,
        brightness: brightness,
      ).copyWith(primary: AppColors.brand, surface: surface),
      textTheme: textTheme,
      dividerColor: isDark ? AppColors.hairlineDark : AppColors.hairlineLight,
    );
  }

  /// Estilo display (Bebas Neue) para títulos de sección/cabeceras.
  static TextStyle display(BuildContext context,
      {double size = 34, Color? color}) {
    final c = color ??
        (Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : AppColors.ink);
    return GoogleFonts.bebasNeue(
        fontSize: size, letterSpacing: 1, height: .98, color: c);
  }
}
