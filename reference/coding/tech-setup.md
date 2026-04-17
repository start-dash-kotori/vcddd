# 项目技术确立线

项目技术确立线的职责是在进入任何域的实现设计之前，确认并记录该项目的技术栈、工程约定与代码规范。

**这是实现线的前置条件。** 如果 `docs/vcddd/tech-stack.md` 不存在，不能进入任何域的实现设计。

---

## 架构前提：域层与框架层的分离

**这条原则不随技术栈变化，适用于所有语言和框架。**

无论最终选择什么技术栈，项目必须遵守以下结构原则：

### 核心思想

域业务逻辑脱离框架独立存在，框架只是一层薄适配器。

```
┌─────────────────────────────────────────────┐
│                框架适配层                    │
│  HTTP 路由 / gRPC Handler / 队列消费者 / CLI  │
│  中间件 / 依赖注入 / 序列化 / 认证           │
│                                             │
│  只做：接收外部请求 → 翻译参数 → 调用 server │
│  不做：任何业务判断、状态决策、不变式保护     │
└─────────────────────┬───────────────────────┘
                      │ 调用
                      ▼
┌─────────────────────────────────────────────┐
│              server/{domain}/（域模块）       │
│                                             │
│  每个域是最小的完整可调度模块：               │
│  业务逻辑 + 数据访问全部封装在域内部          │
│  对外只暴露命令入口 / 事件 / 读模型查询       │
│  不暴露内部聚合、仓储实现、数据库细节         │
└─────────────────────────────────────────────┘
```

### server 包的内部结构：域是最小完整模块

`server/` 内部以**域**为第一层目录。**域内部包含该域的全部内容**——业务逻辑和数据访问实现都在域目录下，没有独立的 `infra/` 或 `infrastructure/` 目录：

```
server/
├── order/
│   ├── aggregate.{ext}            ← 聚合根 + 不变式 + 状态机
│   ├── commands.{ext}             ← 命令定义 + 命令处理
│   ├── events.{ext}               ← 事件定义
│   ├── repository.{ext}           ← 仓储接口（抽象）
│   ├── {db}.repository.{ext}      ← 仓储实现（域自己维护，不外提）
│   └── read_model.{ext}           ← 读模型查询接口
├── payment/
│   ├── aggregate.{ext}
│   ├── commands.{ext}
│   ├── events.{ext}
│   ├── repository.{ext}
│   ├── {db}.repository.{ext}
│   └── read_model.{ext}
└── ...
```

**关键原则**：每个域自己维护自己的数据库访问。仓储实现（Prisma、SQLAlchemy、JPA 等）写在域目录内部，不提取到外层共享目录。框架适配层调用 `server/order/` 这个完整黑盒，不需要知道里面用了什么数据库技术。

**反模式**——把仓储实现提取到外层（错误示例）：

```
# 错误：infra/ 独立于 server/ 之外，域不再是完整模块
server/order/aggregate.{ext}
server/order/commands.{ext}
infra/order/{db}.repository.{ext}   ← 破坏了域的完整性
```

**反模式**——按技术层横切（错误示例）：

```
# 错误：按技术层组织，理解一个域需要跨三个目录
aggregates/order.{ext}
commands/order_commands.{ext}
repositories/order_repository.{ext}
```

**以域为第一层级的价值**：理解或修改订单域的完整逻辑，只需要读 `server/order/` 这一个文件夹。聚合、命令、事件、数据访问全部内聚，不跨目录跳转，对人和 AI 都友好。

### server 包的边界规则

- `server/{domain}/` 不出现任何框架的 import（不引入 HTTP context、不引入 DI 容器、不引入框架的请求/响应类型）
- 每个域对外暴露**命令入口、事件、读模型查询**，不暴露内部聚合结构和仓储实现
- 框架层依赖 `server/{domain}/`，`server/` 不依赖框架层
- 跨域协作通过事件机制完成，不绕道框架层
- 数据库客户端（Prisma client、SQLAlchemy session 等）由域自己持有，不在域之间共享

### 框架适配层的边界规则

- 框架层只做三件事：参数解析与校验、调用 `server/{domain}/` 的命令入口、把结果序列化成响应
- 框架层内不写业务逻辑，不做业务判断，不保护不变式
- 认证/授权在框架层做校验，但「这个用户有没有权限做这件事」的业务判断归 `server/{domain}/`

这条原则写入 `tech-stack.md` 的"模块组织"部分，后续实现线和域文档必须始终遵守。

---

### 日志规范（强制，不随技术栈变化）

**格式**：所有环境统一使用结构化 JSON 日志，不用拼接字符串的纯文本日志。

**每条日志的必填字段**：

| 字段 | 说明 |
|------|------|
| `timestamp` | ISO 8601，精确到毫秒 |
| `level` | `debug` / `info` / `warn` / `error` |
| `domain` | 产生日志的域名（`order`、`payment` 等） |
| `action` | 当前执行的命令或事件名（`PlaceOrder`、`OrderPlaced` 等） |
| `trace_id` | 贯穿整条请求链路的追踪 ID，由框架适配层在入口处生成并注入 |
| 业务标识 | 至少一个主体 ID（`order_id`、`user_id` 等），不能只有技术标识 |

**必须记录日志的位置**（在任何语言 / 框架下都强制）：

| 位置 | 级别 | 必须包含的字段 |
|------|------|---------------|
| 命令入口 | `info` | 命令类型、关键入参摘要、发起方标识 |
| 状态迁移 | `info` | 迁移前状态、迁移后状态、触发原因 |
| 失败路径 | `error` / `warn` | 失败原因、错误分类（业务拒绝 / 系统异常 / 外部依赖失败）、是否可重试、当前关键上下文 |
| 跨域事件发布 | `info` | 事件类型、事件 ID、目标域 |
| 外部事件消费 | `info` | 事件来源域、事件 ID、处理结果（成功 / 忽略 / 失败） |

**禁止**：
- 在最外层只记录一条 `"处理失败"` 的日志——失败必须在发生的位置记录，保留现场
- 用日志拼接字符串替代结构化字段（`log("order " + id + " failed")` → 应为 `log({order_id: id, error: ...})`）
- 在日志中输出密码、token、完整卡号等敏感字段

**日志级别约定**：
- `debug`：开发调试信息，不在生产环境输出
- `info`：正常业务流程的关键节点（命令入口、状态迁移、事件发布）
- `warn`：可恢复的异常（幂等命中、外部依赖超时后重试成功）
- `error`：需要人工关注的失败（不可重试的失败、不变式冲突、外部依赖持续失败）

这条规范写入 `tech-stack.md` 的"日志规范"部分，后续每个域的实现必须对照执行。

---

## 技术确立流程

### 第零步：判断项目类型

进入流程的第一件事，判断当前是已有项目还是全新项目：

```
项目根目录是否已有源代码文件？
    → 有：走「已有项目识别路径」（第一步A）
    → 无：走「新项目调研路径」（第一步B）
```

---

### 第一步A：已有项目——从代码中识别技术设定

**优先级原则**：已有项目的技术设定从代码中读，不从头调研，不向用户逐项提问。代码本身就是最权威的技术设定文档。

#### 1. 扫描配置文件，提取技术栈

按优先级依次读取：

| 文件 | 提取内容 |
|------|---------|
| `package.json` / `package-lock.json` | 语言（Node/TS）、框架、ORM、日志库、测试框架、所有直接依赖 |
| `pyproject.toml` / `requirements*.txt` / `Pipfile` | 语言版本、框架、依赖库 |
| `pom.xml` / `build.gradle` | 语言版本、框架、依赖 |
| `go.mod` | 语言版本、依赖模块 |
| `Cargo.toml` | 语言版本、依赖 crate |
| `tsconfig.json` | 编译目标、路径别名、严格模式设置 |
| `.eslintrc*` / `ruff.toml` / `.golangci.yml` | Lint 规则 |
| `.prettierrc*` / `pyproject.toml [tool.black]` | 格式化规则（缩进、行宽、引号风格） |
| `.editorconfig` | 通用格式约定 |
| `docker-compose.yml` / `Dockerfile` | 运行时、端口、环境变量、依赖服务 |
| `.github/workflows/` / `Makefile` / `justfile` | 构建命令、测试命令、CI 流程 |

#### 2. 抽样阅读已有代码，识别实际风格

从项目中挑选 **5–10 个有代表性的源文件**（覆盖不同层级：入口、业务逻辑、数据访问、测试），观察并记录：

**命名风格**
- 变量、函数、类、常量各用什么 case
- 事件和命令是否已有命名模式，用什么词汇
- 文件和目录的命名风格

**目录结构**
- 当前项目按什么原则组织目录（按技术层 / 按业务域 / 混合）
- 是否已有类似 `server/` 的域层目录，还是尚未建立

**代码惯用写法**
- 错误处理方式（抛异常 / 返回 Result / 错误码）
- 异步写法（async/await / Promise chain / 回调）
- 导入风格（绝对路径 / 相对路径 / 路径别名）
- 类型声明方式（显式类型注解 / 推断为主）

**日志使用方式**
- 当前用了哪个日志库
- 是否已有结构化日志，字段命名习惯是什么
- 是否有统一的日志格式或封装

**测试风格**
- 测试文件放在哪里（与源码同目录 / 独立 `tests/` 目录）
- 测试命名方式
- Mock 的使用习惯

#### 3. 归纳识别结果

把从代码中读到的内容整理成初步技术设定，标注每条来源：
- `[配置文件]`：从配置文件中直接读取
- `[代码推断]`：从代码模式中归纳，有一定概率
- `[待确认]`：代码中有歧义或找不到足够证据

只有标注 `[待确认]` 的项才需要向用户提问，其余直接写入 `tech-stack.md`。

---

### 第一步B：新项目——调研可行技术栈

根据 `docs/vcddd/requirements/facts.md` 中的业务定位与技术约束，调研完成当前项目目标可行的技术栈组合。

调研维度：

| 维度 | 调研内容 |
|------|---------|
| 语言 | 哪些语言在这个业务场景下有成熟的生态（Web 服务、数据处理、实时系统等） |
| 框架 | 该语言下主流框架的对比（性能、生态、学习曲线、与域层分离的兼容性） |
| 数据库 | 业务的读写模式、事务需求、数据结构是否适合关系型 / 文档型 / 时序型 |
| 消息队列 | 是否有跨域异步协作，事件量级，是否需要持久化和回放 |
| 部署 | 预期规模、运维成本、是否 Serverless 友好 |

调研完成后，给出 2–3 个可行方案，每个方案说明：
- 技术栈组合
- 适合这个项目的理由
- 主要取舍（选了什么，放弃了什么）

向用户确认选择哪个方案。

---

### 第二步：从语言推导出代码规范

语言确认后，以下内容由语言社区的主流约定直接确定，**不需要用户逐项确认**，直接记录：

**命名约定**（按语言）

| 语言 | 变量/函数 | 类/类型 | 常量 | 文件 | 包/模块 |
|------|----------|---------|------|------|---------|
| Go | `camelCase` | `PascalCase` | `ALL_CAPS` | `snake_case.go` | `snake_case` |
| Python | `snake_case` | `PascalCase` | `ALL_CAPS` | `snake_case.py` | `snake_case` |
| TypeScript/JS | `camelCase` | `PascalCase` | `ALL_CAPS` / `SCREAMING_SNAKE` | `kebab-case.ts` | `kebab-case` |
| Java | `camelCase` | `PascalCase` | `ALL_CAPS` | `PascalCase.java` | `reverse.domain` |
| Rust | `snake_case` | `PascalCase` | `ALL_CAPS` | `snake_case.rs` | `snake_case` |

事件和命令命名在任何语言下都遵循以下约定：
- **事件**：`PascalCase` + 过去时动词，表达已发生的事实（`OrderPlaced`、`PaymentCompleted`）
- **命令**：`PascalCase` + 动宾结构，表达业务意图（`PlaceOrder`、`ConfirmPayment`）

**格式化与 Lint**（按语言的主流工具）

| 语言 | 格式化工具 | Lint 工具 |
|------|----------|---------|
| Go | `gofmt` / `goimports`（语言内置） | `golangci-lint` |
| Python | `black` + `isort` | `ruff` |
| TypeScript/JS | `prettier` | `eslint` |
| Java | `google-java-format` / `spotless` | `checkstyle` / `spotbugs` |
| Rust | `rustfmt`（语言内置） | `clippy`（语言内置） |

**日志库**（按语言的主流选型）

| 语言 | 推荐库 | 格式 |
|------|--------|------|
| Go | `slog`（标准库，1.21+）/ `zap` | 结构化 JSON |
| Python | `structlog` + `logging` | 结构化 JSON |
| TypeScript/JS | `pino` / `winston` | 结构化 JSON |
| Java | `SLF4J` + `Logback` / `Log4j2` | 结构化 JSON（`logstash-logback-encoder`） |
| Rust | `tracing` + `tracing-subscriber` | 结构化 JSON |

日志库由语言直接确定，不需要用户逐项确认，直接记录。

---

### 第三步：从框架推导出工程约定

框架确认后，以下内容由框架的主流最佳实践直接确定：

**目录结构**：`server/` 是域层的顶级容器，每个域目录包含该域的全部内容（业务逻辑 + 数据访问实现）。框架适配层与 `server/` 并列，不嵌入其中。

典型示例：

```
# TypeScript + Express
project/
├── server/                        ← 域层（所有域在此）
│   ├── order/
│   │   ├── aggregate.ts
│   │   ├── commands.ts
│   │   ├── events.ts
│   │   ├── repository.ts          ← 仓储接口
│   │   ├── prisma.repository.ts   ← 仓储实现（域内部，不外提）
│   │   └── read_model.ts
│   └── payment/
│       ├── aggregate.ts
│       └── ...
├── app/                           ← 框架适配层（Express）
│   ├── routes/
│   ├── middleware/
│   └── main.ts
└── ...

# Python + FastAPI
project/
├── server/
│   ├── order/
│   │   ├── aggregate.py
│   │   ├── commands.py
│   │   ├── events.py
│   │   ├── repository.py
│   │   ├── sqlalchemy.repository.py   ← 域自己维护 DB 访问
│   │   └── read_model.py
│   └── payment/
│       └── ...
├── api/                           ← 框架适配层（FastAPI）
│   ├── routers/
│   └── main.py
└── ...

# Go
project/
├── internal/server/
│   ├── order/
│   │   ├── aggregate.go
│   │   ├── commands.go
│   │   ├── events.go
│   │   ├── repository.go
│   │   ├── postgres_repository.go   ← 域自己维护 DB 访问
│   │   └── read_model.go
│   └── payment/
│       └── ...
├── cmd/api/
│   └── main.go                    ← 框架适配层入口
└── ...
```

**模块组织**：每个 `server/{domain}/` 是最小的完整可调度模块。域自己维护数据库访问，不设全局共享的 `infra/` 或 `infrastructure/` 目录。框架适配层把 `server/{domain}/` 当作黑盒调用，不感知其内部实现。

**测试约定**：遵循框架 + 语言的主流约定（测试文件位置、命名、运行命令）。

**技术决策**：记录框架选择的理由及被否定的方案。

---

### 第四步：向用户输出确认结果

**已有项目**使用以下格式，标注每条信息的来源，让用户能看到推断依据：

```
## 从项目中识别到的技术设定

**技术栈**
- 语言：{语言} {版本} [配置文件: package.json]
- 框架：{框架} [配置文件: package.json dependencies]
- 数据库：{数据库} [配置文件: docker-compose.yml]
- ORM：{ORM} [配置文件: package.json]
- 日志库：{库名} [配置文件: package.json] / [代码推断: src/xxx.ts 第N行]
- 消息队列：{选型 或 未发现}

**代码规范**（从代码中归纳）
- 命名：{描述，附典型示例，如 "函数用 camelCase，见 src/order/handler.ts"}
- 格式化：{工具 或 未发现配置}
- Lint：{工具 或 未发现配置}
- 错误处理：{描述实际用法，如 "抛 AppError 自定义异常，见 src/errors.ts"}
- 异步写法：{描述实际用法，如 "统一 async/await"}
- 导入风格：{描述，如 "路径别名 @/ 指向 src/"}

**目录结构**（从代码中观察）
- 当前组织方式：{描述，如 "按技术层：controllers/ services/ repositories/"}
- server/ 域层：{已存在 / 尚未建立，需新增}

**测试约定**（从代码中观察）
- 框架：{框架}，位置：{位置}，命名：{命名方式}

---

以下我不确定，需要你确认（共 {N} 项）：
1. {问题} [原因：{为什么代码中看不出来}]
2. {问题}
```

**新项目**使用以下格式：

```
## 项目技术设定草案

**推荐技术栈**（共 {N} 个方案）

方案一：{技术栈概述}
- 适合理由：{理由}
- 主要取舍：{放弃了什么}

方案二：{技术栈概述}
- 适合理由：{理由}
- 主要取舍：{放弃了什么}

请选择一个方案，或告诉我你的偏好。
```

方案确认后，再输出完整设定草案（格式同已有项目，来源标注为 `[语言约定]` / `[框架约定]` / `[选型决策]`）。

确认项只问真正有分歧的选择，不问已由语言/框架约定直接确定的项。

---

### 第五步：写入 tech-stack.md

用户确认后，写入 `docs/vcddd/tech-stack.md`（见 `reference/thinking/templates/tech/tech-stack.md`）。

写入完成后，才可进入实现线。

---

## 后续维护

`tech-stack.md` 一旦建立，实现过程中发现需要引入新的技术选择或调整已有约定时：

1. 停下来，向用户说明：现有设定是什么、新的需求是什么、候选方案是什么
2. 用户确认后，先更新 `tech-stack.md`，再继续编码
3. **不允许在代码里悄悄采用与 `tech-stack.md` 不一致的约定**

---

## 与实现线的关系

```
用户发起实现
    → 检查 docs/vcddd/tech-stack.md
        → 不存在：走完本文件五步，写入后再进入实现线
        → 存在：读取 tech-stack.md，按其规定执行实现线全程
```
