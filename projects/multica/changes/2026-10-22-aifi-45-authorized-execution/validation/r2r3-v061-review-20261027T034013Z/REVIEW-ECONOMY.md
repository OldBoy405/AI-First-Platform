本章裁决：R2 BLOCK（唯一阻断为表名双写，一行可修）
本章裁决：R3 INCOMPLETE（Q13 提交点标识未唯一）

核验：plan sha256 = `1b63d777…842821` 一致；只读 L487–550 与 L135/L160–161/L194–195/L454，未通读、未编辑、未跑 DB。

## Q1–Q13 闭合表（本轮 economy 轴）

| Q | 状态 | 依据（v0.6.1） |
|---|---|---|
| Q1 | closed | §3 L135 改为“判定条件与优先级以 R2.4 为唯一权威”，三档定码+优先级齐 |
| Q2 | closed | 单行当前 + `approved_revision` 单调 + 部分唯一索引；语义钉死“祖先下界”，无 `bound_kind`；多/零行=事实缺失 |
| Q3 | closed | 闭集加 `expected_repo_count`/`repos_digest`；`current_binding: ok\|mismatch\|unknown`，unknown→UNVERIFIABLE |
| Q4 | closed | 主体绑定解析 workspace、仅收 `crID`、他人 crID→404、拒收任何调用方 target/version；`workspace_revision` 已删 |
| Q5 | closed | R2.4 三列映射表 + 优先级 + “已知越界永不降级”+ 与 `crctl.mjs:1883–1884` 顺序一致 |
| Q6 | closed | `provenance_digest` 入闭集、legacy 必填、缺失/不符按事实缺失→UNVERIFIABLE，不降 legacy |
| Q7 | **partial** | 计数已 14（L161）、迁移三例“精确 14 名/每例≥14 PASS leaf”（L326）、无“13 张”残留；**但表名双写**（见 R2-N1） |
| Q8 | closed | 交付面已定并写明理由；§6 L193–195 收 5 端点、GET 码表+“未知按不可用”、映射指向 R2.4；L454 同步 |
| Q9 | closed | 三时点分离；reserve 取 CR `FOR SHARE`→授权 head→写 command，与 §4 L166 锁序一致；revoke `FOR UPDATE` 只等行锁、不取 command slot，不矛盾、无成环；`effect_ref` 定身份、report 幂等 |
| Q10 | closed | journal 三态；恢复先 `git ls-remote` 只读核实三分支；unknown 禁新 publish |
| Q11 | closed | 不新增 CR 状态；`halted:{at_effect,reason}`；receipt 不改写；唯一自动入口 `recoverWriteSet` 且 `input_digest` 不同即拒；不新增 abort |
| Q12 | closed | 零/部分/全部待 finalize 三行矩阵 + `input_digest`；finalize push 为独立 effect |
| Q13 | **partial** | 提交点写成“head 变更**或** grant 撤销记录可见”二选一未定；且 `after-head-read`+`55P03` 只证互斥不证“撤销已提交”可见性 |

## 新 finding

| ID | sev | 位置 | 最小修订 | 归属 |
|---|---|---|---|---|
| R2-N1 | med | L491 vs L160/L161 | R2.1 写 `cr_execution_code_source_freeze`，§4 台账与计数行写 `code_source_freeze`，而 L326 要求 `ChannelTableNames` **精确 14 名**——同一张表两个名字，14 名清单不唯一。统一为单一字符串并四处同改 | author（R2） |
| R2-N2 | low | L135 vs L514 | §3 声明 5 码，R2.4 又出现 `AUTH_SCOPE_REPOSITORY_IDENTITY_MISMATCH`；需注明其为 findings 子码、外层仍折叠 `AUTH_SCOPE_VIOLATION` | author |
| R2-N3 | low | L509–515 vs L519 | `head_revoked→REVOKED`、`head_id 与重读值不同→HEAD_MOVED` 无对应 leaf，与 L135“每条各配 leaf”不合 | balanced |
| R2-N4 | low | L504 | `repos_digest` 不含 `freeze_revoked`/`current_binding`；补一句“摘要只证集合完整与授权事实，易变字段按 R2.4 单独判定” | author |
| R3-N1 | low | L493 vs L530 | 撤销提交点词汇三处不一；建议只认“freeze 当前行 `revoked_at IS NOT NULL` 可见”，夹具钩位相应写明 | author（R3） |

残留 token：`workspace_revision` 仅 L454/L489 两处，均为“已删除”陈述；无“13 张”；无“未定交付面”。L454 记录“13→14”“3→5”与实际一致。

## 最小通过集合

1. 统一 freeze 表名为单一字符串（同步 §4 台账、计数行、迁移 14 名清单、R2.1）。
2. 写死撤销提交点唯一可观测标识，R2.1/R3.1/夹具用同一词（消 R3-N1、闭合 Q13）。
3. 补 R2-N2 子码说明与两条缺失 leaf（REVOKED、HEAD_MOVED）；R2-N4 一句边界说明。
4. 以上均为文档级单点修订，不改已定事项。

残余风险：Q13 若不先定标，“撤销先提交/reserve 先提交”两支夹具可能各按不同可见性锚定，出现假 PASS。
