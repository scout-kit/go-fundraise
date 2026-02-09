import 'package:flutter/material.dart';

class AppTheme {
  static const _primaryColor = Color(0xFF2E7D32); // Scout green
  static const _secondaryColor = Color(0xFFFFA000); // Scout gold

  // Shared component themes (identical for light and dark)
  static const _appBarTheme = AppBarTheme(
    centerTitle: false,
    elevation: 0,
  );

  static final _cardTheme = CardThemeData(
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
  );

  static final _inputDecorationTheme = InputDecorationTheme(
    filled: true,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    contentPadding: const EdgeInsets.symmetric(
      horizontal: 16,
      vertical: 14,
    ),
  );

  static final _elevatedButtonTheme = ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(
        horizontal: 24,
        vertical: 14,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
    ),
  );

  static const _fabTheme = FloatingActionButtonThemeData(
    elevation: 4,
  );

  static const _listTileTheme = ListTileThemeData(
    contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  );

  static final _chipTheme = ChipThemeData(
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(8),
    ),
  );

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryColor,
        secondary: _secondaryColor,
        brightness: Brightness.light,
      ),
      appBarTheme: _appBarTheme,
      cardTheme: _cardTheme,
      inputDecorationTheme: _inputDecorationTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      floatingActionButtonTheme: _fabTheme,
      listTileTheme: _listTileTheme,
      chipTheme: _chipTheme,
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _primaryColor,
        secondary: _secondaryColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: _appBarTheme,
      cardTheme: _cardTheme,
      inputDecorationTheme: _inputDecorationTheme,
      elevatedButtonTheme: _elevatedButtonTheme,
      floatingActionButtonTheme: _fabTheme,
      listTileTheme: _listTileTheme,
      chipTheme: _chipTheme,
    );
  }
}
