# tools 包 prompt 过时/冗余审计（对齐 crctl 现状）

> 对象：phase0-tools（`C:/Users/GOBAO/Downloads/AI/tools`，`custom/main`）的 SKILL.md 与 pipeline JSON prompt
> 方法：以 crctl 实际强制的门禁/子命令 + CR-2026-019/020 交付的能力为基线，三片并行逐行审读（develop / requirement+cr / writeback+sync+pipeline）+ 主仓侧 grep 核验
> 日期：2026-08-05　　范围：只读审计，未改动任何文件
> 判定分级：`CONTRADICTS`（prompt 教的动作会被工具/guard 当场拦截或产生错误，必改）＞ `OUTDATED`（教手动做工具已做的事）＞ `REDUNDANT`（工具已强制，prompt 重复叙述，可精简）＞ `STALE-REF`（引用已被取代的机制/漏更的清单）

---

## 结论先行

**根因一句话：`ARCHITECTURE.md` 已经把规矩立对了（§4 不变量 2 明写"不得在 Skill 文档里描述账本文件的手工编辑步骤"、§3 已记 CR-2026-020 脚本），但一批 SKILL prompt 停留在 crctl 子命令/门禁/PreToolUse guard 落地之前的写法，集体滞后于文档。** 跑 ARCHITECTURE 自己规定的一致性 grep 就能把违规点炸出来。

按严重度，5 类问题：

| 主题 | 级别 | 涉及文件数 | 一句话 |
|---|---|---|---|
| A. `approve-*` 手写 approval.yml | **CONTRADICTS** | 5 | approval.yml 被 PreToolUse guard **deny**，crctl approve 独占写，prompt 教的手写会被拦 |
| B. `cr-status-set` 整体被架空 | **STALE-REF（系统性）** | 8+ | 它直接写 cr.md（guard deny），被 `crctl advance` 取代；全仓引用都指向死机制 |
| C. 裸 git 未走 controlled-shell | **CONTRADICTS** | 6 | guard line 127 deny 裸 git；一批 SKILL 仍写 `git add/commit` |
| D. merge-commits 6 字段契约分叉 | **CONTRADICTS（最新最紧）** | 2 | 校验 6 字段但生产者只写 3，**每个 CR 回写都会 MERGE_COMMITS_MISSING** |
| E. write-test-report 手写 frontmatter + review-loop 手写 | **CONTRADICTS/OUTDATED** | 3 | frontmatter 应 `crctl test` 生成、轮次应 `crctl attempt` |

外加两类轻的：F. 工具已兜底的冗余 prose（`--spec-id`/worktree/status 映射），G. 文档自身 staleness（`_index.yml` crctl brief 漏子命令、AGENTS.md #6 警告的 cp 危害已消除）。

**好消息**：AGENTS.md #6 最担心的 `cp` 覆盖基线——在 `writeback-prd-sdd` SKILL 里**已经不存在**，该 SKILL 已完成 CR-2026-020 脚本化改造。`implement-code`、`requirement-register`、只读查询类 skill 都是干净的正面样例。

---

## 主题 A — `approve-*` 手写 approval.yml（CONTRADICTS，必改）

approval.yml 现在是 `crctl approve`（TTY 人类 / --grant 签名）**唯一写者**：它自校验证据 pass-condition、算 canonical evidence-digest、写 approval.yml 段、级联 advance。adapters 的 **PreToolUse guard 直接 deny** 对 approval.yml 的 Write/Edit。以下 prompt 教的手写动作会被当场拦截：

| 文件:行 | 原文（摘） | 建议 |
|---|---|---|
| `develop/approve-code/SKILL.md:31-42` | 写入或更新 approval.yml 的 `code` 段 + 整段 YAML | 删手写 YAML，改"运行 `crctl approve --stage code`（TTY）" |
| `develop/approve-code/SKILL.md:29` | 不一致必须在 approval.yml 记录偏差 | 偏差走 crctl approve notes，不由模型落 approval.yml |
| `develop/approve-code/SKILL.md:55` | cr-status-set 失败→回滚 approval.yml 修改 | 删（模型从不写 approval.yml，无可回滚） |
| `develop/approve-tech-design/SKILL.md:28-38` | 写入或更新 approval.yml 的 tech-design 段 | → `crctl approve --stage tech-design` |
| `develop/approve-tech-design/SKILL.md:49` | cr-status-set 失败→回滚 approval.yml | 删 |
| `develop/approve-dev-start/SKILL.md:41-52` | 在 approval.yml 写入 development-start 段 | → `crctl approve --stage dev-start` |
| `requirement/approve-requirement/SKILL.md:3,25,38-51,63,83` | description + Step 2/3 写 approval.yml + 手改 cr.md status + 回滚 | 整体折叠为 `crctl approve --stage requirement` |
| `cr/cr-review-record/SKILL.md:15,41-52` | 写入/更新 approval.yml 的 `supplemental-reviews` 段 | **见主题 F**（crctl 无补充审查写入口，核心动作无合法落点） |

> pipeline 侧（architecture node-4、code node-5/node-11、requirement node-6）的"写 approval.yml"是**委托给 approve-* skill 执行**，本身不直接教会话手写——不判 CONTRADICTS，但它们继承了上面 skill 的问题，随 skill 一并修复即可。

## 主题 B — `cr-status-set` 整体被架空（STALE-REF，系统性）

`cr/cr-status-set/SKILL.md` 自我定位为"状态机中心校验与写入点"，其 Step 4 **直接写 cr.md frontmatter**——正是 PreToolUse guard 现在 deny 的写入，且它只校验 state_machine 转换、**不跑 gates.json 门禁**。真实的中心推进入口是 `crctl advance`（状态机 + 门禁 + CAS + outbox 一体）。

因此以下"调用 cr-status-set 推进状态"的引用都指向已被取代的机制（不是改名，是换机制）：

| 文件:行 | 建议改为 |
|---|---|
| `approve-code:44` / `approve-tech-design:40` / `approve-dev-start:53` | 删独立推进步骤（`crctl approve` 已级联 advance） |
| `review-code:132-133` / `review-tech-design:95` / `review-requirement:111` | `crctl advance --to … --trigger … --expect …` |
| `write-dev-tasks:79` | `crctl advance --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed` |
| `cr-review-record:53-54`（reject/withdraw） | `crctl advance` |
| `cr-status-set/SKILL.md:15-17,63`（自身） | 标注 **legacy/deprecated**，正文改述为"状态推进见 crctl advance" |

## 主题 C — 裸 git 未走 controlled-shell（CONTRADICTS）

guard line 127 deny 裸 git；一切 git 须经 controlled-shell（`crctl git <sub> --cwd`）。sync/merge 类 SKILL 已用 runGit，但以下仍写字面 `git`：

| 文件:行 | 原文 |
|---|---|
| `develop/review-code/SKILL.md:37-42` | 裸 `git merge-base` / `git diff` / `git log` |
| `develop/write-dev-plan/SKILL.md:58-60` | `git commit -m "feat(...): draft dev plan"` |
| `develop/write-dev-tasks/SKILL.md:81` | `git commit -m "feat(...): task breakdown"` |
| `writeback/writeback-prd-sdd/SKILL.md:59-62` | `git add specs/... ; git commit` |
| `writeback/writeback-tasks/SKILL.md:54-57` | `git add delivery/task/ ; git commit` |
| `writeback/writeback-traceability/SKILL.md:73-76` | `git add ...traceability.yml ; git commit` |
| `pipeline resume-cr node-1（0014-…0001）:40` | prompt 内嵌 `git ls-remote --heads origin 'requirement/...'` 字面 |

建议：统一改走 `crctl git` / controlled-shell runGit，与 sync/merge SKILL 约定一致。

## 主题 D — merge-commits 6 字段契约分叉（CONTRADICTS，最新最紧，与本次 FR-8 直接相关）

`crctl merge-metadata`（及 merge-feature-branch:156）现在只写 **`{repo,trunk,sha}`**（branch 由 crctl 自动补，本次 FR-8）。但下游校验仍要求 6 字段——**按现基线每个 CR 回写都会 `MERGE_COMMITS_MISSING` 硬失败**（这正是 CR-2026-020 那 ~6min bug 的 prompt 侧残留，脚本侧已修、prompt 侧未跟上）：

| 文件:行 | 原文（摘） | 建议 |
|---|---|---|
| `writeback/writeback-traceability/SKILL.md:107` | 校验六字段 repo/trunk/sha/branch/source-sha/merged-at 齐全 | 降为 `{repo,trunk,sha}` 必填，branch 可选 |
| `writeback/writeback-traceability/SKILL.md:84,120` | "脚本已强制六字段齐全" / "字段不齐全" | 口径改 3 字段 |
| `writeback/merge-feature-branch/SKILL.md:156` | branch "按需扩展" | 注明 branch 由 crctl 自动注入 |
| `pipeline feature-writeback node-4（0013-…0004）:67` | "六字段齐全校验，缺失 MERGE_COMMITS_MISSING" | 改三字段校验 |

## 主题 E — 测试报告与 review-loop 手写（CONTRADICTS / OUTDATED）

- **`write-test-report/SKILL.md:51-84`（CONTRADICTS）**：Step 3 手写 test-report.md 的 frontmatter（`status: pass|block`、commands）。guard line 139 要求走 `crctl test`；crctl test 按**真实退出码**生成 status/commands，文件明写"模型不得改写"，仅 `<!-- crctl:analysis-below -->` 以下允许人工补分析。→ frontmatter 交 crctl test，模型只写分析段。
- **review-loop 轮次手写（OUTDATED）**：`write-test-report:66-81,108-124`、`review-code:131`、`review-tech-design:93` 手动持久化 `review-loop.current-attempt`/`attempts[]` 到 traceability。→ 轮次唯一记账点是 `crctl attempt <cr> --loop`。
- **`review-code:44-50`（REDUNDANT）**：直接 `pnpm lint/test/build` 当评审证据。→ 优先读 `crctl test` 生成的 test-report.md，缺失才补跑（且经 controlled-shell）。
- **`writeback-tasks/SKILL.md:3,16`（OUTDATED 措辞）**：description 说"全量重建全局 _index.yaml"，但脚本实为"保留既有条目 + 只构造新条目"（同文件 line 78 已如此描述）。→ 措辞改"保留既有+追加"，与 CODE-BLOCK-001 修复口径统一。

## 主题 F — 手动账本编辑但 crctl 无对应子命令（需决策，不是简单改 prompt）

这几处手改 `_backlog.yml` 字段，crctl **没有**对应子命令、且**不在** guard deny 名单，但擦到 AGENTS.md #7"账本禁手写"边界。需要一个决策：**要么 crctl 补 field-patch 子命令，要么明确它们是合法例外并在 prompt 标注**。

| 文件:行 | 手改字段 | crctl 现状 |
|---|---|---|
| `cr/cr-review-record/SKILL.md:41-52` | approval.yml `supplemental-reviews` | crctl approve 无补充审查入口——**核心动作无合法落点**，建议改落 review-annotations |
| `requirement/write-requirement-prd/SKILL.md:87-89` | `_backlog` 的 `prd-path` | 无子命令（正是上一轮手工补过的字段） |
| `sync/handover-cr:66-68` / `sync/resume-from-remote:86` | `_backlog` 的 `owners.{role}` | 无 owner 子命令 |
| `sync/push-progress:63-77` | `_backlog` 的 `remote-ref/last-push-at/checkpoints[]` | 无 checkpoint 子命令 |
| `cr/cr-archive/SKILL.md:84-93` | 手动更新 `_index.yml`（Step 5） | **半迁移遗留**：Step 3 已用 `crctl archive-move`（它一并更新 index），Step 5 属重复+违反 #7，**直接删** |
| `cr/cr-archive/SKILL.md:54,92` | 手改 cr.md status；Step1 cr-status-set | → `crctl advance --to archived --spec-id ...`（缺 --spec-id 现会 BAD_ARGS fail-fast） |

## 主题 G — 工具已兜底的冗余 prose（REDUNDANT，可精简）

本次新增的 `--spec-id` fail-fast 与 `STATUS_DIVERGED` 让一批手动提醒/核对 prose 有了工具兜底：

| 文件:行 | 冗余内容 | 兜底 |
|---|---|---|
| `implement-code:67` | 手动校验各仓分支为 requirement/{cr} | `crctl status` 报 STATUS_DIVERGED |
| `sync/pull-progress:64-66` | 手动进 worktree 读 cr.md 展示状态 | `crctl status` |
| `sync/resume-from-remote:99-113` + `pipeline resume-cr node-3` | 整段 status→下一节点手工映射（两处重复维护同一张表） | `crctl status` + verdict 判定，收敛到一处 |
| `pipeline feature-writeback inputs/node-2/node-3` | 冗长"必须显式提供 spec_id/target_version 否则空路径" | 缺参现 BAD_ARGS fail-fast |
| `approve-*` 各处 | 推进前手动查 verdict=pass && blockers=[] | passCondition 门禁已强制 |

## 主题 H — 文档自身 staleness

- **`skills/_index.yml:274`**：crctl 的 brief 列子命令 `status/advance/gate/approve/validate/attempt/test/next/git`，**漏了 CR-2026-019 加的 `task done`/`merge-metadata`/`archive-move`/`migrate-backlog`**。ARCHITECTURE §8 规定"crctl 新增写入子命令"须触发文档修订，此次漏更。
- **`AGENTS.md`（主仓）#6**：警告的"writeback-prd-sdd SKILL 字面写 cp 覆盖"危害**已消除**（该 SKILL 已脚本化）。纪律可更新为"回写走入库脚本、只追加不改写"，把 cp 反例降为历史注脚。
- writeback 几条 `_index.yml` brief 未提 CR-2026-020 入库脚本（轻微）。

---

## 干净无 finding（正面样例，别误伤）

- `develop/implement-code`（Step 4.5 已用 `crctl task done` 且显式禁手写 _index）
- `requirement/requirement-register`（注册不归 crctl，手写 cr.md/_backlog/派生 worktree 合法）
- `cr/cr-inbox`、`cr/cr-query`、`cr/cr-show`、`cr/cr-dashboard`（只读，正确以 cr.md 为权威状态源）
- `cr/inbox-emit`、`cr/feedback-writeback`（写非 guard-deny 文件，crctl 无对应子命令，未被取代）
- `sync/list-remote-checkpoints`（全程 controlled-shell runGit）
- pipeline `architecture-design` / `code-implementation` / `requirement-authoring`（approve 节点委托 skill，无直接冲突）

---

## 修复优先级建议（本报告不改动，仅排序）

1. **P0 必改（会当场失败/被拦）**：主题 D（merge-commits 3 字段，否则每个 CR 回写失败）＞ 主题 A（approve-* 手写 approval.yml，被 guard deny）＞ 主题 C（裸 git 被 deny）＞ 主题 E 的 write-test-report frontmatter。
2. **P1 系统性清理**：主题 B（`cr-status-set` 标 deprecated + 全仓引用改 `crctl advance`）——牵涉最广，建议一次性扫改。cr-archive Step 5 删手写 _index。
3. **需先决策再动**：主题 F（crctl 是否补 field-patch 子命令 / 哪些 _backlog 写入算合法例外）——尤其 cr-review-record 的核心动作无合法落点，得先定它的新定位。
4. **P2 精简**：主题 G（冗余 prose）、主题 H（_index brief 补子命令、AGENTS.md #6 更新）。

## 一个诚实的元观察

这批过时不是"写错了"，而是**工具能力跑在了 prompt 前面**：CR-2026-019 把账本操作收敛进 crctl 子命令、CR-2026-020 把回写机械步骤脚本化、PreToolUse guard 把账本文件写入锁死、本次又加了 fail-fast/STATUS_DIVERGED——每一步都让一批"手把手教手动操作"的 prompt 从"必要指引"变成"冗余甚至冲突"。ARCHITECTURE.md §8 已经列了"crctl 新增写入子命令"要触发文档修订，但修订只覆盖了架构文档、没下沉到 SKILL prompt。**根治办法不是这一次清理，而是把"crctl 新增/变更能力 → 扫描并更新受影响 SKILL prompt"纳入每个治理 CR 的回写清单**（可作为主题 H 之外的一条流程改进）。
