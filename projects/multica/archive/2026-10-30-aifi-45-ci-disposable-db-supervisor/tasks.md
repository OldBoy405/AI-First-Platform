# AIFI-45 一次性库实例生命周期与测试守卫边界 — 任务清单

## 1. TMPDIR 拒绝（test-wrapper-path-guard，P0）

- [x] 1.1 在 `test-go.test.sh` 写 TC-TWG-001（RED：修复前假命令被执行）
- [x] 1.2 `go-test-with-agent-cli-guard.sh` 在 mktemp 前拒绝含 `:` 的 TMPDIR（GREEN）
- [x] 1.3 TC-TWG-003：空 TMPDIR 回退 `/tmp`
- [x] 1.4 `test-go.test.sh` 自身在 mktemp 前拒绝，并写 TC-TWG-002（只验修复后）

## 2. 实例模块（disposable-test-instance，P0）

- [x] 2.1 `instance.test.mjs`：TC-DTI-001、TC-DTI-003、TC-DTI-004（RED）
- [x] 2.2 `instance.mjs`：`buildRunArgs`、`releaseInstance`、`startInstance`（GREEN）
- [x] 2.3 `instance.real.mjs` TC-DTI-005：强杀入口后 TTL 自毁（依赖 2.2）

## 3. 入口接线（P0）

- [x] 3.1 `run-selection.test.mjs` TC-DTI-002（RED）
- [x] 3.2 `run-selection.mjs`：拒绝 `--admin-url`、取消 `AIFI45_ADMIN_URL`、`startInstance`/`finally` 释放（依赖 2.2）
- [x] 3.3 `instance.real.mjs` TC-DTI-006：一个通过、一个失败的真实入口运行

## 4. governance 身份核验（P0）

- [x] 4.1 `TestMainRejectsWrongDisposableNonceBeforeSetup`（RED：临时去掉核验）及 `TestVerifyDisposableTestDatabaseRejectsMismatch`；TC-DTI-007 的冻结证据使用 `selections.identity.json` 的 `governance-nonce-gate` 与 `governance-identity-check` 两个单测试选择
- [x] 4.2 TestMain 增加 `verifyDisposableTestDatabase`，修正陈旧注释（GREEN）

## 5. 测试与验证

- [x] 5.1 完整 `selections.json` 的 13 个选择经入口真实运行一次（C2 回归，需 `AIFI45_TOOLS_ROOT`，不属冻结证据）
- [x] 5.2 `provision.test.mjs`、`selection.test.mjs`、`test-go.test.sh` 全部通过
- [x] 5.3 `CUSTOM.md` 按其结构登记本 change 的定制
- [x] 5.4 C1 三路评审、C2–C7、test-report.md
