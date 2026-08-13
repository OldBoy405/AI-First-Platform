---
cr: CR-2026-033
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-13T22:02:13+08:00"
commands:
  - { command: "node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-033/test-evidence/cmd-01.log" }
  - { command: "node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-033/test-evidence/cmd-02.log" }
  - { command: "node --check skills/shared/crctl/scripts/crctl.mjs", exit: 0, log: "change-requests/CR-2026-033/test-evidence/cmd-03.log" }
---

# 测试报告 · CR-2026-033

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-033/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-033/test-evidence/cmd-01.log |
| 2 | `node --test skills/writeback/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-033/test-evidence/cmd-02.log |
| 3 | `node --check skills/shared/crctl/scripts/crctl.mjs` | 0 | change-requests/CR-2026-033/test-evidence/cmd-03.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

### 结果摘要

- crctl tests：275/275 pass；writeback tests：10/10 pass；CLI 语法检查通过。
- checkpoint 专项：22/22 pass（初版 5 项扩充至 22 项，不再用全仓测试总数代替专项覆盖）。
- 额外静态验证：`lint-prompts --mode enforce` 0 findings；4 个 Pipeline JSON 全部可解析；`git diff --check` 通过。

### 代码评审 blocker 回归覆盖

- 首次发布：三个 bare remote 均不存在 requirement ref 时以 exact-head 创建成功，锁定 `rev-parse --verify -q` 语义。
- 恢复：source commit、confirm、push 响应丢失、metadata write-set/commit、metadata commit/save、metadata push 后故障、residual complete journal 均可重放收敛且不重复提交；账本候选不会被吞入 KB source。
- 远端关系：advanced、diverged、published 后 history rewrite 使用真实 bare remote 集成场景验证；classifier 另有纯函数边界断言。
- 安全与零副作用：畸形 snapshot、损坏 index 导致 Git 查询失败、敏感路径/私钥头、worktree missing/wrong-branch 均使用冻结错误码并验证零错误推送。
- 平台边界：CRLF backlog、文件名含空格、`.env.example`、普通 `.pem`、tracked/untracked/ignored 组合均覆盖。
- T05：Pipeline prompt 只编排 `push-progress`/`list-remote-checkpoints`，active `review-alignment` reader 只读 `latest-checkpoint`，静态契约防止旧 `checkpoints[]` 回归。
- journal 错误输出：journal 创建后的错误固定含 `txId`、`phase`、`sideEffects`、`recoverCommand`；损坏业务 payload 返回 `TX_RECOVERY_CONFLICT`。

### TASK 对应

- TASK-01/02：checkpoint generic envelope、5 个 fault point、业务 payload 与 durable envelope 职责边界保持原设计。
- TASK-03：batch-id、单一 latest-checkpoint 整块替换、排序与 snapshot 结构校验由 happy/malformed/CRLF 场景覆盖。
- TASK-04：三仓 source/publish/metadata、no-op、exact-head 分类、故障恢复、敏感预检及固定错误 JSON 由 22 项专项覆盖。
- TASK-05：6 个 Pipeline 节点与 active reader 迁移有静态测试；旧 CLI 不恢复。

### 范围外风险

- 未模拟真实托管平台权限策略、网络代理和跨设备文件系统；本地三 bare-remote 覆盖 Git graph/lease/replay 语义，真实环境由本 CR 的统一 checkpoint dogfood 再验证。
- 未新增通用事务框架、schema engine、消息队列或第三方依赖；修复继续复用 `durable-tx.mjs`、Git 与现有 YAML 子集解析。
