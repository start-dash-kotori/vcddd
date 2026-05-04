/// 命令抽象基类。
///
/// 所有域命令的根类型。每个写命令携带唯一 [commandId]
/// 和所属域标识 [domain]，用于幂等检测和日志追踪。
///
/// 各域的具体命令继承此基类并扩展业务字段。
///
/// 纯 Dart，不依赖 Flutter。

/// 命令抽象基类。
abstract base class Command {
  const Command({
    required this.commandId,
    required this.domain,
  });

  /// 命令唯一标识（UUID String），由调用方传入。
  ///
  /// 用于幂等检测：同一 commandId 重复提交时返回首次结果。
  final String commandId;

  /// 所属域名称（如 `order`、`payment`）。
  final String domain;

  @override
  String toString() => '$runtimeType(commandId: $commandId, domain: $domain)';
}
