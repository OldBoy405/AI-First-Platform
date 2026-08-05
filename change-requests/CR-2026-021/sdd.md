---
id: CR-2026-021-sdd
type: SDD
cr-ref: CR-2026-021
title: prompt 对齐 crctl（写入面补齐 + prompt 收敛 + 漂移防线）技术设计
status: draft
created: "2026-08-05T11:10:00+08:00"
updated: "2026-08-05T11:10:00+08:00"
---

# SDD — prompt 对齐 crctl（写入面补齐 + prompt 收敛 + 漂移防线）

> 目标代码仓 = **tools 仓自身**（改 `crctl.mjs` / `skills/**` / `pipeline-templates/**` / `.githooks/`），按 write-tech-design SKILL Step 1 例外条款，`tools/ARCHITECTURE.md` 是本设计的权威架构判据。

## 0. 事实基线（已核实，纪律 #4）

| 事实 | 位置 / 命令 |
|---|---|
| `crctl.mjs` 刻意单文件（ARCHITECTURE §3、§5），顶层执行 `main()`、零导出；新增子命令应写进本文件的 dispatch，不新开脚本 | `crctl.mjs`；`ARCHITECTURE.md:43,83-89` |
| §8 维护规则明列「crctl 新增写入子命令」为触发 ARCHITECTURE.md 修订的变更之一——本 CR 属之，SDD 含配套修订项 | `ARCHITECTURE.md:108` |
| `casWrite(p, expectedHash, newText)`：写前重读文件、`sha256(cur)!==expectedHash` 即 `fail('CAS_CONFLICT')`，**无重试**，重试是调用方责任 | `crctl.mjs:677-682` |
| `casWriteMulti(writes)`：三阶段（全校验 sha256 → 全写 `.tmp-{pid}` → 连续 rename），任一 hash 失配则两侧均不落盘；`expectedHash==null` 语义为「期望目标不存在」，存在即 `CAS_CONFLICT`（创建冲突） | `crctl.mjs:691-705` |
| 门禁唯一事实源 = `dir-graph.yaml` 状态机 + `skills/shared/crctl/gates.json`，经 `crctl gate --for <status>` 执行；**pipeline JSON 不承载门禁** | `ARCHITECTURE.md:26,45-47`；`crctl.test.mjs:177,389` |
| `feature-writeback.pipeline.json` 节点字段仅 `id/kind/label/ref/prompt/onFail/timeoutMinutes`——**无 `passCondition`/`gate`/`precondition` 字段**；前置校验写在自然语言 prompt 里、失败靠 `onFail:"abort"` | `feature-writeback.pipeline.json` nodes[]（node-1:39 ~ node-5:75） |
| 「cr-guard」在仓内的真实存在 = CI 适配器模板 `skills/shared/crctl/adapters/ci/cr-guard.template.yml`（CI 侧远端复核），**不是** pipeline 节点 | `skills/shared/crctl/adapters/ci/cr-guard.template.yml`；`ARCHITECTURE.md:61-63` |
| pre-commit 钩子现状：两行 `node .../check-skill-matrix.mjs \|\| exit 1` + `check-agents-contract.mjs \|\| exit 1`；lint 类检查器落点 = `skills/shared/crctl/scripts/` | `.githooks/pre-commit:4-5` |
| CAS 冲突**黑盒（spawnSync 调 CLI）无法注入读后改时序**；既有范式为组件级——正则抽出 `casWriteMulti` 函数体 + 注入 stub `readFileChecked`/`sha256`/`fs`、令一侧 hash 失配触发 | `crctl.test.mjs:730-731,924-961` |
| 前置态非法测试统一手法：`status===1` + 结构化 `error.code`（如 `ILLEGAL_LEDGER_STATE`/`CR_STATUS_TRANSITION_NOT_ALLOWED`）+ `after===before` 文件快照 | `crctl.test.mjs:809-820,863-873,912-922` |
| 测试基建：`makeWorkspace()`(mkdtemp+`change-requests/`)、`writeCrEntry()`(`_backlog`+`cr.md` 一致)、`runCrctl()`(spawnSync+JSON)，`try/finally` 清理 | `crctl.test.mjs:26-40,105-108` |
| **tools 包无自有 semver**：无根 `package.json`、无 VERSION/CHANGELOG、无 git tag；仓内 `v0.14~v0.16` 均为**使用方产品** target_version（`product-planning-agent.md:105-106` 规划到 v0.15.0；pipeline `placeholder:"v0.16.0"` 仅占位） | 仓根；`product-planning-agent.md:105-106`；`feature-writeback.pipeline.json:30` |
| review-annotations stage→文件名映射（门禁读取口径）：`requirement`→`requirement.yml`、`tech-design`→`sdd.yml`、`code`→`code.yml` | `crctl.mjs:1230,1524,1534,1549/1554`（PRD §1.3 已核实） |
| 硬不变量约束本设计：①状态单一写者(advance)②账本单一通道(crctl CAS+审计)③零第三方依赖④CRLF 归一+硬失败⑥git 权威 outbox 投影⑦人工审批无旁路 | `ARCHITECTURE.md:79-89` |

## 1. 架构概览

### 1.1 落点与模块边界

本 CR **不新增独立可执行库**，两类新代码各有归属：

```
tools/
├── skills/shared/crctl/scripts/
│   ├── crctl.mjs                 # ★ 扩：+9 写子命令 +2 只读子命令 +1 git commit 分支（写进现有 dispatch，单文件不拆）
│   ├── lint-prompts.mjs          # ★ 新增检查器（非账本脚本，类比 check-agents-contract.mjs）
│   └── test/
│       ├── crctl.test.mjs        # ★ 扩：新子命令用例（黑盒 + 组件级 CAS）
│       └── lint-prompts.test.mjs # ★ 新增：R1~R6 fixture + ignore 豁免用例
├── skills/{requirement,develop,cr,...}/**/SKILL.md   # 改：prompt 收敛为调 crctl（Phase 1~4）
├── pipeline-templates/*.json                          # 改：node prompt 口径修正（Phase 1/4）
├── skills/shared/crctl/adapters/ci/cr-guard.template.yml  # 改：CI 侧接 lint-prompts --enforce（FR-24 硬门禁真实挂点）
├── .githooks/pre-commit                               # 改：+1 行 lint-prompts（分阶段 report→enforce）
└── ARCHITECTURE.md                                    # 改：§3 代码地图 + §8 触发记录（新增写子命令）
```

**为什么新子命令写进 crctl.mjs 而非新脚本**（不变量 2 + §5 单文件哲学）：它们是账本/受控文件的写入,必须与既有 `advance`/`approve`/`task done` 共用同一条「状态机 + CAS + `.crctl/audit.log` 审计」写入路径。另开脚本 = ARCHITECTURE §6 明否的「第二条账本写入通道」。单文件体量增长是刻意接受的代价（改动即全貌可见）。

**为什么 lint-prompts.mjs 是新脚本而非 crctl 子命令**：它**只读** `SKILL.md`/pipeline JSON + `rules.json`/`crctl.mjs`,不写任何账本/受控文件,是**检查器**（与 `check-skill-matrix.mjs`/`check-agents-contract.mjs` 同类同目录）,不触碰不变量 2 的写入通道,故不撞 §6「否决独立**账本操作**脚本库」（否决对象是账本写入,不是只读校验）。

### 1.2 依赖方向（合 ARCHITECTURE §4，只朝下）

```
Pipeline → SKILL(prompt 收敛后调 crctl) → crctl.mjs(受控文件唯一写者) → 账本/受控文件
                                        └→ lint-prompts.mjs(只读 SKILL/pipeline/rules.json) → 报告(不写)
pre-commit / CI cr-guard → lint-prompts.mjs（gate）
```

### 1.3 不变量合规自查（评审重点）

| 不变量 | 本 CR 相关点 | 合规论证 |
|---|---|---|
| ①状态单一写者 | S5 `backlog-set` | 白名单硬拒 `status`（§3），状态仍只经 `advance` |
| ②账本单一通道 | S1~S8 + inbox-emit | 全部走 crctl 子命令 + CAS + 审计,无旁路 |
| ③零第三方依赖 | 新子命令 + lint-prompts | 仅 Node 内建;lint-prompts 用行级正则读 SKILL/JSON,不引 YAML 库 |
| ④CRLF+硬失败 | review-record 解析 payload、lint-prompts 扫 prompt | 读入先 `replaceAll('\r\n','\n')`,解析失败 `fail()` 不静默 |
| ⑥git 权威 | 各写子命令 | 复用既有 `emitOutboxEvent`,失败只记审计不阻塞 |
| ⑦审批无旁路 | S2 `review-note` | 只写 `approval.yml#supplemental-reviews[]`,**不碰** `#requirement/#code` 审批段（那仍只经 `crctl approve` TTY） |

## 2. 数据模型

### 2.1 guard-deny 面 ↔ crctl 写入面（本 CR 后闭合）

| 受控文件 / 字段（guard deny） | 本 CR 前写口 | 本 CR 后写口 |
|---|---|---|
| `review-annotations/{stage}.yml` | 无（孤儿） | **S1 review-record** |
| `approval.yml#supplemental-reviews[]` | 无（孤儿） | **S2 review-note** |
| `_backlog#checkpoints/remote-ref/last-push*` | 无（孤儿） | **S3 checkpoint-add** |
| `_backlog#owners.{role}` | 无（孤儿） | **S4 owner-set** |
| `_backlog#prd-path/sdd-path` | 无（孤儿） | **S5 backlog-set** |
| `_backlog#notify-log/notify-pending` | 无（孤儿） | **inbox-emit** |
| `cr.md`（首次建档）+ `_backlog`/`_index` 登记 | 无（手写 frontmatter） | **S8 cr-init**（原子） |
| `tasks/_index.yml`（TASK-ID 分配） | 无 CAS（手算） | **S7 task allocate** |

### 2.2 review-record payload schema（S1，判断/写入分离）

agent 判断落**非受控**临时路径 `.crctl/tmp/review-{stage}.yml`（`.gitignore` 补 `.crctl/tmp/`），crctl 校验后写 canonical。payload 必填结构（校验失败 `SCHEMA_INVALID` 非零退出、不写）：

```yaml
verdict: pass | block              # 枚举,其它值拒
blockers: []                       # 必须是列表(可空);block 时非空
dimensions: {结构完整性: ..., ...}  # 该 stage 门禁要求的维度齐全
suggestions: []                    # 可选
```

canonical 目标由 stage 显式映射（**非同名**,`tech-design`→`sdd.yml`）。写入含 crctl 生成的 `reviewer=identity(ws)`/`reviewed-at=nowIso()`。

### 2.3 分配即写入（S6/S7/S8 的并发安全模型）

CR-ID / TASK-ID 的「不撞号」不来自「读时抢占」,而来自**写时 CAS**：

- **S6 next-cr-id = 只读预览**：扫 `_index.yml`/`_backlog.yml` 现有 max、返回 `CR-{Y}-{NNN+1}` 候选。**不写文件、非权威**——两个并发调用会返回同一候选（不保证唯一）。仅供 prompt/人预览下一个号,不作为登记依据。
- **S8 cr-init = 权威原子分配**：以 `casWriteMulti` 一次写 `cr.md`(新建,`expectedHash==null`)+`_backlog`(追加条目)+`_index`(登记),`expectedHash` 取读时 sha256。并发下第二个写者见 `_index`/`_backlog` hash 已变 → `CAS_CONFLICT`,两侧不落盘 → 调用方(requirement-register SKILL)重跑 cr-init(重读 max、拿新号)。**与 crctl「无内部重试」惯例一致**（§0：重试是调用方责任）,不在 crctl 内加 retry 循环、不引 WAL（合 §6 YAGNI）。
- **S7 task allocate** 同理：以 `casWrite` 写 `tasks/_index.yml`,冲突即 `CAS_CONFLICT` 由调用方重跑。

## 3. 接口契约（CLI）

统一：时间戳/操作者身份一律 crctl 生成（`nowIso()`/`identity(ws)`),拒绝调用方传入；输出 JSON,退出码 0=成功、非 0=结构化 `error.code`。

### 3.1 写子命令（9）

```
crctl review-record <cr> --stage <requirement|tech-design|code> --from <payload.yml> [--bump-attempt]
crctl review-note   <cr> [--stage <s>] --note <text>                 # 追加 supplemental-reviews[];无 --by
crctl checkpoint-add <cr> --repo <r> --sha <sha> [--remote-ref <ref>]
crctl owner-set     <cr> --role <requirement|development|test> --id <id>   # --id=被指派人(业务数据),非操作者身份
crctl backlog-set   <cr> --field <prd-path|sdd-path> --value <v>     # 白名单标量;硬拒 status/updated-at/owners/merge-commits
crctl inbox-emit    <cr> --event <...>                                # notify-log 事件追加
crctl next-cr-id    [--year Y]                                        # 只读预览(§2.3),不写
crctl cr-init       <cr-id> --title <t> --owner-requirement <id>     # 原子 casWriteMulti 建档+登记
crctl task allocate <cr> [--slug <s>]                                # 扩展现有 task 族;CAS 写 tasks/_index.yml
```

### 3.2 只读子命令（2）+ git 扩展（1）

```
crctl worktree-path <cr> --repo <r>            # 派生 bucket/path,不写,无 CAS
crctl report | crctl cr-metrics [--period P]   # 跨 CR 聚合,只读
crctl git commit --template <register|task-breakdown|writeback|...>   # 现有 git commit 加格式化分支,非新顶层命令
```

### 3.3 lint-prompts（检查器）

```
node skills/shared/crctl/scripts/lint-prompts.mjs [--mode report|enforce] [--json]
```

- `--mode report`（Phase 0~2 默认）：打印 `file:line + 规则 + 级别`,**退出 0**（不阻断提交）。
- `--mode enforce`（Phase 3 漂移清零后 pre-commit 切换 / CI cr-guard 恒用）：命中 CONTRADICTS/STALE-REF 即**退出 1**。
- 段落级豁免：命中处附近有 `<!-- lint-prompts:ignore -->` 则跳过该段。

### 3.4 错误码（新增,风格同既有 fail()）

`SCHEMA_INVALID`(payload 校验失败) / `STAGE_UNKNOWN` / `FIELD_NOT_ALLOWED`(backlog-set 白名单外) / `CAS_CONFLICT`(复用) / `ILLEGAL_LEDGER_STATE`(前置态非法,复用) / `CR_ALREADY_EXISTS`(cr-init 撞已存在) / `LINT_DRIFT`(lint-prompts enforce 命中)。

## 4. 关键算法与流程

### 4.1 review-record（S1，判断/写入分离）

```
读 .crctl/tmp/review-{stage}.yml → CRLF 归一 → schema 校验(verdict 枚举/blockers 列表/dimensions 齐全)
  失败 → SCHEMA_INVALID(不写)
stage → canonical 文件名显式映射(requirement→requirement.yml / tech-design→sdd.yml / code→code.yml)
  未知 → STAGE_UNKNOWN
注入 reviewer=identity(ws)/reviewed-at=nowIso() → casWrite(canonical, sha256(读时), 新内容)
[--bump-attempt] → 级联现有 attempt 记账逻辑
成功 → 删除 .crctl/tmp/review-{stage}.yml(避免残留/跨 CR 串味) → emitOutbox
```

### 4.2 cr-init 原子分配（S8，回应 next-cr-id 并发安全）

```
读 _index.yml/_backlog.yml → 计算候选 CR-ID(或采用入参 cr-id) → 校验该 id 尚不存在(否则 CR_ALREADY_EXISTS)
构造三文件新内容(cr.md 全量 frontmatter: owners/owner-history/时间戳全 crctl 生成)
casWriteMulti([
  {path: cr.md,     expectedHash: null},        # 期望不存在
  {path: _backlog,  expectedHash: sha256(读时)}, # 追加条目
  {path: _index,    expectedHash: sha256(读时)}, # 登记
])
  CAS_CONFLICT → 两侧不落盘,返回错误 → 调用方 SKILL 重跑(重读 max)
```

### 4.3 lint-prompts R1~R6（检测算法）

```
载入判据: rules.json#protectedPaths.deny(R1 面) + rules.json#git(R2) + 字面黑名单(R3 cr-status-set / R4 六字段口径)
遍历 skills/**/SKILL.md + pipeline-templates/*.json:
  按段落切分(标题/JSON node 边界) → 段内若含 <!-- lint-prompts:ignore --> → skip
  R1: 段内出现 write/create/编辑 + deny 文件名,且**同段无** crctl <cmd> 调用 → CONTRADICTS(邻近判定,避免"解释为何不该手写"误报)
  R2: `git <sub>` 字面且非 `crctl git` → CONTRADICTS
  R3: 出现 `cr-status-set` → STALE-REF
  R4: `source-sha`/`merged-at`/"六字段"作为必填 → CONTRADICTS
  R5: `review-loop.current-attempt`/`attempts[]` + 写动词 → OUTDATED
  R6: `test-report.md` + 手写 `status:`/`commands:` → CONTRADICTS
命中输出 file:line+规则+级别; --mode enforce 且有 CONTRADICTS/STALE-REF → exit 1
```

R1 判据直读 `rules.json`——未来 deny 面新增文件,R1 自动覆盖,无需改 linter（判据零派生物,NFR-6）。

### 4.4 FR-24 两层 gate 分阶段启用（回应 REQ-BLOCK-001）

| 阶段 | pre-commit | CI cr-guard.template.yml | 效果 |
|---|---|---|---|
| Phase 0~2 | `lint-prompts --mode report`（exit 0） | 未接入 | 本 CR 自身开发期 commit 不被存量漂移阻断 |
| Phase 3 起 | 切 `--mode enforce`（exit 1） | 接入 `--mode enforce` | 漂移提交不进来 + CI 远端兜底 |

归档硬门禁的**真实挂点是 CI cr-guard 适配器**,不是 pipeline passCondition（§0 已核实其不存在）；`cr-archive` 节点 prompt 另加一句软提醒(与 node-1 "校验 status 否则 abort" 同形态)。

## 5. 技术选型与替代方案

| 决策 | 选择 | 已否决的替代及理由 |
|---|---|---|
| 新子命令落点 | 写进 crctl.mjs 单文件 | 新独立脚本：撞 §6 第二写入通道否决 + 破坏单文件不变量 |
| lint-prompts 落点 | 独立检查器 `scripts/lint-prompts.mjs` | 做成 crctl 子命令：它只读、不写账本,塞进 crctl 反而混淆「写者」职责 |
| CR-ID 并发安全 | 分配即写(cr-init casWriteMulti,调用方重试) | next-cr-id 读时抢占：纯读不可能防撞号(§2.3);crctl 内 retry 循环：违「无内部重试」惯例;WAL/2PC：§6 YAGNI 否决 |
| 归档 lint gate 挂点 | CI cr-guard 适配器(enforce) + cr-archive prompt(软) | pipeline passCondition：**字段不存在**(§0);硬塞 gates.json：gates.json 是声明式 path/equals 判据,容不下"跑脚本"语义 |
| gate 启用时序 | 分阶段 report→enforce | Phase 0 即 enforce：拦死本 CR 自身开发期 commit(REQ-BLOCK-001) |
| CAS 冲突测试 | 组件级抽函数注入 mismatch hash | 黑盒并发注入：spawnSync 无法注入读后改时序(§0,测试文件自注);篡改真文件走 CLI：不可靠 |
| 通用写入 | 仅 purpose-specific 白名单子命令 | `crctl patch <file> <path> <val>`：万能逃生口,绕过语义/前置/schema 门禁(PRD NFR-3) |

## 6. FR → 技术实现映射

| FR | 实现 | 验收对齐 |
|---|---|---|
| FR-1 review-record | §4.1 + §2.2 payload schema + stage 显式映射 | AC-1(含临时文件删除) |
| FR-2 review-note | §3.1;只写 supplemental-reviews,身份 crctl 生成 | AC-2(拒 --by) |
| FR-3/4/5/6 | §3.1 各子命令 + `_backlog` 定向字段 casWrite | AC-3(backlog-set 硬拒 status) |
| FR-7 next-cr-id+cr-init | §2.3 + §4.2 分配即写,合并实现共享 casWriteMulti | AC-4(并发不撞号:组件级测) |
| FR-8 task allocate | §2.3 casWrite tasks/_index.yml | AC-5 |
| FR-9/10/11 | §3.2 只读派生 + git commit --template | AC-6 |
| FR-12 D13 溯源 | Phase 0 门槛调查,结论二选一(§1.7 PRD);**本 SDD 不预判路线**,调查产出后若"复活"再补设计小节 | AC-7(结论入 SDD) |
| FR-13 文档+白名单 | ARCHITECTURE §3/§8 修订(§9)、`crctl help`、rules.json#git 补 shape | AC-8 |
| FR-14~17 Phase 1 | prompt 改口径(见下 §6.1) | AC-9 |
| FR-18 Phase 2 | cr-status-set 清退(见 §6.1) | AC-10 |
| **FR-19 Phase 3（拆到任务级,回应 suggestion-4,见 §6.1）** | 13 处改点逐条列 | AC-11 |
| FR-20~22 Phase 4 | 状态映射去重 + 工时措辞 + brief 补齐 | AC-12 |
| FR-23 lint-prompts | §4.3 R1~R6 | AC-13(fixture+ignore) |
| FR-24 两层 gate | §4.4 分阶段 | AC-14(Phase0~2 不阻断) |
| FR-25 回写清单项 | feature-writeback 回写清单模板 + SDD「prompt 采纳影响」强制小节 | AC-15 |

### 6.1 FR-19 Phase 3 改点清单（suggestion-4：单条巨型 FR 拆到任务级）

| # | 文件:锚点 | 现状 | 改为(子命令) | Phase |
|---|---|---|---|---|
| P3-01 | review-code / review-tech-design / review-requirement | 直接 Write review-annotations + 手写 review-loop | S1 review-record --bump-attempt | 3 |
| P3-02 | write-test-report | 手写 review-loop 进 traceability | crctl attempt(既有) | 1/3 |
| P3-03 | cr-review-record:53-54 | 写 approval supplemental + reject/withdraw | S2 review-note + advance | 3 |
| P3-04 | handover-cr:66-68 / resume-from-remote:86 | 手改 owners | S4 owner-set | 3 |
| P3-05 | push-progress:63-77 | 手写 remote-ref/checkpoints | S3 checkpoint-add | 3 |
| P3-06 | write-requirement-prd:87-89 | 手改 prd-path | S5 backlog-set --field prd-path | 3 |
| P3-07 | inbox-emit | 手写 notify-log | inbox-emit | 3 |
| P3-08 | requirement-register:48 | 手算 CR-ID max+1 无 CAS | S6 next-cr-id(预览) + S8 cr-init(权威) | 3 |
| P3-09 | write-dev-tasks:45,64 | 手动分配 TASK-ID + slug | S7 task allocate | 3 |
| P3-10 | requirement-register:53-97 | 手写整份 cr.md frontmatter | S8 cr-init | 3 |
| P3-11 | requirement-register:127-133 / merge-feature-branch / push-progress / resume-from-remote | prose 重复拼 worktree path | S9 worktree-path | 3 |
| P3-12 | requirement-register:114 / write-dev-tasks:80 / writeback-traceability:75 | prose 拼 commit message | S10 git commit --template | 3 |
| P3-13 | cr-dashboard / spec-dashboard Step 2 | 手动统计 | S11 report/cr-metrics | 3 |

Phase 1 独立改点：P1-a D7 merge-commits 3 字段(`writeback-traceability` + pipeline node-4)、P1-b approve-* 折叠 crctl approve、P1-c 裸 git→crctl git(先核 rules.json#git shape,`ls-remote` 反例)、P1-d test-report frontmatter 交 crctl test。Phase 2：cr-status-set legacy 化 + 7 处引用改 advance + cr-archive 删手写 _index/status。

## 7. 安全与性能考量

- **信任边界 / 审批无旁路（不变量 7）**：S2 review-note 仅追加 `supplemental-reviews[]`,SDD 与实现均**不得**让任何新子命令写 `approval.yml#requirement/#tech-design/#dev-start/#code`——那四段只经 `crctl approve` TTY/Ed25519（AC：grep 新子命令实现无对这四段的写路径）。
- **guard-deny 闭合**：本 CR 后 `rules.json#protectedPaths.deny` 每类文件都有对应 crctl 写口(§2.1),消除"锁死但无出口"孤儿态。
- **失败安全**：写子命令一律「先在内存构造全部新内容 → schema/前置校验通过 → 才 casWrite」,前置态非法/schema 失败均硬失败不落盘(§0 前置态测试范式)。
- **CRLF/硬失败（不变量 4）**：review-record 读 payload、lint-prompts 扫 prompt 均先 `\r\n→\n`,解析失败 `fail()` 不静默降级。
- **性能**：目标文件（_backlog/_index/SKILL.md）均 <1000 行,同步一次性读写,无性能敏感点；lint-prompts 全仓扫 ~60 SKILL + 8 pipeline,单次遍历,pre-commit 可接受。

## 8. 与已审批 PRD 的偏差记录（供 review-tech-design 与人工审批确认）

| # | PRD 原文 | SDD 决策 | 理由 |
|---|---|---|---|
| D1 | FR-24：接「feature-writeback 的 cr-guard(或归档前 passCondition)」 | 归档硬门禁挂 **CI cr-guard 适配器 `adapters/ci/cr-guard.template.yml`**（+ cr-archive prompt 软提醒）;pipeline **无 passCondition 字段**（§0 核实） | PRD 措辞把两个不同层混为一物：pipeline JSON 不承载门禁,真实"cr-guard"是 CI 适配器。功能意图(归档前 lint 必过)不变,落点纠正 |
| D2 | FR-7：next-cr-id「CAS 保护抢占式分配、并发失败重试不撞号」 | next-cr-id **降为只读预览(非权威)**;抢占/防撞号由 **cr-init 的 casWriteMulti + 调用方重试**承担（§2.3/§4.2） | 纯读命令不可能"CAS 保护抢占"——两并发读同一 max 必撞;防撞号的唯一正确位置是写时 CAS。功能意图(不撞号)不变,机制归位 |
| D3 | PRD frontmatter `target-version: tbd`（需求评审 suggestion-1：建议定版本号） | **决策：保持不绑产品版本,以治理里程碑 T1.3 追踪**（回应 suggestion-1） | tools 包无自有 semver(§0);仓内 v0.15/v0.16 是**产品** target_version,强套会污染产品 spec 追溯。本 CR 是 tools 治理链改动,不并入产品 v0.x 线,与 CR-2026-019(T1.1)/020(T1.2) 同一治理里程碑序列 |

**其余 3 条需求评审 suggestion 落实位置**：suggestion-2(cr-guard 挂点确证)→ §0 + §8-D1 已确证并纠正;suggestion-3(CAS 冲突测试构造)→ §5 + §0 定为组件级抽函数注入 mismatch hash;suggestion-4(FR-19 拆任务级)→ §6.1 十三行改点表。

## 9. 参与仓与交付物清单 + ARCHITECTURE.md 修订

| 仓 | 交付物 |
|---|---|
| tools（trunk=custom/main） | crctl.mjs 扩(+9 写 +2 读 +1 git 分支);`lint-prompts.mjs` + `lint-prompts.test.mjs`;`crctl.test.mjs` 扩;`.githooks/pre-commit` +1 行;`adapters/ci/cr-guard.template.yml` 接 lint;20+ SKILL.md + pipeline JSON prompt 收敛;`rules.json#git` 补 shape;`ARCHITECTURE.md` 修订;`crctl help`/`skills/_index.yml` brief 补齐 |
| knowledge-base（trunk=master） | 本 CR 产物(prd/sdd/tasks/评审记录) |
| multica | 不参与（无代码改动,空分支跳过） |

**ARCHITECTURE.md 修订项**（§8 维护规则触发「crctl 新增写入子命令」,随本次评审确认）：
- §3 代码地图 `crctl.mjs` 条目补：写入子命令族扩至覆盖 review-annotations/approval supplemental/_backlog 非 status 字段/CR-TASK-ID 分配/首次建档;新增 `scripts/lint-prompts.mjs` 检查器条目（职责 = prompt↔crctl 漂移检测,只读非账本）。
- §7 横切「测试」补 lint-prompts 回归入口。
- **不改不变量条款**（本 CR 全部合现有不变量,§1.3 已逐条论证）——仅登记新增能力面,不动 §5/§6 判据。
