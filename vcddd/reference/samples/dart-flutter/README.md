# Dart/Flutter 样板代码

基于 VCDDD 架构原则的 Dart/Flutter 项目骨架。新项目可直接复制此目录，替换 `{project_name}` 即可使用。

## 使用方式

1. 复制整个 `dart-flutter/` 目录到新项目
2. 全局替换 `{project_name}` 为实际包名
3. 根据 tech-stack.md 调整 `pubspec.yaml` 中的依赖
4. 开始在 `server/{domain}/` 下实现各域

## 目录结构

```
├── server/shared/                ← 共享域基础设施（纯 Dart）
│   ├── command.dart              Command 基类
│   ├── domain_event.dart         DomainEvent 基类
│   ├── domain_event_bus.dart     进程内事件总线
│   ├── errors.dart               sealed class 错误层次
│   ├── idempotency.dart          幂等接口 + 值对象
│   ├── read_model.dart           ReadModel 标记接口
│   ├── result.dart               Result<T> sealed class
│   └── shared.dart               barrel 文件
│
├── infrastructure/database/      ← 基础设施连接器（空壳）
│   └── app_database.dart         AppDatabase（不含任何表）
│
├── app/                          ← 框架适配层（Flutter + Riverpod）
│   ├── main.dart                 入口 + logging
│   ├── ledger_app.dart           AppRoot（MaterialApp 配置）
│   ├── router/app_router.dart    GoRouter 骨架
│   ├── providers/                Riverpod Provider 占位
│   ├── pages/                    页面骨架
│   ├── widgets/                  通用组件
│   └── theme/                    主题配置
│
└── pubspec.yaml                  依赖清单
```

## 关键约束

- `server/shared/` 是纯 Dart，不依赖 Flutter
- `infrastructure/database/` 只有连接器，`@DriftDatabase(tables: [])` 不含任何表
- 表定义（`table.dart`）属于各域，在 `server/{domain}/` 下
- `app/` 只做参数解析和 UI 渲染，不包含业务逻辑
