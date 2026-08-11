---
cr: CR-2026-030
status: block
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-11T11:01:08+08:00"
commands:
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-01.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-02.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-03.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-04.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-05.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node -e \"const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));\"", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-06.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server\" && go vet ./internal/governance/", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-07.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server\" && set \"CRCTL_PATH=C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030/skills/shared/crctl/scripts/crctl.mjs\" && go test ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl -count=1 -json | node -e \"let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{process.stdout.write(s);const ok=s.split(/\r?\n/).some(l=>{try{const x=JSON.parse(l);return x.Action==='pass'&&x.Test==='TestGrantCrossVerifiesWithCrctl'}catch{return false}});process.exit(ok?0:1)})\"", exit: 1, log: "change-requests/CR-2026-030/test-evidence/cmd-08.log" }
---

# 测试报告 · CR-2026-030

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-030/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node --test skills/shared/crctl/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-01.log |
| 2 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | 0 | change-requests/CR-2026-030/test-evidence/cmd-02.log |
| 3 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node skills/shared/crctl/scripts/check-skill-matrix.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-03.log |
| 4 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node skills/shared/crctl/scripts/check-agents-contract.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-04.log |
| 5 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node --test skills/writeback/scripts/test/*.test.mjs` | 0 | change-requests/CR-2026-030/test-evidence/cmd-05.log |
| 6 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030" && node -e "const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));"` | 0 | change-requests/CR-2026-030/test-evidence/cmd-06.log |
| 7 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server" && go vet ./internal/governance/` | 0 | change-requests/CR-2026-030/test-evidence/cmd-07.log |
| 8 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server" && set "CRCTL_PATH=C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030/skills/shared/crctl/scripts/crctl.mjs" && go test ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl -count=1 -json | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{process.stdout.write(s);const ok=s.split(/\r?\n/).some(l=>{try{const x=JSON.parse(l);return x.Action==='pass'&&x.Test==='TestGrantCrossVerifiesWithCrctl'}catch{return false}});process.exit(ok?0:1)})"` | 1 | change-requests/CR-2026-030/test-evidence/cmd-08.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

## Code review round 1 回修结果

- tools@157236c：修复 `owner-history: []` 被插到 frontmatter 首行的数据损坏；R7 按 YAML 直接父子层级定位权威 transitions；EMIT_FAILED audit 增加 `cr`/`event_kind`。对应新增 2 项 Node 回归测试，当前 **225/225** 全绿。
- multica@8685198a8：恢复 FR-10.1 精确白名单；Go error 全检查；Tools Root 从最终解析的 crctl 路径派生；四 stage 表驱动 approve/reject + 邻接重放共 8 个 subtest。最终相对 `c8c96e5` 净 diff 恰为 `approval_crosscheck_test.go` + `CUSTOM.md`。
- 四 stage seam 逻辑曾在临时、未提交的 TestMain 定向 bypass 下真实执行，8/8 subtest 通过；该 bypass 已恢复，最终 branch 未修改 `crsync_test.go`。

## 当前唯一阻断（环境）

- cmd-08 显式要求 JSON 事件中出现 `TestGrantCrossVerifiesWithCrctl` 的 PASS；本机无 Docker/PostgreSQL，包级既有 TestMain 在测试函数执行前整体 skip，因此命令按设计退出 1，报告保持 `status: block`，避免 `go test ok` 假绿。
- 解除方式：在可用 PostgreSQL 且 migration 158 已应用的环境重跑 cmd-08；确认 8 个 subtest 均 PASS 后再由 `crctl test` 生成 pass 报告并进入第 2 轮代码评审。
