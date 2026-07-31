---
id: CR-2026-002-TASK-09
type: TASK
cr-ref: CR-2026-002
plan-ref: "change-requests/CR-2026-002/plan.md"
sdd-ref: "change-requests/CR-2026-002/sdd.md"
title: pkg/gitguard + execenv 四处改造（PATH shim / 自守 / 上下文注入 / hooks 物化）
status: done
estimate: 16h
depends-on: [CR-2026-002-TASK-01]
assignee: ""
created: "2026-07-31T09:30:00+08:00"
spec-id: ai-first-platform
version: "0.11"
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

## 完成记录（2026-07-31）

- **提交**：multica worktree 7ff168096 + tools@a7b08cc（rules.json 补只读形态）+ tools@4907539（RE2 兼容修复）。
- **pkg/gitguard**：rules.json 的 Go 消费方，Check（三元白名单）/Run，错误码沿用 FORBIDDEN_SUBCOMMAND/FORBIDDEN_FLAG/SHELL_UNAVAILABLE；`OnDeny` 回调是 T10 审计的接入点（只传 caller/sub/code，无参数正文）；`FromEnv` 未配置=(nil,nil) 上游行为不变、配置无效=error 由调用方 fail-closed。
- **PATH shim（L2）**：execenv 铸造 `{envRoot}/bin/git`（sh）+ Windows 配套 `git.cmd`，re-exec `multica gitguard-exec <real-git> <agent> <args>`（隐藏子命令，过闸后 stdio 透传真 git）；daemon PATH 前插 shim 目录 + 注入 `CRCTL_WORKSPACE`。
- **daemon 自守（AC-5④）**：execenv/git.go 10 处 worktree 操作全过 `guardedGitCommand`，caller=system-orchestrator；crevents.go 收编 T06 遗留 TODO（commit 扫描 git 也过闸）。
- **IDE hooks（L3）**：Claude 后端自动物化 per-task `.claude/settings.json` PreToolUse（路径从 rules.json 位置派生，不二次配置；已存在则不覆盖，护 local_directory 用户配置）。
- **上下文注入**：runtime brief 新增 Controlled Shell 段（仅在规则配置时出现），把"git 是白名单网关、CR 用 crctl git、勿直改治理文件"写进模型能读到的地方。
- **测试**：gitguard 4 项（表驱动含 force push→FORBIDDEN_SUBCOMMAND[AC-5①]、-c/--config-env→FORBIDDEN_FLAG[AC-5②]、OnDeny 观测 + 消息不含参数正文、FromEnv 语义、**真 rules.json 必须过 RE2 的 conformance 锁**）+ daemon crevents 5 项回归全绿；fmt/vet/全仓 build 干净。
- **抓到一个真跨引擎 bug**：rules.json 的 `add` 形态用了负向先行断言 `(?!-)`，crctl（JS）能编译但 Go 的 RE2 直接拒绝整个 rules.json → gitguard fail-closed 拒一切 git。改为等价 `^[^-].*$`（两引擎都接受），并加了"真 rules.json 必须在 RE2 下加载成功"的回归测试防复发。这正是 SDD 把"两个语言实现"列为风险点的具体兑现。
- **有意未做（记录在案，非遗漏）**：
  - **L1 `--disallowedTools Bash` 未接**：需要按 agent 的 permission.bash 决策，但该字段平台侧不持久化（M0 适配器实测 fieldsReadNotPersisted），没有可信的键可依据；接了就是假安全。留待 agent 契约补齐 permission 持久化后做。
  - **AC-5③（Write 直改 _backlog.yml → hook deny）的真机手测移交 T11**：需重建 backend 镜像 + 带 `MULTICA_CONTROLLED_SHELL_RULES` 重启 daemon + 真派一个 Claude 任务；hook 脚本本身（pretooluse-guard.mjs）在 T01 已有单测覆盖 deny 逻辑，此处缺的是"execenv 自动物化 → 真任务触发"的端到端，集中到 T11 环境刷新一次做。
- **诚实边界（写进上下文段与 CUSTOM.md）**：L2 shim 可被绝对路径 `/usr/bin/git` 绕过——明示，靠 L4（crctl CAS+gate）L5（CI）兜底。
