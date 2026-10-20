# AIFI-45 四阶段 Registry 合同与提示词对齐（tools 侧）

<!-- source_hash: 9430aa9032887dff -->
<!-- generated_at: 2026-10-19T19:27:50.380039 -->
<!-- canonical: canonical/proposals/2026-10-19-aifi-45-runner-contracts.yaml -->

## Why

registry 导出与节点合同只覆盖需求、技术设计两段；节点 owner 虽已生成到 gate_nodes_gen，
派发仍把调用者当全部节点的执行者（设计期 RUNNER_SKILL_MISSING 的直接原因）；coding 与
writeback 模板的输入、canonical 结果、reviewLoop 与实际深原语（crctl 的 spec_id/
target_version、release-subjects、testCr）存在漂移；agents 与 Skill 提示词里仍保留评论委派、
审批后自行 start、跨阶段"按 next 继续"等重复编排。


## What Changes

- M1 合同半：扩展 pipeline-templates/emit-registry.mjs 的导出、编译与 digest，覆盖
requirement-authoring、architecture-design、code-implementation、feature-writeback 四个模板；
生成物与平台 registry 生成器保持同一份声明（不新增第二份节点事实源）。

- 节点执行绑定声明：用既有 pipelineOwner、owns/can-call 与独立评审规则，在既有模板里生成按
node_id 的执行绑定（共享 Skill 交给已授权阶段 Agent，评审交给独立 reviewer），并把绑定与
授权纳入 digest；不给逻辑 system 身份新建执行 Agent，不新建路由配置。

- coding/writeback 模板输入对齐：dev-plan、测试结果、upstream 路由的投影合同与 canonical 结果
字段补齐；模板入参与深原语一致（spec_id/target_version 来自 crctl authority 与既有机器输出，
不从 Issue 标题猜、不在交付阶段重复填写）；缺 spec 或真实版本不静默降级、不生成同义占位值。

- agents 提示词去接力：requirement-writer、dev-agent、quality-reviewer-agent、delivery-agent、
cr-coordinator-agent 只执行当前节点，删除评论委派、审批后自行 start、跨阶段"按 next 继续"；
协调者只处理入口、异常汇总与必要人类输入，状态/门禁/下一步仍引用 crctl status/next，
不复制路由表；失败回执只展示 CR-ID/registration key、错误与影响摘要。

- 审批 Skill 合同保持与回归：approve-requirement / approve-tech-design / approve-code /
approve-dev-start 当前已只做审批收尾与 next 查询，没有 start/resume 尾命令（Phase 2 核查
更正，目标结论不受影响）；保留此边界并补负向回归，实际删除对象是 Agent/模板中的跨节点
接力职责。保留人工授权、TTY/grant、幂等与驳回结果，不为制造 diff 改写已正确的 Skill。

- 文档与索引对齐：README、skills/_index.yml、agents/_index.yml、agent-skill-matrix.yml、
dir-graph.yaml 的相应条目与新增/变更 Skill 保持一致（不改业务节点与产物的必要性、不新增 lint）。

- 本次一并诊断与修复 tools 测试超时：从最小命令、真实退出码、子进程与 Git/环境边界核实
是正常慢测试、输出缓冲还是阻塞；比较可完成用例，定位共同根因后先写回归再修复。
保留 crctl 全部 31 个测试文件、output-guard 3 个、registry 1 个及新增回归的发现范围；
不因超时排除文件、不削弱断言、不用未完成/跳过代替通过。若属正常耗时，按实测预算运行
并报告证据，不编造代码缺陷或制造不必要修补。


### New Capabilities

- **node-execution-binding-contract**：registry 导出四阶段节点的执行绑定（owner/actor/独立评审），平台按绑定派发

### Modified Capabilities

- **pipeline-registry-export**：导出/编译/digest 覆盖四个阶段模板，生成物与平台共用同一声明
- **four-phase-templates**：coding 与 writeback 模板入参、canonical 结果与 reviewLoop 对齐深原语
- **agent-prompts**：五个 Agent 提示词只做当前节点，删除评论委派与阶段自启
- **approve-skills**：保持四个 approve Skill 当前仅收尾审批的边界，回归防止跨阶段启动，不无故改写
- **test-execution-reliability**：测试超时根因可复现可验证，完整测试发现范围保留，未完成与跳过不计作通过

## Success Criteria

- [ ] emit-registry 对四个 pipeline 模板导出可在平台消费的合同，每节点含确定执行绑定，生成物与 digest 一致
- [ ] 代码中不再存在把调用者当全部节点执行者的路径；无评审的交付阶段不硬造 reviewLoop
- [ ] code-implementation 与 feature-writeback 模板入参与 crctl 深原语逐项一致（spec_id/target_version 来源、release-subjects、testCr 结果消费）
- [ ] 五个 Agent 提示词中不含评论委派、审批后自行 start、跨阶段按 next 继续的表述
- [ ] 四个 approve Skill 只描述当前审批收尾，不含下一阶段启动命令
- [ ] node skills/shared/crctl/scripts/check-agents-contract.mjs、check-skill-matrix.mjs、lint-prompts.mjs 全部通过（lint-prompts 既有 OUTDATED 项按现状记录，不新增）
- [ ] registry 导出/编译产物与模板 JSON 通过既有一致性检查，无新增检查命令
- [ ] 12 个限时未结束文件得到证据支持的分类；真实缺陷有最小失败复现与修复后回归，不以先验假说判定挂死
- [ ] Gate 3 完整发现并执行 crctl/output-guard/registry 测试与新增回归，记录命令、实际退出码、耗时、测试与 skipped 数；未完成或意外跳过明确阻塞交付，不能仅凭管道 tail 的退出码报告成功
