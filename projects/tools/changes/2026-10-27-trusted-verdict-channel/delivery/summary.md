# DELIVER — tools 侧（配对 change）

配对主 change 见 `projects/multica/changes/2026-10-27-trusted-verdict-channel/delivery/summary.md`。

## 本侧交付物

| 项 | 内容 |
|---|---|
| 新增 lib | `execution-control-protocol`、`execution-control-store`、`execution-control-policy`、`merge-scope`、`merge-facts`、`merge-effects`、`execution-control-readiness`、`execution-control-recovery`、`execution-control-worker`、`execution-control-isolation` |
| 新增 test | 上列各自的 `test/*.test.mjs`，以及 `test/fixtures/control-vectors.json` |
| 改动文件 | `lib/change-scope.mjs`、`lib/component-readiness.mjs`、`test/change-scope.test.mjs`（rebase 冲突面，见 `conflict-surface.txt`） |
| 验收 label | node 侧 9 个；证据与变异编号见主 change 的 `validation/` |

## 未声称

Windows 平台隔离 2 leaf（ADJ-13 延后，需受限 Windows 令牌 + 令牌驱动）。

## 提交状态

未提交（用户决定 a）。未跟踪的 `.crctl/keys/aifirst-approval-2026-07.pub` 早于本 change（2026-10-20），被既有 fixture 引用，不属于本次改动，已排除在 `fork-changed-files.txt` 之外。
