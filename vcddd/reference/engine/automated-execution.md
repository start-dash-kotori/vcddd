# 自动化执行层

D1 用户确认后，D2→D3 阶段的自动化编排。编排者（执行 VCDDD 的 AI session）读取本文档，驱动整个自动化流程。

**本文档的定位**：编排者的操作手册。不是给 subagent 读的（subagent 只需要任务描述 + 域文档 + tech-stack.md）。

---

## 入口判断

```
用户确认了 D1（所有域的 boundary.md + business.md）？
    │
    ├── 是 → 加载本文档，启动自动化执行层
    │
    └── 否 → 停止。先完成 D1 确认。
```

---

## 第零步：检测 SuperPower 执行引擎

在进入 D2-auto 之前，先检测 SuperPower skills 是否已安装。

**检测方法**：检查文件系统 `~/.claude/skills/subagent-driven-development/SKILL.md` 是否存在（不依赖 Skill 工具，因为 Skill 工具仅在会话启动时注册技能列表，新安装的技能在同一会话中不可见）。

```
检查 ~/.claude/skills/subagent-driven-development/SKILL.md 是否存在？
    │
    ├── 存在
    │     → 设置 VCDDD_EXEC_ENGINE=superpower
    │     → 加载 SuperPower SKILL.md 文件内容作为执行指令
    │     → 后续 D3-auto 使用 SuperPower skills 作为执行引擎
    │
    ├── 不存在 → 检查 ~/.codex/.tmp/plugins/plugins/superpowers/skills/subagent-driven-development/SKILL.md
    │     ├── 存在
    │     │   → 自动链接到 ~/.claude/skills/
    │     │   → 加载并设置 VCDDD_EXEC_ENGINE=superpower
    │     │
    │     └── 不存在
    │           → 向用户提示：
    │             「VCDDD 自动化执行层推荐使用 SuperPower 作为执行引擎。
    │               SuperPower 提供了 subagent-driven-development、TDD、两道审查等能力。
    │               
    │               安装命令：npm install -g @superpowers/skills
    │               
    │               是否安装 SuperPower？
    │                 - 安装：安装后我将使用 SuperPower 引擎继续执行
    │                 - 跳过：我将使用 VCDDD 内置的执行模式」
    │           → 用户选择安装 → 等待安装完成，重新检测
    │           → 用户选择跳过 → 加载 reference/engine/fallback-execution.md
    │           → fallback-execution.md 加载完毕后继续 D2-auto
    │
    检测通过后继续 D2-auto
```

### 检测通过后加载 SuperPower 技能

检测通过后，编排者读取以下 SuperPower SKILL.md 文件，将其执行逻辑内化：

| SuperPower 技能 | 加载方式 | VCDDD 中的用途 |
|----------------|---------|---------------|
| `~/.claude/skills/subagent-driven-development/SKILL.md` | Read 全文 | 理解 subagent 派遣流程、审查机制、状态处理 |
| `~/.claude/skills/test-driven-development/SKILL.md` | Read 全文 | 理解 TDD 循环规范，将其注入 subagent 指令 |
| `~/.claude/skills/writing-plans/SKILL.md` | Read 全文 | 理解计划文档格式，构造传给 SuperPower 的输入 |
| `~/.claude/skills/receiving-code-review/SKILL.md` | 按需 Read | 审查阶段 |

编排者不通过 Skill 工具调用 SuperPower（同一会话中不可见），而是**阅读 SKILL.md 文件后自行遵循其指令执行**。SuperPower 的 SKILL.md 是纯文本指令，编排者阅读后即可按其中的流程操作。

---

## 禁止性规则

1. D1 未确认 → 不启动自动化执行
2. tech-stack.md 不存在 → 不派遣任何 subagent
3. 每个域的 Implementer subagent 必须遵循 TDD（测试先行、确认失败、最小代码通过）
4. 每个域必须通过 Stage 1（Spec Compliance）和 Stage 2（Code Quality）两道审查，由该域的 Reviewer 执行
5. 审查发现的问题必须由该域的 Implementer subagent 修复并重新审查（每轮对抗最多 10 轮，详见 review-loop.md 通用对抗生成框架）
6. 发现 business.md 内部矛盾 → 暂停自动化，回退到需求线修正文档
7. 不同域的 subagent 不并行派遣（避免文件冲突）
8. 全部域完成后 → 必须执行跨域集成验证

---

## D2-auto：自动化技术确立

D2-auto 不依赖 SuperPower，始终使用 VCDDD 自身的流程。

### 核心理念

技术栈决策权在用户手中。AI 的角色是分析、归纳和推荐，不是决定。只有用户明确声明"不关心技术选型，你来定"，AI 才能自行决定。

### 决策树

```
用户是否有明确的技术栈要求（facts.md 或直接声明）？
    │
    ├── 有明确要求
    │     → 遵循用户要求，直接写入 tech-stack.md
    │     → 不调研、不推荐、不替换
    │     → 要求不完整时（如只指定了语言和框架，未指定数据库）：
    │         针对缺失部分向用户提供 2-3 个补充建议
    │
    └── 无明确要求 / 要求不完整
          │
          ▼
    检查项目目录是否已有源代码？
          │
     ┌────┴────┐
     ▼         ▼
   有代码     无代码
     │         │
     ▼         ▼
  分析现有     提供 2-3
  框架和       个可行技术
  编码习惯     栈方案
     │        （含适合理由
     ▼        和取舍）
  向用户呈现   │
  分析结果     ▼
     │      向用户确认
     │      选择哪个方案
     └──┬───┘
        │
        ▼
  用户确认后写入 tech-stack.md
        │
  除非用户明确声明
  "不关心，你来定"
        │
        ▼
  AI 自行选择后写入 tech-stack.md
```

### 流程

```
加载 reference/engine/tech-setup.md
        │
        ▼
判断用户是否有明确的技术栈要求？
        │
   ┌────┴────┐
   ▼         ▼
 有明确要求   无明确要求
   │         │
   ▼         ▼
 遵循用户     检查是否有现有代码？
 要求写入      │
 tech-    ┌───┴───┐
 stack.md 有代码  无代码
   │       │       │
   │       ▼       ▼
   │    分析现有   调研 2-3
   │    框架和     可行方案
   │    编码习惯   提供选择
   │       │       │
   │       └───┬───┘
   │           │
   │           ▼
   │    向用户呈现草案
   │    （标注来源：
   │     配置文件 / 代码推断 /
   │     社区约定 / 待确认）
   │           │
   └──────┬────┘
          │
     ┌────┴────┐
     │ 用户确认？ │（或用户声明"不管"→ AI 自行决定）
     └────┬────┘
       是 │  否（有修改意见）
          ▼   ▼
     写入     修改后重新呈现
     tech-    直至用户确认
     stack.md
```

### 有明确技术栈要求时

如果 facts.md 直接写了技术栈（如"用 Go + PostgreSQL"），或者用户通过自然语言指定了，直接使用。**不做替代方案调研，不推荐其他语言或框架。**

仅当用户的要求不完整时（如：只说了"Go"，没指定 Web 框架、数据库），针对缺失部分提供 2-3 个补充建议，由用户决定。

### 有现有代码时

分析现有项目的框架、编码习惯和约定，向用户呈现分析结果，标注每条信息来源（配置文件 / 代码推断），由用户确认后再写入。

**不是 AI 分析后直接写入**——分析结果必须经用户确认。

### 无现有代码时

提供 2-3 个可行技术栈方案（附适合理由和取舍），由用户选择。不自行决定。

### 用户声明"不管"

当用户明确说出"不关心技术选型，你来定"或等价表述时，AI 自行选择后写入。但必须记录"由 AI 自主选择"的原因，以便后续复查。

---

## D2.5-auto：项目骨架生成（SCAFFOLD）

tech-stack.md 写入完成后、D3-auto 开始前，执行骨架生成。

### 流程

```
tech-stack.md 写入完成
        │
        ▼
[VCDDD] 加载 steps/SCAFFOLD/SKILL.md
        │
        ▼
[VCDDD] 根据 tech-stack.md 技术栈，查找 reference/samples/ 下的样板代码
        │
        ├── 有匹配样板 → 复制并替换占位符
        └── 无匹配样板 → 从零生成骨架（严格遵循 tech-stack.md 架构原则）
        │
        ▼
[VCDDD] 生成骨架代码：
        ├── server/shared/    域共享基础设施（纯语言，不依赖框架）
        ├── infrastructure/   基础设施连接器（空壳，不含任何域 schema）
        ├── app/              框架适配层骨架
        └── 依赖清单          pubspec / package.json / go.mod 等
        │
        ▼
[VCDDD] 验证骨架：
        ├── infrastructure 不含域逻辑 ✓
        ├── server/shared/ 无框架依赖 ✓
        ├── 依赖方向正确 ✓
        └── 编译/构建通过 ✓
        │
        ▼
继续 D3-auto
```

### 禁止性规则

- **infrastructure/ 目录禁止包含任何域的表定义或仓储实现**
- server/shared/ 禁止 import 框架包
- 骨架验证不通过 → 不进入 D3-auto

---

## D3-auto：Subagent 编排实现

### SuperPower 引擎路径（VCDDD_EXEC_ENGINE=superpower）

VCDDD 负责**准备上下文**，SuperPower 负责**执行**。分工如下：

| 环节 | 负责方 | 使用的 Skill/文档 |
|------|--------|------------------|
| 构建域依赖图 + 拓扑排序 | VCDDD | facts.md + boundary.md + subagent-orchestration.md |
| 逐域生成测试规格（TDD Bridge） | VCDDD | tdd-bridge.md（每域有独立的 Generator ↔ Reviewer 对抗） |
| 派遣 Implementer 完整实现域 | 编排者遵循 SuperPower subagent-driven-dev 指令 | `~/.claude/skills/subagent-driven-development/SKILL.md` |
| TDD 循环（RED-GREEN-REFACTOR） | Implementer 遵循 SuperPower TDD 指令 | `~/.claude/skills/test-driven-development/SKILL.md` |
| 三层审查：Spec → Quality → VCDDD | 编排者遵循 SuperPower 审查机制 | VCDDD 提供三层审查标准（review-loop.md） |
| 跨域集成验证 | VCDDD | integration-verification.md |
| 完成分支 | 编排者遵循 SuperPower finishing-a-branch 指令 | `~/.claude/skills/finishing-a-development-branch/SKILL.md` |

#### 流程

```
tech-stack.md 就绪 + 骨架代码已生成（D2.5-auto）
        │
        ▼
[VCDDD] Step 1: 构建域依赖图 + 拓扑排序
        决定各域的实现顺序（被依赖的域先实现）
        │
        ▼
[VCDDD] Step 2: 按拓扑顺序，逐域执行
        │
        ├── 域 A（无依赖）
        │    ├── TDD Bridge → test-spec.md（Generator ↔ Spec Reviewer 对抗）
        │    ├── Implementer → 完整实现域 A 全部代码（TDD 循环）
        │    ├── Spec Reviewer → 核对代码 vs business.md（最多 10 轮）
        │    ├── Quality Reviewer → 核对代码 vs tech-stack.md（最多 10 轮）
        │    └── VCDDD Reviewer → 核对 VCDDD 合规性（最多 10 轮）
        │
        ├── 域 B（依赖 A）
        │    ├── TDD Bridge → test-spec.md
        │    ├── Implementer → 完整实现域 B 全部代码
        │    ├── Spec Reviewer → 核对代码 vs business.md
        │    ├── Quality Reviewer → 核对代码 vs tech-stack.md
        │    └── VCDDD Reviewer → 核对 VCDDD 合规性
        │
        └── ...
        │
        ▼
[VCDDD] Step 3: 全部域完成，执行跨域集成验证
        加载 reference/engine/integration-verification.md
        │
        ▼
[VCDDD + SuperPower] Step 4: 加载 finishing-a-development-branch/SKILL.md
        遵循其指令完成分支
        │
        ▼
[VCDDD] Step 5: 生成最终报告
```

#### 编排者调度循环（强制执行）

**流程图只是概览。以下调度循环是编排者的强制执行指令——每个域完成后必须按此循环推进，不需要用户提醒。**

```
对每个域，按以下顺序严格执行：

┌─ 循环开始 ─────────────────────────────────────────────┐
│                                                         │
│  1. 派遣 TDD Bridge                                     │
│     → 生成 test-spec.md                                 │
│     → Generator ↔ Spec Reviewer 对抗（最多 10 轮）       │
│     → 返回 test-spec.md 后继续                           │
│                                                         │
│  2. 【立即】派遣 Implementer                             │
│     → 传入：business.md + boundary.md + test-spec.md    │
│            + tech-stack.md + 依赖域 boundary.md 摘录     │
│     → Implementer 完成全部代码 + 测试                     │
│     → 返回状态：DONE / DONE_WITH_CONCERNS / BLOCKED     │
│                                                         │
│  3. Implementer 返回后【立即】派遣 Spec Reviewer          │
│     → 不等待用户确认，不跳过，不省略                      │
│     → 核对代码 vs business.md（Stage 1）                 │
│     → 一次性给出全部问题                                 │
│     → 返回：PASS / ISSUES（含问题列表）                  │
│                                                         │
│  4. Spec Reviewer 返回 ISSUES 后【立即】：               │
│     → 重新派遣 Implementer，传入问题列表                 │
│     → Implementer 修复后重新提交                         │
│     → 重新派遣 Spec Reviewer 审查                        │
│     → 循环直到 PASS 或达到 10 轮上限                     │
│                                                         │
│  5. Spec Reviewer 返回 PASS 后【立即】派遣 Quality Reviewer│
│     → 核对代码 vs tech-stack.md（Stage 2）               │
│     → 返回：PASS / ISSUES                               │
│                                                         │
│  6. Quality Reviewer 返回 ISSUES 后【立即】：             │
│     → 重新派遣 Implementer 修复                          │
│     → 重新派遣 Spec Reviewer（确认修复未引入新问题）       │
│     → 重新派遣 Quality Reviewer                          │
│     → 循环直到 PASS 或达到 10 轮上限                     │
│                                                         │
│  7. Quality Reviewer 返回 PASS 后【立即】派遣 VCDDD Reviewer│
│     → 核对 VCDDD 合规性（Stage 3）                       │
│     → 返回：PASS / ISSUES / CONDITIONAL                 │
│                                                         │
│  8. VCDDD Reviewer 返回后：                              │
│     → PASS → 标记该域完成，进入下一个域                   │
│     → ISSUES → 重新派遣 Implementer 修复，从 Step 3 重审  │
│     → CONDITIONAL → 标记 DONE_WITH_CONCERNS，进入下一域   │
│                                                         │
│  9. 该域三道审查全部通过后【立即】进入下一个域             │
│     → 不等待用户确认，不暂停，直接取拓扑排序中的下一域     │
│                                                         │
└─ 循环结束（直到所有域完成）──────────────────────────────┘
```

**关键约束**：
- **审查不可跳过**：Implementer 返回 DONE 不等于域完成，必须通过三道审查才算完成
- **审查不可省略**：不能因为"代码看起来没问题"就跳过 Reviewer
- **审查不可并行**：Spec → Quality → VCDDD 必须串行，后一道审查依赖前一道的结果
- **修复后必须重审**：Implementer 修复问题后，必须从 Spec Reviewer 重新开始审查
- **不需要用户提醒**：整个循环是自动的，只在升级条件触发时才打断用户

#### 编排者传递给各 Agent 的上下文

**Implementer 上下文：**

```
## 任务
你是 {domain} 域的开发者。请完整实现该域的全部代码及测试。

## 强制执行顺序（不可跳过）

### Phase 1: 实现领域代码
1. 实现聚合根 + 不变式 + 状态机
2. 实现命令处理逻辑
3. 实现事件、仓储、读模型、事件消费
4. 每个组件命名与 business.md 通用语言一致

### Phase 2: 编写测试
1. 基于 test-spec.md，为每个测试 ID 编写黑盒测试函数
   - 测试函数名包含 ID（如 test_CMD_001）
   - 只调用公开命令入口，不假设内部实现
2. 编写白盒测试：分支覆盖 + 数据边界 + 异常路径
3. 覆盖率自检：逐条核对 test-spec.md，确认每个 ID 都有对应测试

### Phase 3: 运行测试 + 自审
1. 运行全部测试，确认全部通过
2. 有失败 → 修复代码或测试，重跑直到全部通过
3. 自审：命名、错误处理、日志符合 tech-stack.md

## 域业务设计
{domain}/business.md（全文）

## 域边界设计
{domain}/boundary.md（全文）

## 测试规格
{domain}/test-spec.md（全文）— 每个测试 ID 必须有对应测试函数

## 技术约定
tech-stack.md（全文）

## 依赖引用
{被依赖域的 boundary.md 摘录（仅事件/命令结构定义）}

## 要求
- 先写领域代码，再写测试
- 黑盒测试函数名必须包含 test-spec 中的 ID（如 test_CMD_001）
- 覆盖 test-spec.md 中的全部测试 ID
- 实现完成后自审
```

**Spec Reviewer 上下文：**

```
## 审查任务
审查 {domain} 域的 Spec Compliance。

## 域业务设计
{domain}/business.md（全文）

## 实现代码
{Implementer 产出的全部代码文件}

## 审查要求
- 逐条核对 business.md：全部不变式、状态迁移、命令路径、失败分支
- 核对企业 boundary.md：命令/事件结构定义
- 详见 reference/engine/review-loop.md Stage 1 核对清单
- 一次性给出全部问题，不允许分批抛出
```

**Quality Reviewer 上下文：**

```
## 审查任务
审查 {domain} 域的 Code Quality。

## 技术约定
tech-stack.md（全文）

## 实现代码
{Implementer 产出的全部代码文件}

## 审查要求
- 逐条核对 tech-stack.md：命名、目录、依赖、日志、错误处理、事务边界、测试约定
- 详见 reference/engine/review-loop.md Stage 2 核对清单
- 一次性给出全部问题，不允许分批抛出
```

**VCDDD Reviewer 上下文：**

```
## 审查任务
审查 {domain} 域的 VCDDD 合规性。

## 域业务设计
{domain}/business.md（全文）
{domain}/boundary.md（全文）

## 技术约定
tech-stack.md（全文）

## 实现代码
{Implementer 产出的全部代码文件}
{Spec Reviewer 的审查结果}
{Quality Reviewer 的审查结果}

## 审查要求
1. VCDDD 定义准确性
   - 域边界是否被正确遵守（代码没有越过 boundary.md 定义的边界）
   - 通用语言是否一致（代码命名与 business.md 的词汇表一致）
   - 决策主权是否未被侵犯（没有其他域的代码做了本域的决策）
   - 修复：Spec Reviewer 发现但未解决的问题是否合理

2. 技术栈规则遵守
   - tech-stack.md 中关于域层与框架层分离的规定是否被遵守
   - 每个域是否保持了模块完整性（含数据访问实现）
   - 框架适配层是否没有混入业务逻辑
   - **基础设施边界：infrastructure/ 目录是否只包含连接器，不含任何域的表定义、仓储实现或业务逻辑**

3. VCDDD 专项要求
   - 事务边界是否与聚合边界对齐（一个事务不修改多个聚合）
   - 状态迁移是否通过聚合方法执行（无直接字段赋值）
   - 事件是否在事务提交后发布（不在事务内）
   - 跨域协作是否通过事件机制（非直接耦合）
   - 文档与代码的偏差：新发现与 business.md 的矛盾（如有，标记为 [待确认]）

## 三项判定
✅ VCDDD 合规 — 该域实现通过 VCDDD 审查
❌ 不合规 — 列出具体问题，交由编排者判断是否返回 Implementer 修复
⚠️ 有条件合规 — 存在非关键问题，标记为 DONE_WITH_CONCERNS 并在最终报告中列出
```

---

### 编排者呈现给用户的进度

执行期间，编排者定期更新进度。编排者展示 VCDDD 层进度（域级别）+ SuperPower 执行的详细状态由 SuperPower 自身展示。

```
[D3-auto] 3 个域

域 order (依赖: 无):
  ✅ 实现完成 + 审核通过
  （12 文件，32 测试通过，0 残留问题）

域 payment (依赖: order):
  🔄 Implementer 实现中...

域 inventory (依赖: order):
  ⏳ 等待 order 域审核通过后派遣
```

---

### 升级触发条件（打断用户）

| 条件 | 处理 |
|------|------|
| SuperPower 未安装 | 提示用户安装；用户拒绝后加载 fallback-execution.md |
| tech-stack.md 用户尚未确认 | 向用户呈现分析结果/方案，等待用户确认后继续 |
| business.md 内部规则矛盾 | 暂停自动化，呈现矛盾的具体描述，请求用户澄清 |
| Subagent 报告 BLOCKED（业务层面） | 暂停自动化，呈现阻塞原因，请求用户决策 |
| 对抗循环超过 10 轮仍未通过 | 按 review-loop.md 升级流程处理（拆分或标记 DONE_WITH_CONCERNS） |
| 集成验证发现技术问题（字段、幂等、依赖方向） | 编排者直接协调对应域 Implementer 修复，不打断用户 |
| 集成验证发现业务细化问题（事件顺序、并发冲突） | 暂停，向用户呈现场景，用户决策后更新 business.md |

### 注意：以下情况不打断用户

- Subagent 的实现问题（由审查循环自动修正）
- Subagent 的 NEEDS_CONTEXT（编排者补充上下文即可）
- 审查不通过后 Implementer 修复（自动循环）
- 同域内任务之间的等待（正常流程）
- 集成验证发现技术问题，编排者直接协调修复（不涉及业务决策）

---

## 最终报告格式

全部域实现完成 + 集成验证通过后，向用户呈现：

```
## VCDDD Implementation Complete  [引擎: SuperPower / 内置]

### Domain Summary

| Domain | Tasks | Status | Tests |
|--------|-------|--------|-------|
| order | 6/6 | DONE | 23 passing |
| payment | 5/5 | DONE | 18 passing |
| inventory | 3/3 | DONE | 12 passing |

### Integration Verification

- Contract structure: 7/7 verified
- E2E workflows: 3/3 passing
- Idempotency: 4/4 verified
- Event ordering: 2/2 handled
- Dependency direction: clean

### Concerns (if any)

- order/Task 3 (PlaceOrder): 审查 2 轮通过，初始实现遗漏了库存不足的幂等处理

### Code Locations

- server/order/ — Order domain implementation
- server/payment/ — Payment domain implementation
- server/inventory/ — Inventory domain implementation
- app/ — Framework adapter layer
- docs/vcddd/design/*/implementation.md — Per-domain technical decisions
```
