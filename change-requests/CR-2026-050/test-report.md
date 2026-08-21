---
cr: CR-2026-050
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-21T13:49:02+08:00"
command-digest: 362dfd0aefdb081481254ab98d97999a03c896459a73e7bd63aa1f6d9eba7fee
commands:
  - repo: tools
    cwd: .
    executable: node
    args: [--test, skills/shared/crctl/scripts/test/pipeline-structure.test.mjs]
    timeout-seconds: 300
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-050/test-evidence/cmd-01.log
  - repo: tools
    cwd: .
    executable: node
    args: [skills/shared/crctl/scripts/lint-prompts.mjs, --mode, enforce]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-050/test-evidence/cmd-02.log
  - repo: tools
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs');const files=fs.readdirSync('pipeline-templates').filter(f=>f.endsWith('.json'));for(const f of files)JSON.parse(fs.readFileSync('pipeline-templates/'+f,'utf8').replace(/\r\n/g,'\n'));console.log('json ok:',files.length)"]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-050/test-evidence/cmd-03.log
  - repo: multica
    cwd: .
    executable: node
    args: [server/internal/governance/gen/generate-gate-nodes.mjs, --tools, "C:/Users/GOBAO/Downloads/AI/AI First Platform/.rayai-worktrees/tools/requirement/CR-2026-050", --check]
    timeout-seconds: 120
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-050/test-evidence/cmd-04.log
  - repo: multica
    cwd: .
    executable: node
    args: [-e, "const fs=require('fs');const t=fs.readFileSync('server/internal/governance/gate_nodes_gen.go','utf8').replace(/\r\n/g,'\n');const sha='14b4458fdd444916e634cbf21ea1312274d3ba57';if(!t.includes('// Source: tools@'+sha+' '))throw new Error('Source SHA mismatch');console.log('source sha ok:',sha)"]
    timeout-seconds: 60
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-050/test-evidence/cmd-05.log
  - repo: multica
    cwd: server
    executable: go
    args: [test, ./internal/governance/, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-050/test-evidence/cmd-06.log
---

# 测试报告 · CR-2026-050

<!-- crctl:analysis-below -->

## 测试摘要（code-review attempt 1 回修后）

CR-2026-050 为文本契约与生成产物变更。首次代码评审发现职责收敛假阴性、规划输入闭环、cr-show 数据源及 registry 证据缺口；本轮修复后由 `crctl test` attempt 2 重建全部机器证据，状态为 `pass`。

## 机器命令与结果

| # | 命令 | 结果 | 覆盖 |
|---|---|---|---|
| cmd-01 | `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | exit 0，30/30 pass | 节点/UUID/reviewLoop；FR-01/05/06/07/10/11/12；AC-02～04；approve 双路径；DD-7 正反例 |
| cmd-02 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | exit 0，0 findings | prompt 与 crctl/保护面漂移 |
| cmd-03 | 8 条 pipeline JSON.parse | exit 0，`json ok: 8` | 全部 JSON 语法 |
| cmd-04 | `generate-gate-nodes.mjs --tools <CR tools worktree> --check` | exit 0，consistency OK | architecture registry 与 tools prompt 同步 |
| cmd-05 | 生成产物 Source SHA 精确断言 | exit 0，`tools@14b4458…` | Source 指向本轮 tools 修复提交 |
| cmd-06 | `go test ./internal/governance/ -count=1` | exit 0 | multica governance registry/digest 消费 |

## BLOCK 回修覆盖

1. **BLK-C1 职责收敛**：architecture/requirement/code 节点删除 `crctl advance`、`task init`、`crctl test`、marker、runner/fallback、具体落盘/回修重建算法；保留 authority path、route 与 reviewLoop 机器字段。cmd-01 的 AC-06/07/11/12 禁项测试对这些原文直接负向断言。
2. **BLK-C2 规划闭环**：product-planning 明确全量竞品 + 30 天默认窗口并传 reviewer；`fetch-competitor-updates` 增 `competitor-slug` 唯一精确解析；competitive-radar node-2 结构化输出 reportDraft + product-snapshot，node-5 先正式报告后规划条目。cmd-01 AC-02～04 覆盖。
3. **BLK-C3 事实源**：cr-show 改从持久化 checkpoint metadata commit 历史读取最近三次，并以 `_backlog.yml#latest-checkpoint` 补最新详情；feature-writeback node-1 删除 code-approved 前提文本。cmd-01 AC-10/11 覆盖。
4. **BLK-C4 测试假阴性**：由 23 条增至 30 条；新增 P0 正向结构断言、职责禁项、approve grant/TTY 角色 owner、8 pipeline 节点数/UUID、cr-show 事实源；DD-7 增故意 `feat(`/`[planning]` 反例。
5. **BLK-C5 registry 证据**：cmd-04/05 新增可审计日志，cmd-06 保留 governance 定向测试；test-report 与 traceability 使用新 command digest `362dfd0a…`。

## TASK/FR 结论

- 14/14 TASK 仍为 done；阶段一 checkpoint `9d989acb29e9125a`（三仓 confirmed）早于 TASK-07 首个实现提交，AC-14 时序不受回修影响。
- 8 条 Pipeline 节点数保持 `8/7/5/16/5/3/5/5`，UUID 全局唯一；reviewLoop/replayNodes/passCondition/onFail/timeout 未改。
- 四个 approve Pipeline 节点仍按已审批 SDD §3.4 只传 `cr_id`；四个 approve Skill 的 grant 与 TTY 命令均显式传对应角色 owner 的 `--approver`。PRD FR-05.2/AC-05 的 revision 留待 writeback，或以最终代码评审记录确认该已审批偏离。

## 未覆盖风险

1. 未跑 multica 全仓测试；本 CR 只改 governance 生成产物，cmd-06 定向覆盖相关包。
2. approve-* 未执行真实 grant/TTY 审批（本轮不是审批阶段）；cmd-01 已确定性检查两条命令及角色 owner，最终 PowerShell code approval 将验证 TTY 实路径。
3. cr-show 最近三次 checkpoint 尚未通过一次真实 UI/resume 展示验收；契约已改用远端可持久复现的 metadata commit，不再依赖不存在的数据结构。
4. product-planning 跨域 can-call 偏差为 SDD §3.3 明确的既有偏差，本 CR 不扩 matrix；应另开 CR。

## 下一步

以 `crctl next CR-2026-050` 为准：完成回修 checkpoint 后重新执行 `review-code`。
