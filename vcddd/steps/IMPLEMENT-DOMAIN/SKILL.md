---
name: vcddd-implement-domain
description: VCDDD — 一个 Agent 完成域代码 + 白盒测试 + 黑盒测试
---

> 子 Agent 指令：本文件为子 Agent 的完整执行指令，由总控 Agent 传入并派遣执行。

# Step: IMPLEMENT-DOMAIN — 域代码实现

一个域的所有代码和测试由同一个 Agent 一次性完成。

## 前置条件

- 该域 `business.md`、`boundary.md`、`test-spec.md` 就绪
- `tech-stack.md` 已存在
- 被依赖域已实现完成

## 输入

- 该域 `business.md`、`boundary.md`、`test-spec.md`（全文）
- `tech-stack.md`（全文）
- 被依赖域 `boundary.md` 摘录

## 输出

```
server/{domain}/
├── aggregate.{ext}
├── commands.{ext}
├── events.{ext}
├── repository.{ext}
├── {db}.repository.{ext}
├── read_model.{ext}
├── event_consumers.{ext}
├── __tests__/unit/          ← 白盒测试（内部分支 + 边界）
└── __tests__/blackbox/      ← 黑盒测试（命令级验证）
```

## 完成要求

1. 写全部代码：聚合、命令、事件、仓储、事件消费、读模型
2. 写白盒测试：覆盖内部分支（if/else/switch 全部路径）+ 数据边界（null/边界值/异常输入）
3. 写黑盒测试：基于 test-spec.md 中的自然语言目标覆盖全部测试 ID
4. 命名与 business.md 通用语言词表一致
5. 所有测试通过
6. 在 progress.log 中记录操作
7. **报告状态**：DONE / DONE_WITH_CONCERNS / BLOCKED

## 完成后的控制器行为

Implementer 返回状态后，控制器必须按以下规则继续：

| Implementer 返回 | 控制器下一步 |
|-----------------|-------------|
| DONE | **立即**进入 REVIEW-DOMAIN（三道审查循环） |
| DONE_WITH_CONCERNS | **立即**进入 REVIEW-DOMAIN（审查中会处理 CONCERNS） |
| BLOCKED | 暂停自动化，向用户呈现场景和阻塞原因 |

**控制器不得在 Implementer 返回 DONE 后暂停或等待用户确认——必须自动进入审查流程。**

完整 Prompt 见 `implementer-prompt.md`。

## 如果卡住

读 `../../reference/engine/implementation.md` 获取强制规范。
