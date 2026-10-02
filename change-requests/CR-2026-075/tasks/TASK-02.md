---
id: CR-2026-075-TASK-02
type: TASK
cr-ref: CR-2026-075
plan-ref: "change-requests/CR-2026-075/plan.md"
sdd-ref: "change-requests/CR-2026-075/sdd.md"
target-version: 0.48
title: daemon 绑定解析与三元组成对发布
slug: daemon-task-workspace-binding-resolve-publish
status: pending
estimate: 12h
depends-on: [CR-2026-075-TASK-01]
created: 2026-10-03T00:15:00+08:00
---

## 任务描述

在 multica daemon 实现绑定解析与发布的唯一实现点（FR-01、FR-02；SDD §2.1/§2.2/§3.3/§4.1）：Pipeline 与普通 Issue 两条 CR 入口都经同一 `resolveTaskWorkspaceBinding` 取得可信绑定；`execution_context` 由本次触发评论解析（不依赖 `PipelinePrompt` 非空）；绑定三元组成对写入/成对清除；Git trust config 与 crctl launcher 由「仅 Pipeline」泛化为「有绑定的任务」。本 TASK 与 TASK-01 构成同批交付门：CLI 归一（TASK-01）先完成，本 TASK 的绑定发布才生效。

## 涉及文件 / 模块

- `server/internal/daemon/pipeline_task.go` — 新增 `resolveTaskWorkspaceBinding`、`parseExecutionContext`；`configurePipelineGitEnvironment` 泛化为 `configureTaskGitEnvironment`；`installPipelineCrctlLauncher` 泛化为 `installCrctlLauncher`（有绑定即安装）。
- `server/internal/daemon/daemon.go` — `injectTaskCRWorkspaceEnv` 扩参并按 SDD §4.1 发布；装配顺序与三个调用点（`daemon.go:8313`、`daemon.go:8646`、`daemon.go:10718`）随泛化调整。
- `server/internal/daemon/pipeline_task_test.go`、`server/internal/daemon/cr_workspace_binding_test.go` — 同包表驱动用例（保留既有锚点用例名 + 新增固定前缀用例名）。
- 不修改：`server/cmd/multica/cmd_gitguard.go`（`CRCTL_TASK_AUDIT_ROOT` 仍是 gitguard 拒绝事件唯一落点）、`server/go.mod`（复用既有 `gopkg.in/yaml.v3 v3.0.1`，零新依赖）、`CUSTOM.md`（台账登记属 TASK-09）；不新增 API/DB 字段、不持久化绑定。

## 实现要点

- 解析（SDD §4.1 逐条，唯一解析点）：
  - `task.PipelinePrompt != ""` → 沿用既有预检字段：`task.PipelineWorkspace`/`task.PipelineLocalWorkDir` 任一为空 → 空绑定（不是错误）；否则 `{CRRoot: clean(PipelineWorkspace), Operational: clean(PipelineLocalWorkDir)}`。
  - `PipelinePrompt == ""` → `parseExecutionContext(task.TriggerCommentContent)`（SDD §2.2：扫描围栏块含 ```yaml/```yml/无语言标记；`yaml.Node` 解析以识别重复键；含顶层键 `execution_context` 的块必须恰有一个；`cr_id` 匹配 `^CR-[0-9]{4}-[0-9]{3,}$`、`operational_workspace` 非空字符串；多块/重复键/非法值/类型不符 → 错误，终止节点准备；评论文本完全不含 `execution_context` → 返回 `nil` 上下文，走普通任务分支，不报错）。
  - CR 委派：唯一已验证 KB `local_directory` 根（无根或歧义 → 错误终止）→ `inspectPipelineWorkspace(ctx, root, ctx.CRID)` 只读复检（坏 worktree/越界/非 healthy → 错误终止）→ `sameRealPath(realpath(ctx.Operational), realpath(inspected))` 不等即错误终止（声明≠预检）。
  - 普通任务：`root := taskCRWorkspaceRoot(task, localAssignment)`（既有定义）；`root == ""` → 空绑定；否则 `{CRRoot: root, Operational: root}`。
- 发布（SDD §2.1/§4.1，仍在 `layerCustomEnvAndHermesHome` 之后执行，`custom_env` 不可覆写）：
  - 先 `delete` 三值：`CRCTL_WORKSPACE`、`CRCTL_OPERATIONAL_WORKSPACE`、`CRCTL_TASK_AUDIT_ROOT`（成对清除，绝不留半绑定）。
  - 绑定为空或 `agentEnv["MULTICA_TASK_ID"]` 去空白为空 → 直接返回（清除后无写入）。
  - 否则写 `realpath(Operational)` → `CRCTL_OPERATIONAL_WORKSPACE`、`realpath(CRRoot)` → `CRCTL_TASK_AUDIT_ROOT`；`CRCTL_WORKSPACE` 保持不存在（DEP-1 的删除行为延续）。
- 泛化（有绑定即执行，不再限于 `PipelinePrompt != ""`）：`configureTaskGitEnvironment(agentEnv, binding)` 写 `<CRRoot>/.crctl/task-gitconfig` 并置 `GIT_CONFIG_GLOBAL`；`installCrctlLauncher(env.GitShimDir)` 生成 `crctl`/`crctl.cmd` shim；Codex 提供者沿用 `pipelineCodexWritableRootConfig(auditDir)` 追加可写根。同环境下直接 `node crctl.mjs` 与 launcher 必须同结果，且都不能绕过绑定。
- 边界：daemon 不解析 `dir-graph.yaml` 判 workspace 健康度，`crctl workspace inspect` 仍是唯一 CR authority 核实通道（只读复用既有预检，不重复根探索）；不启停或修改数据库/消息队列/常驻服务。

## 验收条件

1. 在 multica CR worktree 的 `server` 目录执行证据命令 `cmd-08`（plan §6.2 原样：repo=multica、cwd=`server`、executable=`go`、args=`["test","./internal/daemon/","-count=1","-v","-run","Test(InjectTaskCRWorkspaceEnv|DaemonEnvBuildHasNoConfigFirstRootFallback|PreparePipelineTaskHydratesMachineLocalPaths|ConfigurePipelineGitEnvironment|ConfigureTaskGitEnvironment|InstallPipelineCrctlLauncher|InstallCrctlLauncher|ResolveTaskWorkspaceBinding|ParseExecutionContext|TaskWorkspaceBinding)"]`、timeout=900）：全绿，且 `-v` 输出的 `--- PASS` 行中下列名集**每个分支至少命中一条**（用例名由本验收条件固定，改名即视为证据失效）：
   - 既有锚点：`TestInjectTaskCRWorkspaceEnv*`、`TestDaemonEnvBuildHasNoConfigFirstRootFallback`、`TestPreparePipelineTaskHydratesMachineLocalPaths`、`TestConfigurePipelineGitEnvironment`、`TestInstallPipelineCrctlLauncher`（`pipeline_task_test.go:46/75/105`、`cr_workspace_binding_test.go:74/92/115/137/150/183` 既有组织，表驱动、无新框架）。
   - 新增前缀：`TestResolveTaskWorkspaceBinding*`、`TestParseExecutionContext*`、`TestTaskWorkspaceBinding*`、`TestConfigureTaskGitEnvironment*`、`TestInstallCrctlLauncher*`。
   真实运行范围 = `./internal/daemon/` 单包定向名集；**不声称该包全量通过**（R10：`TestRegisterTaskReposAllowsProjectOnlyURL` 在本机 Windows 因临时仓路径超 MAX_PATH 失败，与本 CR 无关），不使用 `go test ./...`、不使用 `make test`。
2. 用例逐条覆盖 AC-A1/A2/A3/A4/A7：
   - AC-A1/A2：Pipeline 有效绑定下首次归一成功（无 `WORKSPACE_REQUIRED`、无重试/恢复委派）；同环境直接 `node` 与 launcher 同结果、不能绕过绑定。
   - AC-A3：普通 Issue 的 `execution_context` 触发预检绑定，不依赖 `PipelinePrompt` 非空。
   - AC-A4：缺失/重复/冲突/非法上下文、无根/歧义/越界/坏 worktree 一律停止节点准备或零写入失败（无 agent 执行）。
   - AC-A7：并发 task 隔离；`custom_env` 在 `layerCustomEnvAndHermesHome` 之后不可覆写；无绑定清旧值（三值全清，含 `CRCTL_WORKSPACE`）。
3. 文件集检查经受控入口（argv 固定），cwd = multica CR worktree 根；`<tools-worktree>` 取 Pipeline `resources[]` 中 repo=`tools` 的 `worktreePath` 原样值：

   `node <tools-worktree>/skills/shared/crctl/scripts/crctl.mjs git status --porcelain --cwd <multica-worktree> --workspace <multica-worktree>`

   断言输出仅含本 TASK 声明的四个文件。status 仅证明文件集，语义正确性由验收条件 1/2 证明。

## 完成标志

- `cmd-08` 全绿且上述九个名集分支各自命中；`-v` 输出作为证据留存。
- 解析/发布/泛化三处语义与 SDD §4.1 逐条对应；`taskWorkspaceBinding` 不持久化、不序列化回服务端。
- `CUSTOM.md` 零改动（TASK-09 登记）、`cmd_gitguard.go` 零改动、`go.mod` 零改动。
- 产物已落盘并提交，commit 自含其新增/调整测试；本 TASK 不改 tools 仓文件。

## 接口契约

**消费**（逐字对齐 SDD §3.3 与目标仓现状）：

- `preparePipelineTask(ctx context.Context, task *Task) error`（`server/internal/daemon/pipeline_task.go:33`，语义不变）：Pipeline 分支的预检链复用；失败即终止任务准备。
- `findPipelineCRRoot(roots []string, crID string) (string, error)`（`pipeline_task.go:50`）、`inspectPipelineWorkspace(ctx context.Context, root, crID string) (string, error)`（`pipeline_task.go:141`）：CR 根唯一性与只读预检。
- `pipelineCodexWritableRootConfig(auditDir string) string`（`pipeline_task.go:136`）。
- `taskCRWorkspaceRoot(task Task, localAssignment *localDirectoryAssignment) string`（`daemon.go:10754`）：普通任务绑定的既有定义，不新增主机根回退。
- `layerCustomEnvAndHermesHome(agentEnv, customEnv map[string]string, overlayHome string, logger *slog.Logger)`（`daemon.go:10692`）：绑定写入点必须在它之后。
- `gopkg.in/yaml.v3 v3.0.1`（`server/go.mod`，`dep-32`）：`execution_context` 解析用 `yaml.Node` 识别重复键，不新增第三方依赖。

**产出**（SDD §3.3 逐字签名，Go 形态落到目标仓；`resolveTaskWorkspaceBinding` 的形参以 §3.3 表格为准，§4.1 伪码中的两参写法是同一函数在 `ctx` 已可见处的简写）：

```go
type taskWorkspaceBinding struct {
    CRRoot      string // realpath(CR 根)：ledger/audit 根；空串 = 空绑定
    Operational string // realpath(operational workspace)：业务写入根
}

// 唯一绑定解析点；返回 {CRRoot, Operational} 或空绑定（不是错误）
func (d *Daemon) resolveTaskWorkspaceBinding(ctx context.Context, task *Task, localAssignment *localDirectoryAssignment) (taskWorkspaceBinding, error)

// SDD §2.2 的解析；错误即终止任务准备；文本不含 execution_context 时返回 nil, nil
func parseExecutionContext(text string) (execCtx, error)
// execCtx 至少含：CRID string（匹配 ^CR-[0-9]{4}-[0-9]{3,}$）、Operational string（非空）

// SDD §2.1 的成对写入/成对清除；仍是 custom_env 之后执行的唯一写入点
func injectTaskCRWorkspaceEnv(agentEnv map[string]string, task Task, localAssignment *localDirectoryAssignment, binding taskWorkspaceBinding)

// 由 configurePipelineGitEnvironment 泛化；写 Git trust config + GIT_CONFIG_GLOBAL，返回 auditDir
func configureTaskGitEnvironment(agentEnv map[string]string, binding taskWorkspaceBinding) (auditDir string, err error)

// 由 installPipelineCrctlLauncher 泛化：有绑定的任务即安装 crctl/crctl.cmd shim
func installCrctlLauncher(binDir string) error
```

- 绑定三元组定义（`MULTICA_TASK_ID`/`CRCTL_OPERATIONAL_WORKSPACE`/`CRCTL_TASK_AUDIT_ROOT` 的语义与有效性条件）是本 CR 的共享契约，与 TASK-01 的 CLI 归一判据逐字一致；两侧都不得缩写、改名或另立第二份定义。
- 下游引用：TASK-09 的部署副本与生效版本台账消费本 TASK 的绑定发布面（`cmd-10` 的部署基线）；TASK-10 复跑 `cmd-08` 作为 A 段证据。
