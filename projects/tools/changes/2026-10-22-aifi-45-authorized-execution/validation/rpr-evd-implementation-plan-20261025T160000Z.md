# RPR / EVD 实现计划（逐条可执行）— 2026-10-25

> **先纠正一条错话**：我在 gate3 closeout §9 写过“剩余 40 条形态只有三种 = 写测试文件”。
> 那句话对 RUN/NTF 成立（缺 Go 测试），但对 **RPR 12 与 EVD 10 不成立**：tools 侧
> `grep -rn "repair"` 与 `evidence-delivery|delivery-contract` 在 `skills/shared/crctl/scripts` 下**零命中**，
> 既没有 lib 也没有动词。**它们是功能面，测试文件只是这些功能的最终产物**。
> 本文件把这两个功能面拆成可执行的切片，避免下一轮再从零推导。

## 0. 可复用的既有产物（不必新造）

| 产物 | 位置 | 已含字段 |
|---|---|---|
| 评审标注 | `<cr>/review-annotations/{requirement,tech-design,sdd,code}.yml` | `verdict: pass|block`、`subject-sha256`（requirement/tech-design/dev-plan）、`release-subjects`（code，机器注入） |
| 评审轮次 | `<cr>/review-loop.yml` | `current-cycle`、`attempts[].{attempt,at,by,cycle}` |
| CR 头 | `<cr>/cr.md` frontmatter | `status`、`owner`、`execution-contract`、`target-version` 等 |
| 证据文件 | `<cr>/validation/**` | 现有 sha256 清单可算 |
| 授权/额度 | `.crctl/grants/*.execution-grant.json` | `repair_limit`、`sensitive_actions`、`lineage_id` |
| 账本原语 | `lib/durable-tx.mjs` | `acquireLock`、`durableWriteFile`、journal、`faultPoint` |

结论：EVD 的 10 条**大部分不需要新格式**；RPR 的额度/回执/停止也需要一份账本，但账本形状可以由
`durable-tx` 的既有 journal 习惯决定，不需要新的对外契约。

## 1. EVD（10 条）→ 一个 lib + 两个动词

### 1.1 代码面

| 新增 | 作用 |
|---|---|
| `lib/evidence-delivery.mjs` | 纯判定：`evaluateDelivery(facts)` 返回 `{decision: 'deliver'|'blocked', findings[]}`；事实采集与判定分离，便于逐条单测 |
| `crctl evidence check <CR>` | 采集事实 → `evaluateDelivery` → 输出 findings（只读，零写入） |
| `crctl evidence deliver <CR>` | 在 `check` 通过后写一条 `delivery receipt`（复用 `acquireLock` + `durableWriteFile`），幂等按 `subject` 键 |

### 1.2 逐条映射

| TC | 判定规则 | 事实来源 | 是否需新格式 |
|---|---|---|---|
| EVD-001 | 最小内容齐全（目标/范围/可信授权/结果/证据 + 长期规则源已更新）即可放行；不要求 PRD/SDD/plan 套餐，不改累积基线 | `cr.md` + `validation/**` 清单 + baseline 是否被覆写（git 树比对） | 否 |
| EVD-002 | 文件齐但缺**当前授权**或**验证证据**，或长期规则变化未更新权威源 → 阻断并点名缺什么 | 授权：`.crctl/grants` 当前 lineage；证据：validation 产物与 `test-report` 的 subject 一致 | 否 |
| EVD-003 | 实质变更只有作者自报 PASS、或只是同一身份（含同一真实 UUID）的 review → 拒绝 | `review-loop.yml#attempts[].by`、annotation `verdict`、`cr.md#owner` | 否 |
| EVD-004 | 机械变更例外：需**完整且匹配当前 subject** 的确定性检查证据 | 一份“确定性检查”产物（可由现有 `crctl test` 报告派生）+ subject 摘要 | 否（复用 test 报告） |
| EVD-005 | 生成规则/输入/工具/业务规则/授权/验收任一语义变化 → 不得免审 | test 报告的 plan/输入/工具版本字段 | 否 |
| EVD-006 | 在途 legacy CR（无 `execution-contract`）不追溯阻断、不自动获新额度 | `cr.md#execution-contract` 缺失 ⇒ 走 legacy 判决，直接 deliver 并注明 | 否 |
| EVD-007 | tools/生成物/Agent-Skill/Runner 版本**未知或不一致** ⇒ 标未就绪、保留旧恢复路径 | `crctl upgrade-check` 的既有事实 + 组件清单 | **是**（组件清单从哪来，见 D3） |
| EVD-008 | 显式迁移：历史可核实则保留并算剩余；不可核实则拒绝 | 授权 lineage + 消耗历史 + 未决任务 | 部分（迁移动词） |
| EVD-009 | 发布事务边界失败后恢复同一操作，**不重复**审批/修复扣额/cycle reset | 复用 merge/checkpoint journal 的既有 receipt | 否 |
| EVD-010 | scope 未变但 review 后的实际 subject/release tree 或 cycle 已变 → 拒绝旧证据，走最小重验 | annotation `subject-sha256` / `release-subjects` + 当前 git 树 + `review-loop` cycle | 否 |

### 1.3 建议切片顺序（每条都能独立验收）

1. **切片 1（无决策依赖）**：EVD-003 + EVD-010 + EVD-006（作者自报/旧证据/legacy 不追溯）。三者都只读既有标注与 git 树。
2. **切片 2**：EVD-001 + EVD-002（内容/缺口判定 + 点名缺失）。
3. **切片 3**：EVD-004 + EVD-005（机械例外，依赖 test 报告字段）。
4. **切片 4**：EVD-007（需 D3）、EVD-008（迁移）、EVD-009（发布事务恢复）。

## 2. RPR（12 条）→ 一个 lib + 三个动词

### 2.1 代码面

| 新增 | 作用 |
|---|---|
| `lib/repair-governance.mjs` | 修复账本：`origin` → `repair_id`/`receipt`、额度（`repair_limit`）、`progress_epoch`、`stop` |
| `crctl repair-admit <CR> --origin <id> ...` | 准入一次修复；同 origin 返回原 receipt（TC-005）；额度耗尽拒绝（TC-002/004/008） |
| `crctl repair-assess <CR> --assessment <file>` | 记录一次“有/无实质进展”的独立评估（TC-009/010/011/012） |
| `crctl repair-resume <CR>` | CAS 解除精确 stop 并新建 `progress_epoch`（TC-012 正例） |

### 2.2 逐条映射与依赖

| TC | 规则 | 需要什么 | 决策依赖 |
|---|---|---|---|
| RPR-001 | 正常实施不扣额；未解决阻断的新 run 不能冒充首次 | 账本区分 `implementation` 与 `repair` origin | — |
| RPR-002 | 6 次用完，第 7 次拒绝且不派发 | 额度来自 grant `repair_limit` | — |
| RPR-003 | 失败仍计 1 次；有界技术重试不另扣 | 准入先记账，执行结果只更新状态 | — |
| RPR-004 | 跨阶段/cycle/supersede 累计不归零 | 账本按 lineage 存累计，cycle 只影响 `progress_epoch` | — |
| RPR-005 | 同 origin 并发/换 ID/重放 → 只一条消费并返回原 receipt | `acquireLock` + 唯一键 `(lineage, origin)` | — |
| RPR-006 | 写/提交/返回三边界故障注入后按已提交事实恢复；同键异 origin 明确冲突；不夹带无关改动 | `faultPoint` + write-set | — |
| RPR-007 | 追加 2 次 → 总额 8、已消费仍 6、追加只生效一次、旧历史保留 | **签名增量凭据**（引用原授权） | **D4**：追加凭据是否复用 `execution-authorization` 的 payload 扩展 |
| RPR-008 | 无签名增量/非法整数/改本地默认 → 拒绝扩额 | 校验 + “默认值不可被本地改写”的白名单 | — |
| RPR-009 | 两次无进展即使有余额也停，升级通知含根因/已试/证据/余额/所需动作 | 评估记录 + 通知产物（可复用 `inbox-emit`） | — |
| RPR-010 | blocker 同名但测试实质改善 → 允许下一次 | 评估需引用**当前 subject** 的测试结果 | — |
| RPR-011 | 有效假设排除 + 独立评审指出证据如何改变判断 → 算进展 | 同一评估结构，类型不同 | — |
| RPR-012 | 拒绝无效进展（自报/日志扩写/旧 subject/同输入/根因改名/缺 assessment）；正例走 CR 锁内 CAS 解除精确 stop 并新建 epoch，只生效一次 | 评估结构 + CAS | **D5**：“独立评审”在本地如何证明（见下） |

### 2.3 建议切片顺序

1. **切片 1**：账本 + `repair-admit` 的额度/origin 幂等 → RPR-001/002/003/005（4 条，无决策依赖）。
2. **切片 2**：跨阶段/cycle/supersede 累计 + 非法整数/本地默认 → RPR-004/008（2 条）。
3. **切片 3**：`faultPoint` 三边界恢复 + 冲突 → RPR-006（1 条）。
4. **切片 4**：评估 + stop + resume → RPR-009/010/011/012（4 条，需 D5）。
5. **切片 5**：签名增量 → RPR-007（需 D4）。

## 3. 需要决定的三件事（不是我该单方面拍的）

| # | 问题 | 为什么必须由你/Gate 定 | 我的建议 |
|---|---|---|---|
| **D3** | EVD-007 的**组件清单**从哪来（tools 版本、生成物、已安装 Agent/Skill、Runner 实际版本） | 这是新的对外事实源，一旦写进 `dir-graph.yaml`/`binding.yaml` 就成为别的仓库要维护的契约 | 在 `.stdd/binding.yaml` 增加可选 `components: [{id, version, digest}]`，缺失即“未知→未就绪”；不新建独立清单文件 |
| **D4** | RPR-007 的“追加 2 次凭据”用什么载体 | 它要引用原授权，可能扩展 `execution-authorization` 的 payload（已签名 schema） | 复用现有签名链：新增 `purpose: 'repair-extension'` + `supersedes_grant` 指向原 grant，`repair_limit` 表增量；**先改规范再改代码** |
| **D5** | “独立评审”在本地如何被证明（RPR-009/010/011/012 全靠它） | 本地无法证明身份独立；现在 `review-loop.yml#attempts[].by` 只是 `git config user.name` | 明确“独立”= **不同 identity 且具备对应 stage 的 review 记录**（与 EVD-003 同一判据），并在文档里写明这是**流程约束而非密码学证明** |

## 4. 现在就能开工、不依赖任何决定的顺序

`EVD 切片 1`（003/010/006）→ `RPR 切片 1`（001/002/003/005）→ `EVD 切片 2` → `RPR 切片 2`。
四条切片合起来是 **9 条 TC**，且都不需要 D3/D4/D5。
