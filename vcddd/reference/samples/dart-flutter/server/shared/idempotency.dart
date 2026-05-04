/// 幂等检测抽象接口。
///
/// 各域的 repository 实现此接口，提供基于 [commandId] 的
/// 幂等记录查询与写入能力。底层使用统一的
/// `command_idempotency_records` 表。
///
/// 纯 Dart，不依赖 Flutter。

import 'package:{project_name}/server/shared/result.dart';

/// 幂等记录值对象。
///
/// 表示一次已执行命令的快照，用于重复请求时直接返回首次结果。
class IdempotencyRecord {
  const IdempotencyRecord({
    required this.domain,
    required this.commandId,
    required this.resultPayload,
    required this.createdAt,
  });

  /// 所属域标识（如 `order`、`payment`）。
  final String domain;

  /// 命令唯一标识。
  final String commandId;

  /// 首次执行结果的 JSON 序列化快照。
  final Map<String, dynamic> resultPayload;

  /// 首次执行时间。
  final DateTime createdAt;

  @override
  String toString() =>
      'IdempotencyRecord(domain: $domain, commandId: $commandId, '
      'createdAt: $createdAt)';
}

/// 幂等检测仓储抽象接口。
///
/// 实现要求：
/// - [check] 按 `(domain, commandId)` 查询，返回已有的幂等记录或 null。
/// - [record] 写入幂等记录，唯一约束在 `(domain, commandId)` 上。
/// - 幂等检测与业务写入必须在同一 Drift `transaction()` 内完成。
abstract class IdempotencyRepository {
  /// 查询幂等记录。
  ///
  /// 返回 [IdempotencyRecord]（命中）或 null（未命中）。
  /// 系统异常时返回 [Failure]。
  Future<Result<IdempotencyRecord?>> check(
    String domain,
    String commandId,
  );

  /// 写入幂等记录。
  ///
  /// [resultPayload] 为首次执行结果的 JSON 快照。
  /// 重复写入同一 `(domain, commandId)` 时由底层唯一约束拒绝。
  Future<Result<void>> record(
    String domain,
    String commandId,
    Map<String, dynamic> resultPayload,
  );
}
