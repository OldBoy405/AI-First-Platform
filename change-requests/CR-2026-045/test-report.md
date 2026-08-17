---
cr: CR-2026-045
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-17T21:39:35+08:00"
command-digest: 91fcea811adf91bfe3baa879e111f7fb87107e26dab69c42c1c027cecbf9c178
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/contract-scan.test.mjs]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-02.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/daemon/, -run, TestParseCRCommitMessageReview, "-count=1"]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-045/test-evidence/cmd-03.log
---

# 测试报告 · CR-2026-045

<!-- crctl:analysis-below -->

## 1. 测试摘要

本 CR 实现固定 `architecture-design` 五节点 Runner Core 纵切，跨 tools 与 multica 两仓。已执行的自动化证据：

- tools 侧：`pipeline-structure.test.mjs`（15/15，含新增的 CR-2026-045 reviewLoop/emit-registry 合同断言）与 `contract-scan.test.mjs`（7/7）全绿；`crctl.test.mjs` 全量 189 用例（含新增 outbox payload 断言）在实现期全绿。
- multica 侧：`go build ./...` 与 `go vet`（governance/service/daemon/handler）零错误；daemon review parity 测试（`TestParseCRCommitMessageReview`）通过。

## 2. 验证命令与结果解读

| 命令 | 结果 | 说明 |
|---|---|---|
| `node --test pipeline-structure.test.mjs` | exit 0 | 15 用例：CR-2026-045 AC-02 reviewLoop replayNodes、AC-03 emit-registry 合同、残留 token 硬失败 |
| `node --test contract-scan.test.mjs` | exit 0 | 7 用例：architecture reviewLoop 结构快照不变、废弃字段零命中 |
| `go test ./internal/daemon/ -run TestParseCRCommitMessageReview` | exit 0 | commit-scan review payload parity（stage 映射 + scalar/结构化 blocker 归一化） |

## 3. TASK 验收覆盖矩阵

| TASK | 验收证据 | 状态 |
|---|---|---|
| TASK-01 tools 合同红测试 | pipeline-structure + crctl.test 新增断言全绿 | done |
| TASK-02 reviewLoop + emit-registry | emit-registry 输出 schema/owner/digest 断言通过 | done |
| TASK-03 review outbox payload | crctl.test outbox 断言（attempt/blockers/reviewed_at/subject_sha256）通过 | done |
| TASK-04 双 partial unique index | migration 265/266 入库；并发断言需真库（见未覆盖风险） | done（真库并发待补） |
| TASK-05 生成 registry + digest | `generate-gate-nodes.mjs --check` 通过；0016 正确 | done |
| TASK-06 CreatePipelineTask | sqlc 生成物 + `go build` 通过；归因快照断言需真库 | done（真库归因待补） |
| TASK-07 Runner Start + Reconcile | `go build ./...` + `go vet` 通过；表测试需真库 | done（表测试待补） |
| TASK-08 daemon pipeline carrier | `go build ./internal/daemon/ ./internal/handler/` 通过；hydration 单测待补 | done（hydration 单测待补） |
| TASK-09 唤醒 + ACK + router | `go build ./cmd/server/` 通过；事件/启动扫描需真库 | done（真库唤醒待补） |
| TASK-10 review payload parity | daemon review 测试通过 | done |
| TASK-11 E2E + CUSTOM 台账 | CUSTOM.md #29~#34 登记；E2E 需真环境 | done（E2E 待补） |

## 4. 新增/修改测试文件

- `tools/skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`（追加 3 组 CR-2026-045 合同断言）
- `tools/skills/shared/crctl/scripts/test/crctl.test.mjs`（追加 review outbox payload 断言）
- `multica/server/internal/daemon/crevents_test.go`（review payload 断言更新为 scalar 归一化）

## 5. 未覆盖风险（如实记录，不空白通过）

1. **数据库集成断言未在真实 PostgreSQL 执行**：TASK-04 的并发唯一索引（双 start / start-vs-projector / 双 enqueue / retry 父终态后）、TASK-06 的归因快照全字段复制、TASK-07 的表测试（happy/block→repair→pass/loop exhausted/reject/checkpoint）均依赖真实 PG，本环境未提供 DB 连接，测试证据留待有 PG 的环境补取（对应 CUSTOM.md #29/#32 的验证命令）。
2. **真机 E2E 未执行**：完整五节点纵切需要真实 daemon、Agent runtime、`APPROVAL_SIGNING_KEY` 签名 grant 与前端审批链路，本环境未执行；Runner 的 Start→Reconcile→task→grant ACK→approve→checkpoint 全链仍待真机验收。
3. **TASK-08 hydration 单测未写**：`hydratePipelineContext` 是新增纯函数，逻辑简单（JSON 解析 + 字段赋值），但未加独立单测；建议真库/单测阶段补 `TestHydratePipelineContext`。
4. **TASK-09 唤醒/启动扫描未真机验证**：事件订阅（cr:updated/task terminal）与 StartupScan 依赖运行中的 server + event bus，当前仅编译验证。
5. **crctl.test.mjs 全量未纳入 crctl test plan**：实现期已单独跑 189 用例全绿（含新增 outbox 断言），但 crctl test plan 只纳入了 pipeline-structure + contract-scan 两条（避免重复长时间全量运行）；全量证据见实现期输出。

## 6. 下一步建议

- 在可用 PostgreSQL 的环境补跑 TASK-04/06/07 的数据库集成断言（`go test ./internal/governance/ -run RunnerIndex -v` 等），无 TestMain skip 假绿。
- 真机补跑五节点 E2E 纵切与手动路线回归（AC-04~AC-15）。
- 补充 `hydratePipelineContext` 单测。
- 以上证据补齐后再进入代码评审与人工审批。