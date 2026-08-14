---
cr: CR-2026-037
status: pass
tester: "Ray"
generated-by: crctl-test
generated-at: "2026-08-13T11:16:29+08:00"
commands:
  - { command: "node --check skills/shared/crctl/scripts/crctl.mjs && node --test skills/shared/crctl/scripts/test/crctl.test.mjs", exit: 0, log: "change-requests/CR-2026-037/test-evidence/cmd-01.log" }
  - { command: "node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce && node --test skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs skills/shared/crctl/scripts/test/check-agents-contract.test.mjs", exit: 0, log: "change-requests/CR-2026-037/test-evidence/cmd-02.log" }
  - { command: "node -e \"const fs=require('fs'),cp=require('child_process');const expected=['pipeline-templates/code-implementation.pipeline.json','skills/develop/write-dev-tasks/SKILL.md','skills/shared/crctl/SKILL.md','skills/shared/crctl/gates.json','skills/shared/crctl/scripts/crctl.mjs','skills/shared/crctl/scripts/test/crctl.test.mjs'];const changed=cp.execFileSync('git',['diff','--name-only','8a2e6a1...HEAD'],{encoding:'utf8'}).trim().split(/\r?\n/).filter(Boolean);if(JSON.stringify(changed)!==JSON.stringify(expected))throw Error(JSON.stringify(changed));const p=JSON.parse(fs.readFileSync('pipeline-templates/code-implementation.pipeline.json'));if(p.nodes.length!==14)throw Error('pipeline node drift');console.log(JSON.stringify({changedFiles:changed.length,pipelineNodes:p.nodes.length}))\"", exit: 0, log: "change-requests/CR-2026-037/test-evidence/cmd-03.log" }
---

# 测试报告 · CR-2026-037

> status 与 commands 段由 crctl test 依据真实退出码生成，模型不得改写。
> 原始输出见 change-requests/CR-2026-037/test-evidence/。

## 命令与结果

| # | 命令 | 退出码 | 日志 |
|---|------|--------|------|
| 1 | `node --check skills/shared/crctl/scripts/crctl.mjs && node --test skills/shared/crctl/scripts/test/crctl.test.mjs` | 0 | change-requests/CR-2026-037/test-evidence/cmd-01.log |
| 2 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce && node --test skills/shared/crctl/scripts/test/check-skill-matrix.test.mjs skills/shared/crctl/scripts/test/check-agents-contract.test.mjs` | 0 | change-requests/CR-2026-037/test-evidence/cmd-02.log |
| 3 | `node -e "const fs=require('fs'),cp=require('child_process');const expected=['pipeline-templates/code-implementation.pipeline.json','skills/develop/write-dev-tasks/SKILL.md','skills/shared/crctl/SKILL.md','skills/shared/crctl/gates.json','skills/shared/crctl/scripts/crctl.mjs','skills/shared/crctl/scripts/test/crctl.test.mjs'];const changed=cp.execFileSync('git',['diff','--name-only','8a2e6a1...HEAD'],{encoding:'utf8'}).trim().split(/\r?\n/).filter(Boolean);if(JSON.stringify(changed)!==JSON.stringify(expected))throw Error(JSON.stringify(changed));const p=JSON.parse(fs.readFileSync('pipeline-templates/code-implementation.pipeline.json'));if(p.nodes.length!==14)throw Error('pipeline node drift');console.log(JSON.stringify({changedFiles:changed.length,pipelineNodes:p.nodes.length}))"` | 0 | change-requests/CR-2026-037/test-evidence/cmd-03.log |

## 分析（由测试负责人 / 模型补充）

<!-- crctl:analysis-below 此标记以下允许人工/模型补充 TASK 覆盖、未覆盖风险等分析内容 -->

- AC-01～AC-07：`crctl.test.mjs` 的 CR-2026-037 黑盒组覆盖 canonical create、工时、CRLF、no-op、pending refresh、坏卡、悬空/成环、进度保护、状态、TASK freshness 与索引 CAS；完整 suite 169/169 通过。
- AC-08～AC-09：缺索引的 gate/advance/next 与 Skill/Pipeline 采纳均有测试；Pipeline 保持 14 个节点，JSON 可解析。
- AC-10～AC-11：Prompt lint 0 findings，Skill/Agent contract 9/9；相对权威 tools 基线 `8a2e6a1` 精确六个白名单文件。Multica 相对 `main` 零提交差异且 worktree clean。
- AC-12：保留为合入 tools `custom/main` 后的发布验收。届时只能从 `workspace.tools_package_path` 解析出的权威 Tools Root 对 CR-2026-032 执行正式 `task init`；本次未使用候选 worktree提前治理该 CR。
