# 独立代码审核：F4 锁修复 + RUN-009 run 维度修复

- 审核：STDD review agent `code`（tier strong），非作者只读会话 `01a176f7-6899-77b9-a3c5-0f484069393c`；requested `OpenAIPersonal/gpt-6.1-sol:high`，actual 无后端回执 = unknown。
- 作者：主会话。本文件由主会话按审核回复落盘；处置栏为主会话所写。
- **结论：BLOCK**（三条 finding 全部针对 RUN-009 修复；F4 无 finding）。
- **适用范围补注**：BLOCK 针对当时的 RUN-009 run 补丁，该补丁现已撤回；它不是对当前 F4 修复的否决，也不是 AIFI-45 的 Gate 结论。AIFI-45 全量 Gate 仍以原 NO-GO 记录为准。

## Findings 与处置

| # | 级别 | 位置 | 问题（审核原意） | 处置 |
|---|---|---|---|---|
| 1 | major | `gate_projection.go:394`（修复版） | 判定只凭“有历史 run、无活跃 run”就认定迟到，不识别评审属于哪一轮。到达顺序不保证：`crsync.go:173` 按请求顺序处理，`lockCR` 只串行执行；`internal/daemon/crevents.go:1407` 先追加全部 outbox 事件、再追加 commit-scan 事件，不按时间合并 → 新一轮评审可能早于开轮状态事件到达，被标记 processed（`crsync.go:332`），之后重投被去重（`:322`）→ **永久丢失**。 | **采纳；撤回修复。**正确修法需要稳定的轮次/代次绑定（评审 payload 目前无 run/轮次标识），属于 RUN-009 剩余的 cycle 维度工作。 |
| 2 | major | `gate_projection.go:385–397`（修复版） | check-then-create 竞态对**现有**生产终态写入者成立：`runner.go:1607` 失败 run、`runner.go:895` 完成 run，Runner 用 run-ID advisory lock（`runner.go:704`），投影器不拿；活跃唯一索引（`migrations/590…:13`）挡不住“前一个终态后再建”。 | **采纳**（随撤回失效）；正式修复须让“评审资格判定 + run 选择/创建 + 投影”在终态写入者也遵守的同一同步下原子完成，并配确定性并发回归。 |
| 3 | minor | `gate_review_late_test.go:54` | 丢弃第二次 `postEvents` 响应；摄入失败时同样留下“有历史、无新 run、无 attempt-2 行”，可误过。 | **采纳**（随撤回失效）；复现源码另存 `run009-late-review-repro_test.go.txt`，未来修复时须补断言：accepted 且无 rejected、workspace 作用域 `processed_at IS NOT NULL`、重投仍不投影。 |

## 审核已核实、无问题的项

- **F4 锁序**：在已查生产写入者中未发现 `cr`↔`approval_record` 反序；初始授权/撤销先锁 `cr`；普通审批插入为 autocommit（`approval.go:425`）；ACK 只更新投递（`approval.go:611`）。
- **谓词不一致**：锁辅助函数缺 stage/decision 谓词只会**扩大加锁范围**，不扩大授权；后续 head JOIN 仍强制二者（`approval.sql:32–35`），无效记录仍 fail-closed。
- **错误映射**：activation/binding/consumption 均把辅助函数与 head 查询的 `pgx.ErrNoRows` 映射为 409。
- **F4 测试**：断言要求钩子执行、两次探针都被挡、HTTP 200、一条 issuance 行；未发现 vacuous 通过路径。
- **活跃状态集**：`migrations/585…:20–21` 只允许 `running/waiting_approval/completed/failed/cancelled`。
- **既存红 `TestApproveAfterIngestReviewEvent`**：审核读码判断为夹具在评审摄入前未建 workspace owner，而 `findOrCreateRun` 需要 owner（`gate_projection.go:161`）。

## 主会话处置后的验证

- 撤回：`gate_projection.go` 回到 436 行全 CRLF（= 459 − 本次 23 行），`SC-RUN-009` 残留 0。
- 夹具：`TestApproveAfterIngestReviewEvent` 在 `resetCR` 后先 `testUserID(t)` → **根因实测证实**。
- 回归（`f4-final-after-revert-20261026`）：**run 109 / pass 109 / fail 0 / skip 0 / leaf 99**；`original_unchanged:true`、会话/锁 0、`owned_resources_cleaned:true`。F4 用例与该既存红用例均在 PASS 叶子中。
