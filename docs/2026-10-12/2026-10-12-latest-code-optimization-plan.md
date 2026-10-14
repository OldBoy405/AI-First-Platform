# 最新代码核验结果与最小优化实施方案

## 1. 结论和核验边界

本次重新 checkout/fetch 两仓，确认检出 HEAD 与 `origin/main` 相同，产品工作树干净：

| 仓库 | 核验版本 |
|---|---|
| AI-First-tools | `c69336475d01c4de5a42efc0dc087a5e605b5c82` |
| AI-First-multica | `c47381ae72d4a274cf55208ea45bc105bb0bfc77` |

两仓最新主分支均已合入 CR-2026-076。本报告只针对之前讨论的异常及其直接关联合同，不做全仓架构重建。

**核验结论：**上一份报告低估了 Multica 的剩余工作。除了模板/说明残留，本次复现了两类跨仓合同缺陷：

1. 平台状态机生成表没有最新的 `write-dev-tasks:finalize` 转换，真实合法性函数返回 false。
2. 默认 coding 已取消开发启动审批，但平台门禁映射、生成器和默认审批卡判断仍沿用旧规则；直接重生成会造成 stage 共用节点。

**建议顺序：先修上述真实缺陷，再做需求/架构节点文件收敛。**复用现有生成器、投影、可信绑定、正式证据和测试，不新增数据表、服务、通用交接协议或审批绕过。

本次没有修改产品文件、创建 CR/Issue、变更任务状态或操作线上运行。诊断副本仅放在工作区临时目录。源码和隔离测试证明不等于线上故障已经回放，也不等于实际部署已更新。

## 2. 哪些问题仍存在

| 编号 | 问题 | 本次证据 | 判断/优先级 |
|---|---|---|---|
| A1 | 状态机生成表漏新 finalize trigger | tools 声明存在；Multica 生成表缺失；`--check` 失败；真实 `IsLegalTransition` 隔离测试失败 | **确认的代码合同缺陷，P0** |
| A2 | 开发启动审批已从默认 coding 移除，平台仍投影/展示旧门禁 | 已提交表仍指向删除的 …0004；生成器重跑把 dev-start/code 共指 …0010；pendingApprovalStage 仍将 task-breakdown 当 dev-start | **确认的默认流程投影缺陷，P0** |
| B1 | 需求模板要求读取 node-1，daemon 却声明当前可信上下文为权威 | 需求注册、四个后续 skill 和 human_approval 仍引用 node-1；daemon 已发布 Verified execution_context | **契约残留，P1**；有兜底不代表模板已经正确 |
| B2 | 架构 node-1/2/4 重复摘要 | 模板明确要求写文件；后续节点各自 inspection，正式 SDD/评审/审批已承载业务事实 | **冗余设计，P1**；可做纯减法 |
| C1 | Agent 按惯例补未声明节点报告 | 需求 node-2/3/4/6 强制输出已取消；现有通用约束未明确禁止按编号惯例补文件 | **历史风险/规则缺口**，不是本次新复现的 node-3 故障 |
| C2 | 文档未清楚区分默认审批与兼容审批 | README 仍写四个审批节点；当前 coding 11 节点、只有代码 human_approval，dev-start 兼容 API/Skill 仍保留 | **说明残留，P2**；不要把兼容能力删掉或恢复到默认路径 |

## 3. A1：漏同步状态机转换——已复现

### 3.1 源码证据

- tools `dir-graph.yaml:230` 声明：

```yaml
- { from: task-breakdown, to: developing, trigger: "write-dev-tasks:finalize" }
```

- Multica `server/internal/governance/transitions_gen.go:35` 只有同一状态对的旧 `approve-dev-start` trigger，没有新 finalize trigger。
- `transitions_gen.go:98` 的 `IsLegalTransition`：trigger 非空时必须逐字匹配。
- `server/internal/governance/crsync.go:480` 正常状态同步分支调用该函数，并传入事件的实际 trigger。

因此，带新 finalize trigger 的事件不能按当前生成表走正常合法转换同步。这里不能用“两个状态之间原本能转换”来证明新 trigger 已支持，也不能用空 trigger 的 fallback 掩盖问题。

### 3.2 实际检查结果

```text
node server/internal/governance/gen/generate-transitions.mjs --tools ../AI-First-tools --check
exit=1
transitions_gen.go differs from a fresh regeneration off tools dir-graph.yaml — state machine drift
```

本次将当前生成表逐字复制到隔离 Go 包，不改实现，直接调用真实函数：

```text
write-dev-tasks:finalize -> developing: FAIL（返回 false）
approve-dev-start -> developing: PASS
同一状态对、空 trigger fallback: PASS
```

这是当前源码的实际判定结果，不是模拟一套新的状态机。未运行生产数据库同步，因此不声称某个现有 blocked Issue 就是由此导致。

### 3.3 最小修法

- 不改 tools 的正确转换定义，不在 crsync 写特殊放行分支。
- 用已有 `generate-transitions.mjs` 从固定的最新 tools revision 重新生成。
- 在现有 `transitions_test.go` 加一个 finalize 正例，保留旧显式审批正例和未知 trigger 反例。
- 使用现有隔离数据库测试环境验证 outbox 正常同步；不得改线上库或跳过合法性校验。

## 4. A2：默认审批节点投影还在旧布局——已复现

### 4.1 当前模板与已提交生成表不一致

最新 `code-implementation.pipeline.json` 是 11 节点：

- 第 4 节点是 `write-dev-tasks` 收尾，ID …0018，kind=skill。
- 已移除的开发启动 human_approval ID …0004 不在当前模板中。
- 代码评审 ID …0009 在第 9 位。
- 唯一 human_approval 为代码审批 ID …0010，在第 10 位。

平台已提交的 `gate_nodes_gen.go` 仍包含：

| 映射 | 已提交值 | 当前默认模板 |
|---|---|---|
| dev-start | …0004，seq=4，human_approval | 此节点已移除 |
| code approval | …0010，seq=11 | seq 应为 10 |
| code review | …0009，seq=10 | seq 应为 9 |

现有 `generate-gate-nodes.mjs --check` 实际退出 1。该检查会忽略来源 SHA 注释，因此不是因为 merge commit 的 SHA 不同，而是生成内容真正不同。

### 4.2 不能只重跑生成器

`gen/generate-gate-nodes.mjs:50` 起仍把 dev-start 放在 STAGES，约第 84 行用“第一个 human_approval”定位它。

本次将原生成器复制到隔离目录，用最新 tools 生成，不改产品文件，得到：

```text
dev-start -> …0010, seq=10, human_approval
code      -> …0010, seq=10, human_approval
```

即生成器把代码审批错认成开发启动审批。

此外：

- `gate_projection.go` 的 `statusGateAction` 仍包含 task-breakdown→dev-start running、developing→dev-start passed。
- `project_gates.go:26` 起的 `pendingApprovalStage` 仍把 task-breakdown 直接返回 dev-start。
- `stageForNodeID` 从 stage map 反向建索引；若直接重生成形成重复 node ID，后一个 map 写入覆盖前一个，代码审批的 stage 标签有错误风险。

这些是源码和隔离生成确认的缺口；本次未操作线上审批卡，也不声称已经观察到线上随机标签。

### 4.3 最小修法

1. **生成器只映射当前模板真正拥有的审批步骤。**沿用现有 STAGES/模板读取，不增加 schema：明确关联既有 `approve-*` skill 和它前面的 human_approval。
2. 默认模板不存在 `approve-dev-start` 时，不生成 dev-start 的默认 gate 映射。requirement/tech-design/code 必需步骤缺失仍硬失败，不能通用地“找不到就跳过”。
3. 不同默认 approval stage 不得复用同一 node ID，且节点的 ID/kind/seq 必须与模板一致。
4. 默认待审批卡判断复用 `ApprovalGateNodes`：stage 在当前默认映射不存在时，不显示为等待人工审批。
5. `projectGateTransitionErr` 已有“stage 不在映射则返回”的处理，优先复用；不要新增投影服务或新的状态。
6. 保留 tools `gates.json` 和平台签名审批的 dev-start 兼容入口，不删除历史 approval_record，不把旧节点重新塞回默认 Pipeline。

**关键区别：**保留兼容审批能力，不等于默认流程必须投影一个已不存在的审批节点。历史数据不自动重写；若历史展示需要 stage，应优先消费已有记录事实，不以恢复默认旧门禁解决。

## 5. B1/B2：节点文件收敛的最小范围

### 5.1 需求上下文：先消除权威冲突，再停产文件

源码位置：

- tools `pipeline-templates/requirement-authoring.pipeline.json:88/97/106/115/143/152`：注册 producer、四个后续 skill、人工审批均有 node-1 约定。
- Multica `server/internal/daemon/prompt.go:298`：已经发布当前 task 的 Verified execution_context，并要求优先于 node-1。

实施顺序：

1. 已注册任务统一消费当前 task 的可信上下文；同步 human_approval，不能只改 skill 节点。
2. 注册尚无最终 CR-ID/worktree，继续消费 register 的真实结构化返回，不能把“已有 task 的上下文”当成注册前已知事实。
3. 验证注册后通过既有已注册需求入口接续，保持 source、promotion/CR 归属、registration_key 幂等和真实本机 preflight。
4. 注册接续尚未验证时，保留 node-1 的临时兼容生产，不把它作为已注册任务的权威输入。验证全部入口后再取消生产要求。
5. runtime_context 等公开 Skill 输入继续复用原合同；不增加通用注册 inputs.cr_id 副本或新的节点存储。

验收：无 node-1 的 resume 走通；旧文件中的错误 CR/路径不能覆盖当前绑定；缺失/半绑定在写入前停止；新注册正确接续，不重新注册、不猜 source/路径。

### 5.2 架构摘要：直接删除三处输出要求

源码位置：tools `pipeline-templates/architecture-design.pipeline.json:32/41/91`。

- write-tech-design 不再写 node-1 摘要/YAML副本。
- review-tech-design 不再写 node-2 评审副本。
- approve-tech-design 不再写 node-4 审批副本。

保留 SDD、inspection、独立 reviewer、canonical 评审、审批、reviewLoop、crctl next；节点数仍为 4、UUID 和顺序不变。历史文件不删。

### 5.3 对历史 node-3 的处理

需求 node-2/3/4/6 摘要要求已经由 AIFI-60 取消，不再重复开发该删除。

只在现有 tools 行为约束集中增加一句：

> 不按节点编号惯例产生额外报告。执行摘要留在现有运行输出；正式业务/治理产物由生产者依既有提交/checkpoint 合同收尾，不交给评审者代为处理。

不新增提交节点、自动 stash/clean、日志目录协议或宽泛 ignore；不降低 clean。当前源码没有强制写需求 node-3，这项应作为历史风险防复发，而不是声称现行代码仍必然产生该文件。

## 6. 哪些问题已不应重复修

| 历史问题 | 当前代码已有能力 | 本次处理 |
|---|---|---|
| 普通任务只绑定安装根 | daemon 已消费 task/issue 正式 CR 关联，唯一关联继承、冲突拒绝、无 CR 信号才普通 fallback | 聚焦绑定测试通过；只需核验实际部署，不新建绑定系统 |
| owner 输入显示名/membership ID | register/owner-set 已有成员 user_id 写入前校验，模板输入示例已修订 | 复用 handover-cr 修历史事实，不自动清洗 |
| reviewer 嵌套 reviewer | 生效模板已声明平台单层派发、禁止作者自评 | 不再增加第二层委派，不以 Pi 嵌套能力修复为前置 |
| Task 正常退出但无正式评审交付 | 已有 RUNNER_REVIEW_DELIVERY_MISSING、正式证据判定、事件同步顺序与受控恢复 | 不解析模型 prose 猜 abort，不伪造 BLOCK |
| 需求失败 run 恢复、旧 digest 交接 | 已有受控 resume、迟到证据消费和显式旧 digest 交接 | 复用原入口；不批量修改 digest/attempt |
| task token、审批授权、真实 dirty 拒绝 | 原有安全/业务保护 | 不放宽、不代签、不提供绕过开关 |
| 编码实现结果、规划建议草稿的文件交接 | 有实际下游消费者，正式替代输入尚需逐项验证 | 本轮不删，不扩展全部 executor、不新建通用 handoff 服务 |

这里的“已存在”是源码判断，不代表部署结果。owner/恢复未在本次做生产回放；不能用仓库 commit 自动将业务 Issue 标为完成。

## 7. 可落地的实施顺序

### Task 1｜P0：修平台默认流程合同，单独交付

**主要文件：**
- `server/internal/governance/gen/generate-gate-nodes.mjs`。
- `server/internal/governance/project_gates.go`。
- `server/internal/governance/transitions_test.go`。
- 现有 `gate_projection_test.go`、`gate_review_test.go`、`crsync_approval_gate_test.go` 中受默认布局影响的用例。
- 生成物：`transitions_gen.go`、`gate_nodes_gen.go`；requirement registry 只按生成器输出同步，不手工改。

步骤：

- [ ] 在现有状态机测试补 finalize trigger 正例、旧 approve-dev-start 兼容正例和未知 trigger 反例。
- [ ] 为默认门禁补断言：不存在 dev-start 默认审批、代码审批节点唯一、反向 stage 为 code、task-breakdown 不显示开发启动审批卡。
- [ ] 按第 4.3 节修生成器；默认 stage absence 与兼容 API 分开。
- [ ] 默认待审批卡复用已有映射判断。投影端优先用已有 absent-stage 分支，不新增状态机。
- [ ] **修生成器后**再重生成两类表；不能仅生成旧算法的错误输出。
- [ ] 两个 `--check` 必须退出 0；验收新 finalize 状态事件同步和默认无人工开发启动等待。
- [ ] 保留 legacy approve-dev-start 命令、签名审批授权和历史记录，确认没有安全放宽。

最小状态机回归可直接放入已有 Go 测试文件：

```go
func TestFinalizeTransitionIsLegal(t *testing.T) {
    if !IsLegalTransition("task-breakdown", "developing", "write-dev-tasks:finalize") {
        t.Fatal("latest declared finalize transition must be legal")
    }
    if !IsLegalTransition("task-breakdown", "developing", "approve-dev-start") {
        t.Fatal("legacy explicit approval compatibility must remain")
    }
    if IsLegalTransition("task-breakdown", "developing", "unknown-trigger") {
        t.Fatal("unknown trigger must still fail closed")
    }
}
```

**不做：**不改正确的 tools 状态定义，不在事件同步中加特殊放行，不恢复已删除的默认审批节点，不新建迁移表或清空旧 run。

### Task 2｜P1：tools 节点文件收敛，两仓成对交付

- [ ] 修改需求、架构模板；需求先完成注册后接续验证，架构只取消三份摘要。
- [ ] 同步必要的 Skill/AGENTS 说明，不复制多份规则。
- [ ] 在现有 `pipeline-structure.test.mjs` 增加针对需求/架构的窄范围检查；临时兼容 producer 必须在测试/交付说明明确，不假称已经完全清除。
- [ ] 补无文件 resume、错误历史文件、source 继承、半绑定拒绝和真实产物收尾的回归。
- [ ] 从固定 tools commit 再生成平台 registry；处理本次 prompt 改动产生的 digest 变化。

**不做：**不动编码/规划的独有交接文件，不引入 node-result.json、结果数据库或 Agent 历史扫描。

### Task 3｜P2：说明与防漂移收口

- [ ] README 区分“默认 requirement/tech-design/code 人工审批”与“仍可显式使用的 dev-start 兼容审批”。
- [ ] 更新 10 月 10 日方案的 12 节点假设；当前 coding=11，按模板/索引核验，不回退实现。
- [ ] 双仓合同变更的交付/发布流程固定 tools commit，运行两个现有 `--check`；没有必要建立新监控或审计服务。
- [ ] 将测试 skip 与真实通过分开列示。不要仅看 go test 退出码。

## 8. 实施时的既有命令

以下生成命令会写产品生成物，**本次没有在产品仓库运行**；Task 1 修生成器之后由实施者执行。在 Multica 仓库根：

```bash
node server/internal/governance/gen/generate-transitions.mjs --tools ../AI-First-tools
node server/internal/governance/gen/generate-gate-nodes.mjs --tools ../AI-First-tools
node server/internal/governance/gen/generate-transitions.mjs --tools ../AI-First-tools --check
node server/internal/governance/gen/generate-gate-nodes.mjs --tools ../AI-First-tools --check
```

相邻路径只是本次布局；实际环境按 repository 配置确定，不写死机器绝对路径。

在 tools 根：

```bash
node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs
node --test pipeline-templates/emit-registry.test.mjs
```

在 Multica `server/`：

```bash
go test ./internal/daemon -run '^TestResolveTaskWorkspaceBinding$|^TestTaskWorkspaceBinding$|^TestPipelinePromptCarriesTheVerifiedExecutionContext$' -count=1
go test ./internal/governance -count=1
```

最后一项必须在既有、获授权的隔离数据库环境中真正执行。数据库不可用时不能将 skip 当 PASS，也不由 Agent 接管共享数据库生命周期。

## 9. 本次已执行结果

| 检查 | 实际结果 | 含义 |
|---|---|---|
| tools pipeline structure | 36 pass，0 fail，0 skipped | 当前自仓结构规则通过，不证明跨仓表同步 |
| tools registry emitter | 8 pass，0 fail，0 skipped | 导出器通过，不证明平台提交生成物最新 |
| daemon 三项聚焦绑定回归 | package 成功 | 绑定既有能力无需重建；不等同部署验证 |
| gate generator `--check` | exit 1 | 当前 gate 生成物与模板不一致 |
| transitions generator `--check` | exit 1 | 当前状态机生成物与 tools 不一致 |
| 原生成器隔离生成 | exit 0，但 dev-start/code 共用 …0010 | 单纯重生成不是正确修复 |
| 当前真实 IsLegalTransition 的隔离测试 | 新 finalize FAIL；legacy/空 trigger 对照 PASS | 新 trigger 缺口已复现，不依赖数据库 |
| governance 既有状态测试尝试 | 数据库不可用，TestMain 整体跳过，进程 exit 0 | **不能声称这批测试已通过**；不是生产数据库回放 |

### Digest 范围说明

隔离生成证明：当前 architecture Core digest 没变，requirement Core 内容（忽略来源注释）也没变。因此 gate 映射检查失败不能概括为“所有 registry 都过期”。

Task 1 的纯表/默认投影修复不应顺带主动迁移 requirement run 的 digest；实施时核对实际 diff。Task 2 改 prompt 后会重新计算 Core digest，才按对应流程的现有兼容方式处理在途运行。

## 10. 发布与完成标准

- Task 1 先发布：两类一致性检查通过，finalize 事件合法，默认无 phantom dev-start 节点/审批卡，代码审批 stage 唯一。
- Task 2 再发布：注册后接续与无 node-1 resume 验证通过，架构不生成重复摘要，正式证据完整。
- 需求 digest 变化时复用已核验的显式旧 digest 交接；架构未有同类入口时选择安全窗口/匹配版本，不直接改数据库。
- 不删除历史 node 文件、approval_record 或 pipeline 记录，不重置 attempt。
- 正式集成场景通过才算完成；skip/环境阻断、源码检查、隔离函数测试和部署验证分开报告。
- 不依赖本轮新建服务、依赖或状态模型；保留 task token、审批授权、绑定拒绝和 clean 保护。

**最终判断：**当前最优先的问题不是继续讨论要不要节点文件，而是补齐最新 tools 与平台之间的状态/门禁合同。修好这两处小接口，再用现成上下文和正式产物去掉冗余节点报告，既可落地，也不需要大改架构。
