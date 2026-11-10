# prompt-governance — 人工评审副本

> STDD BUILD／DELIVER 所需的非权威兼容视图（人工评审副本），不是 CLI 自动生成或 canon 校验过的产物。历史 Gate 2 已确认方案 A；2026-11-10 修订版 Gate 2 重新确认待完成，状态以 STDD 记录为准。
> 唯一规格源：[Canonical CP](../../canonical/specs/agent/prompt-governance.yaml)。评审直接引用该源；本文不设独立预期或逐项同步维护义务。
> 证据：[已确认提案](../../canonical/proposals/2026-11-06-stdd-default-cr-opt-in.yaml) C1、C3–C6、constraints 与成功标准。

## REQ-PG-001 — 常驻底线与按需资料分层

#### Scenario: SC-PG-001 — 不无条件加载完整 CR 手册

- **CP / TC**：CP-PG-001 / TC-PG-001；**Confidence**：high。
- **GIVEN**：任务为分析、STDD 开发或 tools 包维护。
- **WHEN**：读取常驻入口。
- **THEN**：SHALL 按任务和阶段加载，不无条件读取完整 CR 手册。
- **AND**：根入口 LF 规范化字符量低于当前 6,287；不以精简豁免 tools 工程约束。
- **AND**：README 给出当前 STDD、projects 记录及业务绑定入口；CONTEXT 仅新增适用范围说明，原领域定义不变。

## REQ-PG-002 — CR 说明只引用现行契约

#### Scenario: SC-PG-002 — 修正事实漂移且不改业务配置

- **CP / TC**：CP-PG-002 / TC-PG-002；**Confidence**：high。
- **GIVEN**：读取 CR 兼容说明。
- **WHEN**：定位注册、审批或操作工作区。
- **THEN**：SHALL 引用现行权威合同，不复制节点／状态路由。
- **AND**：不保留错误的“无注册子命令”“非 TTY 一律拒绝”、固定状态数量或本地回退副本说法。
- **AND**：graph 顶部旧回退注释须修正为 `workspace.tools_package_path` 的权威入口说明；只允许约定注释和两个 description 变化，其余业务配置解析后保持一致。

## REQ-PG-003 — 精简不削弱保护或覆盖已有改动

#### Scenario: SC-PG-003 — 共同底线与全局一行修正

- **CP / TC**：CP-PG-003 / TC-PG-003；**Confidence**：high。
- **GIVEN**：对入口进行精简并修正全局优先级。
- **WHEN**：与实施前工作副本和实际修改范围比较。
- **THEN**：SHALL 保留账本合法入口及入库、可测试的版本化脚本要求，禁止会话内现写脚本处理执行账本；其他 YAML 归属不明时按执行账本处理。
- **AND**：可精准编辑的例外仅为记录设计偏离、供人工审阅的 STDD `pending-adjustments.yaml`；保留原记录／扩展字段，依据原话或可靠来源区分方向、具体决定、执行授权和未决事项；核对所属 change、YAML 解析与类型、必需字段、编号唯一、冲突标记与差异，失败或归属不明时停止，resolved 如实。
- **AND**：保留行尾规范化／解析硬失败、累积基线、CUSTOM、权限／唯一入口／CAS／审计／门禁及独立授权要求。
- **AND**：全局第 2 行的唯一预期为“安全与数据完整性是底线；在此前提下优先满足用户明确要求。涉及不可逆操作、数据丢失或敏感信息时，先明确影响并取得必要确认。正确性优先于简洁。”；不维护旧句或并行替代预期。其他行、既有账本、历史、在途变更和用户未提交改动不因本次被改。

## REQ-PG-004 — 不夸大验证覆盖

#### Scenario: SC-PG-004 — 静态、人工与实际运行结果分列

- **CP / TC**：CP-PG-004 / TC-PG-004；**Confidence**：high。
- **GIVEN**：获得静态条款、原生 lint、CP 人工视图或场景评审结果。
- **WHEN**：汇报验收。
- **THEN**：SHALL 分别说明实际覆盖和未覆盖。
- **AND**：不把它们或模型 configured、在途代码说成实际路由、CLI 自动验证、已部署或请求 token 比例实测。

## 覆盖与评审边界

4 Requirements、4 Scenarios、4 Canonical CP、4 TC；high=4、medium=0、low=0。

静态 action 仅检查关键条款。完整性、未提交改动保留、graph 业务配置、全局其他行不变及门禁兼容还须按 [test-plan.md](../../test-plan.md) 核对。原生 lint 不扫描本次所有目标文件，不得以其通过替代这些检查。
