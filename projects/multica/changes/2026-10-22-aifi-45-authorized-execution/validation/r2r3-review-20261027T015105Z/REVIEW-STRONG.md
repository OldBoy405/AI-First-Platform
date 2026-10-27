本章裁决：R2 BLOCK
本章裁决：R3 BLOCK

仅据冻结草案及 tools 符号片段静态复核；未读其他 lane、未执行命令或修改文件。R1=(a) 不重开。

**STR-01｜blocker｜R2 第1项：“UNIQUE(cr_id,repo_id,approved_source_sha)”**
同一 CR/repo 可有多个批准 SHA；没有规定如何按当前 head/grant 唯一选中有效批准记录。端点可能选到旧批准，行存在不等于当前批准存在。
**最小修订**：明确批准记录与 workspace、当前授权 head/grant 的关联及失效规则；定义唯一有效记录的选择谓词，多匹配即拒。实际候选 HEAD 仍仅作本地审计事实。
**归属**：R2。未补前不可写唯一结果断言。

**STR-02｜blocker｜R2 第2–3项：“调用方只能声明 CR 身份”及响应闭集**
认证主体不等于目标绑定：未规定声明 CR 必须等于哪个可信会话绑定、`workspace_revision` 与何者比较。响应只有实际 `head_revision`，没有明确预期 head 的权威来源；`repos` 也无完整集合的权威比较规则。`legacy_proven` 要求证明摘要，但闭集无该字段。
**最小修订**：固定主体→workspace→CR→当前 grant 的解析与相等校验；定义 revision 比较、批准/未撤销的成功响应前置条件及原子读取范围；仓库集合要求与权威集合精确相等、repo 唯一；补证明字段与验证规则。
**归属**：R2。目前身份错配、遗漏仓库、旧 head 的反例无法得到唯一预期。

**STR-03｜major｜R2 第4项：三种失败码**
没有规定端点错误到 CLI 的映射及优先级。现 `crctl.mjs:1883–1884` 将 findings 折成 `AUTH_SCOPE_VIOLATION`、problems 折成 `AUTH_SCOPE_UNVERIFIABLE`；草案未说明 HEAD_MOVED/REVOKED 是否保留，以及已知越界如何输出。
**最小修订**：列服务端条件→响应码→CLI 外层码/结构化原因表，明确多错优先级；不得把已知越界静默变成不可验证。
**归属**：R2。

**STR-04｜blocker｜R3 第1–2、6项：“重验通过那一刻”“M事务的唯一提交点”**
读通过、事务提交和实际 push 是三个时点。缺少重验事务锁哪些共享授权行、如何与撤销互斥、提交何种逐 effect 记录；普通读取不能建立所称总序。“此前失败=零 effect”也只能指当前 effect，不能抹去前仓发布。
**最小修订**：明确授权排序点与远端 effect 确认点分离；定义撤销/重验共享锁、提交的 effect 身份与幂等规则，提交后释放 DB 事务再 push；明确重验提交后撤销是否仍允许该已排序 effect 发布。
**归属**：R3；若改变撤销即时性需人类决定。当前只有措辞闭合，竞态未闭合；不能据此声称网络 push 已被事务保护。

**STR-05｜blocker｜R3 第3–4项：“以journal记录的effect为事实”“先查远端”**
push 成功而 journal 尚未记成功时崩溃，journal 只有 intent；不能据此判定未发布，更不能先因撤销拒绝而跳过远端核实。撤销后的重试也未区分“确认既成事实”与“产生新 effect”。
**最小修订**：持久区分 intent/unknown/confirmed；恢复先只读核实远端，规定相等、后继包含、未发布、改写各分支；未知状态禁止发布；确认旧 effect 不授权后续 effect。
**归属**：R3。补后才可写响应丢失×撤销交错测试。

**STR-06｜major｜R3 第3、5项：“含base变化即拒”“要求新授权”**
部分发布后禁止新事务，但 base 变化又要求新授权，未定义新授权能否续旧 journal；finalize 的独立 push 是否也算 effect 未说明。现源码明确存在 publish rebuild（`workspace-transactions.mjs:2167–2179`）及独立 finalize commit（`:2194–2223`），草案须明确覆盖，并非“尚未实现”缺陷。
**最小修订**：给零发布/部分发布/全部发布待 finalize 的恢复矩阵；明确 base 漂移的失败码、人工终结出口，以及 finalize 重验与漂移规则，禁止默默刷新旧事务输入。
**归属**：R3。

**最小通过集合**：关闭 STR-01～06；固定交付面决策责任人及决策前禁止进入的验收阶段。无需重开 R1，也无需把实际候选 HEAD 升格为授权凭据。
