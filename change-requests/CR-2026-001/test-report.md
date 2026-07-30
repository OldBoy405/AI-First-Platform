---
id: CR-2026-001-test-report
type: TEST_REPORT
cr-ref: CR-2026-001
tester: Ray
tester-assigned-at: "2026-07-30T21:22:32+08:00"
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
      generated-at: "2026-07-31T01:12:32+08:00"
      result: pass
      blocker-count: 0
      repair-target: implement-code
created: "2026-07-31T01:12:32+08:00"
updated: "2026-07-31T01:12:32+08:00"
---

# CR-2026-001 测试报告 — M0 地基

## 1. 测试摘要

M0 四条验收标准（PRD v0.1.2）全部通过，其中 AC-1 第 3 项为机制级验证（字面场景留待首次实际使用补验，见 §5）。5 个 TASK 全部完成并各自留有完成记录。判定依据全部为实际执行的命令输出与活体 HTTP 探测，无"看起来正常"类结论。

## 2. 验证命令与结果

| 命令 | 执行目录 | 结果 | 说明 |
|---|---|---|---|
| `go build ./cmd/server/` + `go vet ./cmd/server/` | multica worktree `server/` | pass | TASK-01 router.go 摘挂载后编译干净 |
| `go build ./pkg/agent/ ./cmd/multica/` + `go vet ./pkg/agent/` | 同上 | pass | claude.go 环境过滤补丁 |
| `go test ./pkg/agent/ -run "Claude"` | 同上 | pass | 补丁相关测试无回归 |
| `go test ./pkg/agent/`（全量） | 同上 | 3 failures（已知基线） | Traecli/Qoder 3 个测试经 `git stash` 对照确认为上游既有失败，与本 CR 全部改动无关；已记入 fork `CUSTOM.md`"已知测试失败基线"，不阻塞 |
| `node check-skill-matrix.mjs` + `node check-agents-contract.mjs` | tools 仓库 | pass | 59 skill / 9 agent 一致性；每次 commit 由 pre-commit 钩子强制执行 |
| `make selfhost-build COMPOSE=docker-compose.exe` | multica worktree | pass | 三容器（postgres/backend/frontend）从含改动的源码构建并启动 |
| `node aifirst/agent-import.mjs ...`（三次运行） | multica worktree | pass | 首跑 7 建 2 败（暴露已知不一致）→ 修复后 2 建 7 跳 → 三跑 0 建 9 跳 0 败（幂等），退出码 0 |

## 3. AC 验收覆盖矩阵

| AC | 验证方式与证据 | 结果 |
|---|---|---|
| AC-1 全栈起来 | `make selfhost-build` 单命令起三容器；`GET /health` 200、前端 `:3000` 200 | ✅ |
| AC-1 计费剥离 | 活体探测：`POST /api/webhooks/stripe` 404、`GET /api/cloud-billing/balance` 404；附加 `mcn_` 假令牌 401 `invalid token` | ✅ |
| AC-1 workspace 管控 | `.env` 置 `DISABLE_WORKSPACE_CREATION=true` 重建容器后 `/api/config` 报 `workspace_creation_disabled: true`，验后恢复引导态 | ✅（机制级，见 §5-1） |
| AC-2 9 Agent 注册 | `GET /api/agents` 返回 9 个，与 `agents/_index.yml` active 清单一一对应；引用 Skill active 由 check-agents-contract.mjs 持续覆盖 | ✅ |
| AC-3 派单闭环 | TES-4：建 Issue → 1s 内 daemon 领取（WS 唤醒）→ claude 执行 56s → task `completed`、Issue `in_review`、标记 `SMOKE-CR-2026-001-OK` 命中评论（v0.1.2 口径）；TES-5 复验根修后链路依旧通 | ✅ |
| AC-4 一致性 CI | 注入假 Skill 引用 → 校验 exit 1 且报错精确到 agent/skill 名 → 恢复后通过；CI workflow + pre-commit 双通道接入，提交时实际触发 | ✅ |

## 4. TASK 验收覆盖

5/5 done：TASK-01（起服务+剥离）、TASK-02（契约查证 6 结论）、TASK-03（适配器 9/9 幂等）、TASK-04（冒烟 TES-4/TES-5）、TASK-05（agents.contract 校验器）。逐项验收明细见各 `tasks/TASK-0N.md` 的"完成记录"。

## 5. 未覆盖风险与不适用说明

1. **AC-1③ 字面场景未跑**："注册第二个 workspace 被拒"需先有真实账号与第一个 workspace 的生产使用；机制级验证已过（配置→`/api/config` 传导），字面补验留待首次实际锁定部署时执行。
2. **上游既有测试失败 ×3**：见 §2；根因未诊断（疑测试对本机环境有隐含假设），已建基线台账，不属于本 CR 修复范围。
3. **M0 的 Agent 执行无 gitguard 约束**：SDD §7 明示的诚实边界——本阶段 Agent 理论上可执行任意 shell，controlled-shell 下沉是 P1-F5 范围。M0 验收通过 ≠ Agent 执行安全。
4. **59 个 Skill 未导入 Multica**：TASK-02 结论⑥的显式范围排除，属后续安装器工作。

## 6. 下一步建议

进入 `review-code`（评审对象：multica worktree 5 个 `[cr]` commit + tools 仓库 3 个 commit），通过后 `crctl approve --stage code` 人工审批，再走 `/writeback` 归档。后续 CR 建议：① 上游回馈 PR（claude.go 过滤名单）；② Traecli/Qoder 测试失败根因诊断；③ P1 治理核心立项。
