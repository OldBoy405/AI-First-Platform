# 2026-11-15-multica-backend-tests-green — 待处理设计偏离

## ADJ-BTO-1：启动扫描不再在游标打开时调用 Reconcile（2026-11-15，BUILD 中发现）

- **原设计**（`design.md` Decisions 3）：TestMTick003 在池上限 4 时挂起归因于阻塞式 `pg_advisory_lock` 占着池连接等锁；只要求 `withRunLock` 替换 `runner.go`、`runner_code.go`、`runner_requirement.go` 三处。
- **实测**：`withRunLock` 落地后，`governance-mtick003` @池 4 仍然挂起（`GOFLAGS=-timeout=120s` 下 exit=1、pass=0）。此时阻塞锁已只剩 `runner_requirement_entry.go`，不在该路径上。
- **实际根因**：`StartupScan` 用 `pool.Query` 的 rows 游标持有 1 条连接，并在 `rows.Next()` 循环里调用 `Reconcile`。6 个并发扫描各持 1 条连接后，池 4 已满，每个扫描器再要第二条连接 → 池耗尽；`StartupScanRequirement` 同形。锁等待与扫描持连接是同一表现的两个原因，设计只写了前者。
- **调整**：两个扫描器先收集 `(workspace_id, cr_id)` 目标、`rows.Close()` 释放连接，再逐个 reconcile。不放宽池上限，不改签名、行为语义或受审承诺。
- **影响**：`design.md` Decisions 3 的根因描述不完整，需在 `design-adjustments.md` 如实记录；`spec` 的 SC-RRL-001 不变（且现在满足）。代码净增约 20 行（含注释）。
- **验证**：修复后 `governance-mtick003` selection `PASS ... pass=1 fail=0 skip=0`；`governance` 全包 @池 4（CI 同款 skip-regex、共享一次性库）`2264 pass / 0 fail / 2 skip`，`GO_TEST_EXIT=0`。

## 备注：本地 `ci-provision.mjs --env-file` 在 Node 24 下不可用（环境问题，不属本 change）

`node ci-provision.mjs up --env-file <file>` 在 Node v24 会把 `--env-file` 当作 Node 自身的选项（文件不存在时 `node.exe: <path>: not found`，exit 9），脚本收不到该参数。CI 用 `GITHUB_ENV` 不受影响；本地改用 `GITHUB_ENV=<file>` 跑通。未修改该脚本（不在设计范围）。
