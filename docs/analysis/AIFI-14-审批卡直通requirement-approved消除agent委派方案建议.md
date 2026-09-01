# AIFI-14 审批卡直通 requirement-approved：消除中间 Agent 委派的方案建议

> 状态：方案建议（已完成人工确认，待注册 CR 落地）
> 日期：2026-08-30（v3 收敛：标准审批节点运行时配置化，固定 Runner 不泛化）
> 来源：AIFI-14（Multica聊天会话级配置与Discussion方案 CR-A）运行期间，Ray 提出的流程改进诉求
> 性质：平台级（Multica daemon + 服务端审批配置运行时化）改造建议，不是实施授权

## 1. 背景与问题

### 1.1 对话缘起

AIFI-14（CR-2026-056）需求阶段第 3 轮独立评审 PASS 后，Ray 在项目会话中提出两个问题：

1. **为什么审批后委派了 requirement-writer？** PRD 评审 PASS、点击审批卡片批准后，协调器又委派了一次 requirement-writer，而不是直接进入 SDD（技术设计）阶段。
2. **期望行为**：点击审批卡片后，状态应直接推送至 `requirement-approved`，不再委派任何 Agent 去推进。

### 1.2 事实澄清（第一轮回答）

经核查 AIFI-14 完整评论线程，审批后的那次 requirement-writer 委派**不是重写需求**，而是执行 `approve-requirement` 的状态落盘：

| 时间 | 动作 | 内容 |
|---|---|---|
| 09:29 | 第 3 轮评审 PASS | 协调器 @ Ray 执行人工审批，承诺"批准后路由技术设计阶段" |
| 09:34 | Ray 点击审批卡片 | 服务端签发 Ed25519 grant，落 `.crctl/grants/CR-2026-056-requirement.grant.json` |
| 09:34 | 委派 requirement-writer | 任务为消费 grant：`crctl approve --grant`，写 `approval.yml`，CR 从 `requirement-reviewing` → `requirement-approved` |
| 09:38 | requirement-writer 回报 | 状态已到 `requirement-approved`，`crctl next` 返回 `write-tech-design` |
| 09:38:56 | 委派 dev-agent | 正式进入 SDD 撰写 |

**委派 requirement-writer 的原因**：
- 审批卡片只产生 grant（人类意图），不推进 CR 状态机；`approval.yml` 与阶段流转必须由 crctl 消费 grant 后写入；
- 协调器硬边界禁止执行 `crctl approve` / 写治理状态文件，必须委派给所属管线 owner；
- requirement-writer 消费完成后，协调器立即委派 dev-agent 执行 `write-tech-design`（SDD），流程本身正确。

### 1.3 用户真实诉求

去掉"审批 → agent 消费 grant"这个中间环：**点击审批卡片 → 状态直接 `requirement-approved`**，秒级完成，无评论、无委派、无 LLM 运行。

## 2. 现状链路与根因

### 2.1 既有闭环（AIFI-8《独立评审与人工审批命令闭环设计》v0.4 §7）

```text
ApprovalCard 批准/驳回
→ Multica 服务端重新计算 evidence digest 并校验人类权限
→ 签发既有 Ed25519 grant
→ daemon 投递 grant 到 Operational Workspace（写入 .crctl/grants/）后调 ACK
→ crctl approve --grant 重验签名、状态和证据
→ 原子写 approval.yml、推进 cr.md 状态、产生 outbox
→ Multica 投影新状态并刷新项目会话
```

### 2.2 缺口

最后一步"`crctl approve --grant`"**没有确定性执行者**：

- 协调器（cr-coordinator-agent）硬边界禁止执行 `crctl approve` / 写治理状态文件；
- 因此只能委派管线 owner（requirement-writer）消费 grant，产生一次可见的 agent 委派环；
- AIFI-6《Multica执行性能分析与模块职责边界》§7.1 设计的"审批后自动续跑"也是"ACK 后唤醒 coordinator → 再委派 agent"，**同样保留 agent 环**。

结论：grant 已可靠落盘，缺的只是"由谁机械地执行 `crctl approve --grant`"。

## 3. 方案建议：daemon 在 grant ACK 时直接消费（无 Agent 环）

### 3.1 核心思路

在现有 grant 投递路径（daemon 将 grant 写入目标 worktree 的 `.crctl/grants/`）与 ACK 之间，插入确定性消费步骤：

```text
点击审批卡 → 服务端签发 Ed25519 grant
→ daemon 写入 grant 到 `.crctl/grants/`（现有）
→ daemon 在本地 operational workspace 执行 `crctl approve --grant`
→ 原子写 approval.yml + 推进状态（crctl 现有能力）
→ daemon 以 consumed ACK 通知 server
→ server 标记已消费、投影刷新，审批卡消失
```

触发点取 **grant 已可靠写入 workspace、且 `crctl approve --grant` 成功之后**。新 daemon 的 consumed ACK 不再创建 `approval_continuation` Agent 任务；旧 daemon 的缺省 ACK 保留现有 continuation 兼容路径。

### 3.2 执行命令（示例）

```bash
node {TOOLS_ROOT}/skills/shared/crctl/scripts/crctl.mjs approve CR-2026-056 \
  --stage requirement --grant .crctl/grants/CR-2026-056-requirement.grant.json \
  --workspace {operational-worktree}
```

`crctl approve --grant` 已具备全部所需能力：

- 非 TTY 安全（`--grant` 为 Ed25519 签名授权的服务端人在环入口，与 TTY 二选一）；
- 消费前重验：grant schema / 归属 / 状态 / evidence digest / Ed25519 签名；
- 原子写 `approval.yml`（`via: server-approve`）+ 级联 advance 推进状态；
- 重放幂等（`changed=false`）；
- reject 双模式：驳回自动走 `REJECT_ROLLBACK` 权威回退，同样可被 daemon 自动消费；
- 失败结构化错误码（`GRANT_STATE_MISMATCH` / `GATE_BLOCKED` / `OWNER_WORKTREE_DIRTY` / `ADVANCE_COMMIT_FAILED` 等），零写入。

### 3.3 信任模型不变

- **授权来源不变**：人类授权 = 服务端签发的 Ed25519 grant；daemon 不产生、不代替任何"人"的授权；
- **状态写入路径不变**：`crctl` 仍是状态唯一合法写入路径（drift governance v2 组件 A 的既有原则）；daemon 调用的就是 crctl 本身；
- **审计不变**：crctl audit + `approval.yml`（via=server-approve）+ 平台 `activity_log` 照旧；
- **AIFI-8 §7 不变量全部保持**：Agent 不得代替人类批准；Web grant 与 TTY 审批同入口；review PASS 与人工批准仍是两个不同节点；evidence drift 继续被拒绝。

### 3.4 失败兜底（必须保留，不能吞错误）

| 场景 | 处理 |
|---|---|
| crctl 未能启动、Node/crctl 不可用或 workspace 无法准备 | 保留 grant，记录结构化错误；可按旧 daemon 兼容路径唤醒 coordinator/owner 兜底 |
| `crctl` 拒绝消费（状态不匹配、证据漂移、配置不一致、worktree dirty） | 保留 grant，不删除、不伪造成功；等待同步/人工处理。只有能证明未执行治理写入时才允许 Agent 兜底 |
| `crctl` 返回提交结果不明确 | 不自动创建 Agent 兜底任务；保留 grant，先通过 `crctl status` / `crctl audit` 判定，再重放幂等消费 |
| ACK 失败 | 沿用现有重试循环；grant 已消费时 ACK 重放必须幂等 |
| 重复触发 | 复用 `approval_record.id` 唯一约束和 `crctl` 重放幂等；已消费记录不得再次创建 continuation |
| grant 落盘时 workspace 正被 writer 占用 | `crctl` 的 `OWNER_WORKTREE_DIRTY` / CAS 拒绝；不并发抢写，保留 grant |

### 3.5 改动范围

| 模块 | 改动 |
|---|---|
| Multica daemon 的 grant 投递服务 | 写入后定位唯一 workspace，调用现有 `node + crctl.mjs` 执行 `approve --grant`；成功后以 `consumed=true` 调用 ACK |
| Multica server ACK 服务 | 保留现有 ACK 端点；新 daemon 的 consumed ACK 只标记交付/消费并触发投影，不入队 continuation；旧 daemon 的缺省 ACK 保留旧路径 |
| Multica server governance | 运行时读取标准审批治理配置、动态构建 gate node 映射；固定 architecture Runner 仍保持自身执行契约 |
| tools 仓 | 保持现有 `gates.json` / `dir-graph.yaml` / pipeline JSON 字段兼容；如启用 grant 配置版本校验，仅增加可选 `config_sha` 字段及 crctl 兼容消费逻辑 |
| 测试 | daemon 消费成功/拒绝/结果不明确、ACK 幂等、旧 daemon 兼容、四阶段审批、动态新增标准审批节点 |

这仍然复用现有 `crctl approve --grant`、workspace inspect、ACK、投影和重试基础设施；新增的是消费时机、ACK 语义分流和运行时配置加载，不引入新的审批协议。

### 3.6 效果

- 点击审批卡 → daemon 本地确定性消费 → 秒级完成，无 LLM 委派；
- 四类标准审批（requirement / tech-design / dev-start / code）统一受益；
- 驳回继续由 `crctl` 执行权威 `REJECT_ROLLBACK`，不需要 Agent 介入；
- 消费失败不丢 grant，也不把治理拒绝伪装成可自动兜底的 Agent 任务；
- 新增符合既有协议的审批节点，在运行时配置化完成后无需修改或重新编译 Multica；
- 新增特殊审批语义、节点类型或 Runner 执行能力仍需代码实现和发布。

## 4. 备选方案对比

| 方案 | 说明 | 评价 |
|---|---|---|
| **A. daemon ACK 直接消费（推荐）** | daemon 在写入 grant 后调用本地 `crctl approve --grant`，成功后发送 consumed ACK；旧 daemon 保留旧 ACK 兼容路径 | 秒级、零 LLM 成本、复用现有 crctl；结果不明确时不自动兜底 |
| B. ACK 直接唤醒 writer 限定"仅消费 grant" | 跳过协调器 hop，但仍是一次 LLM 运行 | 分钟级延迟 + token 成本；不解决确定性执行问题 |
| C. 配置化标准审批节点 | server/daemon 运行时读取既有 tools 配置，识别新 stage 和 human_approval 节点 | 适合长期扩展，但需要一次配置同步、解析和一致性基础设施 |
| D. 放开协调器权限直接跑 crctl approve | 协调器自己消费 grant | 削弱职责分离与审计边界，不推荐 |
| E. 维持现状（agent 委派环） | 审批后委派管线 owner 消费 | 与用户目标不符 |

## 5. 风险与边界

| 风险 | 控制 |
|---|---|
| worktree 状态竞争 | 复用 crctl CAS/`OWNER_WORKTREE_DIRTY`，不并发抢写 |
| 自动消费失败被静默吞掉 | 失败保留 grant 并记录结构化错误；治理拒绝不自动转成 Agent 兜底 |
| ACK 语义升级影响旧 daemon | consumed 字段向后兼容；旧 daemon 缺省值继续走 continuation，待版本淘汰后再清理 |
| 配置损坏或版本漂移 | tools 不存在时使用内嵌默认；存在但解析失败则拒绝，不回退旧缓存；带版本的 grant 做一致性校验 |
| 新配置被误认为可执行能力 | 配置只定义标准治理节点；固定 Runner 和新节点执行语义仍由代码控制 |
| 配置快照来源不可信 | 通过现有 daemon workspace 认证同步，server 重算 canonical `config_sha`，按 workspace 隔离 |

## 6. 下一步

1. 人工确认本方案（已完成），按下述运行时配置边界修订文档；
2. 后续注册 Multica CR，先落地 daemon 直通与 ACK 兼容，再落地标准审批治理配置运行时化；
3. 直通验收：点击任一四阶段审批卡后，本地 `crctl` 完成状态推进，无 continuation Agent 委派；构造治理拒绝和结果不明确场景，验证 grant 保留且不误派发；
4. 配置化验收：新增符合既有协议的测试 pipeline、标准审批 stage、human_approval 节点和状态转换，不重编译 Multica，配置同步后可识别、可审批、可正确投影；不把该验收解释为通用 Runner 已支持新流程。

## 7. 权威参考

- AIFI-8《独立评审与人工审批命令闭环设计》v0.4（docs/product/独立评审与人工审批命令闭环设计.md）§7
- AIFI-6《Multica执行性能分析与模块职责边界》（docs/product/Multica执行性能分析与模块职责边界.md）§7.1
- crctl Skill：`approve` 子命令（grant 双模式、幂等、REJECT_ROLLBACK）
- AIFI-14（CR-2026-056）完整评论线程（09:29~09:38:56 审批与状态推进时间线）
- 服务端源码：`server/internal/governance/{project_gates,approval,gate_projection,gate_nodes_gen,transitions_gen}.go`、`server/internal/governance/gen/`
- tools 配置：`skills/shared/crctl/gates.json`、`dir-graph.yaml#change-request-track.state_machine`、`pipeline-templates/*.pipeline.json`

---

# 第二部分：标准审批节点运行时配置化（不承诺通用 Runner）

## 8. 背景与目标

### 8.1 目标与边界

当前 Multica server 将审批和门禁配置部分编译进 Go 生成物。目标是：新增一个符合既有协议的 `human_approval` 节点、审批 stage 和状态转换后，server 无需重新编译即可识别、展示、校验和投影该节点。

这里的“不重编译”有明确边界：

- **包含**：审批 stage、审批节点、评审节点、状态转换和门禁投影的运行时识别；
- **不包含**：通用工作流执行引擎、任意新节点类型、特殊审批语义和新的 Runner 执行能力；
- **仍需代码的情况**：多人会签、条件审批、外部系统审批、新权限模型或新节点执行语义。

因此，新增标准审批节点可以只改 tools 配置；新增执行能力仍需要代码实现和发布。

### 8.2 现状：服务端编译期绑定清单

经源码核实，审批相关能力当前有以下编译期绑定：

| # | 位置 | 内容 | 性质 |
|---|---|---|---|
| 1 | `approval.go` | `approvalStages` stage 白名单 | 手写硬编码 |
| 2 | `project_gates.go` | `cr.status → 审批 stage` 的 switch 映射 | 手写硬编码 |
| 3 | `gate_nodes_gen.go` | `ApprovalGateNodes` / `ReviewGateNodes` 节点 map | 由 pipeline JSON 生成 |
| 4 | `gate_nodes_gen.go` | `ArchitectureCoreRegistryJSON` | architecture Runner 的内嵌 registry |
| 5 | `transitions_gen.go` | 状态机转换列表 | 由 tools `dir-graph.yaml` 生成 |
| 6 | `project_gates.go` / `gate_projection.go` | `stageForNodeID`、status 到 pipeline 的派生映射 | 基于上述生成物的手写派生 |

### 8.3 重编译与运行时配置的取舍

| 维度 | 重编译 | 运行时配置 |
|---|---|---|
| 实现复杂度 | 低，当前生成器已可用 | 高，需要同步、解析、缓存和版本校验 |
| 配置生效 | 需要发布 server | 配置同步后即可生效 |
| 多 workspace 差异 | 不适合 | 可按 workspace 隔离 |
| 配置错误 | CI/build 阶段发现 | 运行时发现，必须 fail-closed |
| 安全边界 | 执行能力固定，边界清晰 | 配置可改变审批和状态语义，控制面风险更高 |
| 回滚 | 回滚二进制 | 回滚配置版本并处理缓存 |

本方案选择折中边界：审批治理配置运行时化，固定 Runner 的执行契约继续由编译期代码保护。

## 9. 配置源与一次性基础设施

### 9.1 配置传输方式

server 不能直接访问 daemon 所在机器的 workspace，因此不能假设 server 能按 `workspace.tools_package_path` 读取本地文件。配置链路应为：

```text
tools workspace 文件
→ daemon 读取必要的 gates / state machine / pipeline 配置
→ 复用现有 daemon workspace 认证和 cr-events 重试链路同步配置快照
→ server 按 (workspace, config_sha) 校验、缓存和消费
```

tools 目录中的 `gates.json`、`dir-graph.yaml` 和 pipeline JSON 仍是唯一事实源；server 数据库中的配置快照只是同步缓存，不是人工维护的第三份配置。

配置快照至少需要包含：

- `gates.json#approvalStages`、相关 `statusGates` 和 `reviewLoops`；
- `dir-graph.yaml#change-request-track.state_machine`；
- active pipeline JSON 中的治理相关节点和必要 registry 信息。

传输内容可以是必要配置文件的原始文本，server 使用标准 JSON 和现有 YAML 解析能力校验，不新增独立的 manifest schema。

### 9.2 一次性改造点

1. `approvalStages` 白名单改为读取运行时 gates 配置；
2. `pendingApprovalStage` 改为根据 `approvalStages[*].expect` 反查；
3. `ApprovalGateNodes` 和 `ReviewGateNodes` 改为扫描运行时 pipeline JSON，按稳定 node UUID 建立 map；
4. `stageForNodeID` 改为由运行时节点 map 构建；
5. gate projection 根据运行时节点所属 pipeline 和状态机配置识别新审批节点，不再增加固定 switch 分支；
6. `Transitions` 改为运行时加载状态机配置，并复用现有 wildcard 展开和硬失败规则；
7. 配置按 workspace 和 `config_sha` 缓存，解析失败的版本标记为 invalid，不覆盖可用版本；
8. ACK 直通逻辑使用同一份配置版本信息，避免 server 展示旧审批语义而 daemon 按新语义消费；
9. 现有 `architecture-core/v1` Runner 继续保留编译期 registry 和固定节点校验。运行时配置化不把它改造成通用 Runner。

原有生成脚本保留为 CI 一致性检查，直到运行时 gate projection 完成并稳定；不再把生成物作为新增标准审批节点的唯一运行时来源。

### 9.3 缓存、同步和失败策略

- server 收到新的配置快照后先做完整解析和跨文件校验，成功后才替换该 workspace 的 active cache；
- 相同 `(workspace, config_sha)` 直接复用缓存；
- tools 包完全不存在：使用当前内嵌四阶段配置，并标记 `config_source=embedded-default`；
- tools 包存在但文件缺失、格式错误、节点关系不一致或状态机非法：拒绝 gates 查询和审批，不回退旧缓存；
- 配置同步失败只延迟新版本生效，不删除旧配置快照和本地 grant；
- 配置快照必须使用已认证 daemon 的 workspace 绑定，server 重新计算 canonical `config_sha`，不能只信任请求字段。

### 9.4 配置版本与 grant 兼容

配置版本不能加入现有 grant 的签名 canonical 串：

```text
v1|cr_id|stage|decision|approver|approved_at|evidence_digest
```

否则会破坏既有 grant 的验签兼容性。版本信息作为附加元数据处理：

- 新 grant 可附带可选 `config_sha`，但不进入签名串；
- 新 daemon 的 ACK 携带 `config_sha`，server 校验它与已缓存配置一致；
- `crctl approve --grant` 可增加对可选 `config_sha` 的兼容校验；
- 旧 grant 不带 `config_sha` 时跳过该校验，独立使用 crctl 的行为不变；
- 配置版本不一致时拒绝消费并保留 grant，返回 `CONFIG_VERSION_MISMATCH`；
- `CanonicalDigestFromEvidence` 和 crctl 的 evidence digest 算法不改。

如果启用 grant 侧校验，tools 仓只需增加向后兼容的可选字段消费，不改变现有 gates、pipeline 和状态机字段含义。

## 10. 渐进落地路线

| 阶段 | 内容 | 验收 |
|---|---|---|
| P0 | daemon 写入 grant 后本地执行 `crctl approve --grant`；ACK 增加 consumed 语义；旧 daemon 保留 continuation 兼容 | 四阶段批准/驳回直通；无重复 continuation；失败保留 grant |
| P1 | server/daemon 配置快照同步；运行时读取 `approvalStages` 和 `expect` | 既有四阶段回归通过；新增标准 stage 可被 gates 查询识别 |
| P2 | 运行时解析 pipeline JSON，动态构建 approval/review node map 和 stage 反查 | 新增 `human_approval` 节点后审批卡和节点投影出现；不修改固定 Runner |
| P3 | 运行时解析状态机、配置版本校验和旧 grant 兼容 | 新增合法状态转换无需重编译；坏配置拒绝；版本不一致拒绝 |

每阶段可以独立发布。P2/P3 完成后，新增标准审批节点不需要修改 Multica 业务代码；新增特殊语义或 Runner 能力仍需代码 CR。

## 11. 新标准审批节点接入方式

以 `security-review` 为例，接入只需要配置变更：

1. 在 pipeline JSON 增加带稳定 UUID 的 `kind=human_approval` 节点；
2. 在 `gates.json#approvalStages` 增加 `security-review`，声明 `to`、`trigger`、`expect`、`approvalSection`、`evidence` 和必要的 `passCondition`；
3. 在 `dir-graph.yaml#change-request-track.state_machine` 增加 approve 和 reject 回退转换；
4. 通过 tools 配置同步让 server 获得新版本；
5. daemon 使用同一 workspace 配置执行通用 `crctl approve --grant`。

只要新节点仍遵守以下既有协议，就不需要新增 Go/TypeScript 业务分支：

- 人类授权由 server 签发 Ed25519 grant；
- grant 使用既有 stage、decision、evidence digest 和签名格式；
- approve/reject 由状态机声明转换；
- 节点类型为已有 `human_approval`；
- 后续执行由已有 Agent/Pipeline 编排，而不是依赖新的 Runner 语义。

## 12. 整体改动范围

| 模块 | 改动 |
|---|---|
| Multica daemon grant 投递 | 写入后定位唯一 workspace，调用现有 `node + crctl.mjs`；成功后发送 consumed ACK |
| Multica server ACK | consumed ACK 只标记已消费并刷新投影；旧 daemon 缺省 ACK 继续走 continuation |
| Multica server governance | 配置快照接收、解析、缓存、版本校验和标准 gate projection 运行时化 |
| tools 仓 | 保持现有配置字段兼容；如启用 grant 版本校验，增加可选 `config_sha` 的兼容消费 |
| 固定 Runner | 保留 architecture Runner 的编译期 registry、节点顺序和执行契约 |
| 生成器 / CI | 继续作为一致性守卫，待运行时投影稳定后再决定是否退役 |
| 测试 | 直通、旧 daemon 兼容、四阶段回归、动态标准审批节点、坏配置、版本漂移、幂等和失败结果不明确 |

改动集中在 Multica 的 daemon、governance 和测试边界，不侵入上游业务模块；tools 配置 schema 不做破坏性改动。

## 13. 对其他 Agent 的影响与兼容边界

### 13.1 结论

其他 Agent 继续直接使用 tools 和 crctl，不依赖 Multica server 的编译产物。运行时配置化只是让 server 读取与 crctl 相同的配置事实源，不改变其他 Agent 的执行方式。

### 13.2 兼容边界

1. **既有配置字段不改语义**：`gates.json`、`dir-graph.yaml` 和 pipeline JSON 的现有字段继续按 crctl 规则解释。
2. **tools 缺失可用**：server 使用内嵌默认配置保证既有四阶段审批可用，并显式标记来源。
3. **配置损坏不静默降级**：tools 存在但解析失败时拒绝新 gates/审批，不使用旧缓存冒充新配置。
4. **旧 grant 可消费**：无 `config_sha` 的旧 grant 按兼容规则跳过版本校验；新 grant 具备版本信息时执行校验。
5. **证据摘要不变**：`CanonicalDigestFromEvidence` 与 crctl 的字节级一致继续由共享测试向量保护，行尾仍先归一化。
6. **固定 Runner 不泛化**：配置能让 server 识别标准审批节点，但不宣称 server 能执行任意新 pipeline。
7. **节点 UUID 保持稳定**：历史 `pipeline_node_run.node_id` 不因运行时读取而重写；配置变更导致节点身份冲突时拒绝加载。

### 13.3 明确不在本方案内的内容

- 通用 workflow engine；
- 新增审批节点类型；
- 多人会签、条件审批和外部审批协议；
- 由配置直接授予新的权限；
- 配置变更后自动迁移运行中的 pipeline；
- 删除旧 continuation 任务、生成物和兼容代码。

## 14. 最终建议

“不重编译即识别新流程”作为**标准审批治理配置的运行时目标**是合理的；作为“新增任意流程后 server 自动执行一切”的承诺则过度设计。

本方案采用以下最终口径：

> 新增符合既有 `human_approval`、grant、evidence 和状态机协议的审批节点，只需修改 tools 配置并同步 workspace，不需要修改或重新编译 Multica。新增特殊审批语义、节点类型或 Runner 执行能力时，仍需要代码实现和发布。

审批直通与配置运行时化仍应分阶段验收：先保证点击审批卡后确定性推进状态，再验证标准审批节点的动态识别；任何配置解析、版本校验或 workspace 竞争失败都必须显式失败，不得静默吞错。
