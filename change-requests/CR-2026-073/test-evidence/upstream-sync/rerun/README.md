# CR-2026-073 B-C2 重跑证据索引（rerun/）

本目录是 CR-2026-073 TASK-04 / AC-7「上游同步场景」的取证结果：按 Ray 对 B-C2 的裁决（选 2），
在**既有三个提交**上重跑同条件全量带库 Go 套件，保留未截断原始日志与同批基线对照；
**未执行任何 merge/rebase，未修改 multica 代码**。

## 目录结构

| 路径 | 内容 |
|---|---|
| `COMPARISON.md` | 机器生成的对照报告：运行清单、条件与偏离、逐包条数 vs 已记录基线、逐项失败名单对照、超时/中止、环境噪声量化、结论 |
| `counts.tsv` / `counts.json` | 每个条件 × 每棵树的逐包失败条数（由原始日志派生） |
| `failure-sets/<cond>-<tree>.txt` | 每个条件 × 每棵树的失败项清单（`包 :: 测试名`，排序） |
| `cond-a-tasktmp/<tree>/` | 条件 A：TMPDIR 继承本任务环境（`...\Temp\multica-task-2074477066`） |
| `cond-b-shorttmp/<tree>/` | 条件 B：TMPDIR/TEMP 指向短根 `C:/rt/...`（消除 Windows 长路径类噪声） |
| `cond-b-shorttmp/premerge/03-targeted-merged-only-tests.log` | 对「仅在 merged 失败」的 25 项在合并前树做定向复跑 |
| `_preflight-aborted-attempt/` | 作废尝试留档（口令错误的首轮、缓存未清空的重跑），**不计入任何数字** |
| `scripts/` | 本轮使用的版本化脚本（重跑与再生成对照报告） |

每个 `<cond>/<tree>/` 内固定四件：

| 文件 | 内容 |
|---|---|
| `00-meta.txt` | 条件、树路径、提交 SHA、库名、命令、cwd、GOCACHE、TMPDIR、起止时间、Go/Node 版本、exit code、日志字节数与 sha256、`(cached)` 条数 |
| `00-db-setup.log` | 该次运行前 drop+create 空库的原始输出 |
| `00-lineendings-normalization.txt` | 唯一一处工作树改动的完整记录（行尾归一化，含归一前后 sha256 与「内容全等」证明；cond-b 运行时该文件已为 LF，记录为 no-op 但仍保留） |
| `01-migrate.log` | `go run ./cmd/migrate up` 的未截断原始输出 |
| `02-test-go.log` | `bash scripts/test-go.sh` 的未截断原始 stdout/stderr |

## 三个提交

| 树 | 提交 | 含义 | worktree |
|---|---|---|---|
| merged | `820bb5a11a53463486383c4c1f5e9c17c5a9a43e` | 第七次同步合并结果（fork `main`） | `C:\Users\GOBAO\Downloads\AI\cr073-rerun\merged` |
| premerge | `95da7c9d7b026918fa0827652644b944a744b336` | 合并前 fork 树（记录中的 A/B 基线树） | `C:\Users\GOBAO\Downloads\AI\cr073-rerun\premerge` |
| upstream | `4736a85d41b966b10ce9f60778cbfc47cecad4cb` | 纯上游树 `upstream/main` | `C:\Users\GOBAO\Downloads\AI\cr073-rerun\upstream` |

## 结果摘要（数量级与已记录基线一致，逐项对照见 COMPARISON.md）

| 条件 | merged | premerge | upstream | merged − upstream | merged − premerge | premerge − merged | upstream − merged |
|---|---|---|---|---|---|---|---|
| cond-a-tasktmp | 176 | 148 | 178 | 0 | 33 | 5 | 2 |
| cond-b-shorttmp | 135 | 115 | 137 | 0 | 25 | 5 | 2 |

已记录基线（`multica/CUSTOM.md`《已知测试失败基线》第七次同步行）：merged 140、合并前树 114、差集 26 逐项归因、反向差集 0。
`cond-b-shorttmp` 与它同包同名同量级；差额来源（空库 vs 累计库、premerge 的 `cmd/multica` 挂起被包超时中止、`execenv` Hermes 组取到本任务 `MULTICA_TASK_CONFIG_ROOT`）逐条列在 `COMPARISON.md` §3–§6。

## 复现

```bash
# 前置：multica 仓三个提交的干净 worktree（git worktree add --detach <dir> <sha>）；postgres 容器 multica-postgres
bash scripts/run_one.sh cond-b-shorttmp merged
bash scripts/run_one.sh cond-b-shorttmp premerge
bash scripts/run_one.sh cond-b-shorttmp upstream
bash scripts/targeted_premerge.sh
node scripts/gen-evidence.mjs
```

脚本以 multica 仓 `.env` 的 `DATABASE_URL` 口令连本机 postgres；每个提交用**新建空库** + **全新 GOCACHE**，
`core.autocrlf=true`，无 `--race`（本机无 gcc）。任何一项不满足都会在 `00-meta.txt` 里显形。
