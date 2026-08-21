---
cr: CR-2026-050
status: pass
tester: Ray
generated-by: crctl-test
generated-at: "2026-08-21T13:02:48+08:00"
command-digest: 7eaf99eb51ef5c6c0d3de2fa5b6cd0e79d1a028152068ca05bd2fdb89eb39c53
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
    cwd: server
    executable: go
    args: [test, ./internal/governance/, "-count=1"]
    timeout-seconds: 600
    exit-code: 0
    signal: null
    timed-out: false
    started: true
    log: change-requests/CR-2026-050/test-evidence/cmd-04.log
---

# 测试报告 · CR-2026-050

<!-- crctl:analysis-below -->

## 测试摘要

CR-2026-050（Pipeline 流程优化 — 职责边界与契约漂移修复）为纯文本/契约变更，14 个 TASK 全部完成并标记 done。验证面 = 8 条 pipeline JSON 可解析性 + 确定性断言（pipeline-structure.test.mjs，23 条）+ lint 漂移检查（lint-prompts enforce）+ multica governance 包测试（再生后 digest 一致性）。

## 验证命令与结果解读

| # | 命令 | 结果 | 对应 TASK |
|---|---|---|---|
| cmd-01 | `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` | exit 0（23/23 pass） | TASK-01/02/07/09/10/14 新增断言 + 既有断言全部通过 |
| cmd-02 | `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` | exit 0（0 findings） | 全部 TASK：收敛后无 R1 触发（deny 路径字面量零残留） |
| cmd-03 | 8 条 pipeline JSON.parse | exit 0（json ok: 8） | 全部 TASK：节点数不变（7/5/5/8/5/16/5/3 逐仓核对） |
| cmd-04 | `cd server && go test ./internal/governance/ -count=1` | exit 0（ok） | TASK-07：gate_nodes_gen.go 再生后 governance 测试通过，digest fail-closed 不误报 |

## TASK 验收覆盖矩阵

| TASK | 验收覆盖 | 证据 |
|---|---|---|
| TASK-01 | FR-01 三条 human approval 收敛 | FR-01 测试（无 review-annotations/reject_reason + …0010 保留 checkpoint 前提） |
| TASK-02 | FR-05 四个 approve 节点 + SKILL --approver | FR-05 测试（无命令细节/owners 拼接/写死下一 pipeline）；4 SKILL 命令 diff |
| TASK-03 | FR-02 product-planning 输入契约 | AC-02 grep 核对（topic/skip 分支/顺序调用链/无跨文档写入） |
| TASK-04 | FR-03 market-to-plan + extract-market-insight 简报模式 | AC-03 grep 核对（mode=brief/raw_insight_path/context+intent）；SKILL 参数表 diff |
| TASK-05 | FR-04 competitive-radar 闭环 | AC-04 grep 核对（reportDraft/confirmed=false→true 顺序）；SKILL reportDraft 契约 diff |
| TASK-06 | 阶段一 gate（AC-01~05） | 三命令全绿 + checkpoint `9d989acb`（phase=complete、三仓 confirmed）早于 TASK-07 首个实现 commit |
| TASK-07 | architecture 收敛 + multica 再生 + CUSTOM.md | :149 断言修订后 18/18；`generate-gate-nodes.mjs --tools --check` exit 0；go test governance ok；Source SHA 与 tools HEAD 一致 |
| TASK-08 | write/review-tech-design SKILL 收窄 | SKILL diff（FR-07.1/07.2 路径与提交口径、FR-08.1~3、FR-08.4 四维度、前缀 [cr]）；无 feat( 残留 |
| TASK-09 | requirement-authoring 收敛 + FR-12.2 断言 | FR-12.2 测试（7 节点序/owners/auto_push 分支/reviewLoop 字段集） |
| TASK-10 | code-implementation 收敛 + FR-12.3 断言 | FR-12.3/12.3b 测试（16 节点序/replayNodes 5 项/保留字面量/负向断言） |
| TASK-11 | resume-cr + cr-show | node-3 收敛为 cr-show(section=all)；SKILL Step 3.5 输出契约含最近三次 checkpoint |
| TASK-12 | feature-writeback node-1 预检删除 | node-1 prompt 无 code-approved 字面量、保留 merge Skill 调用与失败中止 |
| TASK-13 | 规划类 FR-09 下沉 + write-roadmap 前缀 | market-to-plan node-1 无章节/路径/索引；write-roadmap 前缀 [cr] |
| TASK-14 | FR-13 全量自检 + DD-7 扫描 | DD-7 测试（全 SKILL Commit 前缀命中白名单，CRLF 归一 + 硬失败）；发布前 checklist 5 项全绿 |

## 新增/修改测试文件

- `tools/skills/shared/crctl/scripts/test/pipeline-structure.test.mjs`：新增 FR-01 / FR-05 / FR-12.2 / FR-06.1+07.4+07.5 / FR-12.3 / FR-12.3b / DD-7 七个测试（23 条）；修订 `:149`（CR-2026-044 FR-07 溯源注释保留）

## 未覆盖风险

1. **multica 全量测试未跑**：本 CR 只改生成产物（gate_nodes_gen.go），`go test ./internal/governance/` 定向覆盖已够；前端/其它包不受影响（tools 侧零代码运行路径）。
2. **approve-* SKILL `--approver` 双路径仅文本核对**：grant/TTY 两条命令均已在 SKILL 文本补 `--approver {cr.md owners.{角色}.id}`，真实审批流验证需在下一 CR 的人工审批环节观察 approval.yml 落 owner 而非 identity(ws)（SDD §3.4 AC-05 改判口径）。
3. **cr-show 最近三次 checkpoint 展示未端到端验证**：输出契约已写入 Step 3.5，实际展示依赖 `checkpoints.yml`/`_backlog.yml#checkpoints` 数据形态，跨 CR 使用时观察。
4. **SKILL 自检清单（FR-13.5）人工项**：validate-doc 等价校验、受控 shell 走闸等为既有工具能力，本 CR 不引入新调用面，仅确认无回归（lint enforce 0 findings）。

## 下一步建议

- 以 `crctl next CR-2026-050` 为准进入代码评审（review-code）；评审重点：§3.4 的 approver 改判口径、DD-4 断言处置清单逐条核对。
