# BUILD 切片执行计划

## Dependency Graph Summary

```text
Slice 1 (冻结/隔离/验证 helper)
   └── Slice 2 (合并 + 67 双边裁决)
          └── Slice 3 (迁移 v337 + 探针)
                 └── Slice 4 (生成物重建)
                        └── Slice 5 (质量验证 + 上游覆盖)
                               └── Slice 6 (台账 + 审计收口)
```

- 单 capability（upstream-sync-merge），无可并行切片：全部操作共享同一同步 worktree 与 index，顺序执行避免 index/暂存冲突。
- 人工 TC（TC-USM-002 fork 归因、TC-USM-004 上游覆盖）在 C2 以同 run 的 `stdd agent confirm` 签收，不绑定切片登记。

## Slice Execution Plan

| # | 优先级 | 风险 | 工作量 | TC 覆盖 | 实现目标 | 依赖 |
|---|---|---|---|---|---|---|
| 1 | P0 | 中 | M | TC-USM-001 | 隔离 worktree/分支/回滚锚；冻结证据；验证 helper（freeze）与其自测 | 无 |
| 2 | P0 | 高 | L | TC-USM-003 | `merge --no-ff --no-commit`；67 双边逐行裁决；527 fork 归因核对；门禁 TSV 贴回 | 1 |
| 3 | P0 | 高 | M | TC-USM-005 | v298→v337 顺延；registry/latest 重建；基线 TSV/金标准；顺序/registry/空库探针 | 2 |
| 4 | P0 | 高 | L | TC-USM-006 | regen:all 二次无漂移；build:admin + 嵌入清单；admin/bun.lock；VERSION 门禁 | 3 |
| 5 | P0 | 高 | L | TC-USM-007 | typecheck、定向批次、Admin 套件、PGLite E2E；失败基线 A/B；未跑项登记 | 4 |
| 6 | P0 | 中 | M | TC-USM-008 | 双父 diff 审计；CUSTOM-LEDGER 记录；交付边界；test-report | 5 |

## Rationale

### Slice 1：隔离候选与冻结证据

- 依赖：后续全部操作以可回滚候选为前提。
- 风险：远端 tip 已前进到 0a6aa6c409，冻结目标仍为 Gate 1 的 22f8c793b1，不得追新。
- 工作量：worktree/分支/tag + freeze CP + helper 骨架，属于 M。
- 经验库：无匹配。

### Slice 2：三方合并与行为裁决

- 依赖：冻结候选稳定。
- 风险：67 双边路径多数无文本冲突；生成物与门禁 TSV 不能手拼；上游删除路径须解释。
- 工作量：527 fork 路径归因 + 67 裁决 + 冲突解决，属于 L。
- 经验库：无匹配（台账 154/208 行的历史事故作为检查清单）。

### Slice 3：迁移顺延

- 依赖：合并后 registry 输入稳定。
- 风险：同名 v298 被旧库跳过；基线 TSV 漏改造成门禁红；金标准手拼。
- 工作量：迁移改名 + 生成器重建 + 三类探针，属于 M。
- 经验库：无匹配。

### Slice 4：生成物重建

- 依赖：源码与手写基线已裁决。
- 风险：只跑 freshness 不重建无法证明输入正确；Admin 嵌入清单未暂存会假红。
- 工作量：regen 18 artifact + Admin 构建 + lock 重算，属于 L。
- 经验库：无匹配。

### Slice 5：质量验证

- 依赖：生成物稳定。
- 风险：Windows 全量 runner 无完整信号；同项同因失败须 A/B；未跑项不得冒充通过。
- 工作量：typecheck + 定向批次 + Admin 套件 + E2E，属于 L。
- 经验库：无匹配。

### Slice 6：审计与台账

- 依赖：全部验证信号已取得。
- 风险：双父 diff 归因缺失、whitespace 误判、越权交付。
- 工作量：Git 审计 + 台账记录 + 报告，属于 M。
- 经验库：无匹配。
