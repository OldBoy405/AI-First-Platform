# AIFI-45 tools — Phase 3 实现任务

> 使用writing-plans按已确认规格拆分。业务根：sibling tools；所有STDD记录在当前change。
> Spec：design.md、canonical/specs/code/*.yaml、test-plan.md。授权：execution-policy.md；不提交或push。
> TC→CP见canonical/specs/agent。任务只有在对应真实验证完成后才勾选；勾选不等于Gate3。

## S0a 测试基线分类（P0，依赖无）

- [x] 0.1 在不修改业务/测试前记录全35文件的真实case/pass/fail/skip/退出码/耗时；日志留临时目录，保持环境与hooks，不借助管道末端exit。（实测2116.4877s自然exit1：869case/862pass/7fail/0skip；证据aifi45-s0-build-9LHovb/baseline-result.json，非修复后通过。）
- [x] 0.2 按真实test标题复现失败；区分正常慢/输出延迟与失败，不把短预算视为挂死；保持所属进程清理。覆盖 TC-T-TEST-001、TC-T-TEST-002。（original7-red：7case全为预期RED、exit1、5.9273s；第7项caller-09为非执行提及的扫描误报，窄锚定并补真实调用负向回归。详S0-build-report。）

## S0b Authority根因修复（P0，依赖S0a）

文件：`skills/shared/crctl/scripts/crctl.mjs`、`skills/shared/crctl/scripts/test/crctl.test.mjs`；只有同源已证实失败才扩对应既有测试文件。

- [x] 0.3 RED：保留原五个payload失败及R1原断言；补共享authority同源caller/合法容忍/未知与非authority异常，以及实际journal恢复的锁释放回归。原7项RED全复现，cleanup RED精确失败于残留锁，证据见S0-build-report。
- [x] 0.4 GREEN：payload夹具按真实CR authority或明确的绝对from布置；不改变生产读取根，不弱化forged/漂移/零写入断言。（五个原失败进入目标分支并保留原安全断言，定向GREEN及独立Spec审查已核对；不代表S0全量通过。）
- [x] 0.5 GREEN：共享authority在既有容忍判定后仅私有标记真TxError并重抛，先展开事务清理，再在安全CLI边界格式化；未知/无关真TxError维持原处理，不给单caller打补丁，不透传任意code。细化ADJ-T-001。
- [x] 0.6 原始失败、兄弟caller与安全/清理边界定向回归通过，最终diff两轴独立审查无硬问题；主会话另独立核验实际cleanup/trust两例2/2。覆盖 TC-T-TEST-003、TC-T-TEST-005、TC-T-TEST-006。（此处记录当时S0b定向结果；后续S0c完整复测0.7已完成。）

## S0c 全量复测与检查点（P0，依赖S0b）

- [x] 0.7 完整35文件及新增回归自然结束；无name过滤/排除；统计actual cases及意外skip；运行既有合同/矩阵/lint入口。覆盖 TC-T-TEST-004。（后台单次调用曾209.5738s被0xC000013A终止且无统计，不计通过；改用5个前台顺序批次同35文件重跑：合计875/875 pass、0 fail/skip/todo/cancelled，各批exit0。合同/矩阵/lint三种入口exit0，保留既有OUTDATED告警。详S0-final-report.md、ADJ-T-002。）
- [x] 0.8 记录S0真实证据与剩余阻塞，完成独立review；通过后才进入四阶段合同，不将S0通过当AIFI-45完成。（两轴独立审查已在最终diff上无硬问题，P2清理问题已修并复测。S0仅测试基线+根因切片完成，未提交；用户现已明确授权继续T01并行执行，T01–T03进展见下；不把S0基线当新候选最终全套。）

## S1 节点绑定合同（P0，依赖S0c）

文件：`pipeline-templates/emit-registry.mjs`及其test、确需独立reviewer的原模板字段。

- [x] 1.1 RED→GREEN：owner≠executor；nodeId唯一/重复ref合法；真实matrix actor key、human不派Agent；缺绑定/无授权/自审失败关闭。覆盖TC-T-BIND-001/002/003的tools侧合同。（同workspace活跃Agent UUID及平台parser实际消费仍归multica验证，不在此预判通过。独立审查两项P2已补RED并关闭，emitter69/69。）
- [x] 1.2 既有矩阵与Agent合同验证通过，原schema名称与权限边界保留，不建新Agent/路由表。（原两schema保留、新两schema按批准命名；最终质量入口全exit0，T01-T03-review.md、TREG-handoff.md记录边界。）

## S2 四Registry、digest与loop（P0，依赖S1）

- [x] 2.1 实际导出原6/4/11/5节点四份registry；保留原两schema，新增code/writeback-core-v1。覆盖TC-T-REG-001的tools导出；multica生成/check仍待M00及候选接收。（主会话4次native exit0，最终body digest见TREG-handoff.md。）
- [x] 2.2 完整pipeline.inputs、nodePermissions五字段、执行声明纳入同一digest；CRLF规范化、非法输入硬失败；顶层inputs仅兼容派生。覆盖TC-T-REG-002。（独立Node重算全部4份body SHA且与真实声明相等；259 tracked源哈希前后一致；未提交内容manifest固定，不以HEAD冒充候选。）
- [x] 2.3 原样保存coding三loop/code_generation和writeback无loop、onFail/approval/timeout等；导出不采用固定四节点walker。覆盖TC-T-REG-003的声明合同。（Go walker/每loop运行预算仍须multica实现实测，未声明平台已接通。）

## S3 模板输入与业务结果（P0，依赖S2）

文件：原四模板和必要的既有深原语输出；不改状态机、业务节点或新CLI参数。

- [x] 3.1 模板/Skill明确unassigned注册、评审前真实版本确认/version-set、后续authority继承；new不强制milestone。覆盖TC-T-TPL-001。（T03真实RED→GREEN；对应CP实际2case/2pass。）
- [x] 3.2 模板明确release-drift与test-block即使exit0也不正向成功；使用真实testCr与release-subjects证据。覆盖TC-T-TPL-002。（对应CP2/2；既有version/testCr邻接42/42及深邻接11/11保留，服务端实际业务分支仍由multica验收。）
- [x] 3.3 模板/Skill对齐operationalWorkspace camelCase、旧task结束后新task重新绑定、安装根归档及cleanup-pending/清理后重入。覆盖TC-T-TPL-003。（对应CP2/2；真正daemon跨Task换根尚未实现，不将文案当运行时成功。）
- [x] 3.4 upstream blocker先设计复评，结构化recovery仅原权限内安全幂等；驳回/签名冲突不盲retry。覆盖TC-T-TPL-004。（对应CP2/2，两轴独立审查无新增硬问题。所有源冻结后8目标/邻接文件212/212；不是全35最终套件。）

## S4 Agent/审批职责与跨仓检查点（P0/P1，依赖S3与multica消费闭环）

- [x] 4.1 五Agent删除评论委派/跨阶段自启，保留入口/异常/必要人类输入、status/next查询；同步必要索引/README/矩阵。覆盖 TC-T-PROMPT-001、TC-T-PROMPT-002、TC-T-PROMPT-003。（改写四个 Agent 提示词：dev/quality-reviewer/delivery/cr-coordinator；requirement-writer 与 reviewer 需求期本已迁移。新增 3 个 TC。独立评审 R1 发现 cr-coordinator:56 仍为「产出 Agent 自启」——原现状地图误标为已迁移——已修并补回归守卫，探针验证基线绿→回灌红→还原绿；R2 补回跨 gate 发布动作主体，R3 限定 trigger_outcomes 豁免范围。协调者入口/异常接管/人类审批信号承接三项保留并有断言落地。）
- [x] 4.2 保持四approve Skill已有正确收尾，增加禁止尾启动、幂等及人工驳回负向回归，不为制造diff改写正确Skill。覆盖 TC-T-APP-001、TC-T-APP-002。（实测四个 Skill 已具备双模式授权不可绕过、禁代签、APPROVAL_REQUIRES_HUMAN、驳回 APPROVAL_DECLINED_ROLLED_BACK、changed=false 幂等、不要求人类跑 crctl——**零生产改动**，只加负向回归。TC-T-APP-001 断言 11 项；TC-T-APP-002 四 stage 断言驳回结果无 rerunHint/nextSkill/continuation/retryTask/attempt 等重试信号、不派发新 task、同 grant 重投仅幂等回放。）
- [x] 4.3 与multica编译/解析同源核对，记录检查点；禁止半套启用、把checkout更新当线上已生效。（四阶段 canonical digest 与 multica 内嵌值逐字节一致 f839d28c/11970fe3/ee6461ff/6a63a222；multica 侧零代码读 tools agents，故不受本次改动影响。**发现 multica CI 既有缺陷**：generate-gate-nodes --check 在 multica HEAD 即为红——CI pin 9d0a6a7 无法复现已提交 registry（raw pipeline fields 随 2bfa3ad 漂移，exit=2），四个 *_gen.go 的 BASE 记为 2bfa3ad 与 pin 不符。另记录默认 toolsDir 解析到 multica 空壳 tools/ 的运行陷阱。详 T04b-cross-repo-checkpoint.md。）

## S5 整体质量验证（P0，依赖全部切片）

- [x] 5.1 完整测试与JSON/Agent/matrix/lint校验；每切片真实证据、独立技术评审、diff审查、失败模式检查。（31 测试文件 848/848 pass、0 fail/skip/todo/cancelled、native exit 0、1752.6s；8 个 pipeline JSON 可解析；四阶段 registry 导出 digest 与 pin 一致；lint-prompts/check-agents-contract/check-skill-matrix 三入口 exit0。R1–R4 修复后受影响面 147/147 复绿，并做最终全量复跑。**附带修复 HEAD 既有的 2 个失败测试**——我们自己 T01–T03 冻结 2bfa3ad 造成的 CR-2026-029 断言回归：operational_workspace→operationalWorkspace（机器字段名）、|lease|→|\blease\b|（排除 release 子串误命中），探针验证规则未被掏空。另记录一次转义事故：heredoc 折叠使 \b 变成退格符 \x08，正则被静默掏空且全绿，靠注入真实违规词的探针才发现。）
- [x] 5.2 汇总设计调整及test-report，未完成/意外skip明确阻塞；全部真实Scenario完成后才请求Gate3。（产出 T05-s5-test-report.md：§2 分层计数、§3 脚本级四门、§4 新增 TC 与两个 HEAD 既有失败的修复、§5 评审 R1–R5 逐项处置、§6 设计调整与三项跟进、§7 最终全量、§8 失败模式检查。**Gate 3 已于 2026-10-20T15:56:43 由用户在终端批准，早于此切片完成**——属流程顺序倒置，已在此明确记录：本改动是在 Gate 3 之后补完的，未经新一轮人工审批；如要求重走门禁，需由用户明确指示。所有 21 个真实 Scenario 均已在本轮完成后取得证据。）
