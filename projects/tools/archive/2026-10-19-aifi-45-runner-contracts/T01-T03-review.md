# T01–T03 独立审查与收敛记录

## 范围与固定点

- tools HEAD：`a5ecb5783fd8f7b5fa1d0d3b328b704199bbe011`；审查未提交候选，不自动提交。
- 第一轮只评审T01/T02的emitter、既有emitter测试、原四个review executor声明及pipeline-structure的未支持pipeline负向夹具更新。
- S0四文件和既有`.gitignore`不属于本轮改造，不重复将其当新发现；T03在建prompt/input/Skills/合同测试另待冻结复审。
- 作者64/64是作者验证；下述独立执行与只读审查分别记账，均不是multica消费/DB集成通过。

## Standards（第一轮）

- 审查者：`01a153d7-d055-75ce-a57c-1b89fee3c277`。
- 结论：无硬性标准违规、无需要增加抽象的可选重构。
- 已核对单一事实源、CRLF与稳定嵌套排序、真实actor/forbidden/独立review、原schema命名保留及不新增命令/flag/业务门禁/错误码/依赖。
- coding已是受支持pipeline，负向夹具改成`unknown-pipeline`，仍保留非零退出、原错误码、空stdout三个断言；旧误导性token测试标题同时按实际内容改正，不以删断言取得绿灯。
- 此轴只读，未执行测试，不把作者64/64归为该审查者独立证据。

## Spec（第一轮发现两项P2；均已在修复轮次1关闭）

审查者：`01a153d7-8513-75ce-a57c-1b86397b38d0`。

1. **缺少reviewLoop时漏掉实际作者自审。** 原emitter在缺loop时跳过关系校验，独立review分支得到空作者集合。隔离夹具授权同一QA actor写PRD并将其绑定为writer，删除reviewLoop后仍能导出同actor自审。违反SC-T-BIND-002与AGENTS自动评审必须有reviewLoop的既有规则。应拒绝没有有效loop/repair关系的独立review，不新造作者选择来源。
2. **ref-only repair歧义被静默取首项。** 保持需求六节点，另一个节点也引用write-requirement-prd，移除review的repairNodeId且不提供消歧replay，原`.find`仍让导出成功。违反SC-T-BIND-003的nodeId身份/不静默退化及SC-T-REG-002失败关闭。应保留显式ID合法重复ref、无ID但唯一ref的合法情况；仅歧义声明失败，不要求所有loop补repairNodeId。

- 独立实际执行：emitter64/64、未支持pipeline负向1/1，均native exit0、0skip；diff检查干净。这些绿灯未能覆盖上述两处畸形声明，不能抵销P2。
- 当前真实四模板的repair关系没有歧义；问题是非法权威声明的漏拒，非已部署CR的故障证明。
- 已交回原作者只修改emitter/既有测试，先补真实RED再修根因；四JSON仍归T03 writer，不并发覆盖。两项关闭前不勾T01/T02审查完成。

## 主会话独立负向核验

- `pipeline-structure.test.mjs`的未支持pipeline负向：实际1case/1pass、native exit0、单调耗时0.1721987s。
- 持久证据：`C:/Users/GOBAO/AppData/Local/Temp/aifi45-t01-main-yp_p3gmd/`。
- 首次收据解析误按TAP格式，而Node默认输出spec footer；checker退出1不是Node测试失败。原始收据/日志保留，复核实际spec footer后写`verified-footer.json`，没有重跑测试或编造统计。
- 另有主会话隔离repair-ref探针；显式ID的合法重复ref正确通过，不将其误报为歧义缺陷。仅移除ID的探针还带唯一匹配replay，因此最终P2以独立reviewer无replay消歧的需求夹具为更强证据。

## 最终独立复审与主会话验证

- Spec原审查者独立确认两项P2均CLOSED：原反例现在非零、空stdout并保留既有PIPELINE_JSON_INVALID；实际emitter69/69与另6项反例/对照都符合预期。unique-ref无ID、显式ID选择合法重复ref仍接受，显式选择的实际作者若与reviewer同人仍拒绝。
- Standards追加复审无新增硬问题；原断言保留，修复复用同一验证repair关系，不新增路由表、业务门禁、权限、flag或错误码。报告中文化保留原失败与历史preT03值。
- T03两轴独立复审均无硬问题。Spec实际跑8/8新增TC；Standards只读，确认仅17个inputs/prompt叶值变化，26节点身份/kind/ref/executor/loop/审批/超时声明不变，原contract-scan完整保留为前缀。
- 主会话全部源冻结后联合8个完整目标/邻接文件212/212、native exit0、单调6.858714s；259 tracked源LF哈希前后相同。证据aifi45-treg-joint-2apx79y2/；这不是35文件全量或平台通过。
- 主会话实际四份导出、源声明全字段相等、Node重算body SHA、matrix真实actor/权限/唯一owner均通过；259源manifest与最终四digest见TREG-handoff.md和aifi45-treg-final-6gl_4tqr/，未以HEAD冒充未提交内容身份。

## 验证命令定位修正（ADJ-T-003，minor）

- TPL三项CP原来在深回归文件中筛选尚不存在的TC标题，改为实际承载8个新增TC的contract-scan；S0 CP003改为真实S0 authority四例。原深回归全部保留，没有为迎合文档标题改已验证源码或删断言。
- 主会话真实执行全部10项T01–T03 CP，逐条正数case、exit0与原stdout断言达成；S0 CP003另4/4。Spec独立只读核对认可方法匹配SC、无实质弱化；收据aifi45-treg-cp-g00_wsuj/。
- Canonical仍11REQ/21SC/21CP无重复/悬空，nativevalidate exit0，既有5个AND累计口径告警保留。原生canon generate的spec参数被实现忽略，仅生成proposal；不声称Agent HumanView已更新，不手改生成物/索引，不扩大范围修STDD。

## 完成与剩余边界

- [x] 两项P2真实RED→GREEN并独立复审关闭。
- [x] T03两轴复审、主会话目标/邻接联合验证及CP落点核验。
- [x] 四份最终body digest及未提交候选规范化内容哈希交接；旧候选值仅历史证据。
- [ ] multica生成/解析、同workspace活跃Agent UUID与Runner/DB验证（仍受M00/B-DB前置约束）。
- [ ] T04平台闭环后的去接力与T05最终全35及新增回归、整套技术审查；不能用S0或本轮212局部绿灯代替。

本文件是集中过程记录，不是产品运行时账本；不构成Gate3或部署授权。
