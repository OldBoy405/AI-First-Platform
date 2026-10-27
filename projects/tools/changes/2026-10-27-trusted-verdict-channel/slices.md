# 可信 T committed verdict channel — tools 切片计划

## Dependency Graph Summary

```text
T-S2 协议/trust manifest ── T-S3 store ── T-S4 worker/fence/恢复 ── T-S5a facts/repair/sensitive
                                     │
multica M-R2 merge-facts 端点 ── T-S5b merge 范围(19 leaf) ── T-R2 客户端(11 leaf) ── T-R3 reserve/report(16 leaf)
                                     │
                     T-S8 readiness 求值器（独立）
```

## Slice Execution Plan

| # | 优先级 | 风险 | 目标 | TC 覆盖 | 依赖 |
|---|---|---|---|---|---|
| T-S2 | P0 | 高 | `VerifyEnvelope`、trust manifest exact keys、跨语言向量 | TC-TR-001/002 | multica M-S2 合同 |
| T-S3 | P0 | 高 | `ApplyOnce`、journal/原子 bundle/冻结帧链 | TC-TR-003/004 | T-S2 |
| T-S4 | P0 | 高 | fence、checkpoint、恢复表（T 侧） | TC-TR-005..007 | T-S3 |
| T-S5a | P0 | 高 | facts 接线、repair 追加、sensitive 规则 | TC-TR-008..011 | T-S3/T-S4 |
| T-S5b | P0 | 高 | `collectCommittedPaths`、四证明、插入点与零写入 | TC-MG-001..008 | multica M-R2、M-S7 |
| T-R2 | P0 | 高 | `merge-facts` 客户端与码序 | TC-MG-009..013 | T-S5b |
| T-R3 | P0 | 高 | `merge-effects` 客户端、journal 三态、恢复矩阵 | TC-MG-014..020 | T-R2 |
| T-S8 | P0/P1 | 中 | readiness 求值器（T 侧） | TC-TR-012 | T-S2 |

## Rationale

- 协议先于 store、store 先于 worker/恢复、恢复先于 facts（否则无法判定「旧账本是否可信」）。
- merge 范围核对必须在 `mergeCr` 的既有 gate **之前**插入，越界只拒；`merge-facts` 客户端随后提供可信事实，
  `merge-effects` 再兑现撤销线性化——顺序不可颠倒（否则会用未核实的授权去 reserve）。
- 每片单 writer；`lib/workspace-transactions.mjs` 只在一处插入，避免并发改同一文件。
- 46 条 merge leaf 的 mutation 不完全 1:1：`越界零写入` 需两条 mutation，`release-subject 缺失` 与「无法核实」共用一条，
  清单必须显式记录，不得用「N:N」概括。
- 真实 merge 与真实 CR 一律不做；只在临时 Git 仓和注入的 publish 端口上验证副作用。
