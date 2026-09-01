# AIFI-14（CR-2026-056）CR 全生命周期复盘与最小改造方案

> 状态：复盘定稿
> 整理范围：PRD、SDD、PLAN/TASK、Coding、审批、评审、Write-back、Archive
> 对应 Issue：AIFI-14
> 对应 CR：CR-2026-056
> 整理依据：本窗口会话中对正式 CR 产物、review annotations、review-loop、跨仓提交记录、Pipeline/Skill 与 crctl 约束的核验

## 1. 执行摘要

AIFI-14 已完成跨仓合并、文档回写和归档，最终状态为 `archived`。本次返工的主要原因不是质量门槛过高，而是质量要求在阶段之间没有被一次性、分层地闭合：

1. PRD 首轮没有按完整 HTTP 契约检查，导致同一契约域的缺口分批暴露。
2. SDD 在修复真实架构问题的同时，曾把 PRD 明确排除的 Discussion 转投路径重新纳入设计，产生范围回摆。
3. PLAN/TASK 没有先验证业务闭环到 TASK owner 的覆盖，Private Ask 后端闭环直到评审后才补出专属 TASK。
4. Coding 阶段暴露出前端请求、schema 降级状态和错误边界顺序等跨层契约问题，说明前序阶段没有把实现边界落实到可执行调用点。
5. Write-back 的原子能力本身有效，但 `TASK-12` 被建模为包含 writeback/archive 的交付任务，和“归档前所有 TASK 必须 done”的门禁形成循环，最终需要人工补标后重跑 tasks writeback。
6. `cr.md`、PRD、PLAN 的 `target-version` 仍为 `tbd`，而 writeback 产物使用了 `0.29`，形成版本事实分叉。

建议的最小改造是：

- 优化现有 review Skill 的首轮完整性和 blocker 分级；
- 在 SDD 审批后冻结批准范围，供 PLAN/TASK 只读消费；
- 在 PLAN 中补一张轻量的 `AC/业务闭环 → SDD 落点 → TASK owner → 证据` 覆盖矩阵；
- 不把 writeback/archive 这类 Pipeline 控制步骤写入交付 TASK ledger；
- 对关键测试被 `SKIP` 的情况收紧 `pass` 语义；
- **目标版本在注册阶段确定，后续阶段只继承并校验，Write-back 不再重新决定版本。**

不建议新增 Agent、Pipeline、状态、review ledger、事务框架、通用 Runner 或第二套 Git/账本机制。现有 `crctl`、Pipeline reviewLoop、CAS、审计和原子 writeback 能力应继续复用。

## 2. 事实与生命周期记录

### 2.1 最终状态

正式分支和 `origin/master` 均以归档提交 `91d95de` 为顶点；`crctl status CR-2026-056` 返回：

```text
status: archived
terminal: true
legalNext: []
next: null
```

注册时间约为 `2026-08-30 16:34`，归档时间约为 `2026-08-31 07:43`。最终目标版本在 `cr.md` 中仍是 `tbd`，但 writeback 后的 baseline、traceability 和 delivery 任务产物使用了 `0.29`。

### 2.2 各阶段评审次数

| 阶段 | 评审结果序列 | 判断 |
|---|---|---|
| PRD | `block(2) → block(3) → pass(0)` | 首轮契约检查不完整，后续 blocker 分批暴露 |
| SDD | `block(6) → block(6) → block(2) → block(3) → pass(0)` | 主要是有效架构问题，另有一次范围回摆 |
| PLAN/TASK | `block(3) → block(5) → block(1) → block(1) → block(1) → pass(0)` | 设计到可执行任务的转换不完整，修复后又暴露执行细节缺口 |
| Coding | `block(3) → pass(0)` | 三个 blocker 均为可复现的跨层实现问题 |

Pipeline 和 Skill 已有 `reviewLoop`、`review_feedback`、`self_repair_attempt` 与 `maxAttempts=3` 机制；本次没有证据表明因达到最大轮次而被迫放行或人工绕过。

### 2.3 Write-back 实际顺序

实际提交序列显示，能够确认的回写阻塞主要是 `TASK-12` 的状态问题：

1. baseline writeback 成功；
2. tasks writeback 成功，但只回写当时已经 `done` 的 TASK；
3. traceability writeback 成功；
4. 归档前发现 `TASK-12` 仍为 `pending`；
5. 人工补标 `TASK-12` 为 `done`；
6. 重跑 tasks writeback；
7. archive 成功。

因此，不能把所有 writeback 提交都描述为“失败后重试”。Git 记录只证明了任务状态闭合不及时导致了一次补标和一次 tasks writeback 重跑。

## 3. 评审标准是否过度设计

### 3.1 应保留的质量要求

以下要求属于当前 CR 的核心质量约束，不应通过降低标准消除：

- session 与 workspace 的隔离条件；
- 首次绑定、发送、快照和失败回滚的事务原子性；
- session 换绑后的独立容器唯一性；
- `chat_config` 的不可变任务快照；
- 显式 container 接口的校验、幂等和错误语义；
- legacy 响应的安全降级；
- backing object 清理和失败重试语义；
- 前端不可在缺少合法 `session_id` 时发出 PATCH 或发送请求；
- 普通 chat session 和 Discussion 路径的回归保护。

SDD 首轮发现的容器唯一键、事务边界、快照、清理和 workspace 条件问题，都能直接映射到数据一致性、安全隔离或可验收性，属于真实 blocker。

### 3.2 真正过重的地方

问题不在 blocker 数量本身，而在评审时机和分级方式：

- 同一 HTTP 契约没有按 endpoint、request、response、error、权限、幂等和验收观察点一次性检查；
- `target-version` 在多个阶段重复作为 suggestion，却没有形成一次性输入校验；
- 设计文档同时描述当前 CR 必须实现的内容和未来相关路径的兼容方向，导致 scope-in/scope-out 容易被误读；
- PLAN/TASK 既检查任务覆盖，又在后续轮次才深入检查命令 cwd、symbol、锁、事务和故障注入，缺少一个前置的转换检查；
- 测试命令 exit 0 与关键测试实际执行之间存在差异，`SKIP` 仍可能被上层摘要为 pass。

因此不建议提高 `maxAttempts`，也不建议把所有 suggestion 强制变成 blocker。应提高首轮检查的完整性和判定一致性。

## 4. 分阶段根因分析

### 4.1 PRD：契约闭合不完整

首轮 blocker：

- `B-001`：旧 Private Ask session 的 `base_*` 回退及 `source` 枚举语义不完整；
- `B-002`：显式创建聊天容器的 endpoint、请求/响应、幂等和 `session_id` 关系缺失。

后续 blocker：

- `B-003`：messages 成功响应缺少 `issue_id`/`session_id` 语义，无法直接验收并发 container/messages 场景；
- `B-004`：runtime offline 时 catalog/capability 来源、缓存有效期和无缓存行为未定义；
- `B-005`：legacy 响应缺少 `session_id/source` 时的安全降级状态和具体 fallback 未定义。

`B-002` 与 `B-003` 实际属于同一 API 契约域，但没有在首轮统一检查。这导致 reviewer 首轮看到部分问题后将其他影响验收的问题留作建议，下一轮才升级为 blocker。

**根因**：需求评审是按文档段落发现问题，而不是按用户可调用的完整契约闭包发现问题。

### 4.2 SDD：真实架构 blocker 与范围回摆并存

首轮及后续主要问题包括：

- session 换绑后容器仍按 project 唯一，无法实现新 session 独立容器；
- 首次绑定与发送不在同一事务，失败会留下半成品；
- 显式 container 接口没有落实配置、readiness 和 catalog 校验；
- merge-forward 缺少 `chat_config` 快照设计；
- draft sweeper 只删除数据库行，未定义 backing object 清理和失败重试；
- Private Ask 查询缺少 `workspace_id` 隔离条件；
- 伪代码引用未导出 symbol，loader 签名与实际基线不匹配。

这些问题多数是真实 blocker，不是评审过严。

但 SDD 后续修复曾重新涉及 PRD 明确排除的 Discussion 转投路径，形成 `BLOCK-013`。最终裁定为：

- Discussion GET、发送、Coordinator→Team Agent 转投调用点和签名零改；
- 只在 `EnsureProjectChatIssue` 内部调整必要的 advisory lock 兼容；
- 转投缺少 `chat_config` 快照不是本 CR 验收项，留给后续 CR。

**根因**：SDD 中的兼容性说明没有和当前 CR 的 scope-out 形成不可误读的边界，设计阶段出现了“顺手统一相关路径”的范围回摆。

### 4.3 PLAN/TASK：设计没有机械落到任务闭环

首轮主要问题：

- Private Ask 后端闭环没有对应 TASK；
- Go 验证命令使用错误的仓库根目录或 package path，无法执行；
- 事务、接口、锁、回滚和故障注入要求没有在首版任务中充分落地。

后续新增 `TASK-13` 承担 Private Ask 后端闭环，覆盖：

```text
GET / 新建 session 快照
→ PATCH config
→ Send
→ task context chat_config 快照
→ creator / workspace / 并发 / 失败回滚测试
```

**根因**：任务拆分先按技术层组织，后按业务闭环补洞；没有在开发启动前要求每个 AC 或业务闭环拥有唯一 TASK owner 和证据命令。

### 4.4 Coding：跨层契约和错误边界顺序未前置闭合

代码首轮发现三个可复现 blocker：

1. 前端 PATCH 未携带必需的 `session_id`，配置修改始终返回 400；
2. schema 硬降级后仍可能显示可写的 Team Agent 设置入口；
3. Private Ask PATCH handler 在权限/会话类型判断前读取 provider，导致普通 session 和非 creator 路径返回错误状态码。

后续实现提交 `cef1ec33a` 修复了三项问题，第二轮 code review 通过。

**根因**：PRD/SDD 对错误语义和 fallback 的文字约束没有在 PLAN 阶段转成“真实请求测试 + 调用顺序测试 + UI 状态测试”。

### 4.5 Write-back/Archive：流程控制任务建模错误

`TASK-12` 的描述包含：

```text
code review → 人工 code approval → checkpoint → merge → writeback → archive
```

但归档门禁要求所有交付 TASK 在 archive 前为 `done`；同时 `crctl task done` 只允许在前置开发态登记。于是形成：

```text
TASK-12 只有流程结束后才能完成
archive 又要求 TASK-12 在归档前已完成
```

这是任务模型与归档门禁的结构性冲突，不是需要新增事务框架或 archive bypass。

**根因**：Pipeline 控制步骤被错误地建成了交付 TASK，交付任务和流程节点没有区分。

## 5. 评审反馈摩擦与范围蔓延判断

### 5.1 已确认的非一次性返回

- PRD 的 B-003/B-004/B-005 在首轮未被一次性闭合；
- SDD 随着设计具体化，陆续暴露锁序、真实 API、清理和转投边界问题；
- PLAN 在补齐 Private Ask TASK 后才暴露其实现级事务和命令问题；
- Coding 首轮 3 个 blocker 均为真实实现缺陷。

### 5.2 不能简单归因于 reviewer 无界扩张

SDD 的大部分 blocker 能映射到 PRD 或既有架构不变量；PLAN 的 blocker 能映射到已批准 SDD；Code blocker 能定位到真实文件和真实 HTTP 行为。没有证据表明 reviewer 通过增加任意新需求来阻止 CR 通过。

### 5.3 明确的 scope creep

明确的范围回摆是 SDD 曾重新纳入 Discussion Coordinator→Team Agent 转投。该问题已通过设计裁定收敛，后续改造应在 SDD 审批后冻结以下内容供下游只读消费：

- scope-in；
- scope-out；
- 不得修改的调用点和签名；
- 后续 CR 承接的已知缺口。

发现与批准范围冲突时，应使用既有 reviewLoop 回到 `write-tech-design`，不得在 PLAN/TASK 中静默扩大范围。

## 6. 已有基础设施与复用边界

以下能力已经存在，应继续作为唯一承载：

| 能力 | 现有承载 |
|---|---|
| CR 状态机、门禁、CAS、审批 | `crctl` |
| review 记录和 attempt | `crctl review-record` / `crctl attempt` |
| reviewLoop、反馈传递和失败中止 | Pipeline JSON |
| 跨仓 merge、release snapshot | `crctl merge` 与 merge verification |
| PRD/SDD 累积回写 | `writeback-prd-sdd.mjs` |
| TASK 回写 | `writeback-tasks.mjs` |
| traceability 生成和校验 | `writeback-traceability.mjs` |
| candidate、manifest、before/after hash、恢复 | `crctl writeback-apply` 与 workspace transaction |
| 归档前 TASK 完成检查 | `crctl archive` 既有门禁 |

本次不应新增：

- 第二套状态机或状态投影；
- 第二套 review ledger；
- Agent 自行写 `_backlog.yml`、`cr.md` 或审批记录；
- Pipeline 内重复实现 Git、事务、CAS 或恢复算法；
- 通用 Runner、动态插件框架或额外事务协调器；
- 为单个 CR 建立专用统计看板。

## 7. 最小改造方案

### P0-1：优化现有 review Skill

只修改现有 Skill 的业务判断和输出约束，不改变状态机和 ledger：

1. PRD 首轮按完整契约域检查：endpoint、request、response、error、权限、幂等、状态和验收观察点。
2. SDD 首先核对批准范围，再检查真实 symbol、签名、调用者闭包、依赖方向、事务和锁序。
3. PLAN/TASK 首先检查 `FR/AC → SDD → PLAN → TASK → evidence` 覆盖，再检查单个任务细节。
4. Code review 检查实际 diff、所有调用者和关键失败路径，区分测试未执行、测试失败和业务缺陷。
5. 每轮 review 明确区分：旧 blocker 已解决/部分解决/未解决、本轮新 blocker、范围外发现。
6. 影响当前实现唯一性或当前验收可达性的缺口必须是 blocker；只影响表达、未来优化或后续 CR 的内容才是 suggestion。
7. 回修后必须逐条输出 `fixed-blockers`，避免只写“已修复”而无法确认评审是否真的重验。

### P0-2：冻结批准范围

SDD 通过审批后，形成供 PLAN/TASK 消费的轻量范围摘要，作为 SDD 正文固定章节承载，不新增独立 ledger：

```text
scope_in: 当前 CR 必须交付的 FR/AC
scope_out: 明确排除的路径和能力
zero_diff: 明确不得改动的调用点/签名
follow_up: 发现但留给后续 CR 的缺口
```

下游不得把 `follow_up` 或兼容性背景自动转成当前 TASK。范围冲突只能回到技术设计修订。

实施落点：`SDD-template.md` 增设固定的「批准范围」章节（承载上述四字段）；`write-tech-design` 契约必填；`approve-tech-design` 通过后该节只读；`review-dev-plan` 与 `review-code` 必须先核对此节再执行其余评审。

### P0-3：增加 PLAN 的轻量覆盖矩阵

PLAN 必须为每条关键 AC 或业务闭环提供唯一 owner 和证据：

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| Private Ask 新建快照 | SDD session/get-or-create | TASK-13 | 新建后首次 GET 精确断言 |
| Private Ask PATCH | SDD §4.7.1 | TASK-13 | creator、403/404、行锁、回滚 |
| Private Ask 发送快照 | SDD send path | TASK-13 | task context 与 DB 快照 |
| Team Agent 首次发送 | SDD bind-in-tx | TASK-07 | container、task、失败零残留 |
| 前端硬降级 | SDD/PRD AC-27 | TASK-10 | schema、组件只读、禁止空 session_id 请求 |

任何关键 AC 没有唯一 TASK owner，不能进入开发启动审批。

实施落点：在 Skill 判断层执行，不新增门禁。`write-dev-plan` 契约要求 plan.md 必含上述覆盖矩阵节；`review-dev-plan` 将「关键 AC 无唯一 TASK owner」判为 blocker，`dev-start` 门禁既有 `passCondition` 已消费其结果。不向 `crctl` 或 `gates.json` 下沉静态检查。

### P0-4：移除流程控制 TASK 的循环

推荐将 M7 保留为 Pipeline 控制阶段，但不生成交付 TASK。若因审计需要保留任务记录，则完成边界必须截止于：

```text
code review 完成 + code approval 完成 + merge 完成
```

不能把 `writeback` 和 `archive` 作为该交付 TASK 的完成前置。`archive` 继续要求真正的交付 TASK 全部 done，不增加人工豁免开关。

实施落点：`write-dev-tasks` 契约增加禁止把流程控制步骤（merge / writeback / archive）建成交付 TASK 的条款，`review-dev-plan` 核验；`deliveryIndexComplete` 归档门禁保持不变。

### P1-1：统一版本事实，选择注册阶段确定

**推荐方案：目标版本在 CR 注册阶段确定。**

现有 `requirement-authoring.pipeline.json` 已将 `target_version` 作为注册输入；writeback Pipeline 也要求显式传入版本，但 writeback 的职责是消费和发布已经确定的业务输入，不应在最后一步重新做版本决策。

统一规则：

```text
注册：确定 target_version
需求/架构/开发：继承并校验
Write-back：校验一致性并消费
```

具体约束：

1. `requirement-register` 必须接收 `target_version`。版本由人工输入，不做自动推导、不自增；发起时未排期的，向用户确认后填 `unassigned`，沿用 `origin` 字段「填写前确认、不自行推测」的先例。
2. 注册生成的 `cr.md`、PRD、SDD、PLAN/TASK 沿用同一版本值。
3. 后续 Pipeline 只传递和校验，不允许各自改写版本。
4. `feature-writeback` 的 `target_version` 与 CR 元数据不一致时直接阻断，不生成部分产物。
5. 正常注册不使用自由文本 `tbd`。如果业务允许尚未排期，应使用团队正式约定的统一未分配值，例如 `unassigned`；如果当前工具尚未定义该值，则在注册前由需求负责人补齐真实版本。
6. 不要求已归档的 AIFI-14 历史产物回写修复；后续 CR 按新规则执行。
7. 执法点仅两处，均在 `crctl`：`register` 对 `--target-version` 硬校验（拒绝空值与 `tbd`，放行真实版本与 `unassigned`）；`writeback-apply` 校验 `--target-version` 与 `cr.md` 版本一致，并拒绝 `unassigned`。中间阶段只继承 `cr.md` 的值，各 pipeline 只传递，不加逐阶段版本门禁。
8. 同步项：`requirement-register` SKILL 输入表 `target_version` 由可选改必填；`crctl.test.mjs` 为两个守卫补最小回归用例；`README.md` 人读流程说明同步「目标版本在注册阶段确定」。

不推荐在 writeback 阶段确定版本，原因是这会让 PRD、SDD、PLAN/TASK 长期携带 `tbd`，最后在 baseline、delivery 文件名和 traceability 中突然变成另一个值，正是 AIFI-14 已出现的事实分叉。

### P1-2：收紧关键测试的 pass 语义

AIFI-14 的测试报告中：

- DB 夹具因无 Postgres 被 `SKIP`；
- 前端测试因无 `node_modules` 未执行；
- 命令 exit 0 仍被机器区记录为 pass。

这可以作为环境限制记录，但不能等价于关键验收已完成。最小规则是：

- 关键测试被 skip 时，review-code 必须在摘要中明确“未测”；
- 如果该测试是当前 CR 的核心 AC 证据，不能仅凭 exit 0 进入代码审批；
- 环境不满足时，使用已有环境阻断/恢复语义；
- 不新增 coverage ledger 或测试指标系统。

关键测试定义：绑定 P0-3 覆盖矩阵，即作为某关键 AC 唯一验收证据的命令，不由 reviewer 自由裁量。

### P1-3：静态检查按重复失败条件触发

只有同类问题再次出现且规则确定时，才向已有版本化脚本或 validator 增加小检查，例如：

- PLAN 引用的文件或 symbol 是否存在；
- TASK 命令 cwd 和 package path 是否有效；
- reviewLoop 的 repair 节点是否存在；
- writeback 前是否存在 pending 交付 TASK；
- writeback 版本参数与 CR 元数据是否一致。

这些检查应下沉到现有确定性工具，不应由 Agent 依赖提示词自觉完成。

## 8. 推荐的后续流程

```text
requirement-register
  └─ 确定 target_version，并写入 CR 元数据

write-requirement-prd
  └─ 只继承 target_version；按完整契约域首轮检查

write-tech-design
  └─ 先冻结/核对 scope-in、scope-out、zero-diff

write-dev-plan
  └─ 生成 AC/SDD/TASK/evidence 覆盖矩阵

implement-code + write-test-report
  └─ 区分 pass、fail、skip；关键证据未执行不得伪装为完整通过

review-code + approve
  └─ 只处理当前批准范围，旧 blocker 逐条复核

merge → writeback → archive
  └─ writeback 消费同一 target_version；无流程控制 TASK 循环
```

## 9. 验收标准

后续最小改造完成后，至少应验证：

1. 注册一个测试 CR 后，`cr.md`、PRD、SDD、PLAN/TASK 和 writeback 输入使用同一 `target_version`。
2. 任一 writeback stage 传入与 CR 不一致的版本时，`crctl` 在无部分写入的情况下阻断。
3. PLAN 缺少某条关键 AC 的 TASK owner 时，不能进入开发启动审批。
4. 流程控制节点不会生成一个必须在 archive 后才可能完成的交付 TASK。
5. review 首轮能在同一轮报告同一 API 契约域的独立缺口。
6. review 回修报告能逐条说明旧 blocker 的解决状态，并能区分范围外发现。
7. 核心测试被 skip 时，代码审批前的结果明确标记未执行，不被单纯 exit 0 掩盖。
8. 现有 `crctl` 状态机、CAS、审计、reviewLoop、writeback transaction 和 archive 门禁回归测试继续通过。

## 10. 最终判断

AIFI-14 的核心问题可以归纳为：

> **质量约束大多正确，但没有在正确的阶段、以完整闭环和唯一事实源的方式传递。**

应保留严格的事务、安全、隔离、快照、错误码和清理要求；应减少的是重复发现、边界漂移、suggestion/blocker 分级不一致、测试 skip 被过度摘要，以及流程节点误入交付账本。

最小有效改造只有五个重点：

1. review Skill 首轮按完整契约和调用者闭包检查；
2. SDD 审批后冻结范围；
3. PLAN 增加轻量覆盖矩阵；
4. 流程控制 TASK 不进入交付 ledger；
5. `target-version` 注册时确定，Write-back 只校验和消费。

这套方案复用现有 Agent、Pipeline、Skill、`crctl`、版本化脚本和 README 职责边界，不重新建设事务、状态机、Git 或 review ledger 框架。

## 11. 主要证据索引

- [CR 元数据](../../change-requests/CR-2026-056/cr.md:16)
- [PRD 范围排除与验收](../../change-requests/CR-2026-056/prd.md:408)
- [PRD 范围排除](../../change-requests/CR-2026-056/prd.md:424)
- [SDD Discussion 转投兼容边界](../../change-requests/CR-2026-056/sdd.md:819)
- [PLAN/TASK 计划与 Private Ask 闭环](../../change-requests/CR-2026-056/plan.md:75)
- [TASK-12 流程任务定义](../../change-requests/CR-2026-056/tasks/TASK-12.md:17)
- [TASK ledger 中的 TASK-12](../../change-requests/CR-2026-056/tasks/_index.yml:69)
- [测试报告未覆盖风险](../../change-requests/CR-2026-056/test-report.md:126)
- [review-tech-design Skill](../../../tools/skills/develop/review-tech-design/SKILL.md:74)
- [review-dev-plan Skill](../../../tools/skills/develop/review-dev-plan/SKILL.md:49)
- [feature-writeback Pipeline](../../../tools/pipeline-templates/feature-writeback.pipeline.json:26)
- [requirement-authoring Pipeline](../../../tools/pipeline-templates/requirement-authoring.pipeline.json:34)
- `tools` 仓库 AIFI-14 合并提交：`7ddeeb7`
- `multica` 仓库 AIFI-14 实现提交：`d062c4e22` 至 `cef1ec33a`
- 平台仓库 AIFI-14 归档提交：`91d95de`
