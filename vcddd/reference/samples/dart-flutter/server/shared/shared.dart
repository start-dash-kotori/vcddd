/// 共享域基础设施层 barrel 文件。
///
/// 导出所有公开类型，各域通过单条 import 引入共享基础。

export 'package:{project_name}/server/shared/command.dart';
export 'package:{project_name}/server/shared/domain_event.dart';
export 'package:{project_name}/server/shared/domain_event_bus.dart';
export 'package:{project_name}/server/shared/errors.dart';
export 'package:{project_name}/server/shared/idempotency.dart';
export 'package:{project_name}/server/shared/read_model.dart';
export 'package:{project_name}/server/shared/result.dart';
