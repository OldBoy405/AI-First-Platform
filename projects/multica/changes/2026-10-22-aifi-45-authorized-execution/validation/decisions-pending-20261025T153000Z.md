# AIFI-45 · 决策记录（含历史 D1/D2 与已决 D7/D8）

> 开头 D1/D2 的背景描述与旧计数为 2026-10-25 历史快照，不作当前进度依据；当前以 TC 台账为准。2026-10-26 用户已决定 D7 转交通道 change、D8=A 不迁移，见本文末；决定归属/范围不等于组件已实现或 Gate 批准。

这两项不是我能在不越权的情况下自行拍板的：一项是**规范没定义的操作语义**，一项是**Gate 级安全取舍**。
其余 39 条缺口的形态是「测试文件/用例未写」，不需要决策（见 `tc-coverage-20261025T153000Z.md`）。

---

## D1 · TC-AUTH-002 的“充分性自查/仅补问关键取舍”到底怎么落地

**规范原文**（`canonical/specs/code/execution-authorization.yaml` SC-AUTH-002）：
> given 原请求缺少决定性验收或交付边界，但环境中的仓库事实可查；
> when 执行方判断授权充分性；then SHALL 自查事实并仅请求必要业务取舍，未授权部分无状态变化或执行任务。

**现状**：tools 侧没有“充分性/提问”的任何概念（`grep -rn "clarif|sufficien|questions"` 零命中），
`TC-AUTH-002` 在 `execution-authorization.test.mjs` 里也没有对应用例（CP 断言 `ok 1 - TC-AUTH-002` 实测不满足）。

**难点**：`acceptance` / `delivery_targets` 目前是**必填且非空**的签名 schema 字段
（`lib/execution-authorization.mjs`），所以“缺少决定性验收”在当前模型里根本无法表达成一份合法 grant：
要么直接判 `EXECUTION_GRANT_PAYLOAD_INVALID`（那是 AUTH-003/004 已覆盖的静态拒绝），
要么就得允许“部分授权 + 待补问”这种状态，而它是否该存在、由谁签发、如何闭合，规范没写。

**可选方案**

| 方案 | 做法 | 代价 / 风险 |
|---|---|---|
| A（推荐） | 把“充分性”定义为**只读自查**：`authorization-bind --check` 在签名合法但 `acceptance`/`delivery_targets` 为空 → 返回 `EXECUTION_AUTHORIZATION_INSUFFICIENT` + `missing: ['acceptance','delivery_targets']`，不绑定、不写盘；仓库事实可查的部分（仓库是否存在、路径是否在仓库内）由工具自查并计入 `checked[]` | 需要把这两个字段从“schema 必填”改为“schema 允许空、由 check 判充分”。这会改变签名 payload 的语义（**规范修订**，不是纯代码） |
| B | 新增 `crctl authorization-sufficiency` 只读动词，输出 `{checked[], questions[]}` | 新增一个只有一条 TC 驱动的动词，YAGNI；且仍要先回答“空字段是否合法” |
| C | 认为该 TC 已被 AUTH-003/004 覆盖（静态拒绝 + 无副作用），在规范里降级/合并 | 最省事，但等于改规范去迁就实现，需要评审同意 |

**我的建议**：选 A，但**先改规范再改代码**——把 `acceptance`/`delivery_targets` 的“必填”改成“可为空数组，但 `--check` 必须报不足”，
否则同一个字段会出现两套互相矛盾的真相。在此之前 TC-AUTH-002 保持 MISSING，不写“假装通过”的用例。

---

## D2 · 准入（`EXECUTION_CONSUMPTION_REQUIRED`）何时解除

**现状**：`tools/.../crctl.mjs` 在绑定 + 来源核验全部成功后**无条件**：

```js
fail('EXECUTION_CONSUMPTION_REQUIRED', '绑定和来源子集已核验；平台当前head/撤销/claim与可信消费事务未接通，拒绝准入且不写receipt');
```

这句注释的前提（“平台 head/撤销/claim 与消费事务未接通”）**已经被本轮建设推翻**：
平台侧已有绑定/撤销/消费/激活四条端点 + head 锁 + 收据表，daemon 也已在交付成功后记录消费
（`recordConsumptionAfterDelivery=true`）。所以现在缺的不是平台能力，而是**T 侧怎么知道“消费已发生”**。

**约束**：T（crctl）没有 daemon token，不能自己调服务端消费端点；消费只能由 daemon 记。
关键在于“daemon 说记了”算不算证据——daemon 是本设计里的本地可信执行者（持 `mdt_`），但它也是本机进程。

**可选方案**

| 方案 | 做法 | 强度 |
|---|---|---|
| A | 端点**先记消费再写响应**，响应头带 `X-Multica-Consumption-Receipt`；T 要求该头存在才准入 | 中：证明 daemon 走完了“记录”路径，但仍以本地进程的话为准 |
| B | 同 A，另加一次 T→endpoint 的 `GET <nonce>/consumption` 复核（同一进程内状态机，非新信任源） | 中（多一跳，可观测性更好，强度不增） |
| C | T 直连服务端查询该 run 的消费状态 | 需给 T 发凭据 → **扩权，不建议** |
| D（当前） | 保持 fail-closed，准入继续关闭 | 最高，但产品等于“授权链已建、执行仍不放行” |

**我的建议**：Gate3 前选 **D**（保持关闭，与本轮“用户授权消费记录但准入仍关闭”一致）；
Gate3 若决定开启，选 **A**（先记后答 + 响应头），并在文档里明确写「这是本地可信进程的陈述，不是服务端可独立验证的事实」，
不得声称“T 侧已独立验证消费”。
**B 不值得做**：它没法把“本地进程的话”变成“服务端的话”，只是多一次往返。

---

## 这两项各自解开会解锁什么

| 决策 | 解锁 |
|---|---|
| D1 选 A + 规范修订 | TC-AUTH-002（AUTH 组 10/10） |
| D2 选 A | 真实派发/准入链可用；RUN 组的多条 TC 才有“准入已开”的前提可测 |
| D2 维持 D | RUN 组仍可测“未授权不得派发/撤销后停止”，但“已授权可推进”这条无法测 |

其余 39 条（RPR 12 / EVD 10 / RUN 10 / NTF 7）不需要决策，纯粹是三个测试面未写：
`repair-governance.test.mjs`、`delivery-contract.test.mjs`、`cmd/server` 的 `TestTC_RUN_*` / `TestTC_NTF_*`。

## D7 · 组件就绪闸门（EVD-007）：已决策归属，未实施

**用户决定（2026-10-26）**：同意挂到后续可信 T committed verdict channel change，并要求给出独立解决方案、修订原方案文档。该 change 仍已搁置、未注册；本次是方案修订，不是实施、启用或 Gate3 授权。

**归属与方案**：T 复用 `evaluateComponentReadiness` 唯一求值；M 负责可信观测登记、裁决来源/绑定校验、原子启用与回退，不在 Go 重写版本/恢复规则。完整方案见 `trusted-verdict-channel-implementation-plan-20261026.md` v0.3 的 Spec §7 与 S8。D7 使用独立的部署就绪控制面，不消耗业务预算、不借 lineage consumption 作为自身冷启动前提，也不新增第三个 change。

**边界**：`workspace.components` 缺失不能视为 strict-ready；仓库文件、环境变量、stdout 和本地 SHA 不是可信部署证明。通道组件可独立验收；真实 strict 启用仍须 AIFI-45 的 AdmissionDecider/单 effect 接线等实际能力证据，不能用组件通过冒充整个平台可上线。EVD-007 与 RUN-008 的相关能力共用此闸门，TC 仍各自验收。

**完成时机**：后续通道 change 交付该模块；任何真实 strict 启用或移除旧接力前，均须先通过就绪闸门并履行各自实施/发布审批。没有相应证据时保持未就绪，不放宽 AIFI-45 的 NO-GO。

## D8 · legacy 历史不迁移：已决策范围，未冒称功能验收

**用户决定（2026-10-26）**：选 A——本期不提供 legacy 业务历史迁移，只允许经权威事实确认无承接历史债务的新 CR/新 lineage 切入。原 legacy run 留在原合同和原恢复路径，历史授权、消耗、审批及未决任务保持原样。

**禁止“换壳清零”**：既有 CR/lineage 有历史、未决任务或状态不可核实时，不得靠删 selection、换 grant、换 lineage 或新建空 store 重新获得额度。重启、key rotation、同 store 的严格恢复不等于业务历史迁移；连续性必须可核实，不确定即冻结。

**范围决定不等于改写规范**：前文把“不迁移”说成“EVD-008 永远只能拒绝、当场收口”过度推断，现撤回。`evaluateExplicitMigration` 已有可核实历史的正分支，SC-EVD-008 也要求正、反两分支；本次不删函数、不改 Canonical、不以拒绝侧测试充当完整实现。后续新 change 的 SPEC 应明确“存量不迁移”的范围；若要从 AIFI-45 的交付承诺中移走正分支，须另行按原流程修订规格/追踪并审阅，不能在 BUILD 文档中静默删减。

**当前验收口径**：已解决策略悬置，不新增迁移动词或入口；原有 CP 单测/PRESENT 口径保留，但“无生产迁移入口”的事实也保留，不新增 TC、不提升 41/49，不关闭 Gate/major。详见原通道方案 v0.3 的 Spec §5 与修订记录。
