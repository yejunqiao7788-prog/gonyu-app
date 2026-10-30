import 'package:flutter/material.dart';

/// 集市身份的主题（PWA manifest：theme #FF5A3C / background #FFF7F3）。
/// 文档不描述 UI 像素，具体数值对照 Web 的 [data-surface='market'] 块；
/// 这里只保证 App 与集市磁贴是同一张脸，且与库存端控制台不同名不同色。
class MarketTokens {
  static const Color primary = Color(0xFFFF5A3C);
  static const Color background = Color(0xFFFFF7F3);
  static const Color surface = Colors.white;
  static const Color surfaceDim = Color(0xFFF2E9E4);
  static const Color ink = Color(0xFF1E1410);
  static const Color muted = Color(0xFF8A7A72);
  static const Color line = Color(0xFFEADFDA);
  static const Color success = Color(0xFF1B7F4B);
  static const Color promo = Color(0xFFB4690E);
  static const double radius = 14;

  static ThemeData light() {
    final base = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: primary, primary: primary), useMaterial3: true);
    return base.copyWith(
      scaffoldBackgroundColor: background,
      colorScheme: base.colorScheme.copyWith(surface: surface),
      appBarTheme: const AppBarTheme(backgroundColor: background, foregroundColor: ink, elevation: 0, centerTitle: false),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: primary, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius))),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: surface,
        selectedColor: primary,
        side: const BorderSide(color: line),
      ),
      cardTheme: const CardThemeData(color: surface, elevation: 0, margin: EdgeInsets.zero, shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(radius)))),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: line)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
    );
  }
}
