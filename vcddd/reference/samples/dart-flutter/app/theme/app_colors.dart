import 'package:flutter/material.dart';

/// 项目自定义语义色彩扩展。
///
/// 继承 [ThemeExtension] 以集成 Material 主题系统。
/// 使用方式：在 `AppTheme` 中通过 `extensions: [appColors]` 注册，
/// 在 Widget 中通过 `Theme.of(context).extension<AppColors>()!` 获取。
///
/// 默认提供 4 组语义色，项目可根据业务需要增减字段。
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.primaryAction,
    required this.secondaryAction,
    required this.destructive,
    required this.success,
  });

  factory AppColors.defaults() => const AppColors(
        primaryAction: Color(0xFF1E88E5),   // blue
        secondaryAction: Color(0xFF43A047), // green
        destructive: Color(0xFFE53935),     // red
        success: Color(0xFF43A047),         // green
      );

  final Color primaryAction;
  final Color secondaryAction;
  final Color destructive;
  final Color success;

  @override
  AppColors copyWith({
    Color? primaryAction,
    Color? secondaryAction,
    Color? destructive,
    Color? success,
  }) {
    return AppColors(
      primaryAction: primaryAction ?? this.primaryAction,
      secondaryAction: secondaryAction ?? this.secondaryAction,
      destructive: destructive ?? this.destructive,
      success: success ?? this.success,
    );
  }

  @override
  AppColors lerp(AppColors? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      primaryAction: Color.lerp(primaryAction, other.primaryAction, t)!,
      secondaryAction: Color.lerp(secondaryAction, other.secondaryAction, t)!,
      destructive: Color.lerp(destructive, other.destructive, t)!,
      success: Color.lerp(success, other.success, t)!,
    );
  }
}
