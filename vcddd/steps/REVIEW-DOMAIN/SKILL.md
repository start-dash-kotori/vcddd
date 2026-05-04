---
name: vcddd-review-domain
description: VCDDD — 三层对抗审查 + 测试验证
---

> 子 Agent 指令：本文件为子 Agent 的完整执行指令，由总控 Agent 传入并派遣执行。
> 本文件同时是控制器的调度参考——控制器必须按以下调度循环执行，不需要用户提醒。

# Step: REVIEW-DOMAIN — 域审查

对已实现的域代码进行测试验证 + 三层对抗审查。

## 前置条件

- IMPLEMENT-DOMAIN 已完成（代码 + 白盒测试 + 黑盒测试已就绪）

## 输入

- 该域 `business.md`、`boundary.md`（全文）
- `tech-stack.md`（全文）
- 实现代码 + 白盒测试 + 黑盒测试

## 输出

审查结果报告（每层的通过/不通过状态 + 问题列表）

## 调度循环（控制器强制执行）

**以下是控制器的强制执行指令。每个步骤完成后立即进入下一步，不需要用户提醒。**

```
┌─ 审查循环开始 ──────────────────────────────────────────┐
│                                                         │
│  1. 运行全部测试（白盒 + 黑盒）                          │
│     → 全部通过 → 继续 Step 2                            │
│     → 有失败 → 立即派遣 Implementer 修复                 │
│       → 修复后重新运行全部测试                            │
│       → 循环直到全部通过                                  │
│                                                         │
│  2. 【立即】派遣 Spec Reviewer                           │
│     → 传入：business.md + boundary.md + 全部代码         │
│     → 核对代码 vs business.md（Stage 1）                 │
│     → 一次性给出全部问题                                 │
│     → 返回：PASS / ISSUES                               │
│                                                         │
│  3. Spec Reviewer 返回 ISSUES 后【立即】：               │
│     → 重新派遣 Implementer，传入问题列表                 │
│     → Implementer 修复后重新提交                         │
│     → 重新运行全部测试（确认修复未引入新问题）             │
│     → 重新派遣 Spec Reviewer 审查                        │
│     → 循环直到 PASS 或达到 10 轮上限                     │
│                                                         │
│  4. Spec Reviewer 返回 PASS 后【立即】派遣 Quality Reviewer│
│     → 传入：tech-stack.md + 全部代码                     │
│     → 核对代码 vs tech-stack.md（Stage 2）               │
│     → 一次性给出全部问题                                 │
│     → 返回：PASS / ISSUES                               │
│                                                         │
│  5. Quality Reviewer 返回 ISSUES 后【立即】：             │
│     → 重新派遣 Implementer 修复                          │
│     → 重新运行全部测试                                   │
│     → 重新派遣 Spec Reviewer（确认修复未引入新问题）       │
│     → 重新派遣 Quality Reviewer                          │
│     → 循环直到 PASS 或达到 10 轮上限                     │
│                                                         │
│  6. Quality Reviewer 返回 PASS 后【立即】派遣 VCDDD Reviewer│
│     → 传入：business.md + boundary.md + tech-stack.md   │
│            + 全部代码 + Spec Reviewer 结果               │
│            + Quality Reviewer 结果                       │
│     → 核对 VCDDD 合规性（Stage 3）                       │
│     → 返回：PASS / ISSUES / CONDITIONAL                 │
│                                                         │
│  7. VCDDD Reviewer 返回后：                              │
│     → PASS → 标记该域审查完成                            │
│     → ISSUES → 重新派遣 Implementer 修复，从 Step 2 重审  │
│     → CONDITIONAL → 标记 DONE_WITH_CONCERNS，审查完成    │
│                                                         │
└─ 审查循环结束 ──────────────────────────────────────────┘
```

**关键约束**：
- **审查不可跳过**：Implementer 返回 DONE 不等于域完成，必须通过三道审查才算完成
- **审查不可省略**：不能因为"代码看起来没问题"就跳过任何一道 Reviewer
- **审查不可并行**：Spec → Quality → VCDDD 必须串行
- **修复后必须重审**：Implementer 修复后，必须从 Spec Reviewer 重新开始
- **不需要用户提醒**：整个循环是自动的

## 三份 Reviewer Prompt

各层 Reviewer 的独立 Prompt 文件：

| 层级 | Prompt 文件 |
|------|------------|
| Spec Compliance | `spec-reviewer-prompt.md` |
| Code Quality | `quality-reviewer-prompt.md` |
| VCDDD Compliance | `vcddd-reviewer-prompt.md` |

## 如果卡住

读 `../../reference/engine/review-loop.md` 获取完整核对清单。

## 日志

在 `docs/vcddd/design/{domain}/progress.log` 追加 Task 节点。各层 Reviewer 记录审查结果和发现的问题。

## 验证

- [ ] 全部测试（白盒+黑盒）通过
- [ ] Stage 1: 所有不变式/状态迁移/命令路径在代码中实现
- [ ] Stage 2: 命名/目录/依赖/日志/错误处理符合 tech-stack.md
- [ ] Stage 3: 域边界正确、通用语言一致、事务对齐、事件事务后发布
- [ ] 每层首次审查一次性给出全部问题
- [ ] 对抗循环不超过 10 轮
