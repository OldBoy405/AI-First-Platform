# 设计调整记录（Phase 3 实施中偏离 / 补充）

> 只记录相对 Gate 2 裁决矩阵的偏离与新增决策，矩阵主体（19 冲突裁决）未变。
> 处置依据始终是 `CUSTOM.md`《合并守则》，本文件不构成新的事实源。

## D1. `AGENTS.md` 从 `llms-full.txt` inline 改为 link-only（计划外）

- **原设计**：以上游 `llms-full.txt` 为基底，由 `bun run build:llms` 重建。
- **实际**：`WARN: llms-full.txt (804884 bytes) exceeds FULL_SIZE_BUDGET (800000)`；
  `test/build-llms.test.ts` 的体积门与 `check:regen-all` 的 llms lane 同时红。
- **量化根因**：上游 `llms-full.txt` = 796289 字节，距预算仅 3711 字节；
  上游 `AGENTS.md` = 29516 字节，fork 因两对 `CUSTOM (Qoder)` 围栏为 37946 字节（+约 8 KB）。
- **处置**：给 `scripts/llms-config.ts` 的 AGENTS.md 条目加 `includeInFull: false`。
  改 link-only 后 766842 字节、`llms.txt` 索引不变、Qoder 仍直接读 `AGENTS.md`。
- **明确未做**：没有删除 Qoder 围栏来凑预算——那是台账标记的二开资产。
- **已写入** `CUSTOM.md`《合并守则》作为本仓特有规则，含「上游若调整预算或 llms-config 结构，
  按上游新基底重贴该行并复跑 `regen:all` + `check:regen-all`」的合并注意。

## D2. 迁移改名后补扫按路径登记的基线 TSV（Gate 3 抓到的真实回归）

- **原设计**（迁移改号执行单 E1–E6）：只改文件名 / 导出名 / `version` / registry，跑迁移三道探针。
- **实际**：`check:page-body-readers` 红——`scripts/page-body-readers-baseline.tsv` 仍留 `v275`
  reviewed row（stale），新 `v298` 文件没有登记（new whole-body reader）。
- **处置**：该行改为 `v298-inbox-workflow-frontmatter.ts / v298 / sql / INLINE`，
  保留 `GBrain Custom` 理由；复跑 `ok, 694 baseline rows`。
- **规则化**：迁移执行单新增 **E7「按路径登记的基线 TSV 全量扫描」**；
  `CUSTOM.md`《合并守则》补「迁移号顺延后必须同步扫所有基线 TSV」。
- **教训**：生成器重建只覆盖 `.generated.ts` / goldens；**人工维护的、以文件路径为键的基线表
  不会自动跟随改名**，这类表在改号时必须逐张 grep 旧号。

## D3. 上游新增 `core-world-reads` ratchet 的基线重贴

- **原设计**：未预见该 guard。
- **实际**：`check:core-world-reads` 把 `src/core/ai/build-gateway-config.ts` 的 `process_env`
  钉在 13，fork 的 `DEEPSEEK_BASE_URL` 两处引用使实际为 15。
- **处置**：按守卫自身的 raise-with-justification 出口把该行改 15 并写明理由。
- **明确未做**：没有删掉 fork 的 `DEEPSEEK_BASE_URL` 增量来迎合上游基线——违反「上游基底 + 二开补回」。

## D4. 上游 `MinionJobContext.idempotency_key` 契约漂移

- **实际**：`bun run typecheck` 报
  `test/inbox-workflow.test.ts(39,3): error TS2741: Property 'idempotency_key' is missing ...`。
- **处置**：fork-only 测试的 `job()` mock 补 `idempotency_key: null`；复跑 `TYPECHECK_EXIT=0`。
- **判断**：上游新增必填字段，fork 侧只需补构造数据，不改运行时契约。

## D5. `admin/bun.lock` 从「取上游基底」升级为「取基底 + 重算」

- **原设计**：按生成物规则 `git checkout --theirs` 取上游 lock。
- **实际**：上游 lock 不含 fork 的 `jsdom` / `tailwindcss` / `vitest`，
  `bun install --frozen-lockfile` 直接 `FROZEN_EXIT=1`（干净安装会失败）。
- **处置**：确认 `admin/package.json` 无 `postinstall` 后，在 `admin/` 下执行 `bun install` 重算 lock；
  复验 `223 installs / 289 packages (no changes)`、`FROZEN_EXIT=0`。
- **边界**：**没有在根仓执行 `bun install`**——`CUSTOM.md` 记录 root postinstall 会动 `~/.gbrain`。
  工作区无 `node_modules`，改用 PowerShell Junction 复用主仓依赖。

## D6. `bun run verify` runner 在 Git Bash 下死锁，改用有界并发驱动

- **实际**：首次全量 verify 跑到第 18 项后 21 分钟零输出；`ps -ef` 显示 runner 子壳卡在
  `$(jobs -rp | wc -l | tr -d ' ')` 的 `wc`/`tr` 上（后台作业持有管道写端，`wc` 等不到 EOF）。
  这是 runner 的节流实现问题，**不是检查失败**。
- **处置**：终止僵死进程树；`git add -A` 消除暂存假阳性；用自写有界并发驱动
  （每批 4 个 + `wait`、单项 `timeout 180`、per-check rc 哨兵）重跑同一 `--dry-list` 95 项。
- **走过的弯路**：Python 版驱动 `subprocess(["bash", ...])` 在 Windows 解析到 WSL `bash.exe`
  被安全策略拦截，清单为空；已弃用并未重试该路径，改用 Git Bash 原生脚本。
- **已写入** `CUSTOM.md`《已知测试失败基线》，注明 `124` 是超时而非 merge accident。

## D7. `check:newlines` 上游解禁照出 fork 存量欠债

- **实际**：上游本轮把该 guard 接进 verify，rc=124 超时。等价快速计算显示
  250 个 `.qoder/repowiki/**/*.md` 缺尾换行。
- **归属判定**：合并前 fork HEAD 上同样 250 个；上游树根本没有 `.qoder/` 目录；
  脚本在合并前 fork HEAD 也存在但未进 verify。→ **存量欠债，非合并事故**。
- **处置**：不在本轮批量改 250 个文档（超出上游合并范围），登记到 `CUSTOM.md`《待办》，
  并记「若 CI 以该门为准，需单独一次性补齐尾换行」。

## D8. 尺寸棘轮两次上调（4 → 5 → 9 个文件）

- **实际**：首次 `check:module-size` 报 4 个超限，写 `ratchet.py` 上调；完整输出后又见 5 个，
  写 `ratchet2.py` 统一上调。曾有一次命令因 `tail` / 工具超时被 SIGTERM，输出不完整。
- **处置**：改为输出重定向到文件后 `grep -E '^FAIL: '` 收集完整清单，一次性按现场行数重贴 9 个文件，
  保留 / 补上 `GBrain Custom` 来源标注（共 11 行）。
- **最终真值**：`check:module-size` 长超时单跑 239s → `OK`、rc=0。

## D9. 全量单测的替代方案（沿用上轮 D6）

- **原设计**：`bun run test` 取全量信号。
- **实际**：Windows 下 shard 统计解析失败 + 挂死文件（`CUSTOM.md` 既有基线），终止。
- **替代**：21 文件合并面定向批（571 用例）+ Admin vitest（227 用例）+ 迁移探针 + 95 项 verify 定性。
- **残留风险**：本地结论**不表述为「全量全绿」**；Linux CI/Ubicloud 需补跑一遍。

## D10. 外置 STDD 档案不伪造 CLI 状态

- **实际**：本轮沿用四 Gate 变体，但**没有通过 STDD CLI 创建 change**。
- **处置**：档案只写人工可验证的记录（proposal / gate1-detail / gate2 矩阵 / test-report /
  design-adjustments / spec-delta / 证据 TSV），**不生成** `.stdd.yaml`、`canonical/`、
  CLI Human View。按 `AI_OPERATING_MANUAL.md`，这些必须由 CLI 推进，手工写会伪造 Gate 确认状态。
- **Gate 3 状态**：验证完成但**未取得用户确认**，因此不标 `deliver: completed`，
  也不把后台任务完成通知当授权。见 `README.md`。
