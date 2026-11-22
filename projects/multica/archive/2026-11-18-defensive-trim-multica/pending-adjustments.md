# BUILD 待处理调整 — 2026-11-18-defensive-trim-multica

## PA-001 同次执行证据缺少实际输入（已解决）

- **原始设计**：`test-plan.md` §六使用逐文件 `stdd-evidence-plan-v1.inputs`，CP 由 `selections.json` 选择并对账；最终证据须绑定实际执行的输入。
- **事实**：`stdd agent verify authorized-runner --change 2026-11-18-defensive-trim-multica --dry-run` 成功，预览冻结 24 个 project 文件。STDD 3.0.7 `stdd/cli/evidence.py::_snapshot` 读取声明清单，不隐式纳入业务 Git diff 或 CP 的调用依赖。`selections.json` 未覆盖，修改选择/期望叶子不会使输入冻结失效。其余遗漏的已改输入（不含 fork 台账）：`server/internal/governance/{execution_activation,execution_authorization_http_test,execution_binding_issue,execution_consumption,execution_control_policy_test,execution_fixture_export_test,pipeline_progress_route_test,requirement_shape_default_contract_test}.go`。另外，取证入口 `scripts/aifi45-disposable/run-selection.mjs` 和确定 Tools 版本的 `.github/aifirst-tools-pin` 是直接依赖，也未冻结。
- **实际修订**：用户授权「授权 PA-001 的 Gate 2 修订。避免重复校验和无意义兜底。」`test-plan.md` 补入 11 项，冻结输入 24 → 35；`design.md` 同步实际实现与 S5 测试调用点；`canonical/specs/agent/ci-backend-environment.yaml` 校正分文件用例数（10+25+16，总数 51、50 pass 和 1 个既有 Windows skip 不变）。继续使用同一固定 Tools 检出和 runner 自建实例。
- **评审补测**：`SC-EWV-101` 原只覆盖 running/null、failed/array；现已补齐 running/failed × 数组/标量/字面 null，并对账 `ewv-progress` 的 40 个叶子。旧 builder 移除后所用的 scope/resource/coordinator 三个既有生产 HTTP 拒绝回归，已纳入 `run-default-contract-issue` 的同次对账。
- **影响**：原 6 个 TC/CP 映射、业务保证、隔离边界和失败出口均不变。Gate 1 仍有效；旧 Gate 2 批准保留但已过期。
- **处理状态**：受审文档已同步，Canonical 检查和同次证据 dry-run 通过。用户明确回复「确认 PA-001 修订后的 Gate 2」，CLI 已重新确认 Gate 2；补测已通过；[`a9eb2552-7233-419a-b476-b9daf95053a6`](validation/runs/a9eb2552-7233-419a-b476-b9daf95053a6/agent-verification-report.md) 冻结 35 项，6 个 CP 全部通过，并通过同 run 的 `ci check-failures`。

## PA-002 将新增测试修复纳入冻结清单（Gate 2 已重审）

- **原始设计**：`test-plan.md` §六要求冻结本次修改的运行和测试输入，台账不作为执行输入；PA-001 已按此重审 Gate 2。
- **事实**：用户同意修复项目质量检查中的 PostgreSQL 观察误报后，`server/internal/handler/workspace_delete_concurrent_test.go` 增加受控回归并修改观察 helper；最终候选的完整 Linux `test-ci` 已通过。此前 run `97eba2d2-6876-4957-970c-a3dbbf8c517c` 的 35 项输入不含这个新修改的测试文件，不能据此称其已被冻结。
- **实际修订**：用户授权「授权将该测试文件加入冻结清单」；`test-plan.md` 已加入该文件（35 → 36），不调整 6 个 TC/CP、生产代码、质量标准或台账排除规则。此前完整后端、前端和 Chromium 检查在业务候选不再变化时复用，不重复全量测试。
- **预检**：`stdd agent verify authorized-runner --change 2026-11-18-defensive-trim-multica --dry-run` exit 0，预览 36 项输入和原 6 个 CP；30 项相对 HEAD 有差异，无未跟踪或被忽略项。预检未执行 CP。
- **影响与状态**：用户明确回复「确认 PA-002 修订后的 Gate 2」，CLI 已重审 Gate 2。新 run [`d6390f73-b7f7-4750-8369-b60d37526b95`](validation/runs/d6390f73-b7f7-4750-8369-b60d37526b95/tc-evidence.json) 冻结 36 项、6/6 CP 通过，同 run 自动化 C4 为 9/9；人工 C4 见 [test-report.md](test-report.md)。Gate 3 尚未批准。

## 质量验证环境（早期对照，后续结果见测试报告）

- 当时 `projects/multica/config.d/quality.yaml` 的 `make test` 会要求 `.env`，调用 `scripts/ensure-postgres.sh` 并迁移普通测试库，不走获授权的 `run-selection.mjs` 自建/回收边界；`scripts/check.sh` 也有同样的前置。隔离 worktree 未复制 `.env`，未调用这些命令。后续 DQB 已将项目测试入口改为一次性 CI 环境的 `test-ci`。
- `pnpm lint` / `pnpm typecheck` 已在离线模式尝试，缺少 worktree 的依赖与 turbo，均 exit 1，检查本身未启动。未安装、联网或借用主工作树。
- 用户授权执行五包 Go 及全脚本基线对照，不等于接受缺口或确认 Gate 3。五包 Go 对照的 147 个失败、142 个跳过事件路径一致；全脚本双方 739 pass / 16 fail / 1 skip，失败与跳过名称一致。两类命令均 exit 1，不记为全量通过。
- 后续用户授权冻结锁文件安装和项目 CI 一次性数据库流程。Windows 隔离副本中安装、`pnpm typecheck`、CI 管理员库测试及清理通过；`pnpm lint`、常规 Go race、agent Go race 未通过。Ubuntu CI 环境未复现，宽测无同条件基线。随后单独执行运行历史 Chromium 冒烟并通过；未执行评论路由、`scripts/check.sh` 或全套 E2E，`critical_only` 的路径仍为空。Linux `repocache` 基线与变更版定向 race 均 149/0/0，Windows lint 的 21 errors/21 warnings 在干净基线逐项复现。补跑相同 Linux CI backend 全量：基线和变更版 regular/agent 均失败，regular 存在 1 基线独有、5 变更版独有失败事件；不得视为全通过或零差异。证据与缺口见 [test-report.md](test-report.md)；未变更项目配置、未申请 Gate 3。
