import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

/// AppDatabase — 空壳数据库连接器
///
/// 不包含任何域的表定义。各域的 Drift Table 定义在
/// `server/{domain}/table.dart` 中，域实现完成后通过
/// @DriftDatabase(tables: [...]) 注册到此处。
///
/// 当前为空壳，待各域实现后逐步注册表。
@DriftDatabase(tables: [])
class AppDatabase extends _$AppDatabase {
  AppDatabase(QueryExecutor e) : super(e);

  /// 创建默认数据库连接（用于生产环境）
  static Future<AppDatabase> createDefault() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, '{project_name}.sqlite');
    return AppDatabase(NativeDatabase(File(path)));
  }

  /// 创建内存数据库（用于测试）
  static AppDatabase createInMemory() {
    return AppDatabase(NativeDatabase.memory());
  }

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // 迁移策略将在域注册表后逐步添加
        },
        beforeOpen: (details) async {
          // 启用 WAL 模式和外键约束
          // 等 build_runner 生成代码后启用：
          // await customStatement('PRAGMA journal_mode=WAL');
          // await customStatement('PRAGMA foreign_keys=ON');
        },
      );
}
