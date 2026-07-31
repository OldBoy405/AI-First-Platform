---
id: CR-2026-003-test-report
type: TEST_REPORT
cr-ref: CR-2026-003
tester: Ray
tester-assigned-at: "2026-07-31T20:20:07+08:00"
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
      generated-at: "2026-07-31T21:27:16+08:00"
      result: pass
      blocker-count: 0
      repair-target: implement-code
created: "2026-07-31T21:27:16+08:00"
updated: "2026-07-31T21:27:16+08:00"
---

# CR-2026-003 测试报告（P1 治理核心修补）

## 1. 测试摘要

3/3 任务（12h）完成并留验证证据。两仓自动化测试全绿（tools JS 21/21、multica governance 真库 33 项 PASS + daemon 快照 4 项），核心验收 AC-3 以真实生产脏数据完成：**卡死 12 小时（CR-2026-001）与 1 小时（CR-2026-002）的两条投影行，在修复部署后第一个 server 对账周期（13:19:14 UTC）自然收敛为 `archived/false`，全程数据库只发 SELECT**。开发期另抓到并修复 1 个 SDD 未预见的新缺陷（占位符冒号 vs Windows 文件名）。**结论：pass。**

## 2. 验证命令与结果

| 命令 | 执行目录 | 结果 | 说明 |
|---|---|---|---|
| `node --test test/crctl.test.mjs` | tools/skills/shared/crctl/scripts | ✅ 21/21 | 新增双 embedded 占位符用例；旧 `--no-commit` 契约测试更新到新口径（空串 → `pending:` 前缀）；文件名无冒号断言 |
| `go test ./internal/governance/`（真库 -v） | multica worktree server/ | ✅ 33 PASS / 0 FAIL | 新增 4：占位符不漏投影指针 + 真实 sha 去重不变（NFR-1）、ParseHistory 四态（LF/CRLF/空/坏 YAML 硬失败）、mergeAuthority 覆盖序、AC-2 卡死形态自愈 |
| `go test ./internal/daemon/ -run "TestCREvent\|TestSnapshot\|..."` | 同上 | ✅ | 快照带 history 字段 + 既有采集回归 |
| `go vet` / `go build ./...` | 同上 | ✅ | gofmt 全目录报警为 autocrlf 检出假差异（CUSTOM.md 基线），diff 核实仅 4 文件 +90/-5 真实改动 |
| AC-3 真机收敛（人工驱动，只 SELECT） | 本机全栈 | ✅ | 证据链见 `tasks/TASK-03.md` 完成记录（前置留档 21:17 → 部署 21:19 → 首周期治愈 13:19:14 UTC） |

真库口径同 CR-2026-002：`DATABASE_URL` 显式取容器真密码走 5433 转发，全部以 `-v` 下 `--- PASS` 确认。

## 3. TASK 验收覆盖矩阵

| TASK | 内容 | 验收证据 |
|---|---|---|
| T01 | crctl `pendingCommitSha()` 占位符 | JS 21/21（占位符互异 + 非 embedded 真实 sha 不变 + 文件名消毒）；tools@0c8e306 |
| T02 | `projectableSha` 防护 + `_history.yml` 快照扩展 | Go 真库 33 PASS（含 AC-1 服务端半边、AC-2 自愈）；multica@6bad142ec |
| T03 | 端到端验收 + 历史收敛 | AC-3 真机时间线证据（TASK-03 完成记录）；审计口径全程只 SELECT |

## 4. 新增/修改测试文件

- tools：`crctl.test.mjs`（+1 新用例，1 契约测试更新）
- multica：`governance/reconcile_test.go`（+4）、`internal/daemon/crevents_test.go`（+1）

## 5. 未覆盖风险与不适用说明

1. **AC-1 真机组合观察点（计划内后移，验证时点已排定）**：「双 embedded 连推投影两步跟上」的真机观察安排在本 CR 自己的 writeback 期（`writing-back → archived` 两连推——正是 CR-2026-002 当初丢事件的原故障序列），届时在归档记录补录。组件级两侧（JS 占位符生成、Go 幂等与防泄漏）均已真测。
2. **`_history.yml` 读取体量**：当前全量解析（2 条记录），量级增长到数千条再做分片/旁路缓存（SDD §7 已记录，评审建议 #2 的结论）。
3. **缺陷 B（commit-scan 对 archive 提交不解析 from/to）本 CR 明确不修**：FR-2 兜底收敛后该支路失败不再影响终态（SDD §5 范围决策）；本次真机收敛即为佐证——两条 CR 都未经该支路而达到正确终态。
4. 上游测试失败基线沿用 CUSTOM.md 台账（本 CR 未触碰相关包，名单无变化）。

## 6. 下一步建议

进入 `review-code`（评审输入：本报告 + 两仓 diff——tools 1 commit、multica worktree 1 commit）。评审重点建议：① `projectableSha` 是否覆盖了全部投影指针写入点（评审时可 grep `projected_commit` 全量核对）；② `mergeAuthority` 的 backlog 优先语义与 `cr-archive` 原子性假设；③ 旧 daemon 兼容路径（无 history 字段）的行为等价性。
