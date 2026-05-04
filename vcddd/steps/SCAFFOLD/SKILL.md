---
name: vcddd-scaffold
description: VCDDD — 项目骨架生成（在 tech-stack.md 确认后、域实现前）
---

> 子 Agent 指令：本文件为子 Agent 的完整执行指令，由总控 Agent 传入并派遣执行。

# Step: SCAFFOLD — 项目骨架生成

tech-stack.md 确认后，生成项目的基础设施骨架代码。这一步确保后续域实现时有正确的代码基底可以遵循，避免大模型自行发明基础设施结构导致边界违规。

## 前置条件

- `docs/vcddd/tech-stack.md` 已确认
- 所有域的 `boundary.md` + `business.md` 已确认（D¹ 完成）

## 输入

- `docs/vcddd/tech-stack.md`（全文）
- `reference/samples/{tech-stack}/` 目录下的样板代码（如有）

## 输出

项目根目录下的骨架代码文件。

## 执行流程

### 第一步：根据 tech-stack.md 确定技术栈类型

从 tech-stack.md 中提取：
- 语言 + 框架
- ORM / 数据库工具
- 状态管理 / DI 框架
- 代码生成工具

### 第二步：查找对应样板代码

```
检查 reference/samples/ 下是否有匹配的样板目录？
    │
    ├── 有（如 dart-flutter/、python-fastapi/）
    │     → 读取样板代码，作为骨架生成的基础
    │     → 替换包名、项目名等占位符
    │     → 根据 tech-stack.md 的具体选型调整依赖
    │
    └── 无匹配样板
          → 根据 tech-stack.md 的架构原则，从零生成骨架
          → 严格遵循 tech-stack.md 中定义的目录结构
```

### 第三步：生成骨架代码

按以下顺序生成文件。**每个文件生成前必须确认其符合 tech-stack.md 的架构原则。**

#### 3.1 域共享基础设施（server/shared/ 或等价位置）

这是所有域共享的类型定义，纯语言实现，不依赖框架：

| 文件 | 职责 | 约束 |
|------|------|------|
| 命令基类 | 所有域命令的根类型 | 携带 commandId + domain |
| 事件基类 | 所有域事件的根类型 | 携带 eventId + occurredAt + domainName |
| 事件总线 | 进程内事件广播 | 不使用第三方包，用语言原生机制 |
| 错误类型体系 | sealed class 错误层次 | 包含业务拒绝/系统异常/外部依赖失败分类 |
| 幂等接口 | 幂等检测抽象 | 定义 check/record 接口 |
| 结果封装 | Result\<T\> sealed class | Success/Failure 两条路径 |
| 读模型接口 | ReadModel 标记接口 | 纯标记，无方法 |
| barrel 文件 | 统一导出 | 所有上述文件的 export |

**此层是纯语言代码，不 import 任何框架包。**

#### 3.2 基础设施连接器（infrastructure/ 或等价位置）

**只生成连接器，不生成任何业务 schema：**

- 数据库连接器：空壳类，只做连接管理
  - `@XxxDatabase(tables: [])` — 表列表为空，待各域实现时注册
  - 包含 `createDefault()` 和 `createInMemory()` 工厂方法
  - 包含迁移策略骨架（onCreate / onUpgrade / beforeOpen）

- 外部服务适配器（如需要）：
  - AI 推理通道
  - 支付网关封装
  - 文件存储适配器

**禁止在此层生成表定义、ORM 模型、仓储实现。**

#### 3.3 框架适配层（app/ 或等价位置）

生成应用入口和框架配置骨架：

- 应用入口（main.dart）：binding 初始化 + logging 配置
- 应用壳（app.dart）：框架根组件配置（MaterialApp / 等）
- 路由骨架：空路由表，预留各域路由占位
- Provider / DI 占位：数据库 Provider（占位，待域实现后替换）
- 主题配置：基础主题骨架

**此层只做框架配置，不包含业务逻辑。**

#### 3.4 依赖清单（pubspec.yaml / package.json / go.mod 等）

根据 tech-stack.md 生成依赖清单，包含：
- 框架核心依赖
- ORM / 数据库依赖
- 状态管理 / DI 依赖
- 测试框架依赖
- 代码生成工具依赖（如有）

### 第四步：验证骨架

生成完成后，执行以下验证：

1. **infrastructure 不含域逻辑**：检查 infrastructure/ 目录下没有任何 table/model/repository 文件
2. **server/shared/ 无框架依赖**：检查共享基础设施工具不 import 任何框架包
3. **依赖方向正确**：app/ → server/ → infrastructure/，无反向依赖
4. **空壳数据库注册表为空**：`@XxxDatabase(tables: [])` 确认为空列表
5. **编译/构建通过**：骨架代码无语法错误

### 第五步：记录操作

在 `docs/vcddd/progress.log` 中记录：
- 生成了哪些文件
- 使用了哪个样板目录（如有）
- 验证结果

## 完成要求

- [ ] 域共享基础设施（server/shared/）已生成
- [ ] 基础设施连接器（infrastructure/）已生成，不含任何域 schema
- [ ] 框架适配层（app/）骨架已生成
- [ ] 依赖清单已生成
- [ ] 骨架验证通过（infrastructure 不含域逻辑、无框架依赖泄漏）
- [ ] progress.log 已更新

## 如果卡住

- 如果 tech-stack.md 中的技术栈没有对应样板代码 → 参考 `reference/samples/` 中最接近的样板，调整后生成
- 如果不确定某个文件应放在 infrastructure 还是 server/ → **默认放在 server/{domain}/**，infrastructure 只放连接器
