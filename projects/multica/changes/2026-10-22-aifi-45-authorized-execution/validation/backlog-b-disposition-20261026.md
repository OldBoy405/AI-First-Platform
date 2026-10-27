# 待办 B 独立分析与归属方案（2026-10-26，经复核补正）

> 作者：主会话（AIFI-45 BUILD）。范围：`gate3-review-20261026/` 两轴 BLOCK 中依赖规范或设计决定的项。
> 本文只是方案：没有实现，也不构成 Gate 结论。台账仍 41/49。并入 M003 的项已原位写进通道方案 v0.4（`trusted-verdict-channel-implementation-plan-20261026.md`）。该方案**仍搁置、未注册**。
> 初稿经三路非作者复核：strong **BLOCK**、balanced **INCOMPLETE**、economy **INCOMPLETE**。本版按其 findings 补正，处置见 `trusted-verdict-channel-v04-review-20261026.md`。

## 0. 更正

上一轮在对话回复里说过：“v0.3 关键词 0 命中，所以 M003 不覆盖”。这个说法只出现在对话中，没有写进任何文件。它有两处错，原因是**关键词搜不到不等于方案没写**：

| 上一轮说法 | 核实结果 |
|---|---|
| strict 靠 null 合同降级：0 命中 | v0.3 已经写明：`execution_verifier.go` 用 trigger 文本判 strict，新可信选择不能依赖它；strict fence 按持久 selection 查询，Unknown/查询失败不能降为 legacy。v0.3 缺的是“已选定后删字段不得降级”的显式断言和 T 侧对应项，v0.4 补上了。 |
| RUN-004/005 永久根接入真实派发，归“AIFI-45 自留” | v0.3 S1 本来就写着 caller-owned Tx、fixed-ID enqueue、postcommit notify。 |

`gate3-review-20261026/CLOSEOUT.md` 曾建议为“F1、终态 fence、strict、claim TOCTOU”另开独立 change。现在**撤回这个建议**：这几项要么已在 M003 的结构里，要么是 AIFI-45 已交付代码的本地缺陷。

初稿本身也有错，复核后已更正：

- **B9 理解错了。** RPR-007/008 要的是有权者签署的追加额度加前驱 CAS，不是“裁决日志追加”。
- **B2 直接加行锁会造成死锁。** 消费路径先持有 CR SHARE 再等 task；`BindCurrentTaskToCR` 先持有 task UPDATE 再等 CR，两条路径成环。
- **B3、B6 的“过渡规则”并不单调收紧。** 任务重领后能绕过；把账本换个位置会让额度归零；`.crctl` 又恰好是 agent 可写的。B6 因此整体移入 M003。
- **F1 只靠 peer credential 不够。** 自报真实 PID 照样能通过；fd 可以转交给别的进程；`/proc/<pid>/root` 也不是工具安装根。
- 初稿还漏掉了 EVD-005 的拆分、RPR 业务身份缺陷（B16）、B1 签发签名缺 generation 这几项。B13、B15 是语义决策，初稿却当成了实现项。

## 1. 逐项核实（只读，行号为当前快照）

| # | 评审项 | 代码事实 | 根因 |
|---|---|---|---|
| B1 | 消费可跨签发复用 challenge | `G/execution_consumption.go:165-168` 的 EXISTS 只比 `workspace_id, cr_id, grant_digest, challenge`；签发签名与重放（`G/execution_binding_issue.go` 约 `:251-255,:295-299,:325-342`）也不含 `dispatched_at`；643 表有 `task_id/runtime_id`，没有 `dispatched_at` | 签发与消费都没有绑定完整 generation |
| B2 | claim TOCTOU | `GetExecutionBindingClaim`（`pkg/db/queries/execution_binding.sql`）是普通 SELECT，JOIN 的 agent/runtime 也不锁；`GetAgentTaskForTerminalClaim`（`agent.sql:817`）按设计不加锁，走 CAS | 读后写之间没有锁，而且锁图没有定义 |
| B3 | 终态 fence 可以省略 | `H/daemon_terminal_claim.go:31-43`：`runtime_id`、`dispatched_at` **两个都缺**时走旧终态（只缺一个会被拒） | fence 由调用方自己选 |
| B4/B12b | strict 与合同选择可以降级 | `D/execution_verifier.go:27` → `pipeline_task.go:558-577` 根据 trigger 评论判定；tools 侧根据 `cr.md` 字段判定 | strict 的来源是可改的文本 |
| B5 | repair-admit 没有验签 | `T/crctl.mjs:1600-1618` 只做解码，`:1736-1745` 直接使用 `payload.repair_limit`；可复用的静态验签在 `T/lib/execution-authorization.mjs::readExecutionGrant`/`verifyExecutionEnvelope`（约 `:300,:321`） | 走了不验签的路径 |
| B6 | sensitive 额度可被重置 | 账本位于 `grant.installDir/actions`（`T/lib/execution-sensitive-action.mjs:33-40`），而 `installDir` 由 `--trust-root` 决定。**同一 operation_id 重放返回原 receipt，这是 SC-AUTH-006 的正当行为**；违规的是复制根目录后换新 operation_id 重新拿到额度 | 账本锚点由调用方决定，没有受保护的存储 |
| B7 | F1 代签 | `D/execution_binding_endpoint.go:129-146` 是 loopback TCP，把请求体里的 challenge（含自报 pid/root）原样交给 signer | 进程事实来自请求体 |
| B8 | dispatch_root 只在测试中可达，且存在 adoption/terminal 竞争 | 非测试文件里只有 `execution_dispatch_root.go` 自己引用 | 缺 caller-owned Tx |
| B9 | RPR-007/008 追加授权不存在 | 现有 initial grant schema 强制 `lineage_id == grant_id`；测试用的是占位签名 | 缺签署的追加凭证和 CAS |
| B10 | RPR-012 resume 不验签 | resume 删除 stop marker 时不要求签名 | 缺签名 resume |
| B11 | SC-AUTH-004 没有检查实际 diff | tools 里没有拿 grant 范围去比对 `git diff` | 规则未实现 |
| B12a | EVD-005 | 生产报告不记录授权摘要，收集端不读摘要，机械例外不比对规则/输入/工具语义 | 报告和收集都没接上 |
| B13 | NTF 去重键不含 recipient/project | 去重键在 `migrations/646` 的 `cr_execution_notice_dedupe(workspace_id, dedupe_key)`；产出方未定 | 改迁移和产出方都要先决策 |
| B14 | 正链永远返回 `EXECUTION_CONSUMPTION_REQUIRED` | 设计如此：没有 AdmissionDecider 就不放行 | 不是缺陷 |
| B15 | EVD-009 receipt 缺原消费引用/repair_charge/cycle；零发布期会刷新 receipt | 消费引用要等通道落地后才有；“还没发布”不等于“显式的新操作” | 依赖项 + 语义决策 |
| B16 | RPR-001/005/006/009–012 业务身份（strong 报告） | 调用方自报的 kind 会被接受；同 origin 不同 subject 返回旧 receipt；同一 assessment 换 request 会被重复计数；progress 证据可以为空；streak 没有按 epoch 隔离 | T 规则本身的缺陷（**我还没有逐条复核，实施前须先核**） |
| — | EVD-001/002/004（规格轴） | 求值函数没有接入 gate/交付入口 | 缺接线 |

## 2. 归属方案

判据：这个缺陷要修好，是否需要“可信的 T 已提交裁决”“受保护 store”或“持久 selection”？需要就并入 M003；不需要、用现有事实就能判定的，在 AIFI-45 就地修；需要人来定语义的，列为决策项。

### 2.1 并入 M003（已写进方案 v0.4）

| 项 | 落点 | 内容 |
|---|---|---|
| B4/B12b | Spec §1，S7 | Strict 持久化之后，删字段只会被拒，不会降级；legacy 必须由可信历史目录证明，缺行或读失败一律按 Unknown 拒绝 |
| B5 | Spec §3，S5 | 额度只来自验签后的 grant，并绑定到 `fact_refs`；静态验签不等于当前有效 |
| B6（整体） | Spec §3，S5 | 额度聚合键与幂等键分开；grant 不是额度桶；旧账本验证后导入，无法核实来源时拒绝新增；授权效力在 M settlement 中线性化，T commit 不等于获准 |
| B7 | P0 | 进程事实由 daemon 按 launch 登记自填；每个 run 一个私有 Unix socket；pidfd 校验进程树；peer credential 只作辅助，主控制仍是身份隔离 |
| B8 | S1 | 用 `55P03` 锁探针验证 adoption/terminal 竞争 |
| B9 | Spec §2，S5（存储侧 S3） | 新增 `execution-repair-extension/v1` 域，只允许 human-authorizer 签名，在 lineage 锁内做 CAS，双重追加只接受一份 |
| B10 | S5（已有） | 沿用 |
| B3 最终规则 | Spec §6，S7 | `fence_required` 持久且单调；与 AIFI-45 的过渡规则取**并集** |
| B14、B15 消费引用 | Goal | 不变；AIFI-45 在通道提供消费裁决后再绑定 |

### 2.2 AIFI-45 就地修（不依赖通道）

| 项 | 修法 | RED（先红） | 注意 |
|---|---|---|---|
| **B2 锁图（先做）** | 先把所有相关路径的取锁顺序列成锁图：消费、CR 绑定（`BindCurrentTaskToCR`：task→CR）、claim/reclaim、终态、runtime access。统一顺序后再加锁：建议消费改成 **task→CR→approval_record**，与 CR 绑定一致；锁 `FOR SHARE OF t, r`，或在锁内重新校验 JOIN 进来的事实。重新生成 sqlc 产物 | 两态分别断言：修复前，读 claim 之后把任务改为终态，消费仍会写入；修复后，终态 UPDATE 被 `55P03` 挡住（`lock_timeout` 探针，超时不算 RED） | 不出锁图就加锁，等于引入死锁 |
| B1 | 把完整 generation（task、runtime、dispatched_at）写进签发记录和签名，消费精确引用签发记录；签发重放遇到绑定不一致时拒绝；Node 侧 verifier schema 同步修改 | task A 的 challenge 被 task B 使用；同 task/runtime、不同 `dispatched_at`；同 nonce、不同证明内容 | **已落地 2026-10-26**（原位改 643 + 签发/重放绑定 + 消费谓词，见 tc-coverage 增量 22）。残余：签名 payload 仍不含 generation，M 的追加式记录是消费权威 |
| B3 过渡 | **已落地 2026-10-26**：`fence_required` = 该 task **任一 generation** 已有 644 消费行。终态 CAS 之后、同事务内判定（CAS 已持行写锁，未提交消费会挡住它），命中即 409；`to_regclass` 探测保证未套用迁移的部署走旧路径。证据见 tc-coverage 增量 24 | 已消费 run 两个字段都缺 → 409；重领为 B 后仍 409；无消费行的旧任务行为不变（handler 50/50 无迁移在跑） | 历史“已消费+无 claim”终态的重放由 200 变 409（有意） |
| B11 | **已落地 2026-10-26（增量 25，接线于增量 26 更正）**：只读自检 `crctl authorization-scope` 遍历全部仓的 CR worktree，按 grant 冻结身份核对（graph 仅定位），越界 `AUTH_SCOPE_VIOLATION`、无法核实 `AUTH_SCOPE_UNVERIFIABLE`；implement-code Step 4.6 自检 | 规则 14 条 + CLI 端到端 3 条（真实签名 grant） | **merge 强制核对归 M003**（用户采纳，方案 v0.5）；当前平台绑定确认需可信 daemon 链；**X7 已决（不设豁免，签发侧须同时给 repo id 与路径前缀）** |
| B12a | **已落地 2026-10-26（增量 27）**：`testCr` 写入 `authorization-digest`（sha256(签名域+payload)，与 `grantDigest` 同算法，叶子模块共用）；`evidence-check` 对合同 CR 强制要求并比对；机械例外比对同一摘要 → `EVIDENCE_MECHANICAL_AUTHORIZATION_DRIFT` | 生产者/收集端/机械例外各有用例，三处变异各自精确打红；全量 1107 tests / 1106 pass / 1 pre-existing skip | **可信采集（验签）归 M003**；**待决 X8**（换授权后同 plan 重放保留旧摘要） |
| B16 | **已复核并部分落地 2026-10-26（增量 29）**：strong 五条断言逐条核实**全部成立**。已修 4 条（SC-RPR-006 subject 绑定、009 评估幂等、011 progress 须带证据、012 epoch 隔离 + stop 内容），各配行为 RED 与变异。**SC-RPR-001（kind 自报）未修**：判“未解决阻断”需要 tools 不拥有的可信事实，按 v0.4 S5 的既有归属留给 M003。 | 4 条 B16 用例（先红后绿）+ 4 处变异各自精确打红；全量 1116/1115/1 pre-existing skip | repair 账本仍 agent 可写；kind 归属 M003 |
| EVD-001/002/004 | **已落地 2026-10-26（增量 28）**：新 gate 检查类型 `evidenceDelivery`，在 `code-approved`（merge 消费）与 `writing-back` 声明；gate 与 `evidence-check` 共用唯一收集器与纯函数；为同步 gate 链把 `verifyReleaseSubjects`/`subjectMatchesAnnotation` 拆为同步实体 + 异步薄包装 | 5 条 gate 用例（含 legacy 不追溯、缺 report 报缺失内容）；两处变异各精确打红；全量 1112/1111/1 pre-existing skip | `gate-registry.json` 早已滞后、未重设基线；回写侧只覆盖进入 `writing-back` 的门禁 |

B6 **不再**在 AIFI-45 做过渡。tools 在 agent 本机运行，没有 agent 写不到的存储；把账本锚到 `.crctl`，正好违背 ADJ-AIFI45-003。过渡期把它记为**已知限制**：复制根目录后换新 operation_id 可以重新拿到额度。

### 2.3 已决（用户 2026-10-26 拍板）

| 编号 | 决定 | 影响 / 待办 |
|---|---|---|
| X1 | **Windows 属 strict 生产平台** | P0 必须补 Windows 身份证明（命名管道 client pid + 进程句柄/令牌 SID + daemon launch 登记，拒绝请求体自报），不能只做 Linux `SO_PEERCRED`；Windows 路径与 Linux 路径同样要出 P0 证据，缺一即 unverified |
| X2 | **643 原位改** | 已执行：`643_...up.sql` 加 `dispatched_at TIMESTAMPTZ NOT NULL`。643 未上生产（HOLD 库停在 642，runner 每次显式套用），不影响既有库 |
| X3 | **确认过渡规则** | “任一 generation 已消费 ⇒ 终态必须带 claim”；实现依赖 B2 的任务行锁（同一锁内判定与插入） |
| X4 | **A：runner 固定映射产出通知**（我的建议，已采纳） | 理由：`BuildNotice` 要求人类可读 cause/conclusion/action，而唯一候选入口 `SyncService.ingest` 只有机读 `OutboxEvent`；crctl 侧没有通知模型（选 B 会把业务文案塞进 tools）；选 C 只交付投放与恢复，缺口仍在。runner 掌握每个节点的权威终局事实，用固定模板表映射，closed enum + 表驱动测试防漂移 |
| X5 | **a：维持现状**（我的建议，已采纳） | 未发生不可逆发布时可刷新 receipt（当前实现与测试保持）。**残余**：SC-EVD-009 的 `given` 需加“已发生不可逆发布”前置才算完全对齐，那是规范调整，另走流程 |
| X6 | **改 646 迁移** | 去重键含 recipient/project，原位改未上线的 646；生效受 X4 制约（产出方落地才有意义） |
| X7 | **已决 2026-10-26：不在 tools 侧设豁免** | 控制根（knowledge-base）里的 CR 账本与文档改动，不列入豁免。理由：①「先改文档事后追认」正是 KB 文档的主要风险面，豁免等于把该风险面整块放出；② 可豁免清单只能由"crctl 写了什么"推导，而 agent 也能写同一路径；③ 后果可接受：签发侧把本 CR 的控制根路径写进 `allowed_repositories` 即可，`authorization-scope` 与 merge 强制核对（v0.5 §3）都只认 grant。已落地影响：带 `execution-contract` 的 CR 在签发侧列出 KB 前，自检会因 KB 改动报 `AUTH_SCOPE_REPOSITORY_UNKNOWN`——这是 fail-closed，不是 bug。 |
| X8 | **已决 2026-10-26：不改 `inputDigest`，触发器即交付 gate** | 不改的理由：`inputDigest` 注释明确"字段集合与顺序即语义，改动会让历史 journal 指纹全部漂移"，且会让在途未完成事务被判 `TX_INPUT_CONFLICT`，破坏恢复路径。触发"授权变更后强制重测"的机制已经存在且已接线：`evidenceDelivery` gate 在 `code-approved`/`writing-back` 比对报告里的授权摘要与当前授权，不符即 `EVIDENCE_AUTHORIZATION_STALE` 阻断（B12a）。恢复路径：产生新 attempt（plan/results 任一变化）。不再新增专门触发器，也不新增错误码。 |

## 3. 建议顺序

1. **B1 ✅ 已落地**（增量 22，证据 `todo-a-20261026/b1-*`）。
2. 待办 A 剩 4 项：643–647 的 down 往返、10 处 `t.Skip`→`t.Fatal`、TC-EVD-009 CP 端到端、`execution-sensitive-action.mjs` 登记。
3. **B2 锁图**（阻塞 B3）：先列出消费/CR 绑定/claim/终态/runtime access 的取锁顺序，统一后再加锁并断言两态。
4. **B3 ✅（24）、B11 ✅（25/26）、B12a ✅（27）、EVD-001/002/004 ✅（28）、B16 ✅ 已复核并修 4/5（29）**。台账 41/49 未变（这些增量修的是 Gate3 待办，不新增台账行）。
5. **X7/X8 已决**（用户要求实施）：X7 不在 tools 侧豁免、签发侧须同时给 repo id 与路径前缀；X8 不改 `inputDigest`、触发器用已接线的交付 gate。v0.5 经 balanced/economy 复核后已按结论修订（③ 输入来源、核对区间=发布区间、失败码闭集、零写入外延、复用边界）；**该轮修订版当时未复核**——后来的状态见步骤 8。M001/M002 缺口已盘成 `m001-m002-evidence-gap-ledger-20261026.md`（G1–G8，A/B/C 分类），**两者仍 major/unresolved**。
6. **v0.5 strong 复核 BLOCK**（三路记录 `trusted-verdict-channel-v05-review-20261026.md`）：已按结论做第二轮修订（核对对象=实际发布对象、插入点前移到现有 gate 之前、授权线性化与部分发布处置、空集合四证明、SHA 采集适配、X7 恢复流程、归属划分、S5 leaf/mutation 再补）。**该修订版随后已复核**，结果见步骤 8。
7. **B17 ⚠ 部分成立（增量 32，后续被增量 33 修正）**：范围核对采集器当时称修了四个可绕过缺陷（引号转义变形、rename 只报新路径、symlink 判不出时放行、变更集缺失当空集合）。其中**引号转义**与 **rename 源端**成立；**symlink 判定（当时用 git index mode）与第四条变异证据不成立**，已由增量 33 改正、并发现经链接目录穿越的新绕过（增量 34）。merge 侧 SHA/tree 采集适配仍归 M003。
8. **第二次三路复核（B17 后）仍全 BLOCK**：三路均为新鲜非作者静态复核，记录与原文见 `v05-rerun-20261026T235224Z/`（`CLOSEOUT.md` + 三份 `REVIEW-*.md` + `REVIEW-RUNS.json` + `integrity-check.json`，22 项输入与 6 份证据零漂移）。阻断项归并为 R1 发布语义 (a)/(b) 未选、R2 可信 merge facts 存储/端点/认证未定义、R3 撤销与实际发布的线性化未闭合、R4 leaf 矩阵与零写入观测法、R5/R6 B17 状态来源与无效变异、R7 G1/G5 前置未声明。**R5/R6 已在 AIFI-45 闭合（增量 33/34，tools `3e2dd7a`、`029b762`）；R4/R7 已修正；R2/R3 已给合同草案。**
9. **R1 已由用户决定为 (a)：核对对象 = merge 实际发布的候选写集（2026-10-26）**。(b) 不采纳——它与现行“KB 允许批准 SHA 为祖先”正面冲突，会大面积误拒。方案已按 (a) 补五条约束（区间取实际候选 source；批准事实来自 M、实际候选 HEAD 写入 journal/receipt 作本地审计而非授权凭据；KB 审批后写入属核对范围；finalize 三个生成路径必须逐项在 `allowed_paths`、漏列即拒无暗设豁免；rename/symlink/删除按选定提交树判定），S5 必达 leaf 由 17 增至 19（`finalize 写集逐项授权`、`核对含 KB 审批后写入`），`symlink 取自批准树`改写为`取自发布候选树`。**R1 已决 ≠ 方案通过**：R2/R3 草案未复核，其余 BLOCK 项未闭合。
10. **G5 已修（增量 36，DB 取证）**：`AdmitDispatchRoot` 既有根读取改 `FOR UPDATE`，adoption 的 UPDATE 加 `terminal_at IS NULL` + 期望 generation + mapping 摘要条件并 `RETURNING`，0 行即拒。`^TestTC_RUN_004/005` 6/6、0 skip；去锁与“双摘要守卫同时移除”两个变异 RED，单独去 CAS/单侧摘要为 GREEN（冗余防线，已如实登记）。governance 全包 954/952，唯一 fail `TestTC_NTF_003` 经基线对照确认既有。**G1 仍未修**。
11. **R2/R3 复核仍 BLOCK（增量 37）**：R1=(a) 后冻结 v0.6 两章三路复核——strong R2/R3 均 BLOCK、balanced R2 BLOCK/R3 INCOMPLETE、economy R2 BLOCK/R3 PASS（仅文档轴）。阻断归并为 Q1–Q13；本轮只修 EC-2 记录项。**Q8（merge-facts 交付面）需人类决策**，Q2/Q7 与 Q1/Q5 必须同批收敛，不得继续追加条目。
5. 之后决定是否注册 M003（从 v0.4 起草，X1 的 Windows 要求已进 P0）。

## 4. 不得冒称

- 本文与 v0.4 都只到计划层，没有实现，也没有动态验证或 Gate 结论。
- 就地修完也不等于 SC 通过。台账按 CP 命令加四条断言另算。
- B6 在 M003 落地之前是已知限制，不得写成已修。
12. **Q8 已定并改写 R2/R3（增量 38）**：用户采纳 `merge-facts` 随本 change 交付、删 `workspace_revision`、残余风险入册；R2/R3 整节改写为 v0.6.1 合同稿（Q1–Q13 全部对应落点），§4 表 13→14、§6 端点 3→5。**未复核**，下一步冻结后重跑三路。
13. **v0.6.1 复核 → v0.6.2（增量 39）**：strong R2 PASS/R3 BLOCK（STR61-01 在途 push 误判零 effect），balanced/economy 余项均为单点修订；v0.6.2 已逐条落点，**待最终复核**。
14. **v0.6.2 复核 → v0.6.3（增量 40）**：R2 两路 PASS、balanced 要求逐条 mutation；R3 三路 BLOCK（远端祖先分类、no_effect 终态格、leaf 互斥与码序）；v0.6.3 已逐条落点，待复核。
15. **v0.6.3 复核 → v0.6.4（增量 41）**：strong 与 economy 对 R2/R3 均 PASS；balanced 只剩 leaf 可测性问题（R2 INCOMPLETE / R3 BLOCK）。v0.6.4 已做 leaf 级修订，待复核。
16. **v0.6.4 复核 → v0.6.5（增量 42）**：R3 三路 PASS（针对 v0.6.4）；R2 仅剩 #5 一处实质缺口，加 nit 一并修订。v0.6.5 改动了 R3 文本，须重审。
17. **v0.6.5 R2/R3 合同稿三路 PASS（增量 43）**：冻结 sha `55ee0d01…a88b4d8`。这是静态设计复核通过，不是实现或批准；6 条 nit 留到实施期。M003 注册与否仍由用户决定。
18. **G1 已修（增量 44）**：共享 `lockExecutionClaimRows`（task SHARE → runtime SHARE → head），三个 `55P03` 探针 RED→GREEN + 三条变异（含锁强度 `FOR KEY SHARE`）全 RED；全包 957/955/1 既有 fail/1 既有 skip，leaf_pass 864。锁图补 G1/G5 两段并登记 workspace teardown 反向对为已知可重试情形。**残余**：未动态证伪死锁；心跳延迟；归属层之外的证据仍归 M003。
19. **G3 本地半 + G2 残余反例（增量 45）**：读不懂的合同（null/空/非字符串/execution 非映射/contract 缺字段）一律拒绝，不再降级 legacy；四条变异各命中，preflight 子集 65/65。G2 补"同 task 真实重领后旧签发不可复用"反例（行为原已成立，非 RED→GREEN；恒真变异证有牙）。全包 958/956/1 既有 fail/1 既有 skip，leaf_pass 865。**残余**：持久化合同半归 M003；签名 payload 不含 dispatched_at。
20. **G2/G4 残余决定不做（增量 46）**：G2 签名 payload 不补 `dispatched_at`（固定 20 键跨仓合同；代次已由服务端强制并有反例证据）；G4 不引入凭 receipt 反推 strict 的新语义，移交 M003。无代码改动。
21. **TestTC_NTF_003 修正（增量 47）**：顺序相关失败（共享 workspace 中最早 owner 不是本用例 owner），断言改为 owner/admin 角色；全包首次 0 fail（958/957/0/1 既有 skip）。另核实 tools 冻结基线只漂移 2 个本 change 记录文件。
