---
id: CR-2026-060-TASK-02
type: TASK
cr-ref: CR-2026-060
plan-ref: "change-requests/CR-2026-060/plan.md"
sdd-ref: "change-requests/CR-2026-060/sdd.md"
target-version: "0.33"
title: G2 PRD/SDD writer-reviewer 与四个 approve 合同
slug: prd-sdd-writer-reviewer-approve
status: pending
estimate: 8h
depends-on: ["CR-2026-060-TASK-01"]
created: 2026-09-03T00:35:00+08:00
---

## 任务描述

按 SDD §3.2 修订 PRD/SDD 作者与 reviewer 的 SKILL 合同，以及四个 `approve-*` 的统一调用面。不改 crctl 算法（pre-review / advance guard 已由 TASK-01 落地，本 TASK 只声明调用顺序与消费字段）。不扩大 PRD 已批准的七维标准。

输入条件：TASK-01 已合入（register JSON 键名与 `crctl gate --mode pre-review` CLI 可用）；CR status=`developing`；tools HEAD 含 TASK-01 commit。

## 涉及文件 / 模块

- `skills/requirement/write-requirement-prd/SKILL.md`：title/summary/source/target-version/owner 只从 cr.md 读；Pipeline 重复字段不得覆盖；source 路径 containment/existence 在 writer 阶段校验；七类章节 + 成功指标 + 范围排除
- `skills/requirement/review-requirement/SKILL.md`：Step 1 与 Step 2 之间固定顺序：先 `crctl gate <cr> --for requirement-reviewing --mode pre-review`；guard pass 才写临时 payload → `crctl review-record`；record=pass 才 `crctl advance`；guard block（含 new mode `unassigned`）→ route=`version-set`，不记录评审、不改状态。声明公开 CLI 直连 advance 亦被 TASK-01 的 advance 层 guard 拦截（Skill 不复制该算法）
- `skills/develop/write-tech-design/SKILL.md`、`skills/develop/review-tech-design/SKILL.md`：writer 参数表 required=`cr_id,operational_workspace,resources`；七维作者/reviewer 标准成对表述；`SDD-CLOSE-*` 逐项关闭义务
- `skills/requirement/approve-requirement/SKILL.md`、`skills/develop/approve-tech-design/SKILL.md`、`skills/develop/approve-dev-start/SKILL.md`、`skills/develop/approve-code/SKILL.md`：required=`cr_id`；缺 approver 取对应 owner；只消费/返回 `crctl approve` 结构化结果；下一步统一「以 `crctl next {cr_id}` 为准」
- 测试：不新增独立测试框架；cmd-01 的 `lint-prompts.test.mjs` / `contract-scan.test.mjs` 覆盖「下一步」收敛与禁止字段。若需对称性夹具，落在既有 test 文件内以文本断言 SKILL 成对关键词，禁止新建测试 runner。

禁止改动：`crctl.mjs` 的 approve/review-record/TTY/grant 算法（zero_diff）；`gates.json`；评审 payload schema。

## 实现要点

1. write-requirement-prd：权威字段只读 cr.md；source 校验失败零写入 PRD；七类章节清单与 PRD AC-04 字面一致。
2. review-requirement：pre-review 是 Step 1/2 之间的固定步骤，不是可跳过提示；guard block 不写 `.crctl/tmp/review-requirement.yml`、不调用 `review-record`、不 `advance`。
3. write/review-tech-design：七维标准与 requirement 侧成对；HTTP 条件基线沿用「本 CR 不新增 HTTP API / 评审矩阵标 N/A」的现状表述，不发明新基线。
4. 四个 approve-*：参数表 required 仅 `cr_id`；禁止 Agent 代签措辞；禁止手写「下一步 = 某 Skill 名」映射（R9）。
5. 不把 Pipeline prompt 收敛放到本 TASK（TASK-04 / FR-05）。

## 验收条件

1. write-requirement-prd 正文明确 cr.md 为 title/summary/source/target-version/owner 的唯一来源，且含七类章节清单（cmd-01 文本抽查 + 人工对照 AC-04）。
2. review-requirement 在 review-record 之前出现 `crctl gate ... --mode pre-review`；出现 guard block → route=`version-set` 的固定句式；不出现「先跑无 mode 的完整 gate」（cmd-01 / AC-03 Skill 面）。
3. write-tech-design 与 review-tech-design 对七维标准使用同一术语集合；`SDD-CLOSE-*` 关闭义务成对出现（cmd-01 / AC-05/AC-06）。
4. 四个 approve SKILL 的 required 均为 `cr_id`；下一步提示均可被 lint-prompts R9 接受（含 `crctl next`，不含 status→节点映射表）（cmd-01 / AC-18）。
5. 本 TASK diff 不触及 `crctl.mjs` 的 `cmdApprove`/`cmdReviewRecord` 与 `gates.json`。

## 完成标志

上述 SKILL.md 已落盘；cmd-01 对改动文件零 CONTRADICTS/STALE-REF；提交 `[cr] implement CR-2026-060 TASK-02`；`crctl task done CR-2026-060 --task CR-2026-060-TASK-02`。

## 接口契约

- 消费（来自 TASK-01，CLI 形态冻结，本 TASK 不复制算法）：
  - `crctl gate <cr> --for requirement-reviewing --mode pre-review` → `{ cr, for, mode:'pre-review', pass, checks }`；fail 外层 `GATE_BLOCKED`
  - `cmdRegister` JSON 键：`cr_id` / `target_spec_id` / `operational_workspace` / `tx_id` / `recover_command`（requirement-register 已在 TASK-01 消费；本 TASK 的 review-requirement 不解析这些键）
- 产出：无新函数。下游 TASK-03/TASK-04 不消费本 TASK 的代码符号；仅依赖本 TASK 落盘的 SKILL 合同文本在实施期保持稳定。
