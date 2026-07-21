import 'package:flutter/material.dart';

/// Shared demo theming: Material 3, light + dark from one seed, following
/// the system preference by default.
class DemoTheme {
  DemoTheme._();

  static const _seed = Color(0xFF00696D);

  static ThemeData get light => ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _seed),
        useMaterial3: true,
      );

  static ThemeData get dark => ThemeData(
        colorScheme:
            ColorScheme.fromSeed(seedColor: _seed, brightness: Brightness.dark),
        useMaterial3: true,
      );
}
