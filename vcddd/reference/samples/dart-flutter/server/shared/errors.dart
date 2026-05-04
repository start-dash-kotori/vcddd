/// 域层通用错误类型体系。
///
/// 提供跨域共享的错误分类基类，各域的 sealed error class
/// 可选择继承这些基类以统一错误处理路径。
///
/// 纯 Dart，不依赖 Flutter。

/// 域错误抽象基类。
///
/// 所有域层业务错误的根类型。每种错误携带 [message] 描述，
/// 可选 [field] 标识涉及的字段，可选 [code] 用于程序化匹配。
sealed class DomainError {
  const DomainError({
    required this.message,
    this.field,
    this.code,
  });

  /// 人类可读的错误描述。
  final String message;

  /// 涉及的字段名（可选）。
  final String? field;

  /// 程序化错误码（可选），用于 UI 层分支匹配。
  final String? code;

  @override
  String toString() {
    final buffer = StringBuffer('$runtimeType(message: "$message"');
    if (field != null) buffer.write(', field: "$field"');
    if (code != null) buffer.write(', code: "$code"');
    buffer.write(')');
    return buffer.toString();
  }
}

/// 字段校验失败。
///
/// 用于前置条件检查：参数非法、格式不合法等。
final class ValidationError extends DomainError {
  const ValidationError({
    required super.message,
    super.field,
    super.code,
  });
}

/// 实体不存在。
///
/// 用于查询/编辑目标缺失。
final class NotFoundError extends DomainError {
  const NotFoundError({
    required super.message,
    super.field,
    super.code,
  });
}

/// 业务冲突。
///
/// 用于唯一性约束或状态冲突：重复名称、重复操作等。
final class ConflictError extends DomainError {
  const ConflictError({
    required super.message,
    super.field,
    super.code,
  });
}

/// 状态不允许的操作。
///
/// 用于状态机保护：非法状态迁移等。
final class DomainStateError extends DomainError {
  const DomainStateError({
    required super.message,
    super.field,
    super.code,
  });
}

/// 基础设施 / IO 失败。
///
/// 用于数据库故障、外部依赖超时等系统级异常。
/// 不作为业务拒绝使用，调用方可重试。
final class InfrastructureError extends DomainError {
  const InfrastructureError({
    required super.message,
    super.field,
    super.code,
  });
}
