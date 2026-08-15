---
id: CR-2026-039-sdd
type: SDD
cr-ref: CR-2026-039
title: tools CR 生命周期最小优化 2/5 — 生命周期证据规范化 技术设计
status: draft
created: 2026-08-15T00:55:31+08:00
updated: 2026-08-15T01:23:01+08:00
---

# 1. 架构概览

## 1.1 设计目标

本设计落实 PRD FR-01～FR-05，将四类生命周期证据漏洞收敛到既有深原语的既有缝（seam）中，不新增命令、账本、schema 或状态：

1. **FR-01**：code Pipeline 在 review-code 与人工审批之间结构性插入一个现有 `push-progress` 节点（一次 `crctl checkpoint` 调用），以节点顺序本身作为"PASS 后必 checkpoint"的强制机制。
2. **FR-02**：`crctl review-record --stage dev-plan` 复用现有 `subject-sha256` 字段写入 plan+TASK composite digest；消费缝只有两处——`cmdNext` 的 task-breakdown 分支与 `runGateChecks` 的 `passCondition(dev-start)` 分支——共用同一个重算 helper。
3. **FR-03**：时间字段收敛为三个 writer 的纯函数级修改（`crMdStatusText`、register 渲染、`editCrOwnerProjection`）；现有 reader 只做通用 frontmatter 解析、不消费时间字段，因此不新增无调用方的兼容 helper，兼容读取规则固定为 `updated ?? updated-at`。
4. **FR-04**：canonical 字段收敛是纯文本契约修订（三个 CR Pipeline JSON + 相关 Skill），零 crctl 代码变更——`review-record` 现有 schema 校验即为准绳。
5. **FR-05**：职责边界不产生运行时代码，体现为上述每个修改点的落点选择（见 §6 映射表"落点模块"列）与 §9 静态测试。

核心不变量：

1. digest 的权威定义只有一个（§4.1 `devPlanCompositeDigest`），写入点与所有消费点都调用它，禁止任何调用方自行拼接。
2. PASS 结论（annotation verdict）与被评审内容（digest）分离存储、消费时绑定；内容漂移使结论失效，而不是覆盖结论。
3. Pipeline 的强制性来自节点顺序与 `onFail: abort`，不来自 prompt 中的告诫文字。
4. legacy 数据（无 digest、旧 `updated-at`）永远走保守路径（重审 / 兼容读），不做批量迁移。

## 1.2 分层与依赖

```text
code-implementation.pipeline.json（节点顺序：review-code → [新]checkpoint → human_approval → approve-code）
  ↓ 一次调用
push-progress Skill（现状已收敛为一次 crctl checkpoint，不改）
  ↓
crctl.mjs + lib/workspace-transactions.mjs（本 CR 只在四个既有 seam 内扩展，无新 dispatch 分支）
  ├─ cmdReviewRecord: dev-plan 分支追加 subject-sha256（复用 sha256 + LF 规范化）
  ├─ cmdNext: task-breakdown PASS 分支追加 digest 重算
  ├─ runGateChecks: passCondition(dev-start) 分支追加 digest 重算
  └─ crMdStatusText / editCrOwnerProjection: updated 字段统一
  ↓
Node 标准库（fs/path/crypto）+ 现有 readEvidenceDoc / readFileChecked / casWrite
```

依赖方向不变：`workspace-transactions.mjs` 中的 `crMdStatusText` 被 `crctl.mjs` 单向引用（merge finalize 亦复用该纯函数，禁止复刻——本次修改该函数即同时覆盖 approve/advance 与 merge 两条状态写入路径）。

## 1.3 与 CR-2026-038 的共享文件集成

CR-2026-038 已合入 tools `custom/main`（merge `162fdf0`）；其实际 diff 修改 `crctl.mjs`、`workspace-transactions.mjs`、durable/writeback 测试与 `feature-writeback.pipeline.json`，**未修改** `code-implementation.pipeline.json`。本 CR 与其共享 crctl 核心文件，但功能边界独立（本 CR 不触碰 writeback preflight/write-set/merge prepare/candidate 路径，CR-2026-038 不触碰 review-record/next/dev-plan freshness/时间字段）。当前 CR-2026-039 tools worktree 仍基于旧 HEAD `c790b7e`，实施约定：

- T1 开工前先通过现有 CR worktree 集成方式把最新 `origin/custom/main`（当前 `162fdf0`）合入该分支：当前 tools 分支无自身提交时只允许 fast-forward；若届时已有已发布提交则使用普通 merge commit。禁止 rebase 已发布分支、force push、逐提交 cherry-pick 或手工重放 CR-2026-038 实现。
- 后续每个 TASK 开工前确认 `origin/custom/main` 未前进；若前进则先按同一非改写历史方式集成，再改共享文件。该集成是实施前置，不进入 Pipeline/Skill prompt，也不在调用层复制 Git 算法。
- `code-implementation.pipeline.json` 没有 CR-2026-038 冲突面；新增 checkpoint 节点只按现有节点 id 定位，禁止依赖数组行号。

# 2. 数据模型

## 2.1 dev-plan annotation（review-annotations/dev-plan.yml）

仅在现有结构上追加一个字段，无新文件、无新账本：

```yaml
cr-id: CR-2026-XXX
reviewer: "..."
reviewed-at: "..."
verdict: pass            # 或 block（block 轨同样写 digest：评审时刻的内容快照同样需要绑定）
blockers: []
dimensions: { ... }
suggestions: []
repair-target: write-dev-plan   # 仅 block 轨，现状保留
subject-sha256: <64-hex>        # 新增：plan+TASK composite digest（LF canonical）
```

- **不写** `subject-file`：composite digest 对应文件集合不是单文件，写 plan.md 会误导消费者把该字段当完整 subject（PRD FR-02）。requirement/tech-design 两阶段的 `subject-file` 现状不动。
- legacy annotation 无 `subject-sha256` 不构成读取错误；消费点按 §4.3 保守路径处理。

## 2.2 composite digest 的 canonical 编码

digest 输入序列（确定性，跨平台一致）：

```text
entries = [
  { path: "change-requests/{cr}/plan.md", content: LF(plan.md) },
  { path: "change-requests/{cr}/tasks/TASK-*.md", content: LF(...) },  # 全部 TASK，按 path 字符串升序
]
canonical = JSON.stringify(entries)   # 键序固定 path→content（对象字面量插入序），无空白
digest = sha256(utf8(canonical))
```

- `path` 为 workspace-relative POSIX 路径；`content` 为 `\r\n → \n` 规范化后的全文。
- TASK 匹配严格按 PRD 的全部 `TASK-*.md`：`/^TASK-.*\.md$/`，只扫 `change-requests/{cr}/tasks/` 一层。现有 `gates.json#statusGates.task-breakdown` 的数字前缀 glob 只负责最低存在性门禁，不是 digest 文件集合的事实源，不得据此收窄 subject。
- `tasks/_index.yml` 不进入（实现期 TASK 状态正常变动）；这是与 task-breakdown 门禁存在性检查的刻意差异，注释写明依据（PRD FR-02 / 规格 FR-05）。
- JSON 编码天然把 path 与 content 都纳入且带长度边界，不同文件集合不可能拼接出相同串（防 `a`+`bc` vs `ab`+`c` 类碰撞）。

## 2.3 cr.md frontmatter 时间字段

目标形态：单一 `updated` 字段。

| writer | 现状 | 目标 |
|---|---|---|
| register（workspace-transactions.mjs 渲染） | 已写 `updated` | 不变 |
| 状态推进（`crMdStatusText`，advance/approve/reject 与 merge finalize 共用） | 仅当 `updated-at:` 行存在时替换 | 统一维护 `updated`：有 `updated-at:` → 替换为 `updated:`；有 `updated:` → 刷新；两者皆无 → 追加。任何情况下不得双字段共存 |
| Owner 正式移交（`editCrOwnerProjection`） | 不触碰时间字段 | 修改 cr.md 时同样按上述规则刷新 `updated` |

其他写入（PRD/SDD/TASK/评审/测试/checkpoint）不经过这三个函数，结构上不可能触碰 `updated`——不靠纪律靠缝。

# 3. 接口契约

## 3.1 CLI（全部为现有命令，无新增/无签名变更）

| 命令 | 行为变化 | 输出变化 |
|---|---|---|
| `crctl review-record {cr} --stage dev-plan --bump-attempt` | 落盘前计算 §2.2 digest 写入 annotation；plan.md 缺失或 TASK 集为空 → 硬失败 `SUBJECT_NOT_FOUND`（与 requirement/tech-design 同错误码，禁止静默降级为空 digest） | 返回 JSON 不变 |
| `crctl next {cr}` | status=task-breakdown 且 annotation PASS 时先重算 digest（§4.3） | 字段不变；`next`/`why` 文本按分流变化 |
| `crctl approve --stage dev-start` | 目标态 `developing` 门禁的 `passCondition(dev-start)` 检查追加 digest 重算；漂移 → 该 check `ok:false`，approve 硬失败 | gateBlockers 文案说明 dev-plan subject digest 不一致；不新增错误码 |
| `crctl advance` / `crctl approve`（状态写入） | cr.md 候选文本经修订后的 `crMdStatusText` 生成 | 不变 |
| `crctl owner-set` | cr.md 投影同时刷新 `updated`（`owner-handover` 为 inbox 事件名，非命令名） | 不变 |

## 3.2 Pipeline 节点契约（code-implementation.pipeline.json 新增节点）

```json
{
  "id": "00000000-0000-0000-0015-000000000015",
  "kind": "skill",
  "label": "代码评审 PASS 后审批前 checkpoint",
  "ref": "push-progress",
  "prompt": "执行 push-progress：cr_id={{inputs.cr_id}}，message=代码评审通过后审批前 checkpoint。\n\n在节点输出中记录 batchId、repositories、phase；phase 非 complete 时中止，不得进入人工审批。",
  "onFail": "abort",
  "timeoutMinutes": 15
}
```

- 插入位置：`review-code`（…0009）之后、human_approval `代码审查通过`（…0010）之前。
- 回修循环无需改 `reviewLoop.replayNodes`：重放序列 implement-code → write-test-report → push-progress → review-code 再次 PASS 后，控制权自然落到 review-code 的下一节点，即本新节点——"再次 PASS 后重新 checkpoint" 由顺序结构性保证。
- human_approval（…0010）的 approvalPrompt 追加一句："且评审后 checkpoint phase=complete"。
- 同时删除该 pipeline `inputs` 中的 `suggestion_policy` 输入定义（FR-04）。

## 3.3 release-subjects 与 PASS 后 checkpoint 的兼容边界

`review-record --stage code` 在写 annotation 前调用现有 `buildReleaseSubjects`：每个 active repo 的 requirement 远端必须等于当前 worktree HEAD，然后把这些 reviewed SHA 与 PRD/SDD/plan/TASK artifact digest 写入 `code.yml`。PASS 后 checkpoint **不得重算或覆盖**该快照；approve-code 继续用原快照执行现有 `verifyReleaseSubjects`：

- knowledge-base 仓允许 reviewed SHA 是当前 HEAD 的祖先，但两者之间只能出现既有白名单路径（`review-annotations/`、`cr.md`、`traceability.yml`、`review-loop.yml`、`approval.yml`、`_backlog.yml`）；因此 review-record/status/checkpoint metadata 导致的 KB 后继提交合法。
- 非 knowledge-base 仓仍要求当前 HEAD 与 reviewed SHA 精确相等；若 review PASS 后出现未评审代码并被 checkpoint 提交，approve-code 必须以 release subject drift 拒绝。
- PRD/SDD/plan/TASK 内容仍按 snapshot artifact 集逐文件和集合 digest 重核；KB HEAD 虽允许前移，也不能借白名单提交改变被审批业务产物。

该边界解释了 FR-01 为何能复用现有 checkpoint 而不放宽 approve-code：正常路径只发布评审账本与状态；任何未评审代码或业务产物变化仍被既有 release-subjects 拦截。

## 3.4 review_feedback 合同（FR-04 收敛后）

```text
review_feedback = { blockers: string[], suggestions: string[], dimensions: {}, repair-target?: string }
```

- 可执行的回修说明直接写在 blocker 字符串内（一句话 blocker + 怎么改），不再有 `repair-instructions` 并列字段。
- 修复结果由下一轮 review 的 blockers 差异自然体现，不再有 `fixed-blockers` 输出义务；各 write/implement Skill 的"逐条消费 blockers"语义不变。

# 4. 关键算法与流程

## 4.1 devPlanCompositeDigest(ws, cr)（新增唯一 helper，crctl.mjs 内部函数）

```text
function devPlanCompositeDigest(ws, cr) -> { ok, digest?, why? }:
  planRel = `change-requests/${cr}/plan.md`
  planRaw = readFileChecked(join(ws, planRel))
  if planRaw == null: return { ok:false, repairTarget:'write-dev-plan', why:'plan.md 缺失' }
  tasksDir = join(ws, `change-requests/${cr}/tasks`)
  if tasksDir 不存在: return { ok:false, repairTarget:'write-dev-tasks', why:'tasks/ 缺失' }
  names = readdirSync(tasksDir).filter(f => /^TASK-.*\.md$/.test(f)).sort()   # 字符串升序
  if names.length == 0: return { ok:false, repairTarget:'write-dev-tasks', why:'TASK-*.md 集合为空' }
  entries = [{ path: planRel, content: lf(planRaw) }]
  for f of names:
    taskRaw = readFileChecked(join(tasksDir, f))
    if taskRaw == null: return { ok:false, repairTarget:'write-dev-tasks', why:`TASK 文件缺失: ${f}` }
    entries.push({ path:`change-requests/${cr}/tasks/${f}`, content:lf(taskRaw) })
  return { ok:true, digest:sha256(utf8(JSON.stringify(entries))) }
```

- `lf = t => t.replaceAll('\r\n', '\n')`（行尾纪律）。读取沿用 `readFileChecked`；任一缺失都返回带明确 why 的失败结果，不跳过、不降级为空集合。
- review-record 调用方见 §4.2：失败结果统一 `fail('SUBJECT_NOT_FOUND', why)`，保证零账本写；freshness 只读调用方见 §4.3：失败结果明确判 stale 并路由重审。仅对预期缺失做结构化转换，权限/I/O 等异常继续抛出，不宽泛 catch。
- 排序以完整相对路径字符串比较，跨平台一致（不依赖 readdir 顺序）。

## 4.2 review-record 写入点

在现有 `if (stage === 'requirement')` / `if (stage === 'tech-design')` 分支序列后追加：

```text
if (stage === 'dev-plan'):
  subject = devPlanCompositeDigest(ws, cr)
  if !subject.ok: fail('SUBJECT_NOT_FOUND', subject.why)
  lines.push(`subject-sha256: ${subject.digest}`)
```

block 轨与 pass 轨同写（评审时刻内容快照对两轨都有意义：block 回修后重审，digest 自然刷新）。

## 4.3 消费点分流（两处共用 freshness 判定）

```text
function devPlanFreshness(ws, cr, annData) -> { fresh, repairTarget?, why? }:
  rec = annData['subject-sha256']
  if rec == null: return { fresh:false, repairTarget:'review-dev-plan', why:'legacy 无 digest，需重审刷新证据' }
  cur = devPlanCompositeDigest(ws, cr)
  if !cur.ok: return { fresh:false, repairTarget:cur.repairTarget, why:`dev-plan subject 不完整：${cur.why}` }
  return cur.digest === rec
    ? { fresh:true }
    : { fresh:false, repairTarget:'review-dev-plan', why:'plan/TASK 已修订，subject digest 不一致' }
```

- **cmdNext（task-breakdown，PASS 分支）**：现行为 `verdict=pass && blockers=[] → suggest approve-dev-start`；改为先 `devPlanFreshness`——不 fresh 则 `suggest(freshness.repairTarget, why)`：plan 缺失→write-dev-plan，TASK 缺失/为空→write-dev-tasks，legacy 或 digest 漂移→review-dev-plan。block 分支与 annotation 畸形判定不变。
- **runGateChecks（passCondition 分支）**：`evaluatePassCondition` 返回 pass 且 `check.stage === 'dev-start'` 时追加 freshness 判定；不 fresh → 该 check `ok:false, why`，使 `approve-dev-start`（目标态 `developing` 门禁）与一切以 developing 为目标的 advance 硬失败。复用现有 gate 失败通道，不新增错误码。
- requirement/tech-design/code 三阶段的 passCondition 评估路径不进入该分支，零影响。

## 4.4 crMdStatusText 修订（workspace-transactions.mjs 纯函数）

```text
现状：仅在 /^updated-at:/m 存在时替换该行
目标：
  fm = fm.replace(/^updated-at:\s*.*$/m, '')        # 旧字段先清除（若存在）
  ts = `updated: "${opts.at || nowIso()}"`
  fm = /^updated:\s*.*$/m.test(fm) ? fm.replace(/^updated:\s*.*$/m, ts) : fm + `\n${ts}`
```

- 替换后需清理可能产生的空行（保持 frontmatter 规整）。
- `editCrOwnerProjection`（crctl.mjs）在生成新 cr.md 文本后，复用同一规则刷新 `updated`（提取为共享小函数 `refreshCrMdUpdated(fm)` 置于 workspace-transactions.mjs 并导出，避免两处复刻）。
- 兼容读：任何需要"最后受控修改时间"的读者按 `updated ?? updated-at` 读取；当前 crctl 无此类消费点，该规则写入代码注释作为 reader 契约。

## 4.5 FR-04 文本契约修订清单（零代码）

修订原则：删除对不存在 canonical 字段的引用；可执行回修说明并入 blocker 文本；不改变 reviewLoop 结构与 passCondition。

| 文件 | 修订内容 |
|---|---|
| `pipeline-templates/requirement-authoring.pipeline.json` | write-requirement-prd / review-requirement 两节点 prompt：删 `repair-instructions`、`fixed-blockers` 引用；回修语义改为"逐条消费 review_feedback.blockers（blocker 内含可执行修复说明）" |
| `pipeline-templates/architecture-design.pipeline.json` | write-tech-design / review-tech-design 两节点 prompt 同上 |
| `pipeline-templates/code-implementation.pipeline.json` | 删 `inputs.suggestion_policy` 定义；implement-code prompt 删 `fixed-blockers` 输出义务与 `repair-instructions` 引用；write-test-report prompt 删 `repair-instructions` 输出；review-code prompt 删 suggestion_policy 全段（strict/lenient、升格判据、dimensions 记录）与 `repair-instructions` 输出 |
| `skills/requirement/{write-requirement-prd,review-requirement}/SKILL.md` | 删 repair-instructions / fixed-blockers 引用，回修步骤改为按 blockers 定点修复 |
| `skills/develop/{write-tech-design,review-tech-design,write-dev-plan,write-dev-tasks,review-dev-plan,implement-code,review-code,write-test-report,coding-discipline}/SKILL.md` | 同上；review-code 删升格判据一节；coding-discipline 的 root-cause 要求保留（不与 fixed-blockers 并列表述） |
| `agents/quality-reviewer-agent.md` 等 Agent 文档、README 中的残留引用 | **不在本 CR 范围**（归实施 CR 5，见 §10 风险） |

`product-planning.pipeline.json` 与 `skills/planning/*` 不动（无 CR 上下文，独立合同，PRD FR-04 明确排除）。

# 5. 技术选型与替代方案

| 决策 | 选择 | 否决的替代 | 理由 |
|---|---|---|---|
| PASS 后 checkpoint 的强制机制 | Pipeline 节点顺序 + onFail:abort | 在 approve-code 门禁里校验 latest-checkpoint 时间戳 | 顺序即机制，零新门禁、零时间比较逻辑；时间戳比较引入时钟与阈值问题 |
| digest 绑定字段 | 复用 annotation `subject-sha256` | 新 freshness ledger / `input-subjects` 数组 | 与 requirement/tech-design 同构，next/gate 消费路径已被验证；新账本违反 PRD NFR-01 |
| composite 编码 | canonical JSON entries（path+content） | 逐文件 sha256 再拼接 / tar 风格串接 | JSON 自带边界，防拼接歧义；Node JSON.stringify 确定性够用，不引依赖 |
| 消费点挂钩 | cmdNext + runGateChecks(passCondition) 各一行调用同一 helper | 新增独立 gate type（如 subjectFreshness） | 两处即全部消费缝；新 gate type 需 gates.json 声明 + checker 实现，浅模块 |
| 时间字段迁移 | writer 侧渐进收敛 | 一次性批量迁移历史 CR | 规格明令不批量迁移；writer 收敛后双字段共存数自然归零 |
| suggestion_policy 移除 | 直接删除输入与 prompt 段 | 保留参数但固定 strict | 保留无用参数是死配置；删除后 review-code 语义更简（verdict 只判 CR 本身） |

# 6. FR 到技术实现映射

| PRD FR | 落点模块（职责边界） | 技术条目 |
|---|---|---|
| FR-01 PASS 后审批前 checkpoint | Pipeline（节点顺序/失败中止）；push-progress Skill 不改 | §3.2 新节点 …0015；human_approval prompt 一句；回修由顺序保证 |
| FR-02 dev-plan digest | crctl（受控证据写入与门禁） | §4.1 helper、§4.2 写入、§4.3 双消费点 |
| FR-03 updated 统一 | crctl（`workspace-transactions.mjs` 内部共享纯函数，仍属受控账本写入边界） | §4.4 三个 writer（register 渲染、`crMdStatusText`、`editCrOwnerProjection`）+ reader 契约；不落到版本化文档转换脚本 |
| FR-04 canonical 收敛 | Pipeline/Skill 文本契约（业务语义层） | §4.5 清单；review-record schema 校验现状即准绳 |
| FR-05 职责边界与 ponytail | 全部（落点选择即实现） | §1.2 分层、§5 选型、§9.2 静态测试 |

# 7. 安全与性能考量

- **安全**：不新增任何执行入口；approve-dev-start 的 digest 门禁只收紧不放宽；legacy 无 digest 一律保守重审，不存在"绕过 digest 的旧通道"。canonical JSON 仅用于哈希输入，不反序列化外部数据。
- **性能**：digest 重算 = plan+TASK 全文读取与一次 sha256（数十 KB 量级，毫秒级）；消费点每次 next/approve 各一次，无缓存需求（YAGNI）。
- **行尾与失败纪律**：所有 digest 与 frontmatter 处理先 LF 规范化（§4.1/§4.4）；预期 subject 缺失返回明确 repairTarget（review-record 转为硬失败，next 转为可执行恢复路由，gate 转为阻断），权限/I/O/解析异常继续硬失败，禁止静默降级（T04 教训）。
- **跨平台**：路径比较用 POSIX 相对路径字符串；Windows autocrlf 检出由 LF 规范化吸收；测试在 Ubuntu/Windows 双跑。

# 8. Prompt 采纳影响

本 CR 不新增 crctl 子命令、不改 `controlled-shell/rules.json` deny 面，但既有命令行为变化，以下 Skill/文档必须同步采纳（随实施 TASK 一并修订，review-tech-design 与人工审批逐条核对）：

| Skill / 文档 | 现状 | 应改为 |
|---|---|---|
| `skills/shared/crctl/SKILL.md`（review-record 行） | 只描述 requirement 阶段写 subject-sha256 | 补注 dev-plan 阶段写 plan+TASK composite digest，next/approve-dev-start 消费前重算 |
| `skills/develop/review-dev-plan/SKILL.md` | PASS 描述不含证据绑定 | 注明 PASS 绑定 plan+TASK digest，正文修订后旧 PASS 自动失效 |
| `skills/sync/push-progress/SKILL.md` | 不变 | 不变（code Pipeline 新节点只是多一个调用方） |
| §4.5 清单全部文件 | 引用不存在的 canonical 字段 | 按清单修订 |

# 9. 测试设计

## 9.1 基线

远端快照 crctl 测试全绿为前置；本 CR 新增用例全部进 `skills/shared/crctl/scripts/test/crctl.test.mjs`（pipeline 结构测试可独立小文件，复用现有 fixture 机制），Ubuntu/Windows 双跑。

## 9.2 用例矩阵

| 需求 | 用例 |
|---|---|
| FR-02 写入 | review-record dev-plan（pass 轨与 block 轨）annotation 含 `subject-sha256`；独立复算相等；修改 plan / 修改任一 TASK / 增删 TASK 文件 → digest 变化；仅改 `_index.yml` → digest 不变；LF 与 CRLF 检出 → 相同 digest；TASK 集为空 → `SUBJECT_NOT_FOUND` 硬失败且零账本写入 |
| FR-02 next | PASS+fresh → suggest approve-dev-start；PASS+drift/legacy → suggest review-dev-plan；plan 缺失→write-dev-plan；TASK 缺失/为空→write-dev-tasks |
| FR-02 gate | approve-dev-start：fresh → 放行；drift/subject 缺失 → gateBlockers 明确说明 digest 不一致或 subject 不完整且零写入；删除全部 TASK 时 `next` 结构化路由重建 TASK/重审，不抛裸错误 |
| FR-03 | `crMdStatusText`：含 `updated-at` 的旧 frontmatter → 输出仅单一 `updated`；含 `updated` → 刷新；皆无 → 追加；CRLF 输入一致。`owner-set` 后 `updated` 刷新。register/advance/approve 产物不含双字段 |
| FR-01 | code Pipeline JSON 结构断言：节点 id 全局唯一；节点序 review-code < 新 push-progress(…0015) < human_approval(approve-code)；新节点 onFail=abort、ref=push-progress；reviewLoop.replayNodes 未被破坏。release-subjects 回归：仅 KB 白名单后继提交仍可审批；非 KB HEAD 前移、KB 非白名单路径变化或 artifact digest 漂移均拒绝 |
| FR-04 | 三个 CR Pipeline JSON 全文扫描零命中 `repair-instructions`/`fixed-blockers`/`suggestion_policy`；`product-planning.pipeline.json` 不在扫描范围；相关 Skill 同口径扫描；既有 review-record schema 校验用例（SCHEMA_INVALID 等）保持全绿 |
| 回归 | 既有全量测试不回归；requirement/tech-design/code 三阶段 passCondition 行为不变 |

# 10. 实施顺序、回滚与风险

## 10.1 TASK 切分（每 TASK 一个可回滚提交）

1. **T1**：`devPlanCompositeDigest` + review-record dev-plan 写入 + 单测（红→绿）。
2. **T2**：cmdNext 与 runGateChecks 双消费点接入 + 单测。
3. **T3**：`refreshCrMdUpdated` 提取、`crMdStatusText` 与 `editCrOwnerProjection` 接入 + 单测。
4. **T4**：code Pipeline 新 checkpoint 节点 + suggestion_policy 删除 + 结构测试。
5. **T5**：§4.5 全部文本契约修订 + 扫描测试。
6. **T6**：`crctl SKILL.md` / review-dev-plan SKILL 采纳修订（§8），全量双平台回归。

## 10.2 回滚

每个 TASK 独立 commit，按序 revert 即可；digest 字段对旧 reader 不可见即无影响（annotation 多一个键），pipeline 新节点 revert 后恢复现状漏洞但不破坏流程。

## 10.3 风险

| 风险 | 缓解 |
|---|---|
| 当前 tools CR worktree 落后于已合入 CR-2026-038 的 custom/main | T1 前按 §1.3 fast-forward/普通 merge 集成且不改写已发布历史；共享 crctl 文件按功能 seam 集成，code Pipeline 无 CR-2026-038 冲突面 |
| legacy 在途 CR（dev-plan 已 PASS 无 digest）合入后 next 建议重审 | 保守路径是有意设计：一次额外 review-dev-plan 即补齐 digest，无数据迁移；在合并说明中提示 |
| Agent 文档 / README 残留旧字段引用（本 CR 范围外） | 显式归 CR 5；§9.2 扫描测试只覆盖本 CR 范围，不回潮由 CR 5 的 lint 规则承接 |
| suggestion_policy 删除影响既有触发习惯 | 该参数本无实现支撑（strict 为缺省且无升格代码路径），删除不改变任何实际评审行为 |

# 11. 不做事项

- 不新增 CLI 子命令、gate type、错误码、账本或 schema（freshness 判定复用 gate 失败通道与 `SUBJECT_NOT_FOUND`）。
- 不为 requirement/tech-design/code 三阶段改动 digest 逻辑；不动 `product-planning` 合同；不改 merge/writeback/archive/checkpoint 任何算法。
- 不实现缓存、批量迁移、Agent/README 整体收敛（CR 5）、测试执行结构化（CR 3）、traceability 证据（CR 4）。
