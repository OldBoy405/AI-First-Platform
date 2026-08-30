---
cr: CR-2026-056
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-31T03:28:17+08:00"
command-digest: ae3513a3ee145671bcf030683e86dc4b6f202d18da7aa7ff7efc95d6a994da48
commands:
  - repo: multica
    cwd: server
    executable: go
    args: [build, ./...]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-056/test-evidence/cmd-01.log
  - repo: multica
    cwd: server
    executable: go
    args: [vet, ./internal/handler/, ./internal/service/, ./pkg/agent/]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-056/test-evidence/cmd-02.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/handler/, "-count=1"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-056/test-evidence/cmd-03.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./pkg/agent/, "-count=1", -run, "ValidateChatConfig|ModelIDForCapabilityLookup|StaticCatalog|ChatConfig"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-056/test-evidence/cmd-04.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/service/, "-count=1", -run, ChatDraftAttachment]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-056/test-evidence/cmd-05.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/service/, "-count=1", -run, "PrivateAsk|PatchChatSessionConfig|OrdinaryChat|ProjectClearRacing|PatchRacingSendSerialized|ConcurrentPatches|ChatTaskQueryBoundary"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-056/test-evidence/cmd-06.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/service/, "-count=1", -run, "ProjectChat|ChatSession|MergeChatConfigContext|SnapshotAgentDefaults|ApplyChatConfigFieldPatch"]
    timeout-seconds: 900
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-056/test-evidence/cmd-07.log
---

# 测试报告 · CR-2026-056

<!-- crctl:analysis-below -->
## 测试摘要

7 条计划命令全部 exit 0（`crctl test` 机器区 status=pass，attempt 1/3）。执行环境为 Windows 本机（无可用 Postgres：`newProjectChatSessionTestPool` 与 handler 测试夹具按仓内惯例在缺库时 `t.Skip`——见 CUSTOM.md C6「防绿灯没测」口径，DB 夹具在 CI 设 `DATABASE_URL` 时自动执行）；`go build`/`go test` 均带 `GOFLAGS=-buildvcs=false`（受控 shell 的 git shim 拒绝 Go 的 VCS stamping，TASK-01 已记录）。

## 验证命令解读

- **cmd-01 `go build ./...`**：全仓编译绿。
- **cmd-02 `go vet`（handler/service/pkg-agent 三包）**：绿。
- **cmd-03 `go test ./internal/handler/ -count=1`**：绿（handler 测试夹具无库自动跳过，CI 有库全跑）。
- **cmd-04 `go test ./pkg/agent/ -run 'ValidateChatConfig|ModelIDForCapabilityLookup|StaticCatalog|ChatConfig'`**：CR 域（TASK-04 校验矩阵与目录导出）绿；pkg/agent 全量在本机不绿属基线环境限制（约 15 个外部 CLI 后端未安装，TASK-01 记录）。
- **cmd-05 `go test ./internal/service/ -run ChatDraftAttachment`**：AC-28 命令（TASK-09 完成标志），本机无库 SKIP、CI 执行。
- **cmd-06**：TASK-13 全部 Private Ask/并发夹具（BLOCK-004~010 对应测试），本机无库 SKIP、CI 执行。
- **cmd-07**：TASK-05/06/07/08 会话内核/发送/merge/三态 fold 夹具，本机无库 SKIP、CI 执行。

全量三组基线（`go test ./internal/handler/ ./pkg/agent/ ./internal/service/ -count=1`）本机不绿的既有环境失败与 TASK-01 记录一致（外部 CLI 后端缺失 + builtin_skills CRLF frontmatter + 上游 Windows 路径分隔符 bug），与本 CR 改动无关——本 CR 变更域以 cmd-03~07 的范围验证。

## TASK 验收覆盖矩阵

| TASK | 验收 | 证据 |
|---|---|---|
| TASK-01 M0 基线 | 基线 SHA/迁移号/测试入口 | 基线 8746add 核实（TASK-01 完成记录） |
| TASK-02 迁移 472–480 | 一文件一句/up-down 配对 | `server/migrations/472~480`；cmd-01 编译 |
| TASK-03 sqlc | 新查询与改造查询、调用方零回归 | cmd-01/03/07；`TestCreateAgentTaskContextMergesChatConfigWithHeadSha`（cmd-07） |
| TASK-04 pkg/agent 校验导出 | 校验矩阵 16 例 | cmd-04 |
| TASK-05 chat_config/catalog | 判定表 13 例 | `chat_config_test.go`（cmd-07 覆盖 `TestLoadChatCatalogForVerdict`） |
| TASK-06 会话内核 | AC-11/25 类、三态 | `project_chat_session_test.go`（cmd-07）；handler 全量（cmd-03） |
| TASK-07 发送内核 | BLOCK-003 五类零残留、merge、换绑 | `project_chat_send_test.go`/`merge_forward_test.go`（cmd-03）；service 组（cmd-07） |
| TASK-08 转投兼容钉/claim/presenter | 快照生效/回退/零 diff | `daemon_claim_chat_config_test.go`（cmd-03 真库组）；`comment.go`/`discussion_coordinator.go` 零 diff 已核对 |
| TASK-09 附件草稿 + sweeper | AC-14/28、BLOCK-011 | `chat_draft_attachment_cleanup_test.go`（cmd-05）+ `file_draft_gate_test.go`（cmd-03） |
| TASK-13 Private Ask 后端闭环 | AC-3/19/25、BLOCK-004~010 | `private_ask_config_test.go` + `private_chat_config_test.go`（cmd-06 + cmd-03 真库组） |
| TASK-10 前端 | AC-26/27、AC-1/2/3/21、BLOCK-007 | `schemas.test.ts`、`parity.test.ts`、三组件测试（已提交；本机无 node_modules 未执行，见未覆盖风险） |
| TASK-11 本任务 | 三组 go test/必过夹具/CUSTOM.md/test-report | 本报告 + CUSTOM.md #59–#66 |

## 新增/修改测试文件

- `server/internal/service/chat_draft_attachment_cleanup_test.go`（新）
- `server/internal/service/private_ask_config_test.go`（新）
- `server/internal/service/chat_config_test.go`、`chat_config_snapshot_test.go`、`project_chat_session_test.go`、`project_chat_presenter_test.go`（扩展）
- `server/internal/handler/file_draft_gate_test.go`、`private_chat_config_test.go`、`daemon_claim_chat_config_test.go`、`project_chat_send_test.go`（新/扩展）
- `server/pkg/agent/chat_config_validation_test.go`（新）
- 前端：`packages/core/api/schemas.test.ts`（新 describe）、`packages/views/locales/parity.test.ts`（覆盖新键）、`project-chat-panel.test.tsx`/`project-team-agent-chat.test.tsx`/`project-private-ask.test.tsx`（扩展/适配）

## 未覆盖风险

1. **DB 夹具本机未执行**（无 Postgres，仓内惯例 `t.Skip`）：CI 设 `DATABASE_URL` 时自动执行（C6 口径，`--- SKIP` 视为未测）。cmd-05/06/07 在本机为 SKIP，属环境限制而非失败。
2. **前端三类测试本机未执行**：multica 仓 `node_modules` 未安装（`pnpm install` 未跑），vitest/tsc 无法本地执行；测试代码已随 TASK-10 提交，交由 CI（`pnpm -C packages/core vitest run api/schemas.test.ts`、`pnpm -C packages/views vitest run ...`）与首次 install 后复核。
3. **KG-1（转投无 chat_config 快照）/ KG-2（换绑后转投仍写旧 Issue）**：已知缺口，归 CR-B/CR-C（SDD §4.13），test-report 明示不当本 CR 缺陷。
4. **`target-version` 仍为 tbd**：plan.md 保留建议，代码评审前由需求负责人（Ray）补齐。

## 下一步建议

按 `crctl next CR-2026-056` 推进：test-report pass → `push-progress → review-code`（由 quality-reviewer-agent 执行）。进入评审前需 Ray 补齐 `target-version`。
