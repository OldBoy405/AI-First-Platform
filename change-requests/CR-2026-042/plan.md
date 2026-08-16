---
id: CR-2026-042-plan
type: PLAN
cr-ref: CR-2026-042
sdd-ref: "change-requests/CR-2026-042/sdd.md"
target-version: tbd
status: draft
created: 2026-08-16T15:34:15+08:00
updated: 2026-08-16T16:00:40+08:00
---

# 1. 交付里程碑

本 CR 是 tools 仓的文档、Pipeline JSON 与确定性治理改造，不改变 `crctl` 生产算法、状态机、账本或 schema。

| 里程碑 | 内容 | 估算 | TASK |
|---|---|---:|---|
| M1 调用方合同收敛 | 收敛 Agent/Pipeline，删除 code Pipeline reviewer 暂停 | 8h（1 人天） | TASK-01 |
| M2 Skill 与人读入口收敛 | 收敛 Skill，重写 README，定点更新 ARCHITECTURE | 12h（1.5 人天） | TASK-02 |
| M3 治理、CI 与发布验收 | lint R10-R13、CI 合并、Pipeline 断言、全量测试与 OpenWiki 发布检查 | 17h（约 2.1 人天） | TASK-03 |

估算总工时：**37h（约 4.6 人天）**。

# 2. 任务依赖图

```text
TASK-01 Agent/Pipeline 合同收敛
    -> TASK-02 Skill/README/ARCHITECTURE 收敛
        -> TASK-03 lint/CI/全量验证/OpenWiki 发布检查
```

三个 TASK 均为 1-3 天粒度。TASK-02 使用 TASK-01 的 reviewer/runtime 最终合同；TASK-03 对前两项产出做确定性治理和全量验收。

# 3. 资源与分工

| 角色 | 职责 | 工时 |
|---|---|---:|
| 开发 owner Ray | TASK-01~03 的 tools 仓改造与本地验证 | 34h |
| 测试 owner Ray | TASK-03 双平台 CI、回归证据与 OpenWiki 生成 PR 核验 | 3h |
| 需求 owner Ray | TASK-02 README 措辞和发布后生成页复核 | 包含在上述工时 |

# 4. 风险与回滚策略

| 风险 | 验证 | 回滚 |
|---|---|---|
| 文本缩短误删业务判断 | 保留 interface，逐项核对 SDD 文件映射与 FR | 按 TASK commit revert |
| lint 扩面误报 | R10-R13 正反例及 LF/CRLF 等价测试 | 回退单条规则 |
| reviewer 节点删除破坏 reviewLoop | 16 节点、后继与 replayNodes 固定断言 | 恢复 `review_llm` 与 `...0013` |
| workflow 合并漏检查 | 单一 CI 保留双 checker、双平台及全量测试 | 恢复独立 workflow |
| OpenWiki 生成页继续传播旧事实 | 合并后触发既有 workflow，检查生成 PR 的旧引用 | 不合并生成 PR；修正源文档后重跑 workflow |

无数据迁移、feature flag 或运行时回滚；本 CR 的最小回滚单位是 TASK commit。

# 5. 验收与发布策略

合并前：

1. `lint-prompts.mjs --mode enforce` 零阻断；
2. `check-skill-matrix.mjs`、`check-agents-contract.mjs` 通过；
3. Pipeline JSON 可解析且固定字段、active Skill ref、replayNodes 断言通过；
4. crctl 与 writeback 全量测试全绿；
5. code Pipeline 为 16 节点，无 `review_llm` 与 `...0013`；
6. `agents/` 与 `skills/` 中 `git add|git commit|git push` 可执行配方零命中（测试描述除外）；
7. README 必需章节与权威链接存在，禁止内容零命中。

合并后：

1. 通过 `.github/workflows/openwiki-update.yml` 的 `workflow_dispatch` 触发既有 OpenWiki 更新；
2. 检查其 `openwiki/update` PR，确认 `check-skill-matrix.yml`、engineering-docs/MCP、旧 reviewer 暂停等失效引用归零；
3. 生成 PR 未通过检查时不合并，修正源 Agent/Pipeline/Skill/README 后重跑 workflow；禁止手改生成页绕过源事实。
