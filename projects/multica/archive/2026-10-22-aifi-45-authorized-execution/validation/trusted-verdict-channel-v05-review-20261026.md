# 可信 T 裁决通道方案 v0.5 三路复核记录（2026-10-26）

> 评审对象：`trusted-verdict-channel-implementation-plan-20261026.md`。三路均为**非作者**只读计划级复核；
> requested/actual 模型见下（actual 无后端回执的记 unknown）。本记录不授予 Gate、commit/push、部署或注册授权。

## 结论汇总

| 档位 | session | 结论 | 核心判定 |
|---|---|---|---|
| strong | `01a1796a-23b8-77b9-a3c5-0f7bb49a78dc`（requested `OpenAIPersonal/gpt-6.1-sol:high`，actual unknown） | **BLOCK / INCOMPLETE**（仅针对 v0.5 增量） | 已批准 SHA 的可信来源、被核对对象与实际发布对象的一致性、零写入边界、mutation 对应关系未闭合 |
| balanced | `01a1796a-6197-77b9-a3c5-0f7c0aa2351c`（requested `Gobao/deepseek-flash:max`，actual unknown） | **INCOMPLETE** | ③ 改动集合取自 agent 可写的 `approval.yml`；零写入/复用唯一实现与已交付代码行为不一致；leaf:mutation 6:5 |
| economy | `01a1796a-91f3-77b9-a3c5-0f7f2e805ad0`（requested `GB-JP/deepseek-flash:high`，actual unknown） | **INCOMPLETE** | 同上（③ 来源），另指出 merge 端点与失败码未定义、X7 表述在字段语义上错误 |

> **errata（2026-10-26 第二轮复核发现）**：本表三个 session id 原误写为 `01a17797-…`，实际为 `01a1796a-…`，已在此更正；`tc-coverage` 增量 30 的同名缩略引用同错。第二轮三路复核（`v05-rerun-20261026T235224Z/`）读的是**修正前**的冻结副本，其结论不变。

## 三路共同命中（已修订）

1. **③ 改动集合的权威来源是 agent 可写文件**：`approval.yml#code.release-subjects` 位于控制根内，与 Goal「三项输入均不得来自 agent 可写处」矛盾。
2. **核对区间小于发布区间**：`trunk...<release subject sha>` 会漏掉 release subject 之后的提交（含 `approval.yml` 自身与 KB 文档）——正是 X7 要守的面。
3. **S5 leaf/mutation 不是一一对应**：`legacy merge 不核对范围` 无对应 mutation。
4. **X7 字段语义错误**：路径前缀属于 `allowed_paths[repo]`，不是 `allowed_repositories`（后者是 repo id）。
5. **文档内部不一致**：修订记录 v0.5 行仍写“提出待决 X7”。

## strong 独立命中（第一轮未覆盖，已修订）

6. **核对对象 ≠ 实际发布对象（最深的一处）**：`mergeCr` 首次发布 preflight 冻结的是**远端 requirement ref == 工作区 HEAD**；KB 允许批准 SHA 为 HEAD 祖先并允许其后审批/文档变化，代码仓本地信任允许 tree 相等。故“工作区不是将发布的内容”推不出“批准 SHA 完整代表将发布的内容”。
7. **现有 gate 不是零副作用**：`approval` 分支 evidence drift 时 `emitDriftAudit` 写 `.crctl/outbox`；`mergeCr` 内的锁（`owner.json`）、journal 创建与 `recoverWriteSet` 也早于 release-subjects 读取。
8. **单次 merge 内的授权 TOCTOU**：prepare → 逐仓 publish → rebuild 多段，开始时的 head 查询不保证发布时仍有效。
9. **`evaluateChangeScope` 空集合 fail-open**：缺失/非数组 changes 当空数组返回 allowed；它是判定器，不是采集完整性验证器。
10. **SHA 采集适配细节**：rename 源/目标都要查；symlink 必须取自选定 tree/blob 而非工作树；路径需无损分隔与引号解转义。
11. **Legacy 口径**：行为不变仅限**可信历史目录证明的** legacy；Unknown/目录故障/Strict 删投影三类入口需正反例。
12. **归属划分**：采集器的通用缺陷（路径编码/rename/symlink）归 AIFI-45 就地修，两条输入路径共用；本方案只定“取哪些 SHA/树”的契约。

## 修订落点

- 第一轮修订（balanced/economy 之后）：③ 权威来源改 M 持久 code 批准记录、核对区间改 `trunk...HEAD`、失败码闭集、零写入外延收窄、与 `verifyReleaseSubjects` 的顺序、复用边界写实、X7 字段语义修正、leaf/mutation 6:5→10:10。
- 第二轮修订（strong 之后）：核对对象 = 实际发布对象（(a)/(b) 二选一，推荐 (a)）、恢复沿用原冻结输入、插入点前移到现有 gate 之前、首次拒绝 vs 并发失败、授权效力线性化与部分发布后处置、空集合四证明、SHA 采集适配细节、Legacy 口径收窄、X7 合法恢复流程、归属划分；S5 再补 6 条 leaf 与 4 处 mutation 触发条件补强。

## 状态

- **修订后的方案尚未复核。** 三路结论只覆盖各自读到的版本；要把本方案作为注册 M003 的依据，需再跑一轮。
- 方案仍为 proposed / 已搁置（用户 2026-10-26 决定由用户自行另开 change），未注册、未实施、未据此建目录或写源码。
