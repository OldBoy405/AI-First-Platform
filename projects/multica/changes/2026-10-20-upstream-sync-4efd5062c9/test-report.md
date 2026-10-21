# 第九次上游同步 — Gate 3 验收报告

> 变更：`2026-10-20-upstream-sync-4efd5062c9`
> Gate 3：pending（未确认，未 push）
> 合并提交：`a3af2341f`（本地 sync 分支）
> 零差异基线修复：`599114cb1`
> 第一父：`d5f58a70`（main）；第二父：`4efd5062c9`（upstream/main）

## 1. 合并范围

- 窗口：`e0f84dda4..4efd5062c9`，101 个上游提交。
- 两边都改文件：119；文本冲突：24。
- 第一父包含工作期间 main 新增的 `5a913605b`、`d5f58a70`；台账修复 `54d5d5bbf` 在其历史中。
- 合并树 CUSTOM.md 为台账修复版（442/1400/541/278 基线、状态/格式已修）。

## 2. 冲突与迁移

- 24 个文本冲突全部解决：9 个 db 生成物重跑 sqlc、5 个 locale JSON 并集、1 个 SQL 真源并集、9 个前后端文件手解。
- fork 迁移 565–621 共 114 个文件（57 对）降序 +20 → 585–641。
- cleanup map、migrate 测试、maturity/task_agent 测试号引用同步更新。
- 迁移号 585–641 连续，无重号；上游 565–584 保持原样（580 缺号）。
- `gateResumeToReachableSession` 的 `dirIdentity` 保留；`task.go` 使用 fork `s.taskEvent` + 上游 reaction target；`runtime_local_skills` 保留 fork 发布门 + 上游 default。
- 零差异适配：上游改了 ChatInputProps 注释与 conversation-starter body，S1/S2 基线刷新；S3/S4/ChatInputCore 未动（见 `design-adjustments.md` ADJ-001）。

## 3. 验收结果

| 检查 | 结果 |
|---|---|
| 挂钩四数（前置 `d5f58a70`） | 442 / 1400 / 541 / 278 |
| 挂钩四数（最终 HEAD） | 442 / 1400 / 541 / 278（零丢失、零新增） |
| 两父路径审计 | 两父均有 6425；合并树缺失 0 |
| 迁移号 | 585–641，无重号 |
| governance 生成器 | `generate-gate-nodes.mjs --check` 通过（tools BASE 9e41ad7） |
| `go build ./...` | 绿 |
| `go vet ./...` | 绿 |
| `pnpm typecheck` | 10/10 绿 |
| views 全量 | 505/505 文件、6359 用例绿 |
| `pnpm test` 全量 | core 178/178、web 35/35、docs 4/4、ui-lab 8/8、ui 1/1、desktop 61/62 |
| desktop 失败 | `scripts/package.test.mjs` SyntaxError，CUSTOM 已知基线 |
| Go 定向测试 | events、cmd/server、pkg/agent OMP/Pi、taskEvent、daemon resume/denial、handler local-skill/project 全绿 |
| 前端定向 | zero-diff 5/5、search-command 37/37、inbox 56/56、locales parity 212/212 |
| 空库迁移（B） | 670 版本，末位 `641_issue_context_refs_gin` |
| 后修提交 | `c1c20e35d` handler 内部错误不回传 cause；`7f47deffe` daemon 测试 global Git config 夹具 |

### 3.1 Go 全量 A/B（非 race，干净库，-count=1）

| 项 | A2（baseline `d5f58a70`） | B3 final（merged `874ea9621`） |
|---|---|---|
| 测试库 | `multica_stdd_9th_a2` | `multica_stdd_9th_b3`（重建） |
| 迁移 | 651 版本，末位 621 | 670 版本，末位 641 |
| 失败包 | 12 | 13（`internal/handler` 并行 flake；单包复跑全绿） |
| 失败测试 | 252 | 165 |
| 相对 A2 的新失败测试 | — | 仅 2 个上游新增 timing 测试：`TestCancelChatTranscriptReadIsBounded`、`TestClaimTasksByRuntime_HTTPFollowupDoesNotWaitForRecovery`；均单跑通过 |
| race | 未跑（本机无 gcc/CGO） | 同左 |

### 3.2 Windows 新增失败处置（原 38 个已清零）

| 组 | 数量 | 性质 | 处置 | 提交/证据 |
|---|---|---|---|---|
| execenv `TestPrepareLocalWorktree*` | 24 | 上游新增；CRLF/autocrlf + Windows 路径 | 测试夹具 pin `core.autocrlf=false` + `git worktree list --porcelain` 路径归一化 | `0e08bb7f4`；65s 全绿 |
| daemon LoadConfig/Hermes/Pi MCP | 4 | 上游新增；host env 泄漏 / HOME vs USERPROFILE | 测试内清 `MULTICA_CR_WORKSPACES`、`MULTICA_CODEX_PATH`、gitguard rules；redirect HOME+USERPROFILE | `f5a1f4f35`；四测通过（Hermes 按既有 Windows symlink skip） |
| service builtin/legacy | 3 | 2 个 baseline + 1 个上游恢复 redirect；CRLF checkout | 测试读取路径 LF 归一化，生产文件未动 | `6bfb33381`；三测通过 |
| wecom quoted media | 5 | 上游新增；Windows 不能 unlink 打开中的临时文件，回退 buffered | streaming 子测试 Windows skip，buffered 子测试保留 | `874ea9621`；4 skip / 4 pass |
| handler partial-success | 2 | 上游新增；全量并行 timing flake | 无生产改动；单跑通过 | 单测/单包通过 |

更正：此前用 `HEAD^1` 做来源判断有误（那是后修提交的父，不是 merge 第一父）。按 baseline `d5f58a70` 复核，原 38 个中 35 个是上游新增测试，3 个是 baseline 测试；不能笼统归为“已知基线”。

最终 B3 原 38 个失败已清零；只剩 2 个上游新增 timing 测试在全量并行下偶发失败，均单跑通过（service 11.0s、handler 5.8s）。这不是确定性 Windows 回归，处理选项：记入已知并行 flake，或降低 CI 并行度；待 Gate 3 决策。

后修提交：`599114cb1`、`c1c20e35d`、`7f47deffe`、`f5a1f4f35`、`0e08bb7f4`、`6bfb33381`、`874ea9621`。

说明：首次 views 全量有 5 个文件失败；单跑 create-project/search-command/mcp-tab 通过，属并行资源 flake；zero-diff 是真实基线漂移，已按 ADJ-001 刷新后 5/5 通过；第二次 views 全量 505/505 全绿。

## 4. 未完成 / 待授权

1. CUSTOM.md 第九次同步记录：草稿见 `custom-update-draft.md`；按 Gate 3 后追加，不重写历史。
2. 2 个上游新增 timing 测试的全量并行 flake：记入已知基线，或降低 CI 并行度；待 Gate 3 决策。
3. push：未授权；Gate 3 确认后才讨论。
4. 清理临时测试库/基线 worktree：Gate 3 后再执行。

## 5. Gate 3 结论

**已确认。** Gate 3 confirmed 2026-10-21T11:30:10（dialog / user / 证据“确认 Gate 3”）。原 38 个 Windows/环境新增失败已清零；2 个上游新增 timing 测试记为已知并行 flake（单跑通过）；CUSTOM 台账提交 `1dc9ffeb7`；未 push。
