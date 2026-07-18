import 'package:flutter/material.dart';

class AppTheme {
  static TextTheme _outfitTextTheme(TextTheme base) {
    return base.copyWith(
      displayLarge: base.displayLarge?.copyWith(fontFamily: 'Outfit'),
      displayMedium: base.displayMedium?.copyWith(fontFamily: 'Outfit'),
      displaySmall: base.displaySmall?.copyWith(fontFamily: 'Outfit'),
      headlineLarge: base.headlineLarge?.copyWith(fontFamily: 'Outfit'),
      headlineMedium: base.headlineMedium?.copyWith(fontFamily: 'Outfit'),
      headlineSmall: base.headlineSmall?.copyWith(fontFamily: 'Outfit'),
      titleLarge: base.titleLarge?.copyWith(fontFamily: 'Outfit'),
      titleMedium: base.titleMedium?.copyWith(fontFamily: 'Outfit'),
      titleSmall: base.titleSmall?.copyWith(fontFamily: 'Outfit'),
      bodyLarge: base.bodyLarge?.copyWith(fontFamily: 'Outfit'),
      bodyMedium: base.bodyMedium?.copyWith(fontFamily: 'Outfit'),
      bodySmall: base.bodySmall?.copyWith(fontFamily: 'Outfit'),
      labelLarge: base.labelLarge?.copyWith(fontFamily: 'Outfit'),
      labelMedium: base.labelMedium?.copyWith(fontFamily: 'Outfit'),
      labelSmall: base.labelSmall?.copyWith(fontFamily: 'Outfit'),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB388FF),
        brightness: Brightness.dark,
        primary: const Color(0xFFB388FF),
        secondary: const Color(0xFF18FFFF),
        surface: const Color(0xFF121212),
        surfaceContainer: const Color(0xFF1E1E1E),
      ),
      textTheme: _outfitTextTheme(ThemeData.dark().textTheme),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
      ),
    );
  }

  static ThemeData get lightTheme {
    const primary = Color(0xFF4A148C);
    return ThemeData(
      brightness: Brightness.light,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primary,
        brightness: Brightness.light,
        primary: primary,
        secondary: const Color(0xFF00B8D4),
        surface: Colors.white,
        surfaceContainerHighest: const Color(0xFFF5F0FF),
        surfaceTint: Colors.transparent,
      ),
      cardColor: Colors.white,
      canvasColor: const Color(0xFFF5F0FF),
      dividerColor: Colors.black12,
      textTheme: _outfitTextTheme(ThemeData.light().textTheme),
      iconTheme: const IconThemeData(color: Color(0xFF1A0533)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFF5F0FF),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF0E6FF),
        elevation: 0,
        centerTitle: true,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: Color(0xFF1A0533)),
        titleTextStyle: TextStyle(color: Color(0xFF1A0533), fontSize: 20, fontWeight: FontWeight.w600),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: const CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Colors.white,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF0E6FF),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        hintStyle: TextStyle(color: Colors.black38),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary;
          return Colors.grey;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return primary.withValues(alpha: 0.3);
          return Colors.grey.withValues(alpha: 0.2);
        }),
      ),
    );
  }

  static ThemeData get amoledTheme {
    return ThemeData(
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFFB388FF),
        brightness: Brightness.dark,
        primary: const Color(0xFFB388FF),
        secondary: const Color(0xFF18FFFF),
        surface: Colors.black,
        surfaceContainer: const Color(0xFF0A0A0A),
      ),
      textTheme: _outfitTextTheme(ThemeData.dark().textTheme),
      useMaterial3: true,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
      ),
    );
  }
}
