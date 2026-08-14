---
id: CR-2026-022-sdd
type: SDD
cr-ref: CR-2026-022
title: 治理工具链 — tools 包 prompt 审查修复（97 条发现全量落地）技术设计
status: draft
created: "2026-08-06T07:35:00+08:00"
updated: "2026-08-06T08:05:00+08:00"
---

# SDD — tools 包 prompt 审查修复（批 1/2/2.5/3/3.5/4 + 收尾）

## 1. 架构概览

### 1.1 落点与模块边界

本 CR 全部落点在 tools 仓（本方法论包自身），改动按 ARCHITECTURE.md §4 分层自上而下分布：

```
Pipeline 层   pipeline-templates/{architecture-design, code-implementation,
              requirement-authoring, competitive-radar, market-to-plan,
              resume-cr, product-planning}.pipeline.json   ← UUID 迁移/节点 prompt 订正/onFail 策略
Skill 层      skills/{cr,develop,requirement,writeback,sync,planning,competitive,review,spec}/*
              + skills/_index.yml / agents/_index.yml      ← 批 1/2/3/4 文本修复与冗余收敛
工具层        skills/shared/crctl/scripts/crctl.mjs        ← 批 2.5 核心代码（FR-9~FR-13, FR-21）
              skills/shared/crctl/scripts/lint-prompts.mjs ← 批 3.5（FR-24~FR-25）
声明层        dir-graph.yaml（新增 1 条转移）+ gates.json（删 1 条死配置）
```

依赖方向不变（Pipeline → Skill → crctl 单向朝下）；本 CR 不新增模块、不新增顶层分组、不拆 `crctl.mjs`（§3 单文件哲学维持）。

### 1.2 关键流程（修复后）

- **注册链**：`requirement-register` → `crctl cr-init --title … --owner-requirement … [--summary --source --target-version]`（一次原子写齐，消灭违纪手写）→ `crctl git commit --template register --cr <cr-id>`（直传已知 CR 号，跳过反向解析）。
- **进度推送链**：pipeline push-progress 节点 → `push-progress` skill Step 3 逐仓 `git rev-parse HEAD` + `crctl checkpoint-add --repo <r> --sha <sha>`（任意非终态可落账）→ `onFail` 产出可见告警（不 skip 不 abort）。
- **审批驳回链**：`crctl approve --stage <s>` 审批人回答非 yes → decline 分支查状态机 `{stage}:reject -> {to}` 回退转换 → `cmdAdvance` 执行回退 + 输出重跑提示（需求阶段经 D-1 新增转换回 `drafting`）。
- **lint 防线**：pre-commit `lint-prompts enforce` 在原 R1~R5 基础上叠加 R6/R7；豁免注释仅对邻近行生效（radius 契约化）。

## 2. 数据模型

本 CR 不新增账本实体，只扩展既有字段写口与声明数据：

### 2.1 cr.md / _backlog.yml 字段写口扩展（FR-9）

`cr-init` 现硬编码三字段改为旗标可覆写，缺省值与旧值同义（向后兼容）：

| 字段 | 旗标 | 缺省 | 写入位置 |
|---|---|---|---|
| `summary` | `--summary <s>` | `""` | cr.md frontmatter（引号包裹，防 `:` 破坏 YAML） |
| `source` | `--source <s>` | `manual` | cr.md frontmatter + `_backlog` 条目 `source` |
| `target-version` | `--target-version <v>` | `tbd` | cr.md frontmatter + `_backlog` 条目 `target-version` |

三字段与既有 owners/时间戳同一次 `casWriteMulti` 事务写入（cr.md + `_backlog.yml` + `_index.yml` 三文件全有或全无），不引入"先建档再补字段"中间态。`BACKLOG_SET_FIELDS` 白名单**不扩**——这三字段属注册时一次性写入，不是后续可反复 set 的标量字段，语义不同。

### 2.2 状态机声明变更（FR-12 ①，D-1 决策落地）

`tools/dir-graph.yaml#change-request-track.state_machine.transitions` 新增**两条**转换（均已 grep 核实现状后定稿）：

```yaml
# ① D-1：需求阶段人工审批驳回回退（现状无任何驳回出口，唯一通道是 cr-review-record:reject 判死刑）
- { from: requirement-reviewing, to: drafting, trigger: "approve-requirement:reject -> write-requirement-prd" }
# ② B3 修复：开发启动审批驳回回退（现状 task-breakdown 只有自环与 -> developing，approve-dev-start 驳回无路可退）
- { from: task-breakdown, to: tech-design-reviewed, trigger: "approve-dev-start:reject -> write-dev-plan" }
```

命名与既有 `approve-tech-design:reject -> write-tech-design`、`approve-code:reject -> implement-code` 同构（`{approve-skill}:reject -> {回退目标 skill}`）。需求阶段 `review-requirement:block` 的语义是**保持 `drafting` 不推进**（现有 `drafting→drafting` 自环，:215），与 tech-design 的显式回退不同，无需新增转换。

**口径变更（§5 不变量 5 联动）**：转移声明 23 → **25** 条，wildcard 展开 45 → **47** 条（两条新转换均不含 wildcard）。所有引用该口径的文档/注释/测试断言同步更新：`tools/ARCHITECTURE.md §3`、主仓 AGENTS.md #2、`crctl.test.mjs` 中的口径断言（如有）。

### 2.3 gates.json 死配置删除（FR-13，D-2 决策落地）

删除 `reviewLoops["review-planning-report"]` 条目（该 loop 从未被 `evaluatePassCondition`/`readAttempts` 消费，且 product-planning 无 CR 上下文、attempts 持久化路径不成立）。`product-planning.pipeline.json` node-6 prompt 的"必须持久化 review-loop.attempts"改为如实描述：评审注记由 `review-planning-report` 自行落盘 `docs/product-planning/review-annotations/{report-id}.yml`，不经 crctl。

### 2.4 market-insights 统一 schema（FR-19）

`docs/market-insights/_index.yml` 目标契约（三写入方共用）：

```yaml
# 单一事实源：本文件 schema 由 CR-2026-022 统一定义，新增写入方须先对齐本声明
insights:                       # 顶层 key（conduct-market-research 从 entries: 迁入）
  - id: MI-YYYY-NNN
    type: MARKET_INSIGHT        # 下划线（conduct-market-research 从 MARKET-INSIGHT 迁入）
    status: raw                 # 生命周期 raw → briefed → published
    file: docs/market-insights/{id}.md   # 三写入方均必填（conduct-market-research 补）
    created: "..."
```

`market-to-plan.pipeline.json` 节点 5 终态 `planned` → `published`，执行方明确为 `write-planning-entry`（它是规划台账写入方，状态推进随其执行步骤发生，不再只存在于 pipeline prompt）。历史数据若存在旧字段名，用入库版本化脚本一次性迁移（落点 `skills/writeback/scripts/migrate-market-insights.mjs` + 同目录测试——该目录是 ARCHITECTURE.md §6 范围澄清后内容文件脚本的既有先例落点，planning 域无 scripts/ 先例、不新建目录；遵守纪律 #7 会话内不现写脚本）。

### 2.5 inbox-emit 事件枚举扩展（FR-15）

`inbox-emit/SKILL.md` 的 event 枚举补 `owner-handover`，三处同步（触发意图列表 / 参数表 / 下游消费方声明 handover-cr）。R7 的枚举校验以该 SKILL.md 声明为判据源（直读，不建快照）。

## 3. 接口契约

### 3.1 crctl 命令面变更（批 2.5 核心，§8 评审对象）

```text
# FR-9（既有命令扩旗标，缺省向后兼容）
crctl cr-init --title <t> --owner-requirement <id> [--year Y]
              [--summary <s>] [--source <s>] [--target-version <v>]

# FR-10（--template 分支扩旗标）
crctl git commit --template <kind> [--cr <cr-id>] [-m <subject>]
  # --cr 提供时：校验格式 ^CR-\d{4}-\d{3}$ + _backlog 存在性，直用，跳过 resolveTemplateCr
  # --cr 缺省时：保留原「分支探测 → subject 正则」兜底路径，存量调用不破坏

# FR-11（LEGAL 白名单扩展，命令签名不变）
crctl checkpoint-add <cr> --repo <r> --sha <sha> [--remote-ref <ref>]
  # 前置态：全部 12 个非终态（实现见 §4.2，从状态机派生不硬编码）

# FR-12（approve 行为扩展，命令签名不变）
crctl approve <cr> --stage <requirement|tech-design|dev-start|code>
  # decline 分支：查回退转换 → 执行回退 → 非零退出（错误码 APPROVAL_DECLINED_ROLLED_BACK，
  # extra 携带 {rolledBackTo, rerunHint}，见 §4.3；无回退转换时维持 APPROVAL_DECLINED）
```

**退出码契约（FR-12 关键点）**：decline 且回退成功时，进程以**非零**退出（审批未通过这一事实对调用方 pipeline 必须可见，`onFail:abort` 语义不变），错误码 `APPROVAL_DECLINED_ROLLED_BACK`，`fail()` 的 extra 字段携带 `{rolledBackTo: <status>, rerunHint: <write-skill>}`，错误消息为"审批未通过，CR 已回退到 {to}，请重跑 {skill}"。无回退转换的 stage 维持现状 `fail('APPROVAL_DECLINED')`（四 stage 经 D-1 + B3 修复后均有回退转换，该兜底理论上不触发）。

### 3.2 lint-prompts 规则契约（批 3.5）

```text
R6（crctl 命令参数形态）：
  触发面：行内含 crctl advance / backlog-set / git commit --template
  advance：必须匹配 --to\s+\S+ 与 --trigger\s+\S+
  LITERAL_BLACKLIST 追加：trigger=  expected_current_status=  commit_mode=
                            全角 ， 、 ）（在命令行内出现即违例）
  backlog-set：--field 取值 ∈ BACKLOG_SET_FIELDS（直读 crctl.mjs 常量）
  --template：subject 必须含 CR-\d{4}-\d{3} 编号（--cr 显式传入时豁免）
R7（inbox-emit 接口）：
  函数式 inbox-emit( 直接违例
  CLI 形态 --event 取值 ∈ inbox-emit/SKILL.md 声明枚举（直读）
豁免范围契约（FR-25）：
  <!-- lint-prompts:ignore --> 只豁免注释所在行 ± radius 行（radius=1，
  在 lint-prompts.test.mjs 以测试向量固化；pipeline JSON 的 node.prompt
  按行拆分后逐行判定，不再整段豁免）
```

判据全部直读源文件（`crctl.mjs` 常量 / `inbox-emit/SKILL.md` 枚举），符合 CR-2026-021 NFR-6「判据零派生物」。

### 3.3 pipeline JSON 契约变更

| 文件 | 变更 | 幂等影响 |
|---|---|---|
| architecture-design.pipeline.json | 5 节点 UUID 前缀 `0014-*` → `0016-*`（含 `repairNodeId` 自引用同步） | seed 幂等恢复（与 resume-cr 不再撞前缀）；**已占用前缀表更新至 0016** |
| code-implementation.pipeline.json | 节点 12 prompt 补 checkpoint-add 描述 | 无节点增删，UUID 不动 |
| 三条流水线 push-progress 节点 | `onFail: skip` 维持不变（JSON 仅 skip/abort 二值，abort 会在 git push 已成功时造成更大混乱）；可见告警改由**工具层**承担——FR-11 ② 重写 push-progress Step 3 时，skill 内逐仓调用 `crctl checkpoint-add` 失败即非零退出并在 node-N.md 摘要中强制输出 `CHECKPOINT_ALERT` 段（skill 执行失败本身即告警，不依赖 onFail 语义） | 运行时行为说明在提交信息中标注 |
| competitive-radar / market-to-plan | 镜像节点 `onFail` 统一 `abort`（D-3） | 运行时行为变更：原静默跳过变为中止，提交信息显式标注 |

> `onFail` 告警的设计取舍见 §5 决策 D-4。

## 4. 关键算法与流程

### 4.1 cr-init 旗标注入（FR-9）

```text
cmdCrInit(ws, gates, flags):
  ... 既有校验 ...
  summary = flags.summary ?? ''
  source  = flags.source ?? 'manual'
  tv      = flags['target-version'] ?? 'tbd'
  fm 中三处硬编码行改为模板注入（summary 引号包裹 + \" 转义，与 title 同款处理）
  backlogEntry 同步注入 source/target-version
  casWriteMulti 一次写三文件（现有事务边界不变）
```

### 4.2 checkpoint-add LEGAL 派生（FR-11 ①）

**不硬编码 12 态列表**（报告 §4.1 的参考骨架是全量枚举硬编码；本设计改为派生，防止状态机未来增态再次漂移）：

```text
cmdCheckpointAdd:
  const { sm } = loadStateMachine(ws)
  const LEGAL = (sm.states || []).filter(s => !(sm.terminal || []).includes(s))
  // 与 cmdOwnerSet 的终态判断同源（sm.terminal），口径永不错位
```

`cmdOwnerSet` 已用同款 `sm.terminal` 判断，模式既有、无新机制。若 `loadStateMachine` 失败维持硬失败（不静默回退旧列表，纪律 #1/#4）。

### 4.3 approve decline 回退（FR-12 ②）

```text
cmdApprove 非 TTY-yes 分支（约 :1074）改为：
  auditLog(..., { result: 'declined' })
  const target = REJECT_ROLLBACK[stage]
    // 静态映射表（与 gates.json approvalStages 一一对应，评审逐条对照）：
    //   requirement → drafting            （经 D-1 新增转换）
    //   tech-design → tech-designing      （既有 :220）
    //   dev-start   → tech-design-reviewed（经 B3 修复新增转换）
    //   code        → developing          （既有 :228）
  const trigger = `${approveSkillOf(stage)}:reject -> ${rollbackSkillOf(stage)}`
  const t = findTransition(sm, current, target, trigger)
  if (!t) fail('APPROVAL_DECLINED', '审批人未确认，且状态机未声明回退转换', { stage, current })
  cmdAdvance(ws, cr, gates, { to: target, trigger, expect: current })
  auditLog(..., { kind:'approve', result:'declined-rolled-back', to: target })
  fail('APPROVAL_DECLINED_ROLLED_BACK', `审批未通过，CR 已回退到 ${target}，请重跑 ${rerunSkill}`,
       { rolledBackTo: target, rerunHint: rerunSkill })
```

`REJECT_ROLLBACK`/`approveSkillOf`/`rollbackSkillOf` 为 crctl.mjs 顶部静态常量表。dev-start 的回退目标 `tech-design-reviewed` 是 write-dev-plan 的前置态（订正 approve-dev-start 现错误表中不可达的"重跑 write-dev-plan"建议——回退后重跑对象正是 write-dev-plan，前置态匹配）。

### 4.4 lint 豁免收窄（FR-25）

```text
isIgnored(lines, i, radius = 1):
  对 k ∈ [i-radius, i+radius]：lines[k] 含 '<!-- lint-prompts:ignore -->' 则豁免
splitPipelineJson 产出的 node.prompt 按 \r?\n 拆行后逐行跑规则，
豁免判断只作用于行索引邻域，不再对整段 prompt 布尔放行
```

### 4.5 merge-feature-branch HEAD 校验（FR-16）

Step1.4 增补：`git rev-parse HEAD` 与 `git rev-parse origin/requirement/{cr_id}` 比对，不等则 `fail-fast` 提示补跑 push-progress，不进入合并阶段。纯 SKILL 文本变更，无 crctl 改动。

### 4.6 cmdNext 判断依据修正（FR-21）

`writing-back` 分支（:2219-2222）现状：`fs.existsSync(change-requests/{cr}/traceability.yml)`（开发期工作稿，恒存在）→ 误判"可归档"。改为检查 writeback-traceability 的产物 `specs/{spec_id}/traceability.yml`。

**spec_id 取值来源（已核实）**：`_backlog` 条目**没有** spec-id 字段（grep 坐实）；specId 在 crctl 内一律是**调用方经 `--spec-id` 旗标传入**的参数（`advance --to writing-back/archived` 缺它即 BAD_ARGS fail-fast，:987-991），不落账本。因此 cmdNext 不能从账本读 spec_id，改为**从文件系统推断**：扫描 `specs/` 目录，若存在唯一子目录则取其名；多个子目录时取 `_backlog` 条目 `merge-commits` 所在仓对应的 spec 目录不可行（无映射），此时输出"多 spec 目录，请显式确认"而非猜。实现：

```text
case 'writing-back':
  const specsDir = path.join(ws, 'specs')
  const subs = fs.existsSync(specsDir) ? fs.readdirSync(specsDir, {withFileTypes:true}).filter(d=>d.isDirectory()).map(d=>d.name) : []
  if (subs.length !== 1) return suggest('writeback-prd-sdd', `specs/ 子目录数=${subs.length}，无法唯一确定 spec_id，先完成 PRD/SDD 回写`)
  const trace = fs.existsSync(path.join(specsDir, subs[0], 'traceability.yml'))
  return suggest(trace ? 'cr-archive' : 'writeback-tasks → writeback-traceability', ...)
```

只读逻辑 bug 修复，不新增写口。

## 5. 技术选型与替代方案

| # | 决策 | 取舍 |
|---|---|---|
| D-1 | 新增 `requirement-reviewing:reject -> drafting`（PRD §1.3 已拍板） | 替代方案"维持 CR 死刑"被否：与其余三阶段不对称且过于刚性 |
| D-2 | 删 gates.json 死配置（PRD 已拍板） | 替代方案"新开不依赖 CR 上下文的 attempts 子命令"被否：单消费者收益不成比例，违反 §6 YAGNI |
| D-3 | onFail 统一 abort（PRD 已拍板） | 替代方案"skip + 空文件降级展示"被否：额外复杂度换不来可用性 |
| D-4 | push-progress 节点 onFail 维持 `skip`，可见告警由工具层承担（skill 内 checkpoint-add 失败即非零退出 + 摘要强制 CHECKPOINT_ALERT 段） | pipeline JSON `onFail` 只有 skip/abort 二值；abort 会在 git push 已成功时造成更大状态混乱（报告 2.1-G 明示不宜 abort）。告警不依赖 onFail 语义，由 skill 执行失败本身承担——这是可执行形态，非"等未来 warn 语义"的悬置方案 |
| D-5 | LEGAL 白名单从状态机派生而非硬编码 12 态 | 报告 §4.1 参考骨架为全量硬编码；派生方案与 cmdOwnerSet 同源、未来增态零成本漂移。代价：checkpoint-add 对"语义上不该记账"的状态（如 rejected 前的边界态）也放行——但终态已由 sm.terminal 排除，非终态记 checkpoint 无副作用 |
| D-6 | decline 回退后仍非零退出 | 替代方案"回退成功即零退出"被否：pipeline onFail 依赖退出码区分"审批通过"，零退出会让流水线误入下一节点 |
| D-7 | 迁移脚本落点 `skills/writeback/scripts/` | 该目录是 ARCHITECTURE.md §6 范围澄清（CR-2026-020）后**内容文件脚本**的既有先例落点（writeback-prd-sdd.mjs 等）；market-insights 迁移是内容文件操作不是账本操作，与先例同构。planning 域无 scripts/ 先例，不新建目录 |
| D-8 | UUID 前缀选 `0016-*` | 0002/0003/0010/0011/0013/0014/0015 已占用，取最小未占用值（沿用报告建议） |

## 6. FR 到技术实现映射

| FR | 实现条目 | 批次 |
|---|---|---|
| FR-1~FR-3 | 8 文件 12 处命令串按报告 2.1-A 目标形态逐处替换（review-requirement 省 `--expect`）；3 处豁免注释外移；死引用/措辞订正 | 批 1 |
| FR-4~FR-8 | cr-status-set 文件+条目删除、validate-doc 两处订正、focus-briefing 反向修（status:new/seen 翻转）、降级路径、pending 清空、record-adr 删前引用计数核实 | 批 2 |
| FR-9 | §2.1/§4.1 cr-init 旗标注入 | 批 2.5 |
| FR-10 | §3.1 `--cr` 旗标优先 + 兜底保留 | 批 2.5 |
| FR-11 | §4.2 LEGAL 派生 + push-progress Step 3 逐仓调用 + 节点 12 补齐 + §3.3/D-4 告警 | 批 2.5 |
| FR-12 | §2.2 状态机新增**两条**转移（D-1 需求驳回 + B3 修复 dev-start 驳回）+ §4.3 decline 回退（含 REJECT_ROLLBACK 四 stage 映射）+ 四份 approve-* 错误表订正 + "无旁路"表述修正 | 批 2.5 |
| FR-13 | §2.3 删死配置 + node-6 prompt 如实描述 | 批 2.5 |
| FR-14 | requirement-register 错误表补 STALE_BASE 降级行 | 批 2.5 |
| FR-15 | §2.5 枚举三处同步 + feedback-writeback/handover-cr 迁 CLI 形态 | 批 3 |
| FR-16 | §4.5 HEAD 校验 | 批 3 |
| FR-17 | competitive-radar node-2 写入目标 + confirmed=false 草稿 + 落盘挪审批后 | 批 3 |
| FR-18 | §3.3 UUID 0016 迁移 + repairNodeId 同步 + seed 幂等验证 | 批 3 |
| FR-19 | §2.4 统一 schema + 节点 5 终态订正 + 原子提交 + 迁移脚本（D-7） | 批 3 |
| FR-20 | handover-cr/resume-from-remote 改调 owner-set | 批 3 |
| FR-21 | §4.6 cmdNext 判断依据 + crctl.test.mjs 用例 | 批 3 |
| FR-22 | cr-show 改调 crctl next、删硬编码表 | 批 3 |
| FR-23 | 八项歧义订正逐条按报告 2.4 目标形态落地 | 批 3 |
| FR-24 | §3.2 R6/R7 | 批 3.5 |
| FR-25 | §4.4 豁免收窄（radius=1 契约化） | 批 3.5 |
| FR-26 | lint-prompts.test.mjs 三类向量（含 product-planning:109 复现场景） | 批 3.5 |
| FR-27~FR-32 | approve-* 对齐、writeback 抽 shared、sync 收敛 + worktree-path、constraints 删、push-progress 样板抽取（以 FR-11 为前提）、评估项下线（write-insight-brief/run-competitive-analysis 合并下线 + 去重 + 跳过检查单份化） | 批 4 |
| FR-33 | 三台账同步 + check-skill-matrix + JSON 自检 + crctl.test.mjs 全量回归 + 状态机口径 25/47 全仓引用核查 | 收尾 |
| FR-34 | ARCHITECTURE.md §8 登记本 CR + crctl/SKILL.md 新旗标 + lint 头部说明 + AGENTS.md 抽 shared 原则 | 收尾 |

FR 覆盖率：34/34。

## 7. 安全与性能考量

- **并发安全**：cr-init 扩旗标不改变 `casWriteMulti` 事务边界；checkpoint-add/approve 改动均走既有 CAS + audit 路径，无新写入范式（NFR-1）。
- **状态机回归风险**：D-1 新转移是纯增量，不改任何既有转换；decline 回退只发生在审批人显式回答非 yes 的分支，`--grant` 签名路径不经过该分支（不变量 7 不受影响）。
- **口径同步**：状态机 25/47 口径变更列入 FR-33 核查清单（grep "23 条声明" 全仓清零旧口径）。
- **行尾纪律**：R6/R7 规则与豁免逐行判定前统一 `replaceAll('\r\n','\n')`；`splitPipelineJson` 跨行正则匹配失败维持硬失败（不变量 4）。
- **性能**：lint 新增两规则为行级正则，全仓扫描耗时增量 <10%（现有 R1~R5 同量级）；crctl 改动均为 O(1) 分支，无性能面变化。
- **回滚**：批 2.5 每子项单 commit（cr-init/--cr/LEGAL/approve/gates 各一），任一可独立 revert；dir-graph.yaml 回退转换删除前留存改前对照（NFR-2）。
- **灰度**：批 2.5 落地后先以一次演练注册走通三条新路径（NFR-5，形式参照 CR-2026-019 AC-9），本 CR 自身后续阶段（任务拆分/开发）即天然灰度消费者。

## 8. Prompt 采纳影响（CR-2026-021 FR-25 条件性小节——本 CR diff 触及 crctl.mjs dispatch，必填）

本 CR 扩展/修改的 crctl 能力面与应采纳的 skill 清单（逐条核对，防"新增能力未被采纳"类漂移）：

| crctl 能力变更 | 现状 | 应改为 |
|---|---|---|
| cr-init `--summary/--source/--target-version`（FR-9） | requirement-register Step 2 无字段传参路径，注册实录被迫违纪手写 | requirement-register Step 2 prompt 改为把 summary/source/target-version 作为 cr-init 旗标传入；删 cr_id 僵尸参数 |
| `git commit --template --cr`（FR-10） | requirement-register Step 4 靠 subject 强制带编号 | 改为显式 `--cr {cr-init 返回值}` 直传 |
| checkpoint-add 全非终态可用（FR-11） | push-progress Step 2-3 只调 runGit、展示 YAML 让人抄 | Step 3 改逐仓 `crctl checkpoint-add --repo <r> --sha <sha>`；三流水线节点 prompt 引用 skill 默认说明（FR-31） |
| approve decline 回退（FR-12） | 四份 approve-* 错误表无"回答非 yes"分支 | 各补一行"驳回后 CR 回退到 {to}，请重跑 {skill}"，与 §4.3 映射表逐一对齐 |
| gates.json review-planning-report 删除（FR-13） | product-planning node-6 承诺"必须持久化" | 改为如实描述自行落盘机制 |
| cmdNext writing-back 修正（FR-21） | cr-show 硬编码映射表 | 改调 `crctl next`（FR-22 同步采纳） |

以上采纳动作全部已在本 CR 的 FR 清单内（非欠账），实施顺序上批 2.5 代码先行、对应 prompt 修改同批跟进，不允许"代码上了、prompt 下批再改"。

## 9. 测试设计

| 层 | 内容 |
|---|---|
| crctl.test.mjs | cr-init 三旗标（缺省兼容/覆写/转义）；`--cr` 直传与兜底路径；checkpoint-add 12 非终态参数化 + 3 终态拒绝；approve decline 四 stage 回退（含 requirement 新转换与 dev-start 新转换）+ 回退失败兜底；cmdNext writing-back 三分支（无 specs 目录/唯一目录/多目录）；状态机口径断言更新 25/47 |
| lint-prompts.test.mjs | R6 三类违例 + backlog-set/--template 覆盖；R7 两类违例；豁免 radius 边界（±1 行命中/±2 行不豁免）；product-planning:109 复现场景 |
| writeback/pipeline 自检 | architecture-design/resume-cr JSON 解析 + seed 幂等（重复 seed 无重复节点）；market-insights 迁移脚本 fixture 测试 |
| 端到端（AC-20） | 报告 §6.2 三场景：完整生命周期串联 / 通知链两事件 / lint 三类违规注入 |

## 10. 风险与残余

- **批 4 抽 shared 的引用失效风险**：前置 FR-24 lint「shared 引用一致性」检查必须先落地（NFR-4），否则把 N 处漂移换成引用失效。
- **focus-briefing pipeline 注册表路径**：运行时路径确认不了时整体删除该数据源（文档已声明可选、删除零副作用）——确认动作在实施期向运行时方取证，取证结果记录在任务产出中。
- **record-adr/adrs.yml 删除**：删前必须完成全仓引用计数核实（含前端/agent 读取面），核实记录入任务证据。
- **onFail 语义限制（D-4）**：可见告警由 skill 执行失败（非零退出）承担，pipeline onFail 维持 skip 不升级——这是当前 schema 下的确定方案，非悬置；若未来 pipeline JSON 支持 `warn` 语义可再评估。
