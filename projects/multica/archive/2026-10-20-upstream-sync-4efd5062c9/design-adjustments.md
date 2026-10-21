# 设计偏离记录 — 2026-10-20-upstream-sync-4efd5062c9

## ADJ-001：chat-input zero-diff S1/S2 基线刷新

| 字段 | 内容 |
|---|---|
| 原设计 | CR-2026-062 zero-diff 以 `117fc6be` 的 `ChatInputProps` / `ChatInput` 为 S1/S2 基线 |
| 实际 | 第九次同步上游修改了 `ChatInputProps` 注释与 conversation-starter 逻辑；merge 后 S1/S2 漂移 |
| 处置 | 从合并后的 `chat-input.tsx` 重新快照 S1/S2；S3/S4 与 `ChatInputCore` 继续 fork 零差异 |
| 原因 | 上游正常演进，不是 fork 对上游组件的越界修改 |
| 影响 | 零差异契约继续锁定 fork 适配层；S1/S2 改为跟踪合并后的上游版本 |
| 验证 | `vitest run chat/components/chat-input-zero-diff.test.ts` 5/5 pass |
| 是否改变口径 | 否；仅刷新基线 |

## ADJ-002：内部错误响应不再回传原始 cause

| 字段 | 内容 |
|---|---|
| 原设计 | handler 的内部错误路径不得把 `err.Error()` 直接回给客户端 |
| 实际 | 合并后 `skill.go`、`skill_appeal.go`、`skill_market.go` 共 8 处上游代码直接回传 `err.Error()`；fork 守门测试 `TestInternalServerErrorsDoNotExposeCause` 失败 |
| 处置 | 统一改为 `slog.Error(..., "error", err)` + 稳定公开文案 |
| 验证 | `go test ./internal/handler -run '^TestInternalServerErrorsDoNotExposeCause$'` 通过；handler 全包 117s 通过 |
| 是否改变口径 | 否；按 fork 安全规则收紧 |

## ADJ-003：daemon pipeline 测试补齐 global Git config 夹具

| 字段 | 内容 |
|---|---|
| 原设计 | `TestInjectTaskCRWorkspaceEnvPipelineTask` 依赖进程的 user-level global Git config |
| 实际 | B 全量测试顺序下该测试先于任何创建 global config 的测试运行，稳定失败；A 全量因顺序不同通过 |
| 处置 | 测试内创建临时 `HOME/.gitconfig` 并清空 `XDG_CONFIG_HOME`；生产 fail-closed 逻辑不变 |
| 验证 | `go test ./internal/daemon -run '^TestInjectTaskCRWorkspaceEnvPipelineTask$'` B 通过 |
| 是否改变口径 | 否；仅测试隔离修复 |
