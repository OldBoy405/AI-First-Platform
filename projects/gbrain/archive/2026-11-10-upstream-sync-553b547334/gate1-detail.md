# Gate 1 明细：§0 台账新鲜度首判（2026-11-10）

> 硬前置，非 STDD 原生步骤。定义见 `multica/archive/2026-10-20-upstream-sync-4efd5062c9/gate1-template-v2.md`，
> 上一轮实例见 `gbrain/archive/2026-10-26-upstream-sync-2568d32ac8/gate1-detail.md`。
> 结论：**BLOCK → 修复 → PASS**，修复提交 `387f1e0341`，随后用户选项「确认继续（推荐）」通过 Gate 1。

## 判定时点

在任何 `fetch` / `merge` 之前，对 `CUSTOM.md` 与现场工作树做四维比对。
冻结窗口后才做冲突预测；两者顺序不可颠倒——台账不新鲜时，冲突裁决矩阵本身不可信。

## 维度一：条目新鲜（fork 侧改动是否全部登记）

**BLOCK**。7 个 fork 侧生成物/金标准在工作树中与上游基底不同，但台账未登记：

```
scripts/structural-suites.tsv
test/fixtures/goldens/cli/help-and-errors.json
test/fixtures/goldens/cli/tools-json.json
test/fixtures/goldens/exports/runtime.json
test/fixtures/goldens/exports/types.json
test/fixtures/goldens/sql-text/_classification.json
test/fixtures/goldens/sql-text/_driver.json
```

风险：这些文件在本轮 19 个冲突里可能命中，若台账没有「生成产物不手工 resolve」的登记依据，
裁决时容易被误当成需人工合并的内容。

**修复**：在《二开专属文件》新增一行：

```markdown
| fork 侧生成物/金标准（上游亦有，冲突不手工 resolve） | `scripts/structural-suites.tsv`、
  `test/fixtures/goldens/cli/help-and-errors.json`、`test/fixtures/goldens/cli/tools-json.json`、
  `test/fixtures/goldens/exports/runtime.json`、`test/fixtures/goldens/exports/types.json`、
  `test/fixtures/goldens/sql-text/_classification.json`、`test/fixtures/goldens/sql-text/_driver.json`
  （另 `test/fixtures/goldens/sql-text/links.json` 见《后端增量》）。这些是生成器输出，fork 侧内容与上游不同；
  冲突一律按《生成产物不手工 resolve》丢弃冲突块后重跑 `regen:all` / `regen:all --goldens`，勿手工合并 |
```

## 维度二：基线新鲜（挂钩四数 / fork-only 文件 / op 三处登记）

**PASS**。合并前实测：

| 项 | 期望 | 实测 |
|----|------|------|
| `CUSTOM (Qoder)` 围栏 | 4 | 4 |
| `CUSTOM ADMIN ROUTES` 行 | 2 | 2 |
| fork-only 跟踪文件 | 434（合并前口径） | 434 |
| inbox/truth/graph_overview 的 op 三处登记 | 齐全 | 齐全 |
| `tsconfig.json` 无 `baseUrl`、`@/*` → `./src/*` | 是 | 是 |

注：`tsconfig` 核对脚本用 `grep -qF "baseUrl"` 判定时曾打印 `FAIL`，但「找不到 `baseUrl`」正是期望状态，
直接 `cat tsconfig.json` 复核后确认无误——是检查脚本的判据写反，不是台账失真。

## 维度三：状态新鲜（与 git 事实是否一致）

**BLOCK**，2 处失真：

| 台账原值 | 现场事实 | 处置 |
|----------|----------|------|
| 《基本信息》`origin/master = 61dffc7613` | `a752cc41a4a7fed1e97a00bc41c6f0f91ead222c` | 删除该失真状态行（宁可缺省，不留错值） |
| 《二开专属文件》`v239-inbox-workflow-frontmatter.ts` | `v275-inbox-workflow-frontmatter.ts` | 改为 `v275`（本轮合并后再改为 `v298`） |

风险：迁移号写错会直接误导「顺延到上游最新号 + 1」的裁决；`origin/master` 写错会让
base-ref 类守卫的假阳性更难定性。

## 维度四：格式可解析

**PASS**。明细表仍为稳定 Markdown 表格，列数一致，无被上游重排的段落。

## 修复与复跑

```
提交 387f1e0341  docs(custom): Gate 1 §0 台账修复（7 项生成物登记 + 2 处状态修正）
UNREGISTERED_NOW=0
git diff --check OK
```

修复提交**独立**于合并，不含任何代码改动，可单独 revert。

## Gate 1 确认

| 项 | 值 |
|----|----|
| 确认方式 | 对话选项 |
| 用户选择 | 「确认继续（推荐）」 |
| 覆盖范围 | 允许继续拉取、冻结窗口、在同步分支上合并并按 `CUSTOM.md` 裁决冲突 |
| **不覆盖** | 推送 `master`/`origin`、部署、代跑本机 brain 迁移 |
| 非确认项 | 后台任务完成通知（系统事件，不是用户授权） |

## 冻结窗口（Gate 1 通过后）

见 `upstream-window.txt`。摘要：

```
BASE                 2568d32ac89052dcc8effacd3f96c073e14e44b1
FORK_HEAD_PRE_SYNC   a752cc41a4a7fed1e97a00bc41c6f0f91ead222c
UPSTREAM_TIP         553b5473344af4b8d9e09ebb8078e4e51a6d15eb
COMMITS              3056
VERSION_STAMPS       180
UPSTREAM_CHANGED     2452
FORK_CHANGED         513
BOTH_CHANGED         51
TRUE_CONFLICTS       19
```

`git fetch upstream --tags` 首次超时（无输出、SIGTERM）；`git ls-remote upstream master` 验证连通后
改为 `git fetch --no-tags --progress upstream master`，约 10 分钟完成：
`2568d32ac8..553b547334 master -> upstream/master`，`FETCH_EXIT=0`。
