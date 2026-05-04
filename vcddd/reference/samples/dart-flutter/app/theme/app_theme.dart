import 'package:flutter/material.dart';

import 'package:{project_name}/app/theme/app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData lightTheme({AppColors? colors}) {
    final appColors = colors ?? AppColors.defaults();
    final colorScheme = ColorScheme.fromSeed(
      seedColor: appColors.primaryAction,
      brightness: Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: [appColors],
    );
  }

  static ThemeData darkTheme({AppColors? colors}) {
    final appColors = colors ?? AppColors.defaults();
    final colorScheme = ColorScheme.fromSeed(
      seedColor: appColors.primaryAction,
      brightness: Brightness.dark,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      extensions: [appColors],
    );
  }
}
