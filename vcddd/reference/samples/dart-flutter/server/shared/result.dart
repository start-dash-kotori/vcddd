/// 域层统一结果封装。
///
/// [Result] 用 sealed class 替代异常控制流，确保调用方在编译期
/// 穷举处理成功与失败两条路径。
///
/// 纯 Dart，不依赖 Flutter。

import 'package:{project_name}/server/shared/errors.dart';

/// 命令执行结果封装。
///
/// - [Success] 携带业务数据。
/// - [Failure] 携带 [DomainError] 错误对象。
sealed class Result<T> {
  const Result();

  /// 便捷构造：创建成功结果。
  static Result<T> success<T>(T value) => Success(value);

  /// 便捷构造：创建失败结果。
  static Result<T> failure<T>(DomainError error) => Failure(error);

  /// 是否为成功结果。
  bool get isSuccess => this is Success<T>;

  /// 是否为失败结果。
  bool get isFailure => this is Failure<T>;

  /// 转换成功值；失败时返回原 [Failure]。
  Result<U> map<U>(U Function(T value) transform) {
    return switch (this) {
      Success(value: final v) => Success(transform(v)),
      Failure(error: final e) => Failure(e),
    };
  }

  /// 链式操作：成功时执行下一步，失败时透传。
  Result<U> flatMap<U>(Result<U> Function(T value) transform) {
    return switch (this) {
      Success(value: final v) => transform(v),
      Failure(error: final e) => Failure(e),
    };
  }

  /// 折叠：分别处理成功和失败路径，返回统一类型。
  U fold<U>({
    required U Function(T value) onSuccess,
    required U Function(DomainError error) onFailure,
  }) {
    return switch (this) {
      Success(value: final v) => onSuccess(v),
      Failure(error: final e) => onFailure(e),
    };
  }

  /// 获取成功值；失败时返回 [orElse] 提供的默认值。
  T getOrElse(T Function() orElse) {
    return switch (this) {
      Success(value: final v) => v,
      Failure() => orElse(),
    };
  }

  /// 获取成功值；失败时返回 [null]。
  T? getOrNull() {
    return switch (this) {
      Success(value: final v) => v,
      Failure() => null,
    };
  }
}

/// 成功结果，携带业务数据 [value]。
final class Success<T> extends Result<T> {
  const Success(this.value);

  /// 业务数据。
  final T value;

  @override
  String toString() => 'Success($value)';
}

/// 失败结果，携带域错误 [error]。
final class Failure<T> extends Result<T> {
  const Failure(this.error);

  /// 域错误对象。
  final DomainError error;

  @override
  String toString() => 'Failure($error)';
}
