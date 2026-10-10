---
id: CR-2026-076-TASK-02
type: TASK
cr-ref: CR-2026-076
plan-ref: "change-requests/CR-2026-076/plan.md"
sdd-ref: "change-requests/CR-2026-076/sdd.md"
target-version: 0.49
title: "任务 Git trust 叠加式 include 与身份保留"
slug: daemon-task-git-trust-include-overlay
status: pending
estimate: 12h
depends-on: [CR-2026-076-TASK-01]
created: 2026-10-10T16:30:15+08:00
---

## 任务描述

目标（FR-02；AC-04）：按 SDD §4.2 与 D-01，把任务 Git trust 从「替换用户全局配置」改为 Git 原生 `include` 叠加，使任务内提交身份来自原全局配置（姓名／邮箱），且全局配置本体不被改写。

背景与输入条件：`dep-6` 结论原文——`configureTaskGitEnvironment` 当前只生成 `[safe] directory` 两行配置并注入 `GIT_CONFIG_GLOBAL`，等效于替换用户全局配置，身份事实随之丢失。原全局配置路径解析：`git config --get` 既有白名单形态不可读全局路径时，回退读取进程启动前的 `HOME`／`USERPROFILE` 下标准位置；两者皆不可判 → 技术失败（不猜、不写死）。

明确不做：不改写用户全局姓名／邮箱、不设非 Git 原生 trust 旁路、不把环境错误记成业务 BLOCK、不新增常驻服务。

## 涉及文件 / 模块

- `server/internal/daemon/pipeline_task.go`：`func configureTaskGitEnvironment(agentEnv map[string]string, binding taskWorkspaceBinding) (string, error)`（:346）
- 产物文件：`<CR 根>/.crctl/task-gitconfig`（E6）
- `server/internal/daemon/pipeline_task_test.go`：`TestConfigurePipelineGitEnvironment`／`TestConfigureTaskGitEnvironment` 相关用例
- 只读核实（结论落入本 TASK 结果，必要时同批收口）：`server/internal/daemon/repocache/cache.go`、`server/internal/daemon/repocache/identity.go`

## 实现要点

1. 生成内容严格按 SDD §2.2 E6 与 §4.2（POSIX 分隔、realpath）：
   ```ini
   [safe]
   	directory = <CR 根 realpath，POSIX 分隔>
   	directory = <operational workspace realpath，POSIX 分隔>
   [include]
   	path = <原全局 Git 配置 realpath>
   ```
   `GIT_CONFIG_GLOBAL` 仍指向该任务内文件，且**只含 safe.directory 与 include 两段**。
2. `[include]` 是身份加载链的关键：身份来自原配置，不因 trust 注入被遮蔽；`include.path` 叠加而非替换。
3. 身份不可用（原全局配置 `user.name`／`user.email` 均缺失）时，正常新操作必须在**账本写入前**报环境问题；已有未完成事务按原恢复合同处理。
4. **核实项（SDD §10 待核实依赖，不得当作既有能力断言）**：`server/internal/daemon/repocache/identity.go`／`cache.go` 是否存在第二处 Git 配置环境写入点。核实结论（存在／不存在、涉及符号与行为）必须原样写入本 TASK 结果；**存在则在同一变更内与 `dep-6` 的叠加式配置同批收口**，不得留双写入点。
5. 注释一律英文；不新增依赖、不改 `GIT_CONFIG_GLOBAL` 以外的环境变量契约。

## 验收条件

1. **AC-04（cmd-02）**：任务内 `git commit` 成功且提交作者为原全局配置姓名／邮箱；任务外对照全局配置文件未被修改；身份缺失时错误发生在新账本写入之前。命令形态与范围以 plan §6.2 cmd-02 行为唯一事实源（`./internal/daemon/` 单包定向名集，4 个测试函数），**不声称**全包或全仓通过。
2. **AC-04（cmd-03）**：`./internal/daemon/repocache/` 单包全文件测试通过——用于 FR-02「第二处 Git 配置写入点」的核实结论；**不声称** `internal/daemon` 全包通过。
3. 核实结论（§10 待核实依赖「repocache 身份加载与 `GIT_CONFIG_GLOBAL` 的交互（平台侧）」）有明确二选一记录：①不存在第二写入点，给出核对符号与依据；②存在，给出同一变更内收口的文件与用例。
4. 真实执行的退出码与输出原样落 `test-evidence/cmd-02.log`、`test-evidence/cmd-03.log`；不得以「本地可跑」替代事实，不得新增 plan 未列命令。

## 完成标志

- `configureTaskGitEnvironment` 生成叠加式配置（safe.directory + include 两段），`cmd-02` 与 `cmd-03` 真实执行退出码 0 并留证；
- repocache 第二写入点核实结论已写入本 TASK 结果（二选一，含符号与依据）；
- 本 TASK 在 `tasks/_index.yml` 即时标记 `done`。

## 接口契约

消费（TASK-01 产出，不得缩写）：
- `type taskWorkspaceBinding struct { CRRoot string; Operational string }`（`pipeline_task.go:32`），两字段成对发布；`func (b taskWorkspaceBinding) bound() bool`（:39）；
- `func (d *Daemon) resolveTaskWorkspaceBinding(ctx context.Context, task *Task, localAssignment *localDirectoryAssignment) (taskWorkspaceBinding, error)`（:202）——本 TASK 只消费其 `CRRoot`／`Operational` 两个 realpath 值。

产出（本 TASK 暴露给 TASK-17 的生效核对消费）：
- `func configureTaskGitEnvironment(agentEnv map[string]string, binding taskWorkspaceBinding) (string, error)`（:346）：返回值语义为「写入 `<CR 根>/.crctl/task-gitconfig` 后注入 `GIT_CONFIG_GLOBAL` 的路径」；失败分支须覆盖「原全局配置不可判」与「身份缺失」两类，且均在账本写入前返回错误；
- 文件契约 `<CR 根>/.crctl/task-gitconfig`（E6）：`[safe]` 两行 + `[include] path` 一行，行序与 SDD §2.2 E6 逐字一致；
- 失败码沿用既有出口（不新增同义错误码，`dep-28` 的 tools 侧口径在 multica 侧对应为既有 error 返回）。
