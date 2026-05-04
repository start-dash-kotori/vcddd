/// 域事件抽象基类。
///
/// 所有域事件的根类型。每个事件携带唯一 [eventId]、
/// 发生时间 [occurredAt] 和所属域标识 [domainName]。
///
/// 各域的具体事件继承此基类并扩展业务载荷字段。
///
/// 纯 Dart，不依赖 Flutter。

/// 域事件抽象基类。
abstract base class DomainEvent {
  const DomainEvent({
    required this.eventId,
    required this.occurredAt,
    required this.domainName,
  });

  /// 事件唯一标识（UUID String）。
  final String eventId;

  /// 事件发生时间。
  final DateTime occurredAt;

  /// 产生该事件的域名称（如 `order`、`payment`）。
  final String domainName;

  @override
  String toString() =>
      '$runtimeType(eventId: $eventId, domain: $domainName, '
      'occurredAt: $occurredAt)';
}
