import 'package:flutter/material.dart';

/// Tokens de color del diseño validado (ver design/design-tokens.md).
class AppColors {
  AppColors._();

  static const brand = Color(0xFFBC0A26); // rojo RadioApp
  static const brandSoft = Color(0xFFFF5A72); // rojo claro (acentos en oscuro)
  static const ink = Color(0xFF15171A);

  // Tema oscuro
  static const bgDark = Color(0xFF23262D);
  static const surfaceDark = Color(0xFF32353C);
  static const tabbarDark = Color(0xFF1E2027);
  static const mutedDark = Color(0xFF8B8E95);
  static const hairlineDark = Color(0xFF35383F);

  // Tema claro
  static const bgLight = Color(0xFFFAFBFC);
  static const surfaceLight = Color(0xFFF6F3F4);
  static const tabbarLight = Color(0xFFFFFFFF);
  static const mutedLight = Color(0xFF9A9A9F);
  static const hairlineLight = Color(0xFFECEAEB);
}
