# VCDDD

[English](./README.md)

VCDDD（Vibe Coding Domain-Driven Design）是一套面向 AI 辅助开发的软件设计 skill 与方法论，同时承载两层相互支撑的含义。

本仓库采用“单 skill 独立仓库”结构，仓库根目录就是 skill 根目录。

## 仓库包含内容

- `SKILL.md`：主 skill 定义与执行规则
- `reference/methodology/`：白皮书与方法论文档
- `reference/thinking/`：需求澄清与域设计流程
- `reference/coding/`：设计确认后的实现线指导

## 目录结构

```text
vcddd/
├── SKILL.md
├── README.md
├── README.zh-CN.md
├── .gitignore
├── LICENSE
└── reference/
    ├── methodology/
    ├── thinking/
    └── coding/
```

## VCDDD 的双层含义

```
┌─────────────────────────────────────────────────────┐
│              第二层：五步工作方法论                    │
│   V → C → D¹ → D² → D³                             │
│   Vision · Context · Domain · Dev Setup · Develop   │
├─────────────────────────────────────────────────────┤
│              第一层：理论基座                          │
│   Vibe Coding × Domain-Driven Design                │
│   AI 时代对 DDD 本体的重新界定                        │
└─────────────────────────────────────────────────────┘
```

### 第一层：理论基座

VCDDD 不是「更轻的 DDD」，也不是「AI 版 DDD」，而是对 DDD 本体的重新界定。

AI 时代的基本前提已经改变：代码不再是最稀缺的资产，可以频繁重写。真正需要被优先保护的是：

- **业务真相** — 系统必须承诺的业务事实
- **语义边界** — 概念在哪里生效，在哪里失效
- **决策归属** — 谁对哪类判断有最终解释权
- **过程状态** — 业务过程在时间轴上的显式位置
- **协作契约** — 跨边界协作的稳定语义协议
- **验证屏障** — 防止实现偏离以上所有定义的机制

> 代码可以频繁变化，但系统对业务世界的表达不能漂移。

「Vibe Coding」承认 AI 生成代码的高度可变性，同时坚持业务模型必须保持稳定。两者不矛盾——正因为代码随时可以重写，业务真相才更需要被提前、独立地建立，并在全程得到保护。

### 第二层：五步工作方法论

| 步骤 | 全称 | 核心任务 | 关键产出 |
|---|---|---|---|
| **V** | Vision（意图视野） | 捕捉并结构化用户意图，不做分析 | `input.md` |
| **C** | Context（事实上下文） | 把意图澄清为逐条用户确认的业务事实 | `facts.md` + 通用语言词表 |
| **D¹** | Domain Design（域设计） | 唯一以 facts.md 为输入，推导域边界、决策归属、不变式、事件与契约 | 每个域的 `boundary.md` + `business.md` |
| **D²** | Dev Setup（开发基础） | 将技术选型写成有约束力的文档约定 | `tech-stack.md` |
| **D³** | Develop（代码实现） | 在 D¹ 域设计和 D² 约定双重约束下生成工程代码 | 工程代码 + `implementation.md` |

每个步骤之间都有不可绕过的前置门禁，上一步产出未经确认，下一步不能开始。这不是仪式感，而是防止「在未经确认的业务假设上建出看似正确的代码」。

## 建议阅读顺序

1. `SKILL.md` — 执行规则与禁止性约束
2. `reference/methodology/vcddd-methodology.md` — 五步方法论完整说明
3. `reference/thinking/requirements.md` — 如何执行 V 与 C
4. `reference/thinking/design.md` — 如何执行 D¹
5. `reference/coding/tech-setup.md` — 如何执行 D²
6. `reference/coding/implementation.md` — 如何执行 D³

如果想先读理论主干：

- `reference/methodology/vcddd-whitepaper.md`
- `reference/methodology/vcddd-design-guide.md`
- `reference/methodology/vcddd-implementation.md`

## 使用方式

本仓库遵循通用的 `SKILL.md` 约定，适合被支持本地 skill 目录的 coding agent 直接消费。

以 Codex 类工具为例，建议把整个目录放到本地 skills 路径下，并保持根目录 `SKILL.md` 不变，例如：

```text
~/.codex/skills/vcddd/
```

适用场景包括：

- 把自然语言需求翻译成经确认的业务事实
- 从业务真相出发划定域边界
- 设计不变式、状态机、事件与协作契约
- 让实现持续服从业务模型，而不是反过来被代码带偏

## 工作流概览

1. **V — Vision**：忠实捕捉用户意图，不做拆解与分析。
2. **C — Context**：把意图澄清为逐条确认的业务事实、状态机与通用语言词表。
3. **D¹ — Domain Design**：仅以确认事实为输入，推导限界上下文、决策边界、关键不变式、事件与协作契约。
4. **D² — Dev Setup**：在写任何代码之前，把技术选型与架构约定锁入文档。
5. **D³ — Develop**：在域设计与技术约定双重约束下生成代码——文档为准，代码服从。

## 许可证

本仓库使用 Creative Commons Attribution 4.0 International（`CC BY
4.0`）许可证。
