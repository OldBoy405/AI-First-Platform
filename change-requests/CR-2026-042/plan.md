---
id: CR-2026-042-plan
type: PLAN
cr-ref: CR-2026-042
sdd-ref: "change-requests/CR-2026-042/sdd.md"
target-version: tbd
status: draft
created: 2026-08-16T15:34:15+08:00
updated: 2026-08-16T15:34:15+08:00
---

# 1. 交付里程碑

本 CR 是纯文档/契约治理改造，无运行时发布面，按「收敛 -> 静态治理 -> 全量验证」三阶段推进。

| 里程碑 | 内容 | 预估工时 | 对应 TASK |
|---|---|---|---|
| M1 调用方合同收敛 | Agent / Pipeline / Skill / README 文本与结构收敛，code Pipeline 删除 reviewer 暂停节点 | 20h | TASK-01~04 |
| M2 静态治理与 CI | lint R10-R13 扩展、Pipeline 固定结构断言、workflow 合并 | 14h | TASK-05~06 |
| M3 全量验证 | Ubuntu/Windows 下 lint、matrix、agent contract、crctl、writeback、JSON 全绿 | 3h | TASK-07 |

估算总工时：**37h**（约 4.6 人天）。

# 2. 任务依赖图

```text
TASK-01 Agent 文档收敛 ─┐
TASK-02 Pipeline 收敛 ──┼──> TASK-04 README/ARCHITECTURE ─┐
TASK-03 Skill 收敛 ─────┘                                  ├──> TASK-07 全量验证
TASK-05 lint R10-R13 ──┐                                   │
                       ├──> TASK-06 CI + Pipeline 检查 ─────┘
（TASK-02 Pipeline 结构）┘
```

- TASK-01/02/03/05 互相独立，可并行；
- TASK-04 依赖 TASK-01/02/03（README 描述收敛后的最终态）；
- TASK-06 依赖 TASK-02（节点数 17→16 的固定断言）与 TASK-05（新 lint 规则入 CI）；
- TASK-07 依赖全部前序 TASK。

# 3. 资源与分工

| 角色 | 职责 | 工时 |
|---|---|---|
| 开发 | TASK-01~06 实现 | 34h |
| 测试 | TASK-07 验证命令执行与证据记录 | 3h |
| 需求 | 范围确认与 README 措辞复核 | 参与 TASK-04 验收 |

本 CR 三角色 owner 均为 Ray；无跨仓分工，全部改动落在 tools 仓（含 README/agents/skills/pipeline/workflow/lint）。

# 4. 风险与回滚策略

| 风险 | 控制 | 回滚 |
|---|---|---|
| 文本缩短误删业务判断 | 按「保留 interface、删除 implementation」逐文件评审，FR 映射表兜底 | 逐 TASK 单独 commit，`git revert` 单任务 |
| lint 扩面误报 | 新规则限定文件类型/段落/字面形态，正反例测试 | 关闭单条规则或回退 lint 改动 |
| reviewer 节点删除破坏 reviewLoop | node ID 顺序与 replayNodes 静态断言 | 恢复 `...0013` 节点与 `review_llm` input |
| CI 合并减少检查 | 主 workflow 保留两个 checker 与全部测试，双平台矩阵不变 | 恢复 check-skill-matrix.yml |
| OpenWiki 未同步 | 由既有 workflow 刷新并扫描旧引用 | 手工触发 openwiki-update.yml |

本 CR 不迁移数据、不改状态机/账本/schema，回滚成本低；所有改动均为可独立 revert 的文档/JSON/lint/workflow commit。

# 5. 验收与发布策略

发布前 checklist（对应 TASK-07）：

1. `lint-prompts.mjs --mode enforce` 零阻断；
2. `check-skill-matrix.mjs`、`check-agents-contract.mjs` 通过；
3. 全部 Pipeline JSON 可解析且固定字段断言通过；
4. `node --test --test-concurrency=2 skills/shared/crctl/scripts/test/*.test.mjs` 全绿；
5. `node --test skills/writeback/scripts/test/*.test.mjs` 全绿；
6. code Pipeline 16 节点、无 `review_llm`、无 `...0013`；
7. README 必需章节与权威链接存在，禁止内容零命中。

发布策略：

- 无 feature flag：本 CR 是文档/治理契约收敛，改动随 tools 分支合入 `custom/main`；
- 回写期只写 specs/delivery，不触发运行时发布；
- code Pipeline 的 reviewer 选择由 runtime 在进入 Pipeline 前完成，属调用方行为，无需发布开关。
