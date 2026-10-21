# 上游同步验收计划（Gate 3 草案，未确认）

> 本文件只定义合并后的对账断言；当前 Gate 1 BLOCKED，未运行测试、未执行 merge。

## 对账断言

| # | 断言 | 命令/方法 | 期望 |
|---|---|---|---|
| A1 | 台账修复后 §0 通过 | CUSTOM 核对命令 + 人工四维 | PASS / PASS-WITH-FIX |
| A2 | 挂钩四数不丢失 | CUSTOM `git grep` 口径 | ≥ 442 / 1400 / 541 / 278；差异逐项归因 |
| A3 | 迁移号无重复 | 列出 565–641 的 up 迁移号 | 上游 565–584；fork 585–641；无重号 |
| A4 | 空库迁移 | 空库 `migrate up` | 末位 641，版本数连续 |
| A5 | 生成物与真源一致 | `make sqlc` + `git diff` | 无意外差异 |
| A6 | 落树路径审计 | `git ls-tree` 两父 + `comm` | 两父均有而缺失 = 0 |
| A7 | Go 构建 | `go build ./...` | 绿 |
| A8 | Go vet | `go vet ./...` | 绿 |
| A9 | 前端类型 | `pnpm typecheck` | 绿 |
| A10 | 定向测试 | 按冲突模块 `go test` / `vitest` | 通过 |
| A11 | 全量测试 A/B | `pre-sync/2026-10-20` vs 合并树 | 失败集不扩大；既有 Windows 基线除外 |
| A12 | locales parity | `vitest run locales/parity.test.ts` | 通过（如涉及前端） |

## 状态

- Gate 1：confirmed at 2026-10-20T22:58:15（dialog / user）
- Baseline 2026-10-20：`go build` / `go vet` 绿；`pnpm typecheck` 10/10；`pnpm test` core/web/docs/ui-lab 绿、views 491/491、desktop 仅 `scripts/package.test.mjs` 已知基线失败。
- Gate 2：confirmed at 2026-10-21T08:44:25（dialog / user）
- Gate 3：confirmed at 2026-10-21T11:30:10
- merge：origin/main `f6e90ab80` (`a3af2341f` + CUSTOM `1dc9ffeb7`/`f6e90ab80`)
- push / deploy：not executed
