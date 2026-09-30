# scope-review 夹具机制自检（**不是 verdict 证据**）

本文件登记 CR-2026-073 TASK-04 / plan §5 的 U/S/P 快照**夹具机制**的自检结果：夹具已可用、可评审状态已建起，但**独立 reviewer verdict 仍未取得**——原因见 §3。

## 1. 三案快照（可复现）

| 案 | CR-ID | 快照头（内容提交，advance 前） | 当前 HEAD（advance 后） | 期望 verdict |
|---|---|---|---|---|
| U | CR-2026-901 | `0bf7acb0134dba54ddc138f2b46a449c00338b82` | `ff5dea8b5c9e0b7bbdb0e8d5651040aecc309103` | `block`（无批准全量却把全仓命令设为关键 `cmd-01`） |
| S | CR-2026-902 | `01b01d144fbd27572f9b88def9211f3ac7d6a1dc` | `428b9f68ce7f38bbfb0a0924750f3da2f54216cc` | `block`（关键 cmd 只跑子集，plan/TASK 声称全量） |
| P | CR-2026-903 | `310cb2668ee184b925fd7589606b7a237255eaa8` | `54da209548804ef1132f65165c5c91feffdd0b2f` | 不因缺全仓测试被 block |

- 夹具定义：`fixtures/`（`shared/` 三案共用同一 SDD/AC；`variants/{U,S,P}/` 只替换 `plan.md` 与 `tasks/TASK-01.md`）。
- 构建：`node fixtures/build-snapshots.mjs --install-root <空目录>`；本次 install root = `C:\Users\GOBAO\Downloads\AI\cr073-scope-fixtures`（**一次性目录，未指向任何业务工作区**）。
- 构建输出：`fixtures/build-output.json`；机制自检原始输出：`fixtures/verify-mechanism.log`。

## 2. 已跑通（原始输出见 `fixtures/verify-mechanism.log`）

| 步骤 | 命令 | 结果 |
|---|---|---|
| clean 前置 | `crctl workspace inspect CR-2026-9xx --workspace <kbWorktree> --detail` | 三案 2 仓均 `classification=healthy`、`dirty=false`、`head=requirement/CR-2026-9xx` |
| 建立可评审状态（合法 crctl 流程） | `crctl advance CR-2026-9xx --to task-breakdown --trigger write-dev-tasks --expect tech-design-reviewed --workspace <kbWorktree>` | `committed=true`，`cr.md` status → `task-breakdown`，并写出 outbox 事件（落在夹具根，未被任何 daemon 扫描） |
| 路由 | `crctl next CR-2026-9xx --workspace <kbWorktree>` | `{"next":"review-dev-plan","why":"缺少 dev-plan.yml 评审记录，先跑 review-dev-plan"}` |
| 落盘机制自检（**合成** payload） | `crctl review-record CR-2026-901 --stage dev-plan --bump-attempt --workspace <kbWorktree> --from <payload>` | canonical `review-annotations/dev-plan.yml` + `review-loop.yml` + `traceability.yml` 落盘；`route=repair`、`repairTarget=write-dev-plan`；随后 `crctl next` → `write-dev-plan` |

> 最后一行用的是**合成** payload（`reviewer-model: fixture-selfcheck`），只证明 canonical 落盘与路由链路可用，**不是任何 verdict**，不得作 AC-6/AC-7 证据。自检后夹具根已整体重建，交付的 U/S/P 快照均处于「未评审的 `task-breakdown`」状态。

## 3. 未闭合：平台委派路径的结构性前置

缺的仍是**新的独立 `quality-reviewer-agent` run 的真实 `review-dev-plan` verdict**。经源码与 Skill 文本核实，平台委派存在硬前置：

1. `skills/develop/review-dev-plan/SKILL.md` Step 3.0：运行具有 Multica task-scoped context 时**先** `multica cr bind-current-task {cr_id}`；绑定失败（七种错误码）按技术失败中止——不写 payload、不调 `review-record`、不写 canonical review（`cr-prompts-revised/quality-reviewer-agent.md` 同口径）。
2. 绑定要求平台侧已存在该 CR 的投影行 `cr(workspace_id, cr_id)`：`server/internal/service/task.go` 的 `LockCrForCrBind` 取不到行即 `ErrCRBindCRNotFound` → HTTP 404 `CR_NOT_FOUND`，零写入。
3. 夹具 CR（`CR-2026-9xx`，隔离 install root）**没有**平台投影行：平台行来自 `crctl` 状态事件的 outbox（`server/internal/daemon/crevents.go` 扫描**已配置 root** 的 `.crctl/outbox/`）或 root `change-requests/_backlog.yml` 的 reconcile 快照。隔离根不在已配置 root 内，夹具事件不会被上报。

**结论**：平台委派的 reviewer run 无法直接评审隔离快照（会在绑定处技术中止）。可行路径（需人工/平台决定）：

- **A｜平台可见的测试 CR**：把同一批快照放到**真实 KB root** 的 CR worktree（并按真实 `dir-graph.yaml` 补 tools/multica 两仓 worktree），用 `crctl advance` 经合法流程把状态事件写进真实 root 的 outbox → 平台插入 `cr` 行 → reviewer 可绑定并评审。副作用：项目侧出现三个测试 CR 行（status `task-breakdown`），业务仓多出测试分支/worktree（本地可清理，平台行须平台侧处置）。
- **B｜无 task context 的本地执行**：按 FR-A7「无 Multica task context 的本地执行 → 跳过绑定」评审同一批快照（保持隔离、无平台副作用）；但该模式无法由 Agent 委派创建（Agent 只能经 issue/评论委派，必然携带 task context）。
- **C｜正式修订验收合同**：若 A/B 均不采纳，须按流程正式修订 AC-6/AC-7 的取证方式（SDD/计划级变更），不以 `cmd` 绿色代替。
