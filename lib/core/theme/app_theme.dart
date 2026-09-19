import 'package:flutter/material.dart';

class AppTheme {
  static const Color primaryColor = Color(0xFF1E3A8A); // Deep Slate Indigo
  static const Color secondaryColor = Color(0xFF0D9488); // Teal
  static const Color accentColor = Color(0xFFF59E0B); // Amber
  static const Color errorColor = Color(0xFFEF4444);

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      secondary: secondaryColor,
      surface: const Color(0xFFF8FAFC),
      error: errorColor,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: const Color(0xFFF8FAFC),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: Color(0xFF0F172A),
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      color: Colors.white,
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
      backgroundColor: const Color(0xFFF1F5F9),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    ),
  );

  static ThemeData darkTheme = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: const Color(0xFF60A5FA),
      secondary: const Color(0xFF2DD4BF),
      surface: const Color(0xFF1E293B),
      error: errorColor,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: const Color(0xFF0F172A),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFF1E293B),
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF334155)),
      ),
      color: const Color(0xFF1E293B),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      side: BorderSide.none,
      backgroundColor: const Color(0xFF334155),
      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.white70),
    ),
  );

  static Color getCategoryColor(String category) {
    switch (category) {
      case '醫學術語':
        return const Color(0xFF0D9488); // Teal
      case '疾病/症狀':
      case '疾病':
      case '症狀':
        return const Color(0xFFE11D48); // Rose / Crimson
      case '疾病分類編碼':
      case 'ICD編碼':
        return const Color(0xFFD97706); // Amber Dark / Deep Orange
      case '主題':
        return const Color(0xFF3B82F6); // Blue
      case '領域':
        return const Color(0xFF8B5CF6); // Purple
      case '方法':
        return const Color(0xFF10B981); // Emerald
      case '對象':
        return const Color(0xFFF59E0B); // Amber
      case '結論':
        return const Color(0xFFEC4899); // Pink
      case '文檔類型':
        return const Color(0xFF6366F1); // Indigo
      case '語言':
      case '年份':
        return const Color(0xFF64748B); // Slate
      case '作者/機構':
        return const Color(0xFF0EA5E9); // Sky
      default:
        return const Color(0xFF64748B);
    }
  }
}
