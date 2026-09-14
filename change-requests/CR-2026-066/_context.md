# CR-2026-066 工作流导航缓存（`_context.md`）

> 本文件是**导航缓存**，不是 canonical 事实。canonical 事实优先：`cr.md`、`review-loop.yml`、
> `traceability.yml`、`review-annotations/**`、`approval.yml`、`_backlog.yml`、`tasks/_index.yml`。
> 用途：返工与 `/resume` 时快速定位「做到哪、卡在哪、从哪继续」。

## 1. 当前状态（最近一次刷新：merge `release-drift` 处置后的 node-17 `workspace-freshness`(review-start) 清脏 run，2026-09-14 18:2x +08:00）

- CR：`CR-2026-066`（AIFI-27；CR-P3「评审 PASS 发布与 checkpoint 委派收敛」）。
- 权威 workspace = `.rayai-worktrees/knowledge-base/requirement/CR-2026-066`；三仓 worktree =
  `.rayai-worktrees/{knowledge-base,multica,tools}/requirement/CR-2026-066`；命令一律带 `--workspace <权威路径>`
  （主 checkout 视图陈旧，AGENTS.md 纪律 #9）。
- 实施 run 节点链：`approve-dev-start` 复核（**未重复审批**）→ `workspace-freshness`（implement-start，`continue`）→
  **`implement-code`（四张 TASK 全部落盘）** → **`write-test-report`（`crctl test`，`status=pass`）** →
  **`push-progress`（node-8）** → **`workspace-freshness`（review-start，`continue`）** → `review-code`（独立 reviewer）。
- 评审 run 结果：`review-code` **cycle 1 / attempt 1 PASS**、`blockers=[]`、`repair-target=null`；canonical 记录提交
  `aaf99ff8`、状态推进提交 `747b94f8`（`developing → code-reviewing`）、导航缓存提交 `bc12d40c`。
- 人工审批（先于 checkpoint 发生）：`approval.yml#code` 由 `crctl approve`（TTY，`via: crctl-approve`、`approver OldBoy405`、
  `approved-at 2026-09-14T17:46:59+08:00`、`evidence-digest 77dd708f…`）写入并推进到 `code-approved`（提交 `6383baac`），
  早于协调者「等 checkpoint 再审批」的指令（相隔约 30 s）⇒ node-15「审批前 checkpoint」的 `phase=complete` 前置被跳过。
- checkpoint 重跑 run（第一次，本机到 github.com 网络中断）：**未完成**——`git fetch origin` 失败
  （`TX_GIT_FAILED`：`Failed to connect to github.com port 443`），连续四次重试同症状；三仓 `git ls-remote` 同样失败
  ⇒ 环境网络问题，非仓库/凭据问题。**零副作用**：KB HEAD 仍 `6383baac`、三仓工作区干净、
  `_backlog.yml#latest-checkpoint.batch-id` 仍 `d3eac1f35ead840e`。
- checkpoint 重跑 run（第二次，网络恢复后）：**发布成功**——`crctl checkpoint CR-2026-066 --message "代码审批结果"`
  ⇒ `phase=complete`、`changed=true`、**batchId `bae239cc68cf584c`**、`metadataCommit 23fbaf57`；同步 `sideEffects`：
  KB 源提交 `e333883d`（内容 = 当时的本文件刷新）+ KB metadata 提交 `23fbaf57`；三仓 `confirmed=true`。
  独立复验：三仓 `git ls-remote origin refs/heads/requirement/CR-2026-066` 与本地 `HEAD` 逐字相等
  （KB `23fbaf57`、multica `d47818025`、tools `25ad2588`）；同命令幂等重放返回 `changed=false` + `phase=complete`。
- **merge run（feature-writeback node-1 `merge-feature-branch`）：`phase=release-drift`，CR 被自动回退**——
  `crctl merge CR-2026-066 --workspace <installation>`：`changed=false`、`txId 51a722b3b0734213a0ecb4d2e88aae71`、
  `drift { kind: code, reason: workspace-invalid, repo: ai-first-platform-docs, classification: dirty }`，
  执行既有转换 `code-approved -> developing`（trigger `merge-feature-branch:release-drift -> implement-code`）⇒ 回退提交
  **`5b853d35`**（只动 `cr.md`）。**零 publish**：merge journal `sideEffects: []`、`merge: null`、
  `crctl merge status` = `phase:none`/`repos:[]`、`_backlog.yml#latest-checkpoint` 未变（仍 `bae239cc68cf584c`）。
- **根因 = 本文件，且是两道独立检查**：`crctl merge` 的 `verifyReleaseSubjects` 对 KB 要求 (1) workspace healthy
  （porcelain 全空）与 (2) `git diff --name-only <reviewedSha>..HEAD` ⊆ 白名单（`approval.yml` / `cr.md` /
  `traceability.yml` / `review-loop.yml` / `_backlog.yml` / `review-annotations/**`）。上一 run 收尾刷新本文件 ⇒ 撞第 (1) 道；
  而 checkpoint 源提交 `e333883d` 已把本文件写进 `bc12d40c..HEAD` ⇒ 即便清干净也撞第 (2) 道（`post-review-path-drift`）。
  **⇒ 回退 / 搭车提交 / 保留不动三条路都过不了 merge，唯一出路是让 `<reviewedSha>` 前移 = 重跑 `review-code`
  产出新 `release-subjects`；不重放 `implement-code`**（交付面自 `25ad2588` 起零变化，重放只会作废已通过的评审与测试证据）。
- **本次 run（node-17 `workspace-freshness` review-start 的 `manual` 分支处置）**：把本文件按当前事实刷新并**提交一次**
  （评审前清脏，使三仓 worktree healthy）；`review-record --stage code` 之后本文件**冻结**——任何 commit 不得再碰它，
  收尾刷新只能「还原」不能「提交」（否则 approve / merge 报 `post-review-path-drift`）。
- 状态：`status = developing`（回退后未被本 run 改动）；`crctl next` = **`review-code`**（`humanApproval=false`，
  why「存在旧评审记录，重跑代码评审刷新证据」）；三仓 CR worktree healthy、freshness route = `continue`。
- 任务账本：`tasks/_index.yml` **四张卡全部 `done`**（TASK-01 15:54 / TASK-03 16:22 / TASK-02 16:28 / TASK-04 17:04，均带 `done-at`）。
- 本 CR 最新一次发布（网络恢复后的 checkpoint 重跑 run）：`--message 代码审批结果` ⇒ `phase=complete`、**batchId `bae239cc68cf584c`**、
  `metadataCommit 23fbaf57`；三仓 `confirmed=true`：KB `e333883d` / multica `d47818025` / tools `25ad2588`。
- 上一次发布（node-8）：`crctl checkpoint CR-2026-066 --message 代码与测试证据` ⇒ `phase=complete`、**batchId `d3eac1f35ead840e`**、
  `metadataCommit 7eb5c223`；三仓 `confirmed=true`：KB `bed340ea` / multica `d47818025` / tools `25ad2588`。
- 提交链：tools `6cd1d60`(TASK-01) → `a0823f8`(TASK-03) → `d2947a5`(TASK-02) → `25ad258`(TASK-04)；
  multica `b37825407`(TASK-02) → `d47818025`(TASK-04)；KB `62d46b35` … → `bed340ea`(测试证据) → `7eb5c223`(metadata) →
  `747b94f8`(status→code-reviewing) → `aaf99ff8`(评审记录) → `bc12d40c`(导航缓存) → `6383baac`(人工审批) →
  `e333883d`(checkpoint 源提交) → `23fbaf57`(checkpoint metadata) → `5b853d35`(release-drift 回退) → 本次刷新提交（评审前清脏）。
- 各 run 未触碰（含本 run）：`prd.md`（冻结 `9b43bbfa…`）、`sdd.md`（冻结 `78846c1b…`）、`plan.md` / `tasks/TASK-0*.md`
  （**评审证据面，一个字节未改**）、`approval.yml`、`review-annotations/**`；`review-loop.yml` / `traceability.yml`
  仅由 `crctl test` 写入其专属段落；`_backlog.yml` 仅由 checkpoint 写 `latest-checkpoint`。

## 2. 实施 run 的实测证据（canonical 见 `test-report.md` 与 `test-evidence/cmd-01…07.log`）

| 项 | 实测 |
|---|---|
| cmd-01 | `verdict=pass` / `files_executed=21` / **`cases_executed=596`** / `failures=0` / `skipped_file_level=0` / `exceptions_count=0` / 906 s（plan §5.4 基线 786 s；差异来自 `archive-tx` 新增 3 fixture 与机器负载） |
| cmd-02 | exit 0（`pipeline-structure` 36 用例含新 A/B/C/D 断言块 + `contract-scan` 含 FR-7 静态断言） |
| cmd-03 | exit 0（10 点）；存在性由 cmd-05 守卫（g）承载：`CR-2026-042 静态合同=5` / `checkpoint T05 contract=1` / `CR-2026-044 AC-13=2` / `CR-2026-044 AC-14=1` / `CR-2026-050 AC-12=1` |
| cmd-04 | exit 0（6 点 = 6 条 `CR-2026-066 AC-8` 用例通过；守卫（f）：token=6 ∧ `test(`=38） |
| cmd-05 | exit 0：`tools diff paths = 25` 双向相等、zero_diff 零命中、hunk 禁改 token 零命中、FR-9 四处正/负 token 全过 |
| cmd-06 | exit 0：`multica diff paths = 4`；权限块含只读 `workspace inspect` ∧ 保留 `checkpoint` 禁止面；三句旧前提零命中；四副本硬规则齐备；`localTrunkSync` 在册；无部署声称 |
| cmd-07 | exit 0：`plan section10 lines = 35`；16 正向 token 齐备；负向零命中；KB diff 全在 `change-requests/CR-2026-066/**` ∪ `change-requests/_backlog.yml` |
| 负控（非证据） | 五组：`_index.yml` 12→16、`ref=push-progress` 篡改、删矩阵注释/删 SKILL「请作者先提交」、`archiveCr` 去掉 `localTrunkSync`、删 Prompt 硬规则 token（tools 与 multica）——**各自对应断言必红，还原即绿** |

## 3. 下一步与恢复入口（canonical：`review-annotations/code.yml`、`review-loop.yml`、`crctl next`）

| 项 | 事实 |
|---|---|
| 当前节点 | node-17 `workspace-freshness`（review-start）`manual` 分支处置完成：KB 侧 `_context.md` 脏标记已按当前事实刷新并提交（本 run；评审前一次清脏，见 §1 根因）⇒ 三仓 CR worktree 均 healthy，freshness route = `continue` |
| **恢复入口（下一步）** | 重跑 `review-code`（独立 quality-reviewer-agent、新 run、`--bump-attempt`，attempt 2/3）⇒ PASS 后 node-15 checkpoint（`phase=complete`）⇒ Ray 在 TTY 执行 `crctl approve --stage code` ⇒ node-12 checkpoint ⇒ `merge`。**不得**重放 `implement-code`（交付面自 `25ad2588` 起零变化，重放只会作废已通过的评审与测试证据） |
| 基线前移的影响 | 新 `code.yml` 的 `release-subjects` KB 基线 = 本 run 提交后的新 HEAD；旧基线 `bc12d40c` 已不可能干净（见 §1）。`code.yml` 一变，`approval.yml#code` 的 `evidence-digest 77dd708f…` 立即 `EVIDENCE_DRIFT` ⇒ **Ray 须重走一次 TTY 代码审批**，旧审批不可复用、不得代签 |
| 发布缺口（先记着） | KB 本地领先 `origin/requirement/CR-2026-066`（`23fbaf57`）：本次刷新提交 + 后续状态/评审/审批提交都在本地 ⇒ `merge` 的 publication preflight 会先报 `RELEASE_REMOTE_NOT_PUSHED`；**至少一次 checkpoint 已绕不过去**（派生预测，非本轮证据） |
| 冻结合同（CR-2026-063 语义） | `_context.md` 不在 KB post-review 白名单（白名单 = `approval.yml` / `cr.md` / `traceability.yml` / `review-loop.yml` / `_backlog.yml` / `review-annotations/**`）。⇒ `review-record --stage code` 之前必须清干净（本次已完成）；review-record 之后**任何 commit 不得再碰本文件**，收尾刷新只能「还原」（`crctl git checkout <path> --cwd <worktree>`），不能「提交」 |
| 已终结节点（勿重跑） | 上一轮 `review-code` cycle 1 / attempt 1 PASS 与 `approval.yml#code` 记录**均不能被本轮 approve/merge 消费**（基线前移，`verifyReleaseSubjects` 必拒）——`review-code` 须 `--bump-attempt` 重跑、人工审批须重走 TTY；不得重复 `approve`、不得代签、不得重放 `implement-code` |
| **BLOCK 回修入口** | reviewer 的 `repair-target=implement-code` ⇒ 按 `reviewLoop.replayNodes` 重放：`implement-code → write-test-report → push-progress → workspace-freshness → review-code`（≤3 轮）；同一根因下所有失败点一次修完（`coding-discipline` §3） |
| 上游设计缺口（备用出口） | `review-dev-plan:upstream-design-blocker` / 状态机既有边 `code-approved -> developing`（release-drift）；**不得**就地放宽 SDD 或 `zero_diff` |
| 证据冻结机制 | `sdd.md`（`78846c1b…`）与 `prd.md`（`9b43bbfa…`）改一字即 `APPROVED_ARTIFACT_DRIFT`；`plan.md`/`tasks` 是评审证据面，实施期零改动 |

## 4. 残余与非阻塞登记（不阻断 review-code；供后续 CR/owner 处理）

| # | 项 | 事实 | 处置 |
|---|---|---|---|
| 1 | AC-6 延期验证点 | 本 CR 交付时不可能产出证据 | 按「登记即达成」提交（`plan.md` §10 与交付评论）；载体 = 交付后新注册的演练 CR（首选）/ CR-P1 首链（次选） |
| 2 | FR-11 平台生成物 | `gate_nodes_gen.go` Seq 与 registry digest 必变 | 走「**未重生成** ⇒ 重新生成前 `AIFIRST_ARCHITECTURE_RUNNER` 保持禁用」分支；重生成归 owner 部署窗口（`follow_up` 第 5 项） |
| 3 | 部署时序（SDD-CLOSE-05） | 本 CR 只改仓库内文本 | 部署窗口必须与 tools 侧改动成对生效；不构成平台部署声称 |
| 4 | `openwiki/pipelines/index.md` / `quickstart.md` 仍含 "mandatory checkpoints" | 不在 SDD §1.2 的 29 文件交付面内；`cmd-05` 的 25 文件白名单双向相等会拒绝越界改动 | 本 CR 不改，登记为残余（建议后续文档 CR / CR-P1 一并清理） |
| 5 | AC-8② 的 `diverged`/`fetch-failed`/`trunk-unavailable`/`ff-only-failed` 未做活值覆盖 | 以函数体赋值路径 + 枚举闭包 + 内存负控判定 | 已记入 `test-report.md` §5；活值覆盖 `synced`/`unchanged`/`skipped(dirty｜wrong-branch)` |
| 6 | 上一版 `_context.md` §4 的 4 条 plan/TASK 精度项 | 均属证据面措辞/计数精度，**实施期未动证据面**（改即 `devPlanFreshness` 漂移） | 保留不动，留待因真实发现重开 `plan/TASK` 时一次性改正（原文见 Git 历史 `bed340ea^` 之前的版本） |
| 7 | `AGENTS.md` replayNodes 描述仍含 "checkpoint 节点" | `zero_diff` 明令零 diff | 保留（通用形状描述，非本 CR 数值面） |
| 8 | AC-6③ 本轮 merge 未走到 publication preflight（`verifyReleaseSubjects` 的 workspace 检查先行返回）⇒ `MERGE_SOURCE_MISSING` / `RELEASE_REMOTE_NOT_PUSHED` **无观测**，不计为已验证 | 「评审 PASS 之后 checkpoint 委派次数 = 0」仍成立 | 与 AC-6 一并登记，不额外记分 |
| 9 | 观察：`merge` 的 release-drift 结果所携 `recovery`（「重跑 merge」）对该结果**恒不可执行**——实测 `MERGE_STATE_MISMATCH`（merge 需 `code-approved`，实际 `developing`）、零写入；漂移第二形态 = 白名单外路径 `post-review-path-drift` | 不在 CR-P3 交付面（明示不改 crctl 事务层与 recovery 合同） | 只作 observation 记档，交后续 CR 处理 |
| 10 | 平台侧 Agent Prompt 仍是 CR-2026-063 之前版本（本 run 收到的 dev-agent Prompt 仍要求「每次 run 收尾刷新或创建 `_context.md`…随 CR 一起提交」） | 与 tools 侧「`_context.md` 已移出 post-review 白名单」并存 ⇒ 每个 CR 的 merge 会周期性撞 `workspace-invalid` / `post-review-path-drift` | 本 CR 靠「评审前清脏一次 + 评审后冻结」处置；根治 = 部署窗口成对落地 CR-2026-063 的 multica 两份 Prompt 副本与 tools 侧改动 |
