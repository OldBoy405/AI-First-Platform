# BUILD 测试报告（tools 侧，截至 2026-10-27）

> 证据入口：multica 侧 `validation/evidence-index.md` 与本目录 `*-report.md`。

## 已验证

| 模块 | 结果 |
|---|---|
| `lib/execution-control-protocol.mjs` | `test/execution-control-protocol.test.mjs` 2/2 PASS；m1/m2 各自只打红自己的 leaf |
| `lib/execution-control-store.mjs` | `test/execution-control-store.test.mjs` 2/2 PASS；m1/m2 各自只打红自己的 leaf |

## 未验证

| 项 | 状态 |
|---|---|
| SC-TR-003 并发三请求、rename 前后 kill | 未测（未注入崩溃点） |
| SC-TR-001 Go↔Node 双向「同字节同 digest」 | Go 侧 `cross_language_vectors` 不存在，当前只有 Node 侧自证 |
| merge 三族（`collectCommittedPaths` + merge-facts 11 leaf + merge-effects 16 leaf） | 未实现 |
| `component-readiness` 严格入口、`merge-facts`/`merge-effects` 门禁接线 | 未实现 |
| Windows 目录 fsync 容忍分支 | 实现已存在，待在 Gate 3 披露其适用条件 |

## mutation 可复现性

mutation 的源文件 sha256 由 multica 侧 checker 的 `record`/`verify` 判定；本侧暂无独立 patch 落盘，缺口与 multica 侧 `test-report.md` §3 相同。
