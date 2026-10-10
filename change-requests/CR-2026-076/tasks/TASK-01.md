---
id: CR-2026-076-TASK-01
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "平台可信绑定：task／来源 Issue 唯一 CR 关联与错误根写前拒绝"
slug: daemon-trusted-binding-cr-association
status: pending
estimate: 16h
depends-on: []
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-01、FR-SUP-05、FR-SUP-06 错误根防线部分；AC-01／AC-02／AC-03／AC-SUP-06／AC-SUP-09）：按 SDD §4.1 判定顺序 2a／2b／2c／2d 与步骤 1e，让「无手工根声明」的任务在启动前自动获得可信 CR 绑定，并让错误项目根／阶段根在业务写入前被拒绝。

背景与输入条件：现状（`dep-5`）只在触发评论带 `execution_context` 声明块时走 `local_directory → findPipelineCRRoot → inspect` 三段预检；无声明时仅回落 task 关联根，**尚无**「task 或来源 Issue 的唯一正式 CR 关联」解析段（`dep-5` 结论原文）。既有拒绝出口 `CR_WORKSPACE_BINDING_UNAVAILABLE`（`dep-4`）与 CR 根唯一性预检（`dep-7`）可直接复用，不新增错误码。

明确不做：不改 `server/internal/daemon/local_directory.go` 的 leader 任务短路（平台侧根治另立 CR，不在本 CR `scope_in`）；不改 crctl 侧绑定归一（TASK-03）；不改 HTTP 契约、不新增 CLI 子命令、不动用户全局 Git 配置本体。

## 涉及文件 / 模块

- `server/internal/daemon/pipeline_task.go`：`(d *Daemon) resolveTaskWorkspaceBinding`（:202）新增解析段；`parseExecutionContext`（:112）保持「唯一 fenced YAML 块」语义不变
- `server/internal/daemon/types.go`：`Task` 镜像认领载荷新增的两个关联字段
- `server/internal/handler/agent.go`：`AgentTaskResponse` 新增可省略字段 `cr_id`／`issue_cr_ids`
- `server/internal/handler/daemon.go`：`buildClaimedTaskResponse`（:2409）投影两个既有关系；读取失败走既有 transient `claimBuildFailure`（不 settled）
- `server/pkg/db/queries/agent.sql` + `server/pkg/db/generated/agent.sql.go`：新增 `ListCRIDsByShellIssue` 只读查询（按 `make sqlc` 重新生成）
- `server/internal/handler/` 内新增投影用例（DB 可达时执行；本机 DB 不可达时该包 `TestMain` 整包 skip，不计入本 TASK 证据面）
- `server/internal/daemon/cr_workspace_binding_test.go`、`server/internal/daemon/pipeline_task_test.go`：新增/扩展定向用例（cmd-01 观测面）
- 只读核对（不改）：`server/internal/daemon/local_directory.go`、`findPipelineCRRoot`（:280）、`inspectPipelineWorkspace`（:378）、`server/internal/handler/cr_bind.go`

## 实现要点

1. **关联载体（裁定结论：既有认领载荷的附加投影）**：`AgentTaskResponse` 新增 `cr_id`（task 的正式 CR 关联＝`agent_task_queue.cr_id`）与 `issue_cr_ids`（来源 Issue 的正式 CR 关联＝工作区内 `cr.shell_issue_id` 反查，按 `cr_id` 字典序）；daemon `Task` 同名字段镜像。**不新增关联存储、不新增独立查询机制、不新增 endpoint**；服务端只投影事实，**唯一性判定全部留在 daemon 侧**；投影读取失败 → `claimBuildFailure`（不 settled，认领可重试），不得静默降级为「无关联」。
2. 判定顺序严格按 SDD §4.1（任一步失败即失败关闭，不自动重试、不切执行器）：
   - 有声明块：1a 唯一块解析 → 1b `local_directory` 唯一 → 1c `findPipelineCRRoot(a, cr_id)` 唯一命中 → 1d `operationalWorkspace` 与声明逐字同根 → **1e（新增）** 声明的 `cr_id` 必须与 task／来源 Issue 的正式 CR 关联一致，不一致拒绝。
   - 无声明块：**2a（新增）** 取 task 正式 CR 关联（`Task.CRID`），唯一则用；**2b（新增）** 否则取当前来源 Issue 的唯一正式 CR 关联（`Task.IssueCRIDs` 恰一个），唯一则用并输出 `BINDING_INHERITED_WARN`；2c 多关联／冲突／有显式 CR 信号但无可确认目标 → 要求合法输入（不猜 CR、不扫历史评论）；2d 无 CR 信号 → 保持既有普通任务行为（不报错）。
   - 绑定产物成对发布：`CRCTL_OPERATIONAL_WORKSPACE`、`CRCTL_TASK_AUDIT_ROOT`、`MULTICA_TASK_ID`（E5；审计根≠操作根是既有事实，`dep-30`，不得判为冲突）。
2. 错误根防线（FR-SUP-06 本 CR 部分）：「路径存在」「同安装根」均**不构成**通过理由；必须同时满足项目归属、CR、阶段 authority、资源健康。归档 CR 的新任务重新解析当前 authority，不沿用旧 worktree 事实。
3. `BINDING_INHERITED_WARN` 只作只读诊断输出（SDD §2.2 code 枚举），不写账本、不改变绑定语义。
4. 注释与提交：multica 仓代码注释一律英文；提交须保留用户身份（本 TASK 不改 Git trust，TASK-02 负责）。

## 验收条件

1. **AC-01／AC-02（cmd-01）**：`cmd-01` 名集内新增用例断言——task 有唯一正式 CR 关联时（消费载荷投影的 `cr_id`），无声明块的任务其环境出现三元组，且 `crctl workspace inspect` 的 `operationalWorkspace` 与该根同根；仅来源 Issue 有唯一关联时（`issue_cr_ids` 恰一个）绑定成功且带 `BINDING_INHERITED_WARN`；多关联时非零退出并要求合法输入；无 CR 信号任务绑定为空且行为不变。
2. **AC-03（cmd-01）**：关联／声明／项目资源／真实根冲突场景在启动前非零退出（`CR_WORKSPACE_BINDING_UNAVAILABLE`），且 CR 账本无任何写入。
3. **AC-SUP-06／AC-SUP-09（cmd-01 关联）**：注册后阶段交接取得正确阶段根——本 CR 只做本 CR 侧集成验收（SDD §1.2 承接边界），reviewer 单层派发与启动预检部分由 AIFI-60 承接，不重复实现、不重复要求同一组证据。
4. **投影面（cmd-01 名集内，不另立命令）**：至少断言「task 关联优先于来源 Issue 关联」「来源 Issue 多值不猜测」「关联字段缺省＝无信号，行为与现一致」三条；新增用例一律写成既有 `-run` 名集已命中函数内的子测试。
5. 证据范围按 plan §5.5 cmd-01 行：`multica/server` 的 `./internal/daemon/` **单包**定向名集（11 个测试函数），**不声称** multica 仓全量通过；服务端 handler 包的投影用例在本机 DB 不可达时整包 skip，不作为本 TASK 证据面；不得另行新增未在 plan §6.2 出现的命令。

## 完成标志

- 代码与英文注释落盘，`cmd-01` 真实执行退出码 0，原样输出落 `change-requests/CR-2026-076/test-evidence/cmd-01.log`；
- plan §5.5 cmd-01 声明的观测面（绑定三元组解析与拒绝面、绑定发布到任务环境、preflight 投影注入、CR 根基数与 workspace 健康预检）逐项有用例覆盖；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`（`crctl task done`，不积压到回写期）。

## 接口契约

消费（既有事实，签名不变，`dep-4`／`dep-5`／`dep-7`）：
- `func parseExecutionContext(text string) (execCtx, error)`（`pipeline_task.go:112`）
- `type execCtx struct { CRID string; Operational string }`（:46），`func (e execCtx) isZero() bool`（:53）
- `func findPipelineCRRoot(roots []string, crID string) (string, error)`（:280）
- `func inspectPipelineWorkspace(ctx context.Context, root, crID string, allowDirty bool) (string, error)`（:378）

产出（本 TASK 扩展，供 TASK-02／TASK-03／TASK-17 消费，消费方不得缩写）：
- 认领载荷新增字段（服务端侧产出、daemon 侧消费）：`AgentTaskResponse.cr_id`（`omitempty`，task 正式 CR 关联）与 `AgentTaskResponse.issue_cr_ids`（`omitempty`，来源 Issue 正式 CR 关联集合，按 `cr_id` 字典序；daemon 镜像 `Task.CRID`／`Task.IssueCRIDs`）；缺省＝无该关联（非错误）；
- `type taskWorkspaceBinding struct { CRRoot string; Operational string }`（:32）与 `func (b taskWorkspaceBinding) bound() bool`（:39）语义不变：两字段成对发布或都不发布（DEC-2）；
- `func (d *Daemon) resolveTaskWorkspaceBinding(ctx context.Context, task *Task, localAssignment *localDirectoryAssignment) (taskWorkspaceBinding, error)`（:202）扩展为「声明块分支 + 2a／2b／2c／2d 无声明分支」；
- 诊断输出 `BINDING_INHERITED_WARN`（SDD §2.2 warnings code 枚举，本 TASK 只产出该 code，`warnings[]{code,message,ref?}` 形状由 TASK-06 统一承载）；
- 错误出口：`CR_WORKSPACE_BINDING_UNAVAILABLE`（本 TASK 全部拒绝面）、`WORKSPACE_CONTEXT_MISMATCH`（crctl 侧失败关闭，`dep-2`，本 TASK 不改）。
