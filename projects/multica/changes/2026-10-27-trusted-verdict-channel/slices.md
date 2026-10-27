# 可信 T committed verdict channel — multica 切片计划

## Dependency Graph Summary

```text
648 迁移(14表) ──┬─ S1 selection/reservation/root/fresh-work
                 │        │
                 │        ├─ S2 协议/trust manifest ── S3 store 状态机 ── S4 恢复
                 │        │                                        │
                 │        └──────────────── S5 facts/repair/resume ─┴─ S6 ingest/binding
                 │                                                        │
                 │                                                        └─ S7 reader/fence
                 │                                                              │
                 └──────────────── R2 merge-facts ── R3 merge-effects ──────────┘
                                          └──── S8 D7 部署就绪（R0–R4）────┘
```

## Slice Execution Plan

| # | 优先级 | 风险 | 目标 | TC 覆盖 | 依赖 |
|---|---|---|---|---|---|
| P0 | P0 | 高 | daemon 侧隔离证明（Linux + Windows 分别出证） | TC-VC-037 | 隔离环境与 profile 授权 |
| M-0 | P0 | 高 | 648 迁移 14 表、`ChannelTableNames`、四组迁移专例 | TC-VC-028/029 | 隔离 nonce 库授权 |
| M-S1 | P0 | 高 | 可信 selection、不可执行 reservation、同 Tx root/task、FreshWork 注册 | TC-VC-001..005 | M-0 |
| M-S2 | P0 | 高 | `VerifyEnvelope`、trust manifest exact keys、Go↔Node 向量 | TC-VC-006..008 | M-S1 |
| M-S3 | P0 | 高 | command/cursor/settlement 状态机、不可篡改、撤销/stop 排序 | TC-VC-009..014 | M-S1/M-S2 |
| M-S4 | P0 | 高 | checkpoint、恢复表、旧 fence 隔离 | TC-VC-015/016 | M-S3 |
| M-S5 | P0 | 高 | typed facts、repair 追加、signed resume、sensitive action | TC-VC-017..020 | M-S3/M-S4 |
| M-S6 | P0 | 高 | ingest/settlement/daemon client、启动前 643–645 全匹配 | TC-VC-021..024 | M-S5 |
| M-S7 | P0 | 高 | DB-only reader、projection fence、终态 fence 并集 | TC-VC-025..027 | M-S6 |
| M-R2 | P0 | 高 | `merge-facts` 端点与 `code_source_freeze` | TC-VC-030..033 | M-S1/M-S7 |
| M-R3 | P0 | 高 | `merge-effects` reserve/report | TC-VC-034..036 | M-R2 |
| M-S8 | P0/P1 | 高 | D7 观测/readiness/activation/launch（R0–R4） | TC-DR-001..006 | M-S1/M-S7 |

## Rationale

- 先有 schema 与不可执行候选，才谈裁决落点；协议先于 store，store 先于恢复，恢复先于 facts（否则无法判定「旧账本是否可信」）。
- `merge-facts` 依赖 selection 与 reader 的判定链，`merge-effects` 再依赖 `merge-facts` 的事实等价性；D7 只依赖 selection 与 fence，不与业务预算耦合，避免自举环。
- 每片单 writer；schema/query/model 与共享 Runner 不并行改。测试先 RED→GREEN，一片完整覆盖并回归后才登记完成。
- 并发/崩溃用确定性 barrier 与 `lock_timeout`/`55P03` 探针；父测试 PASS 不能遮住子用例全 SKIP。
- 真实 `strict-production` 正例归 AIFI-45 下游；本 change 只交组件正例与 strict 反例，不声称生产就绪。
- 任一 required profile/隔离身份未定时记 UNVERIFIED，不跑迁移、不跑 DB 用例，不伪造替代证据。

## P0 门控（Gate 2 前用户采纳）

| 分组 | 片 | P0 未绿时 |
|---|---|---|
| 两条路径都适用 | M-0、M-S1、M-R2、M-R3 | 可先行 |
| 依赖方案 C（daemon 持 T worker） | M-S2 的 daemon trust 部分、M-S3、M-S4、M-S5、M-S6、M-S7、M-S8 | 阻塞，直到 P0 两平台证据齐 |

- P0 排第一；隔离环境授权短期不可得时，只推进「两条路径都适用」组。
- P0 失败：停止 C 路径，转 B 须另行提审；已完成的「两条路径都适用」组按 B 复核后再决定保留，不默认作废也不默认沿用。
- leaf 级验收以 `validation/channel-test-expectations.json` 为准（SPEC 已冻结）。
