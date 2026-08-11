---
cr: CR-2026-030
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-11T12:50:48+08:00"
commands:
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node --test skills/shared/crctl/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-01.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-02.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/check-skill-matrix.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-03.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node skills/shared/crctl/scripts/check-agents-contract.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-04.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node --test skills/writeback/scripts/test/*.test.mjs", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-05.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030\" && node -e \"const fs=require('fs'); for (const f of fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'))) JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8'));\"", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-06.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server\" && go vet ./internal/governance/", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-07.log" }
  - { command: "cd /d \"C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server\" && set \"CRCTL_PATH=C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030/skills/shared/crctl/scripts/crctl.mjs\" && go test ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl -count=1 -json | node -e \"let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{process.stdout.write(s);const ok=s.split(/\r?\n/).some(l=>{try{const x=JSON.parse(l);return x.Action==='pass'&&x.Test==='TestGrantCrossVerifiesWithCrctl'}catch{return false}});process.exit(ok?0:1)})\"", exit: 0, log: "change-requests/CR-2026-030/test-evidence/cmd-08.log" }
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
| 8 | `cd /d "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/multica/requirement/CR-2026-030/server" && set "CRCTL_PATH=C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-030/skills/shared/crctl/scripts/crctl.mjs" && go test ./internal/governance/ -run TestGrantCrossVerifiesWithCrctl -count=1 -json | node -e "let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{process.stdout.write(s);const ok=s.split(/\r?\n/).some(l=>{try{const x=JSON.parse(l);return x.Action==='pass'&&x.Test==='TestGrantCrossVerifiesWithCrctl'}catch{return false}});process.exit(ok?0:1)})"` | 0 | change-requests/CR-2026-030/test-evidence/cmd-08.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->
