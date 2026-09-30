# upstream-sync 证据：**未闭合**（CR-2026-073 TASK-04 / AC-7 上游同步部分）

本目录用于存放一笔**真实上游同步**按 `CUSTOM.md` 运行的全量原始日志（各命令、cwd、commit SHA、时间、exit code，失败也保留）
及同 Windows 环境的合并前/纯上游基线对照。
**当前为空缺：原始日志在本机工作区不存在，不得据此宣称 AC-7 的上游同步场景通过。**

## 本机核查结果（2026-09-30）

- 在 `C:\Users\GOBAO\Downloads\AI` 全量检索（深度 3，排除 `.git/`、`node_modules/`）未找到第七次同步（2026-09-30）全量套件 / 带库 Go 套件 / `make test` 的原始运行日志：命中项只有 `AI First Platform/.crctl/audit.log` 与 `multica/scripts/agent-cli-command-names.txt`，均非测试运行日志。
- 结论：**原始日志、运行命令清单与逐项失败名单不可核** → 按 plan §5「原始日志缺失…不能仅凭 CUSTOM 摘要宣称 AC-7 上游场景通过」处理为**未闭合**。

## 已具备的间接事实（摘要，不构成原始证据）

`../multica/CUSTOM.md`（只读核对，本 CR 未修改）已记录第七次同步（2026-09-30）：
- 带库全量 Go 套件（`DATABASE_URL` → 独立测试库 `multica_go_test`，脚本 `scripts/test-go.sh`）：140 项失败，按包分布 `internal/daemon` 61 / `cmd/multica` 25 / `internal/daemon/repocache` 22 / `internal/daemon/execenv` 11 / `internal/cli` 6 / `internal/integrations/wecom` 6 / `internal/service` 4 / `internal/handler` 2 / `cmd/migrate` 1 / `internal/maintenance` 1 / `internal/storage` 1；A/B 基线为合并前树 `95da7c9d7`（库 `multica_go_test_ab`）同脚本 114 项失败，差集 26 项已逐项归因、反向差集 0；fork 迁移测试全绿。
- `make test` 在 Windows 上入口即败（`scripts/go-test-with-agent-cli-guard.sh` 未剥 `\r` 读名单文件），已由 `.gitattributes` 增 `eol=lf` 修复。

## 缺失（补取方式二选一）

1. 从执行第七次同步的会话/终端取回原始全量日志（含命令、cwd、commit SHA、时间、exit code、未截断输出）与合并前基线日志，存入本目录并逐项比对失败名单/数量；或
2. 等下一次独立授权的上游同步，按 `CUSTOM.md` 全量执行并保留原始日志与同条件基线。

两种方式都需要平台/人工授权（本 CR 不执行 merge/rebase、不修改 multica 代码）。缺失期间：已知失败不得改成绿色 cmd，也不得以本 CR 的定向 `cmd-NN` 代替上游全量。
