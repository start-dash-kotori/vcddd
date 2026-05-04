import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:{project_name}/app/providers/database_provider.dart';

/// 应用设置 Provider 占位。
///
/// 待 app-settings 域实现后替换为实际查询。
final appSettingsProvider = FutureProvider<Object>((ref) async {
  // ignore: unused_local_variable
  final database = ref.watch(databaseProvider);
  // TODO: Load settings from app-settings 域
  return Object();
});
