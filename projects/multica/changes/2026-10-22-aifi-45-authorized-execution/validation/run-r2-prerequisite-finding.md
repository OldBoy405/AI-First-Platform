# RUN R2 前置发现：**不存在**可打开的准入开关

> **更正（2026-10-26，主会话核实 `router.go:249-252` 原文 + strong 设计作者复核）**：下表第一行“执行授权端点被显式禁用（503）”**说法夸大**。原文是 “Nil keeps the execution-authorization endpoint disabled (503)”——503 仅在启动时未注入可信合同时出现；production 已有 manifest loader 注入（`main.go:341-342,712`，未给两项 manifest 参数时才为 nil）。授权/绑定/消费/激活路由真实存在。结论“缺派发准入判定”**不受影响**：真正缺的是把授权+收据+派发根变成派发任务的那一步判定及其 Runner 调用点。另：Runner 已有旧的自动派发开关 `AIFIRST_ARCHITECTURE_RUNNER`（`runner.go:58-65`），所以 nil 的兼容目标是“无新增授权自治派发”，不是“今天没有任何自动派发”。详见 `dispatch-admission-design-20261026.md`（sha256 前缀 `5b28431dfe7f09b3`）。
>
> **方案 A 的 env 开关已撤回**：改为依赖注入 `AdmissionDecider`（nil = 现行为），不改 DB runner。

## RUN-009 侦察（balanced 只读会话 `01a176d1-936e-77b9-a3c5-0f405f8e2b21`，requested `Gobao/deepseek-flash:max`，actual unknown）

先前判断“RUN-009 多半是补接线”**不成立**。九个漂移维度中：

| 维度 | 现状 |
|---|---|
| attempt / template | 已有拒绝（`gate_projection.go:407-415`；`runner_requirement.go:70-83`）|
| policy / receipt / UUID | 只在授权/激活路径有，评审投影路径没有 |
| subject | 只查“非空”，从不与当前 subject 比对（`runner.go:1434`）|
| run / node / cycle | 无检查 |

另：全服务无“实际 diff”检查；无 assessment 摄入路径（是否计划内 UNVERIFIED）。

**更正（2026-10-26，主会话读码；下列旧结论作废）**：旧文“作者自评拒绝在 `reconcileCodeTail` 消费侧缺失（`runner_code.go:455-540`）”**不成立**。
- `reconcileCodeTail` 对每个节点（含 review 节点 `nodes[8]`）都调 `reconcileSkillTaskFor`（`runner_code.go:467/474/500/510`）。
- 该助手分两支：任务行 `completed` → `checkConsumedReviewIndependence`（`runner.go:963-966`，函数体在 `:1321-1340`，读库内已选 review/author 行的执行者是否同一）；任务行不存在 → `enqueueNodeFor` → `checkIndependentReview`（调用点 `runner.go:1037`，函数体 `:1296-1319`）。
- 两支都由 `strings.HasPrefix(reviewNode.Ref, "review-")` 先筛（`:1297` / `:1326`），非评审节点直接放行。
- requirement 阶段另有自己的调用点（`runner_requirement.go:533` / `:622`）。
- 所以代码阶段“派发侧 + 消费侧”自评拒绝**两侧都有**，不应再列为 RUN-009 缺口。当时的错误是把“该文件里没出现这个函数名”当成了“这条链路上没有这个检查”，没往下多看一层共享助手。
- 仍未变的 RUN-009 缺口：node / cycle / UUID 无检查、subject 只查非空、全服务无“实际 diff”检查；run 维度补丁已撤回。

**主会话已亲自核实的一条真缺陷**：`gate_projection.go:141-172` `findOrCreateRun` 在找不到 `running/waiting_approval` 运行时会 **INSERT 一条新的 `running` pipeline_run**，`applyReview`（`:374`）无条件调用它 → 一条在原 run 终态后才到达的迟到评审会**新开一个运行中的 run** 并把节点行写进去。这正面违反 SC-RUN-009“仅保留历史而不推进”。是否会被 Runner 接着派发，尚待核实（UNVERIFIED）；但“新开 run”本身已是可 RED 的事实。

日期：2026-10-26 · 关联：`tc-coverage-20261025T153000Z.md#增量-15`、CUSTOM #198

## 结论（已核实，非推测）

我此前计划里的"在测试里打开准入"**前提不成立**——代码里没有准入判定可开。

| 事实 | 出处 |
|---|---|
| ~~执行授权端点**被显式禁用**，返回 503~~（**此说法已作废**，见本文顶部更正：仅 nil manifest 才 503） | `cmd/server/router.go:249-251`（注释原文："execution-authorization endpoint disabled (503)"）|
| daemon 领取路径**明确声明不读准入证据** | `internal/daemon/execution_task_claim.go:22`（"reads platform claim metadata, not admission evidence"）|
| governance 包里没有任何 `admission` 判定函数或开关 | 全目录 grep：`admission` 只出现在注释里，说明"这不是准入" |
| 没有 `ConsumptionEnabled` / 类似开关 | 全仓 grep 无结果（tools 侧的消费开关与本仓无关）|

也就是说：**准入不是"关着的开关"，而是"还没建的路径"**。D2 之前说"Gate3 前维持 fail-closed"，
实际实现方式是端点直接 503 + 领取路径不咨询授权，而不是一个可翻转的 flag。

## 对 R2 四条的直接影响

| TC | 需要什么 | 现状 |
|---|---|---|
| RUN-002 伪造/自报请求不产生授权 | **真实认证 route** 上的准入判定 | 端点 503，没有判定可测 |
| RUN-003 T 提交前只唤醒、不推进 | wake/dispatch 与消费 receipt 的联动 | 无派发接线 |
| RUN-006 额度耗尽拒新根、允许收尾 | 准入判定 + 根围栏（根围栏已有 ✅） | 缺准入判定 |
| RUN-010 敏感动作缺专项无动作 | 领取/动作路径调用 tools 的消费 | 领取路径不接授权 |

⇒ 这四条**不是"打开开关"**，而是"新建准入判定路径"。这是本 change 剩下的最大一块，
也正是 D2 要求先冻结的那部分。

## 建议做法（需你确认，因为它是新增面）

1. **新增 `DecideAdmission` 判定**（governance 内纯判定：授权包 + 消费 receipt + 根围栏 + 额度 + 敏感动作范围），
   **默认关闭**：不是翻转现有 flag，而是新增一个 env 门（如 `AIFIRST_EXECUTION_ADMISSION=on`），
   默认值 = 关；仅在一次性测试库里设为 on。
2. **把 503 的端点接到判定上**：开关关时行为与今天**逐字一致**（仍 503 / 仍不咨询授权），
   开关开时才走判定。这样生产默认行为零变化，D2 不被违反。
3. 测试用 `-run` 指定四组，runner 传 `AIFIRST_EXECUTION_ADMISSION=on`（需给 runner 增加受控 env 透传，
   且必须记录进 evidence，不能静默）。

代价：这是一条新生产面（判定 + 端点接线 + 开关 + runner env 透传），不是小改。
好处：RUN-002/003/006/010 有了真实入口可测，且生产默认仍 fail-closed。

## 替代方案

- **只做不依赖准入的 RUN-009**（漂移只留历史、作者不能自评 PASS）。它是 runner 既有能力的补接线，
  不需要准入判定。但 RUN-002/003/006/010 仍然缺席，RUN 最多到 3/10。
- **拆分**：本 change 停在 41/49（+RUN-009 = 42/49），RUN 主体另开 CR。
