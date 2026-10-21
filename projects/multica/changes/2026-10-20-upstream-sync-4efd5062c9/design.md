# 上游同步技术设计（Gate 2 草案，未确认）

## Context

- 窗口 `e0f84dda4..4efd5062c9`，101 个上游提交，978 个上游改动文件。
- 两边都改的文件 119 个；其中 server 64、packages 53、.github 1、scripts 1。
- Gate 1/2/3 已确认（Gate 3 2026-10-21T11:30:10）；merge `a3af2341f` + 测试修复至 `874ea9621`；CUSTOM 台账 `1dc9ffeb7`；未 push。

## Decisions（草案）

### D1：merge 还是 rebase

建议 **merge**。理由：

- CUSTOM 的第八次同步记录使用 merge commit `7680aa700`；
- 合并后的「两父均有而在落树缺失」路径审计依赖两父结构；
- rebase 会重写 fork 提交历史，使台账里的 merge 记录和 A/B 审计失效。

CONTRIBUTING 规则三写的是 rebase，需要在 Gate 1 拍板。若选 rebase，验收模型要改成 patch-id / 提交集合等价，不再用两父路径审计。

### D2：迁移号顺延 +20

- 上游本窗口新增 565–579、581–584（565–584 区间，580 缺号）。
- fork 占用 565–621，57 个 up/down 迁移。
- 建议整体顺延 **+20 → 585–641**。
- 需要同步更新：`server/cmd/migrate/main.go` 的 cleanup map、migrate 测试、号引用测试、CUSTOM《迁移编号冲突》。
- 迁移号冲突是数字层面的，git merge 不会报错；必须在合并前主动检测。

### D3：生成物

- 9 个 `server/pkg/db/generated/*.go` 在上游窗口内改动；冲突时丢弃冲突块，重跑 `make sqlc`。
- 本窗口未发现 `governance/*gen*` / registry 上游改动；合并后仍要核对 `gate_nodes_gen.go`、`transitions_gen.go`、registry 生成物，若与真源不一致则重跑生成器，不手改。

### D4：冲突裁决矩阵

- 119 个文件在 Gate 2 按 CUSTOM 四类口径（上游胜出 / 重新摘除 / 取并集 / 贴回挂钩）逐文件或逐 hunk 分类。
- 高风险簇：db generated、daemon、handler、agent、packages/core realtime/chat、locales。
- 同一文件可以按 hunk 拆成多行；Gate 2 确认策略与预测面，不逐个 hunk 预览。

### D5：执行模式

`thorough`。119 个潜在冲突、迁移撞号、9 个生成物、64 个 server 文件，不适合 standard/lightweight。

## Gate 2 矩阵（草案，未确认）

- 文件：[gate2-decision-matrix.md](gate2-decision-matrix.md)
- 机器可读：[gate2-decision-matrix.csv](gate2-decision-matrix.csv)
- 汇总：取并集 58、贴回挂钩 38、按内容核对 12、生成物重跑 9、重新摘除 1、分半 1；合计 119。
- 12 个“按内容核对”均为无标记 server 文件，合并时按内容与台账 #N 复核；发现未登记改动先补台账。
- Gate 2 已确认；merge 执行中。

## Open Questions

1. merge 还是 rebase？
2. 接受一次 101 提交的合并，还是先拆窗口？
3. 是否授权按 `ledger-repair-plan.md` 修 CUSTOM.md（独立于 merge 提交）？
4. 迁移顺延 +20 → 585–641 是否确认？
