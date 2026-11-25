# 交付日志：2026-11-10 后续放行

> 授权依据：用户明确指令「合入 master，提交，推送，部署，跑 gbrain apply-migrations；bun install；处理存量欠债」。
> 后台任务完成通知不是授权；本文件记录的动作全部基于该条用户指令。
> 对应仓库台账：`CUSTOM.md`《阶段记录》2026-11-10 条目末尾《收口》小节。

## 1. 存量欠债（先做，独立提交）

| 项 | 结果 |
|----|------|
| 迁移前备份 | `~/.gbrain/brain.pglite.pre-v298-20261110-1405`（97 MB） |
| 欠债定位 | `check:newlines` 候选 7455 文件中唯 **250 个 `.qoder/repowiki/**/*.md`** 缺尾换行，全部 fork-only，上游树无 `.qoder/` |
| 处置 | 按文件既有 LF 风格各追加 1 字节；`250 files changed, 250 insertions(+), 250 deletions(-)`，无内容改动 |
| 提交 | `06a600043f chore(newlines): 补齐 250 个 .qoder/repowiki 文档尾换行`（独立于 merge commit） |
| 验证 | `bash scripts/check-trailing-newline.sh` 长超时单跑 217s → `trailing-newline check: ok (7202 files)`、rc=0 |

未改上游 guard、未加 `skip .qoder/` 例外、未塞进合并提交。

## 2. 合入 master 与推送

- `master` 被主仓 worktree `C:\Users\GOBAO\Downloads\AI\gbrain` 占用，在该 worktree 执行
  `git merge --ff-only sync/upstream-2026-11-10-553b547334`，快进到 `06a600043f`。
- **整包推送连续失败**：`HTTP 408 curl 22` / `send-pack: unexpected disconnect`（约 3 分钟断连），
  `master` 与同步分支两次均失败。诊断：待传 40386 个对象、原始 **6.1 GB**，
  根因是 180 个 release stamp 各带一份约 4.9 MB 的 `CHANGELOG.md` 历史 blob；
  单提交 push 成功证明链路与权限正常。
- **解法**：设 `http.postBuffer=524288000`、`http.version=HTTP/1.1`、`lowSpeedLimit=0`、`lowSpeedTime=999999`；
  改用「分批推进临时 `gbrain-sync-staging` ref（30 提交/批、force、失败细分到 10 提交/逐提交）
  → 落 merge commit 与 HEAD → 最后用极小 pack 更新 `master`」断点续传，29 分钟完成。
  首轮 408 前已有前 899 个上游提交对象上传，续传从断点开始。
- 首次落地时 `origin/master` = `refs/heads/sync/upstream-2026-11-10-553b547334` = `06a600043f`；
  临时 `gbrain-sync-staging` / `gbrain-sync-probe` 已删除，远端只剩这两个正式分支。
  其后两个文档提交（`9af0323593` 台账收口、`18ba403289` 基本信息表不追 HEAD）已用小 pack 推送，
  **最终两分支均为 `18ba403289`**。
- **教训**：跨 180 个 release 的窗口让 fork 侧首次推送变成 GB 级；「小增量、频繁合并」不只是
  冲突治理要求，也是推送可行性要求。下轮应显著缩短窗口。

## 3. 部署

本仓没有独立 `deploy` script。`~/.bun/bin/gbrain.cmd` 指向主仓 `src/cli.ts`，因此 master 快进后
本机 CLI 自动从 `0.60.461.0` 变为 **`0.60.636.0`**（`gbrain --version` 实测），无需重编译
`bin/gbrain.exe`。主仓 `bun run typecheck` rc=0。

推送因 `VERSION` 变化触发 fork 的 `Release`（ci-gate 需 `Test` + `E2E Tests` 通过才发布），
另有 `Test` / `E2E Tests` / `Actionlint` / `TLA+ specs`。fork Actions `enabled: true`，但历史 run
多为 `queued`（计费受限），不把 CI 当作已取得的信号。

## 4. 安装与本机迁移

- 主仓 `bun install` rc=0（2 packages）；`postinstall` 自动执行过一次
  `gbrain apply-migrations --yes --non-interactive`（`CUSTOM.md` 已记录该副作用）。
- 显式 `gbrain apply-migrations --yes` rc=0、`All migrations up to date`；
  v0.53.0 内容迁移 `shared-skills` 的 `action_required` 属上轮已登记的客户端原生激活稳态。
- `gbrain doctor --json`：`schema_version: Version 298 (latest: 298)`、1392 列校验通过、
  175 张表齐全、schema pack 一致、列宽 1024d 与 gateway 一致。
- doctor 整体 `unhealthy / health_score 0` 由 `sync_freshness`（source 13 天未同步）与
  `cycle_freshness`（333h 未 cycle）两个 fail，以及 harness wiring / trust / backup / graph 类 warn
  造成，属运维状态而非代码回归。报告顶层 `schema_version: 2` 是**报告格式版本**，不是 brain schema。

## 5. 推送后复核

| 检查 | 结论 |
|------|------|
| `check:schema-migration-order` | ✅ 不带 `GBRAIN_MIGRATION_BASE_REF` 覆盖即绿：`0 new migration(s) above origin/master's latest v298` |
| `check:behavior-since` | ✅ 绿 |
| `check:function-size` | ⚠️ 仍 105 FAIL，全是 `src\...` 反斜杠路径，既有 Windows 基线 |
| 远端 / 本地一致性 | ✅ `master`、`origin/master`、同步分支、两处 worktree 的 HEAD 全部 `06a600043f` |

## 6. 未纳入 / 残留

- 全量 `bun run test` 在 Windows 不提供信号，Linux CI/Ubicloud 仍需补跑（2026-11-10 已观察：
  fork 没有 Ubicloud runner，自有 Linux 信号不可得，见第 7 节）。
- `check:newlines` 之外的既有 Windows 假阳性（verify 95 项中其余 20 项）按 `test-report.md`
  第二节定性保持不变，未在本轮逐个消除。
- fork 的 Release 是否真正发布取决于 CI gate 与 runner 可用性（2026-11-10 已观察：`version` job
  success，`ci-gate` 等 Test+E2E 至 120 分钟超时，见第 7 节）。

## 7. 运维项闭环（交付后追加，2026-11-10 15:25–15:55）

- **sync**：`gbrain sync --source default --no-pull` 首跑 **rc=1**——`recovery_required —
  The physical checkout identity changed or belongs to another owner`（1 文件失败、3 条挂起）。
  `gbrain repair content-receipt-root` 预览 `0 item(s)`；`transfer prepare --self-transfer
  --confirm-relocated-root` 报 `No ownership reservation exists beside this checkout`。
  根因是 `C:\Users\GOBAO\Downloads\AI\` 下的 `.gbrain-owner-<hash>.json` reservation 缺失，
  而 checkout 内部的 stamp 与现场 `device`/`inode`/`birth` 完全一致。
  修复前备份 `~/.gbrain/brain.pglite.pre-selftransfer-20261110-1536`（100 MB），
  用**不带** `--confirm-relocated-root` 的 self-transfer（prepare → 重读 `admin_state`/`epoch`/
  `manifest` → accept）重建 reservation，`owner_epoch` 1→2、state active；
  重跑 sync **rc=0**（3 written / 2 modified / 23 chunks，1 个 `worktree_dirty` hold 不阻塞）。
  `doctor --only sync_freshness` → **ok**。步骤已写入 `CUSTOM.md`《运维：source checkout 的
  所有权 reservation 缺失》。
- **dream**：`gbrain dream --source default` **rc=0**，937.9s、partial；`propose_takes` 927s
  （超过 30s worker force-evict 线，#1972；20 页扫描出 6 条新提案 / 16 warning）、`embed`
  新嵌入 15 chunks、`lint` 57 项待办；`synthesize`/`patterns`/`extract_atoms` 因语料或
  active pack 未声明而跳过。`doctor --only cycle_freshness` → **ok**（2 federated sources）。
- **完整 doctor**：`status: warnings`、**0 FAIL**；13 个 warn 均为内容质量类
  （`brain_score` 60/100 的 links 0/25、`git_convergence`/`foreign_writers` 的用户未提交内容、
  `trust_scan`/`trust_tiers` 未回填、`takes_count` 0、`backup_coverage` 等），非代码回归。
- **Linux CI 观察**：fork 最新 push（`18ba403289`）的 Test / E2E 41 分钟仍 `pending` 且
  **jobs=0**；`actions/runners` total_count=0。根因是 workflow 的
  `runs-on: ubicloud-standard-*-ubuntu-2404`，fork 没有 Ubicloud runner；`Release` 的
  `version` job success、`ci-gate` in_progress 等 Test+E2E（120 分钟后超时）。上游
  `garrytan/gbrain` 同窗口 master 的 Test（3m6s）/ E2E（1m0s）/ Release（5m44s）均 success，
  仅作上游基线旁证。**fork 自有 Linux CI 信号仍不可得，与本次合并代码无关**。
- **trust backfill（用户追加授权）**：`--dry-run` 显示 22 页中仅 2 行有确定性信号；apply
  `mode: apply` / `pages.updated: 2`，最终 2 operator_curated / 2 agent_written / 18 unknown。
  `doctor --only trust_tiers` → **ok**（81.82%，阈值内）；完整 doctor 由 13 warn 降到 **12 warn**、
  health 35→40、仍 **0 FAIL**。
- **trust scan（用户追加授权）**：20 页扫描、**0 flagged**、complete（detector v2）；只记 receipt、
  不改行，未抑制任何检索结果。
- **trust claim-sources（用户追加授权）**：`--dry-run` 显示 `default` 可声明（18 行 unknown →
  operator_curated，2 行 agent_written 保持），`shared-skills` 因 `no_legacy_rows` 不可声明。
  apply 返回 `confirmation_required`——CLI 要求 owner 在终端亲自输入 source id，agent / 管道 /
  `--yes` 均不可，**未改动任何数据**（doctor 复核仍 18 行 unverified）。待用户在终端执行
  `gbrain trust claim-sources --brain host`。
- **分支与临时产物收口（同日后续）**：`master` / `sync/upstream-2026-11-10-553b547334` /
  `origin/master` 同点 `dea8d0a6d8`，双向 `merge-base --is-ancestor` 成立、`git diff` 为空。
  本地与 `origin` 的同步分支已删除；回滚锚点 `pre-sync/2026-11-10`（`a752cc41a4`）推 `origin`
  留存、本地 tag 删除；`.workbuddy/` 下 3 个 doctor JSON 与 3 个运行日志已清理（`memory/` 保留）。
  收口提交 `467a60a63b` 已推送。
