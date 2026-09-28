---
id: CR-2026-072-TASK-03
type: TASK
cr-ref: CR-2026-072
plan-ref: "change-requests/CR-2026-072/plan.md"
sdd-ref: "change-requests/CR-2026-072/sdd.md"
target-version: 0.45
title: daemon 任务绑定：删除配置首根回退，普通任务按项目绑定注入
slug: daemon-task-workspace-binding
status: pending
estimate: 4h
depends-on: []
created: 2026-09-28T23:52:00+08:00
---

## 1. 任务描述

multica daemon 任务环境构建中删除普通任务 `CRWorkspaceRoots[0]` 固定根回退：Pipeline 任务继续使用已预检的 task root 与 operational workspace（同名 CR 根歧义维持报错）；普通任务只在已有可信项目 local_directory/CR 根绑定（唯一匹配且验证通过）时注入对应工作区，无绑定时不注入 `CRCTL_WORKSPACE`/`CRCTL_OPERATIONAL_WORKSPACE` 并清除继承的旧 CR 环境键；`CRWorkspaceRoots` 仍供 CR event collector 与 Pipeline 根候选使用，不再作为普通任务当前根。同时为 gitguard 提供独立审计根注入（专用内部环境键 `CRCTL_TASK_AUDIT_ROOT`，本 TASK 注入、TASK-04 消费），并在最终环境叠加后保证其值与任务绑定一致；无可信绑定的任务不写该键。

## 2. 涉及文件 / 模块

- `server/internal/daemon/daemon.go`（agentEnv 段，:8506-8510）：删除 `else if len(d.cfg.CRWorkspaceRoots) > 0 { agentEnv["CRCTL_WORKSPACE"] = d.cfg.CRWorkspaceRoots[0] }` 回退分支；普通任务改走 local_directory 绑定解析；无绑定分支 `delete(agentEnv, "CRCTL_WORKSPACE")`、`delete(agentEnv, "CRCTL_OPERATIONAL_WORKSPACE")`、`delete(agentEnv, "CRCTL_TASK_AUDIT_ROOT")`（防继承宿主陈旧值）
- `server/internal/daemon/pipeline_task.go`（:37 `findPipelineCRRoot(d.cfg.CRWorkspaceRoots, task.PipelineCrID)` 恰一命中；:132 `agentEnv["CRCTL_OPERATIONAL_WORKSPACE"] = opReal`）：Pipeline 预检路径保持不变，另注入 `CRCTL_TASK_AUDIT_ROOT` = 预检 root
- `server/internal/daemon/local_directory.go`（:121 `localDirectoryAssignmentForTask(task Task, daemonID string) (*localDirectoryAssignment, error)`、:182 `findLocalDirectoryAssignment(resources []ProjectResourceData, daemonID string) (*localDirectoryAssignment, error)`）：消费既有解析结果，0 匹配不注入、>1 匹配拒绝（沿用其错误语义），不新增按 CR-ID 猜根服务
- 对应 Go 测试文件（daemon 环境构建用例）

## 3. 实现要点

- SDD §4.3：不能从 `CRWorkspaceRoots[0]` 或 workspace 当前 cwd 猜项目；工作目录为 disposable worktree 时不得等同 CR authority，使用资源对应的项目根，不能确认该项目是 CR 根则不注入。
- 注入是路径提示而非自动运行 crctl 的授权（SDD §3）：Agent 仍须自行验证后传旗标。
- `CRCTL_OPERATIONAL_WORKSPACE` 仅 Pipeline 注入；普通任务即使有可信 root 绑定也不冒充 operational path（operational 以 `crctl workspace inspect` 为准）。

## 4. 验收条件

1. Go 单测：普通任务无匹配 local_directory → agentEnv 不含 `CRCTL_WORKSPACE`/`CRCTL_OPERATIONAL_WORKSPACE`/`CRCTL_TASK_AUDIT_ROOT`，且预置的继承值被清除；唯一匹配且验证通过 → 仅注入该项目根与 `CRCTL_TASK_AUDIT_ROOT`。
2. Go 单测：>1 匹配 → 报错不注入；Pipeline 任务（`task.PipelineWorkspace != ""`）→ 注入预检 root 与 operational path，配置首根回退分支在源码中不复存在。
3. `go test ./...`（cwd `server`）全量通过。

## 5. 完成标志

daemon.go 回退分支删除 + local_directory 绑定注入落地；`go test ./...` 全绿；改动以 `[cr] ` 前缀 commit 提交；`CUSTOM.md` 按惯例登记 multica 定制改动（SDD §9 scope_in）。

## 6. 接口契约

- **消费**：dep-7 既有 `localDirectoryAssignmentForTask(task Task, daemonID string) (*localDirectoryAssignment, error)`（0 匹配返回 nil，重复匹配返回错误）与 dep-5 `findPipelineCRRoot(d.cfg.CRWorkspaceRoots, task.PipelineCrID)`（恰一命中，歧义硬失败）。
- **产出**（供 TASK-04 消费）：专用内部环境键 `CRCTL_TASK_AUDIT_ROOT` —— daemon 在 agentEnv 最终叠加后写入，值 = 本任务预检/绑定的项目 root（Pipeline 任务 = 预检 root；普通任务 = 唯一匹配并验证通过的 local_directory 根）；无可信绑定的任务该键不存在。TASK-04 只消费此键，不再读 `CRCTL_WORKSPACE`。
