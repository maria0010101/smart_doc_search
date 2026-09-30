import 'package:flutter/material.dart';

/// A selectable colour palette for the whole application.
///
/// Beyond the light/dark mode switch the user can pick one of several colour
/// schemes; [AppTheme.themeFor] turns the selection into a Material 3 theme.
class AppPalette {
  final String id;
  final String name;
  final Color seed;
  final Color accent;

  const AppPalette({
    required this.id,
    required this.name,
    required this.seed,
    required this.accent,
  });
}

class AppTheme {
  static const String defaultPaletteId = 'indigo';

  static const List<AppPalette> palettes = [
    AppPalette(id: 'indigo', name: '靛藍', seed: Color(0xFF1E3A8A), accent: Color(0xFF0D9488)),
    AppPalette(id: 'teal', name: '森綠', seed: Color(0xFF0F766E), accent: Color(0xFF0284C7)),
    AppPalette(id: 'ocean', name: '深海藍', seed: Color(0xFF0369A1), accent: Color(0xFF14B8A6)),
    AppPalette(id: 'violet', name: '紫羅蘭', seed: Color(0xFF6D28D9), accent: Color(0xFFDB2777)),
    AppPalette(id: 'amber', name: '暖陽橙', seed: Color(0xFFB45309), accent: Color(0xFF0F766E)),
    AppPalette(id: 'rose', name: '玫瑰紅', seed: Color(0xFFBE123C), accent: Color(0xFF7C3AED)),
    AppPalette(id: 'graphite', name: '石墨灰', seed: Color(0xFF334155), accent: Color(0xFF0EA5E9)),
  ];

  /// Active palette colours. Widgets across the app reference these directly so
  /// switching palettes instantly recolours the whole interface.
  static Color primaryColor = palettes.first.seed;
  static Color secondaryColor = palettes.first.accent;
  static const Color accentColor = Color(0xFFF59E0B);
  static const Color errorColor = Color(0xFFEF4444);

  static String _activePaletteId = defaultPaletteId;

  static String get activePaletteId => _activePaletteId;

  static AppPalette paletteById(String? id) {
    return palettes.firstWhere((p) => p.id == id, orElse: () => palettes.first);
  }

  /// Marks [paletteId] as the active palette so hard-coded accent colours follow
  /// the user's selection.
  static AppPalette activatePalette(String? paletteId) {
    final palette = paletteById(paletteId);
    _activePaletteId = palette.id;
    primaryColor = palette.seed;
    secondaryColor = palette.accent;
    return palette;
  }

  /// Builds the full application theme for [brightness] and the given palette.
  static ThemeData themeFor(Brightness brightness, {String? paletteId}) {
    final palette = activatePalette(paletteId);
    final isDark = brightness == Brightness.dark;

    final scheme = ColorScheme.fromSeed(
      seedColor: palette.seed,
      brightness: brightness,
    );

    final pageBackground = isDark ? const Color(0xFF111A2E) : const Color(0xFFF5F7FB);
    final cardColor = isDark ? const Color(0xFF1B2740) : Colors.white;
    final borderColor = isDark ? const Color(0xFF2E3B57) : const Color(0xFFE2E8F0);
    final onSurface = isDark ? const Color(0xFFE8EDF7) : const Color(0xFF0F172A);

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme.copyWith(
        surface: cardColor,
        onSurface: onSurface,
        outlineVariant: borderColor,
      ),
      scaffoldBackgroundColor: pageBackground,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: onSurface,
        displayColor: onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: cardColor,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 1.5,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 1,
        color: cardColor,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
      ),
      dividerTheme: DividerThemeData(
        thickness: 1,
        space: 1,
        color: borderColor,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF18233B) : const Color(0xFFF1F5F9),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(color: onSurface.withValues(alpha: 0.45), fontSize: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: borderColor),
        backgroundColor: isDark ? const Color(0xFF223052) : const Color(0xFFF1F5F9),
        labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: onSurface),
        secondaryLabelStyle: TextStyle(fontSize: 12, color: onSurface),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: cardColor,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        indicatorColor: scheme.primary.withValues(alpha: isDark ? 0.28 : 0.14),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.primary : onSurface.withValues(alpha: 0.65),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: selected ? scheme.primary : onSurface.withValues(alpha: 0.65),
          );
        }),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        iconColor: null,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: cardColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          side: BorderSide(color: borderColor),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: onSurface.withValues(alpha: 0.6),
        indicatorColor: scheme.primary,
      ),
    );
  }

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
