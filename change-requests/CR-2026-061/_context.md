# CR-2026-061 工作流导航缓存（dev-agent / code-implementation）
> 仅供返工与 /resume 导航；canonical 事实以 cr.md / plan.md / tasks/_index.yml / review-annotations / crctl 为准。
> 最近刷新：2026-09-08（dev-agent：Ray 拍板「同意」后执行第 1 步——advance 回 tech-design-reviewed → 修订 plan §6.2 cmd-02（-run 收敛）+ TASK 完成标志同步 → write-dev-tasks 回 task-breakdown；待 review-dev-plan cycle 2 / attempt 2）

## 当前状态

- status: `task-breakdown`（advance 已 embedded，待随修订一起提交）；`crctl next` = `review-dev-plan`（plan digest 漂移，重审刷新证据，符合预期）
- reviewLoop：`review-dev-plan` = cycle 2 / attempt 1（本轮复评 = attempt 2，余 1 轮）；`write-test-report` = cycle 2 / attempt 1（重跑 = attempt 2，余 1 轮）；`review-code` = cycle 2 / attempt 0（未发起）。本轮回修无 reset、零轮次消耗。
- 代码产物不变：multica `requirement/CR-2026-061` @ `5aadba5be`（B-CODE-01 已闭合，评审对象保持）；tools CR 分支 @ `30b49d2`（治理边已含）；docs CR 分支随本轮提交前移。
- 上轮 canonical 证据（cycle 2 / attempt 1，generated-at `2026-09-08T22:08:13+08:00`）：cmd-01 21/21 PASS、cmd-05 skipped=false（B-CODE-02/03 闭合）；cmd-02 整包真库 7 项上游失败致机器区 block——已由本轮 plan §6.2 cmd-02 收敛修订消除（§9.2）。

## 本轮修订（plan §9.2 / §6.2 / §7；TASK-01/03 §4/§5 完成标志）

- cmd-02 args → `-run` 收敛：`^TestGateProjectionReusesBoundPromotionRun|^TestPromotionMigrationsUpDownRoundtrip|^TestConcurrentIndexCleanupsMatchTheirMigrations|^TestEveryConcurrent`（governance 1 + migrate 4，共 5 项测试函数，AC-13/AC-10 面）
- **预验已跑（本机 dev 库，DATABASE_URL + GOFLAGS=-v，multica `5aadba5be`）**：5/5 PASS、0 FAIL、0 SKIP、exit=0
- 排除 7 项上游失败（governance 5 + migrate 2，名单见 §6.2/§9.2）；4 个相关测试文件相对 trunk 零 diff（`approval_continuation_test.go`、`runner_integration_test.go`、`migrate_discussion_shared_session_test.go`、`migrate_workspace_seam_test.go`）
- TASK-01/TASK-03 §5 完成标志：全包命令标注「非 canonical 实施期全包专项证据」，canonical cmd-02 指向 §6.2 收敛口径
- CUSTOM.md《已知测试失败基线》7 项 DB 失败登记：待下次 multica 合法变更（本轮不触碰 `5aadba5be`）

## 待办（按序）

1. 提交本轮修订 + checkpoint 推送（docs；multica/tools 零改动）→ 见恢复入口
2. quality-reviewer-agent 独立 `review-dev-plan`（cycle 2 / attempt 2，review-record 带 `--bump-attempt`）
3. PASS 后 Ray 交互式终端重批 `crctl approve --stage dev-start`（EVIDENCE_DRIFT 按新证据重签，属预期）
4. dev-agent 重跑 `crctl test --plan`（write-test-report cycle 2 / attempt 2）→ 机器区 `status=pass`、cmd-05 `skipped=false`
5. 新 cycle `review-code`（cycle 2 / attempt 1）→ Ray `approve --stage code` → merge / writeback

## 环境提示（本机复现用）

- DB：主克隆 `C:\Users\GOBAO\Downloads\AI\multica\.env` 的 `DATABASE_URL`（dev 库，迁移 505–507 已应用）
- 受控 git 一律 `crctl git <sub> … --cwd <worktree>`；commit 消息必须以 `wip: `/`[cr] `/`merge(` 开头
- `crctl test` 的 `pnpm` 需 PATH 前置 `$env:TEMP\crctl-pnpm-shim\pnpm.exe`（Go 编译的 node 转发 wrapper）
- plan §6.2 会话环境：`DATABASE_URL` + `GOFLAGS=-v`；cmd-01 21 项 promotion `-run`；cmd-02 收敛 5 项；cmd-05 dot reporter
- 上游基线（CUSTOM.md 已登记）：`TestLoadAgentSkills_*` 3 项（cmd-01 `-run` 排除）；cmd-02 的 7 项 DB 期上游失败（本轮 plan 修订排除，CUSTOM.md 登记待 multica 下次合法变更）
- B-CODE-01 修复在 multica `5aadba5be`；`MergeIssueContextRefPipelineRun` 消费契约见 TASK-01 §6 / TASK-02 §6

## 恢复入口

1. 若本轮（修订+advance）中断：docs CR worktree 中 plan.md/TASK-01.md/TASK-03.md/_context.md + cr.md（embedded advance 已写 status=task-breakdown）待同提交；`crctl git add -A --cwd <docs worktree>` + `crctl git commit -m "[cr] ..."` 后按待办 1 继续。
2. 复评 BLOCK → repair-target `write-dev-plan`（作者 = 本 Agent），按 reviewer 返回逐条回修。
3. 重跑 `crctl test --plan` 时：环境同「环境提示」；目标 `status=pass`、cmd-02 5/5、cmd-05 `skipped=false`。
