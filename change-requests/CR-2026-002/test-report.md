---
id: CR-2026-002-test-report
type: TEST_REPORT
cr-ref: CR-2026-002
tester: Ray
tester-assigned-at: "2026-07-31T07:17:01+08:00"
status: pass
blockers: []
repair-target: implement-code
repair-instructions: []
review-loop:
  pass-condition:
    allOf:
      - path: status
        equals: pass
      - path: blockers
        isEmpty: true
  on-block: route-to-repair-node
  max-attempts: 3
  current-attempt: 0
  attempts:
    - attempt: 0
      generated-at: "2026-07-31T18:10:37+08:00"
      result: pass
      blocker-count: 0
      repair-target: implement-code
created: "2026-07-31T18:10:37+08:00"
updated: "2026-07-31T18:10:37+08:00"
---

# CR-2026-002 测试报告（P1 治理核心 — crctl 接入）

## 1. 测试摘要

11/11 开发任务（T01-T11，120h）全部完成并留验证证据。三个仓的自动化测试全绿（tools JS 20/20、multica governance/gitguard/daemon/handler 相关包全部通过、fmt/vet/build 干净），T11 在本机全栈（Docker 三容器 + daemon + crctl + 真实 GitHub origin）完成 AC-1..7 端到端真机验收，每条 AC 均有可复查证据（见 `tasks/TASK-11.md` 完成记录）。开发与验收期共抓到并修复 6 个真缺陷（含 1 个阻断级），零遗留 blocker。**结论：pass。**

## 2. 验证命令与结果

| 命令 | 执行目录 | 结果 | 说明 |
|---|---|---|---|
| `node --test test/crctl.test.mjs` | tools/skills/shared/crctl/scripts | ✅ 20/20 | 含证据摘要共享向量、EVIDENCE_DRIFT 检出与 outbox 留证、裸 --grant 回归、RE2 兼容锁 |
| `go build ./...` | multica worktree server/ | ✅ | 全仓构建干净（含 cmd/server 治理任务注册、cmd/multica gitguard-exec） |
| `gofmt -l` / `go vet`（治理相关包） | 同上 | ✅ 0 差异 / 0 告警 | fork 新增 .go 文件全部 LF + gofmt 干净 |
| `go test ./internal/governance/`（真库） | 同上 | ✅ 28 过 / 2 跳过 | 跳过项：跨工具验签（需 CRCTL_PATH，T08 已实测过）、GitHub 实测（gated，见下行） |
| `go test -run TestReconcileLiveGitHub`（真库+PAT） | 同上 | ✅ | 对真实 GitHub origin：取 HEAD + backlog，篡改行自愈（AC-3①② server 模式） |
| `go test ./pkg/gitguard/` | 同上 | ✅ 6/6 | 三元白名单表驱动 + OnDeny 最小化 + SpoolDenial 原子写 + RE2 conformance |
| `go test ./internal/daemon/ -run "CREvent\|Snapshot\|DualChannel\|Poisoned\|NetworkFailure\|ParseCRCommit"` | 同上 | ✅ 8/8 | 采集器双通道/三振/离线重试 + 快照首拍/节流/失败不推进 |
| `go test ./internal/handler/ -run TestCompleteTask`（真库） | 同上 | ✅ | 工具调用摘要聚合（AC-6②③），含输入正文泄漏断言 |
| T11 全栈串联（人工驱动，逐条留痕） | 本机全栈 | ✅ AC-1..7 | 证据链逐条见 `tasks/TASK-11.md` 完成记录 |

**测试环境口径**：本机 Go DB 集成测试必须显式取容器真密码并走 5433 转发（CUSTOM.md C6）；`go test` 打 `ok` 不等于测试执行过（TestMain 连不上库时静默跳过），本报告所有"真库"结果均以 `-v` 下 `--- PASS` 确认。

## 3. TASK 验收覆盖矩阵

| TASK | 内容 | 验收证据 |
|---|---|---|
| T01 | rules.json 单一事实源 + hook 改造 | JS 测试（三消费方一致）；完成记录 |
| T02 | crctl outbox 事件 + canonical 摘要 | JS 测试 + 共享摘要向量（c28c5b93…）；本 CR 全程 push 事件自证 |
| T03 | 签名审批 crctl 半边（approve --grant / 两轨 gate） | JS 测试 + T08 跨工具验签 + T11 AC-4 真机 |
| T04 | 迁移 158 三表 + transitions_gen（45 转移 + gen --check） | Go 测试；迁移已在真库应用 |
| T05 | 投影 worker（幂等/合法转移/乱序防护/WS） | Go 集成测试 6 项 + T11 AC-2 真机 |
| T06 | daemon 采集器（双通道/ack 删/三振/离线积压） | Go 测试 5 项 + T11 AC-1 真机（43 条积压补传） |
| T07 | reconcile 双模式 | Go 测试 + GitHub 实测 + T11 AC-3 双模式真机自愈 |
| T08 | Ed25519 签名审批服务端（人类身份/漂移 409/grant 队列） | Go 测试 7 项 + 跨工具验签 + T11 AC-4 全链 |
| T09 | gitguard + execenv 四处改造 | Go 测试 + T11 AC-5①②③ 真机三连拒 |
| T10 | 行为审计（audit 事件 → activity_log + 工具摘要） | Go 测试 9 项 + T11 AC-6①/AC-7③ 真机留痕 |
| T11 | 端到端验收 | AC-1..7 证据链本身 |

## 4. 新增/修改测试文件

- tools：`crctl.test.mjs`（20 用例，含本 CR 新增漂移留证与 --grant 回归）、`test/fixtures/digest-vectors/`
- multica：`governance/{crsync,approval,approval_crosscheck,audit,toolcalls,reconcile,reconcile_live,daemon_workspace,transitions}_test.go`、`pkg/gitguard/{gitguard,spool}_test.go`、`internal/daemon/crevents_test.go`（+3 快照用例）、`internal/handler/daemon_toolcalls_test.go`

## 5. 未覆盖风险与不适用说明

1. **AC-5 组合面观察项**：未真派 Claude agent 任务（费用/时长）；三层拦截各自经真实组件验证（shim 网关=同一二进制、hook=同一脚本、铸造逻辑有 T09 单测），"一个真任务内三层齐动"留待首次生产任务派发时观察确认。
2. **server 模式对账不自举空投影**：设计约束（服务端不猜 workspace 绑定），新环境部署顺序为先起 daemon 通道建立首行、再依赖 server 对账接管——已写入 CUSTOM.md 部署口径。
3. **已知测试失败基线**（上游既有、A/B 逐条核实非本 fork 引入）：pkg/agent 3 + cmd/multica 7 + internal/cli 4 + internal/daemon 26（Windows 环境假设）+ gofmt CRLF 假差异，详见 CUSTOM.md 基线表；数量或名单变化才需排查。
4. **PAT 范围核验受限**：两仓均 public，"仅单仓"无法从 API 外部证实（对 public 仓该只读 token 增量风险为零）；仓库转 private 时需重新核验。

## 6. 下一步建议

进入 `review-code`（评审输入：本报告 + CUSTOM.md 台账 #3-#11 + 三仓提交序列），评审通过后走 code 阶段人工审批 → merge → writeback。评审重点建议：① daemon_workspace.go 的 PAT 绑定信任边界；② audit/snapshot 无账本事件的重复容忍语义；③ 上游 mdt_ 流程接线后 PAT 回退路径的退役计划。
