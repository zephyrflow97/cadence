# 手动调用 Skill 的入口指南

Cadence 默认按完整工作流自动连贯运行，但你也可以从任意阶段手动切入。本文档按"作为对话起点的常见度"分档列出所有 skill，帮助你在需要时直接挑对入口。

## 主入口

绝大多数工作的起点，按场景对号入座：

| 场景 | 入口 skill |
|---|---|
| 构建新功能或新模块 | `brainstorming` |
| 修 bug、查测试失败或异常行为 | `systematic-debugging` |
| 已有 spec，需要拆任务 | `writing-plans` |
| 已有 plan，准备执行 | `subagent-driven-development` |
| 实现完成，要决定如何收尾 | `finishing-a-development-branch` |
| 收到 PR 评论或代码评审反馈 | `receiving-code-review` |

心智模型：沿着工作的自然阶段选入口——构思 / 调试 / 计划 / 执行 / 收尾 / 回应。

## 次入口

通常作为流程中段出现，但单独使用也合法：

- **using-git-worktrees** — 只想起一个隔离工作区
- **dispatching-parallel-agents** — 一次处理多个独立任务
- **requesting-code-review** — 评审已经写完的代码
- **writing-skills** — 创建或修改一个 skill

## 辅助型

被设计为在其他 skill 内部引用，但你也可以单独喊：

- **test-driven-development** — 给没测试的代码补测试
- **verification-before-completion** — 让 Agent 为之前的"完成"声明给出证据

## 触发语速查表

按你开口的第一句话找入口：

| 你想说的话 | 该唤起 |
|---|---|
| "做一个新功能…" | brainstorming |
| "做一个新组件…" | brainstorming |
| "重构 X 模块…" | brainstorming |
| "X 报错 / 测试挂了 / 慢" | systematic-debugging |
| "我有个 spec 在 docs/ 里" | writing-plans |
| "我有个 plan 在 docs/ 里" | subagent-driven-development |
| "代码写完了，下一步呢" | finishing-a-development-branch |
| "PR 上有人评论说…" | receiving-code-review |
| "帮我 review 一下" | requesting-code-review |
| "起个 worktree" | using-git-worktrees |
| "并行处理这堆独立的事" | dispatching-parallel-agents |
| "我想沉淀一个 skill" | writing-skills |
| "补测试 / 加测试" | test-driven-development |
| "验一下是不是真的完成了" | verification-before-completion |

## 手动使用的小诀窍

显式说出 skill 名 + 场景，效果最好：

- 推荐："用 systematic-debugging 调查这个数据丢失问题。"
- 不推荐："查一下这个 bug。"（Agent 可能跳过 Phase 1 直接改）

显式触发的好处是**绕过 Agent 的"我觉得这事儿不需要走流程"判断**——许多时候 Agent 会因为"看起来简单"而省略前置步骤，喊 skill 名就把这扇逃跑门关上了。

## 相关文档

- 完整工作流总览：见仓库根目录 [README.md](../README.md)
- 测试相关约定：[testing.md](./testing.md)
