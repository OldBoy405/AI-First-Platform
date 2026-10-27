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

## 归档

2026-10-27 归档至 `projects/tools/archive/2026-10-27-trusted-verdict-channel`，`status: archived`。归档时使用 `--skip-specs`（不合并到 `projects/tools/specs/`），原因见主 change 的 delivery/summary.md §8。

## 归档后修订：crcrl 全量套件暴露的三条回归（2026-10-28）

归档时的「绿」只覆盖 label 体系（`channel-evidence.mjs verify`，37 label）。当时未运行 crctl 全量套件。次日在 `2026-10-19-aifi-45-runner-contracts` 的交付收口中补跑全量（52 文件 / 1280 测试），暴露本 change 的 `de9bf75` 引入三条回归，均已修复：

| 失败 | 原因 | 修法 |
|---|---|---|
| `CR-2026-064 FR-11 结构断言③` | 本 change 新增夹具 `test/fixtures/control-vectors.json` 未进入该断言冻结的扫描面快照 | 把该路径加入 `contract-scan.test.mjs` 的 fixtures 期望集合（新夹具默认入面） |
| `TASK-09 单缝约束` | `lib/change-scope.mjs` 自行 `rev-parse ^{tree}` 做 zero-change 证明，复制了 tree 解引用判定 | `lib/workspace-transactions.mjs` 导出 `treeFactsFor` 作为单一缝入口，`change-scope.mjs` 改为调用；全仓 `^{tree}` 仍恰一处 |
| `TC-EVD-007` | 本 change 在 `component-readiness.mjs` 新增「`not-applicable` 需 profile 显式批准」规则（规格 §38 要求），旧测试用例的声明未带 `not_applicable_approved` | 测试声明补 `not_applicable_approved: true`，规则不变 |

修订后：Windows 与 Linux 各 `1291 tests / 1290 pass / 0 fail / 1 skip`（skip 为平台原语缺失且互补：Windows 无 symlink、Linux 无 junction）。修复提交在 tools 仓，见该次提交说明。
