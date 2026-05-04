/// 域事件总线。
///
/// 基于 Dart 原生 [StreamController.broadcast] 实现的进程内事件广播。
/// 不使用第三方 EventBus 包，不承担持久化消息职责。
///
/// 使用方式：
/// - 发布：`DomainEventBus.publish(event)`
/// - 订阅：`DomainEventBus.stream.listen(...)`
/// - 测试清理：`DomainEventBus.dispose()`
///
/// 纯 Dart，不依赖 Flutter。

import 'dart:async';

import 'package:{project_name}/server/shared/domain_event.dart';

/// 域事件总线（静态单例）。
abstract final class DomainEventBus {
  static StreamController<DomainEvent>? _controller;

  /// 获取内部 StreamController，懒初始化。
  static StreamController<DomainEvent> get _instance {
    return _controller ??= StreamController<DomainEvent>.broadcast();
  }

  /// 发布域事件到总线。
  ///
  /// 事务提交后调用，不在事务内调用。
  static void publish(DomainEvent event) {
    _instance.add(event);
  }

  /// 域事件订阅流。
  ///
  /// 各域在 server/ 层订阅所需事件，按 domainName 或类型过滤。
  static Stream<DomainEvent> get stream => _instance.stream;

  /// 释放资源，用于测试清理。
  ///
  /// 调用后总线不可用，下次 publish/listen 会重新创建。
  static void dispose() {
    _controller?.close();
    _controller = null;
  }
}
