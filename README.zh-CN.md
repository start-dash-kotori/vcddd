# VCDDD

[English](./README.md)

VCDDD（Vibe Coding Domain-Driven Design）是一套面向 AI 辅助开发的软件设计 skill 与方法论。它尝试把 DDD 的重心重新拉回到业务真相、语义边界、决策归属、过程状态、协作契约和验证屏障上。

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

## 核心定位

VCDDD 的核心判断是：

> 代码可以频繁变化，但系统对业务世界的表达不能漂移。

它主要关注：

- 先有业务真相，再有技术结构
- 限界上下文是语义主权，不是目录划分
- 跨时间业务过程必须显式状态化
- 跨边界协作依赖契约，而不是隐式耦合
- 用验证屏障防止设计在实现中逐步失真

## 建议阅读顺序

1. `SKILL.md`
2. `reference/thinking/requirements.md`
3. `reference/thinking/design.md`
4. `reference/coding/tech-setup.md`
5. `reference/coding/implementation.md`

如果想先看理论主干，建议优先读：

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

1. 先把用户意图翻译成可确认的业务事实。
2. 再从决策归属与语义边界推导出域设计。
3. 明确不变式、状态机和跨域协作契约。
4. 只有在业务设计被确认后，才进入实现线。
5. 始终以文档化业务模型约束代码，而不是以现有代码反推业务。

## 许可证

本仓库使用 MIT License。
