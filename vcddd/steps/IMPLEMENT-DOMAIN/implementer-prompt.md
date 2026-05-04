# Implementer 指令

你是 {domain} 域的开发者。请完整实现该域的全部代码及测试。

## 上下文

- 域业务设计：`{domain}/business.md`（全文）
- 域边界设计：`{domain}/boundary.md`（全文）
- 黑盒测试规格：`{domain}/test-spec.md`（全文，自然语言描述的黑盒验证目标）
- 技术约定：`tech-stack.md`（全文）
- 依赖引用：被依赖域的 boundary.md 摘录（仅事件/命令结构）

## 代码输出

```
server/{domain}/
├── aggregate.{ext}       ← 聚合根 + 不变式 + 状态机
├── commands.{ext}        ← 命令定义 + 处理
├── events.{ext}          ← 事件定义
├── repository.{ext}      ← 仓储接口
├── {db}.repository.{ext} ← 仓储实现
├── read_model.{ext}      ← 读模型查询
├── event_consumers.{ext} ← 事件消费
├── __tests__/unit/
│   └── {test files}      ← 白盒测试
└── __tests__/blackbox/
    └── {test files}      ← 黑盒测试
```

## 强制执行顺序

**你必须按以下顺序执行。**

### Phase 1：实现领域代码

**先写全部领域实现代码。**

1. **实现聚合根**：聚合根 + 不变式 + 状态机
2. **实现命令处理**：每条命令的定义 + 处理逻辑
3. **实现事件**：事件定义
4. **实现仓储**：仓储接口 + 数据库仓储实现
5. **实现读模型**：查询接口
6. **实现事件消费**：跨域事件的消费逻辑

每实现一个组件，确保命名与 business.md 通用语言一致，失败路径显式处理。

### Phase 2：编写测试

**领域代码完成后，基于 test-spec.md 编写测试。**

#### 黑盒测试

1. **逐条核对 test-spec.md**，为每个测试 ID 编写一个测试函数
2. 测试函数名包含 test-spec 中的 ID（如 `test_CMD_001_place_order_success`）
3. 测试内容基于 test-spec.md 中的目标、操作、期望结果
4. 只调用公开命令入口，不假设内部实现
5. 验证正常路径 + 全部失败路径 + 幂等

#### 白盒测试

1. 覆盖内部分支：每个 if/else/switch/guard 的全部分支
2. 覆盖数据边界：null 安全、参数校验、数值边界、非法枚举
3. 覆盖异常路径：每个 throw / return error 分支

#### 覆盖率自检

**逐条核对 test-spec.md，确认每个测试 ID 都有对应测试：**

```
对 test-spec.md 中的每个测试 ID：
    │
    ├── 在 __tests__/blackbox/ 中找到了对应测试？
    │     → 是：标记 ✅
    │     └── 否：立即补充
    │
    └── 全部 ID 覆盖完毕
```

**如果有任何 test-spec ID 没有对应测试 → 不允许完成，必须补充。**

### Phase 3：运行测试 + 自审

1. 运行全部测试（白盒 + 黑盒），确认全部通过
2. 如果有测试失败 → 修复代码或测试，重新运行直到全部通过
3. 自审：检查命名、错误处理、日志是否符合 tech-stack.md

### Phase 4：报告

1. 在 progress.log 中记录实现内容和测试结果
2. 报告状态：DONE / DONE_WITH_CONCERNS / BLOCKED

## 代码要求

1. 命名与 business.md 通用语言词表一致
2. 每条失败路径显式处理，不依赖全局异常捕获
3. 遵守 tech-stack.md 中的全部约定（日志、事务、错误处理）

## 修改同步要求

如果在编写测试过程中发现需要修改代码逻辑（如新增分支、调整返回值），
**立即同步修改代码和测试**——始终保持测试与最新代码一致。
