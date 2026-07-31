---
id: CR-2026-002-TASK-09
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: pkg/gitguard + execenv 四处改造（PATH shim / 自守 / 上下文注入 / hooks 物化）
status: pending
estimate: 16h
depends-on: [CR-2026-002-TASK-01]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
---

## 任务描述
FR-5/D5 Go 半边：rules.json 的 Go 消费方 `pkg/gitguard`（~300 行）+ execenv 铸造改造。仓库：multica。

## 涉及文件
- 新增 `server/pkg/gitguard/`（`Check(sub, args, caller) error` + `Run(...)`，表驱动测试）
- 修改 `server/internal/daemon/execenv/execenv.go`：铸造 `.bin/git` shim（Windows 成对物化 git.cmd + bash shim）、PATH 前插、CRCTL_WORKSPACE 注入（AIFIRST 标记）
- 修改 `server/internal/daemon/execenv/git.go`：10 个 worktree 函数改走 gitguard.Run，caller=`system-orchestrator`（AIFIRST 标记）
- 修改 `server/internal/daemon/execenv/runtime_config_sections.go`：Agent 上下文追加 git 约束一节（AIFIRST 标记）
- 新增 `server/internal/daemon/execenv/crguard_config.go`（仿 openclaw_config.go）：Claude 后端物化 per-task PreToolUse hooks；`permission.bash: deny` → ExtraArgs 追加 `--disallowedTools Bash`

## 实现要点
- rules.json 消费：daemon 启动时从 tools 包安装位置加载；找不到 → 降级为拒绝一切 git（fail-closed）并告警。
- 错误码沿用 `FORBIDDEN_SUBCOMMAND / FORBIDDEN_FLAG / SHELL_UNAVAILABLE`。
- exec.Command 天然不经 shell（与 crctl spawnSync(shell:false) 等价）。
- 收编 T06 遗留的直调 exec.Command TODO（若有）。

## 验收条件
1. 表驱动测试：`push --force` → FORBIDDEN_SUBCOMMAND；`-c core.editor=…` → FORBIDDEN_FLAG（AC-5①②）。
2. 手测：Agent 任务内 Write 直改 `_backlog.yml` → hook deny（AC-5③，Claude 后端）。
3. daemon worktree 操作日志出现 caller=system-orchestrator（AC-5④）。
4. Windows 实测：PowerShell 与 Git Bash 下 shim 均生效（本机环境）。

## 完成标志
go test 绿 + 手测三项记录 + 完成记录回填。
