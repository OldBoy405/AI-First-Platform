# Phase 2 设计与规格审查记录

> 本记录只描述文档/结构审查，不是业务代码评审、Gate2批准或任何测试通过证明。
> 审查完成时两项目为SPEC/in_progress，Gate2待确认。随后用户原文“确认 Gate 2”已登记，并选择“普通模式”，两项目现BUILD/in_progress。BUILD并行核查新发现2项major：可信安装根绑定和不可变授权来源合同尚不完整；当时按B4暂停并写pending-adjustments.yaml。随后用户原文“采纳你的建议，继续别停下来等指令”已采纳补正并授权继续BUILD，普通模式与Gate3人工边界保持；共享补正在wire-contract.md，实现/验证未闭环故major仍unresolved。下述审查是Gate2前快照，不能作为当前阻断为0或业务测试通过证明。

## 1. 范围与事实来源

需求为工作区`docs/AIFI-45-CR流程减负目标方案.md`；批准范围见两项目canonical proposal。旧两个STDD change仅供L3锚定；当前facts由只读子会话核对tools/multica实际源码，不能把历史报告或本地SHA当部署证据。经验库JavaScript与Go查询均为空，不据此宣称无风险。

本轮文档由主会话设计；当前quality配置无model_tiers，未额外派planner或声称升档。独立只读会话审查两份跨仓design，不替代未来产品运行时的独立reviewer。

## 2. 独立设计审查及处置

首轮提出8项阻断和3项建议；主会话同步设计、canonical行为规格与测试方案后，二轮确认原8项已消除，另指出1处原文提取跨仓不一致；修订后第三轮明确该处已消除。SPEC审查结束时已知文档阻断为0；随后用户以原文“确认 Gate 2”批准，CLI登记成功。BUILD模式已由用户另选普通；BUILD调查新增的2项major尚待完整验证；补正执行依据是用户后续明确采纳并要求继续，不是挪用原Gate2批准。

| 发现 | 回修落点 | 结果 |
|---|---|---|
| 过期/撤销缺可执行合同 | T Decisions§2、M§2：首版明确无时钟到期，签名revision撤销、当前head检查、失联关闭与安全收尾 | 原承诺矛盾消除；不宣称撤销可回滚已发生副作用 |
| 追加/旧包重放歧义 | T§2：唯一活动head、前驱CAS、初始额加唯一已接受增量，旧包不降级scope | 并发/重放纳入RPR-007 |
| 敏感动作换operation ID可避额度 | T§2：聚合键不含operation_id，操作幂等键另含它，同lineage继承 | AUTH-006覆盖 |
| 最后一名额用尽挡住测试/review | T§3、M§2：只拒绝新准入，已admitted仍可验证/PASS交付 | RPR-002、RUN-006覆盖 |
| 跨run复用原任务与旧证据拒收矛盾 | T§3、M§2/4：不可变origin与当前binding分开，显式adoption映射与当前证据重验 | RPR-005、RUN-004/009覆盖 |
| no-progress恢复不闭合 | T§4、M§2：精确stop version、签名恢复、新独立证据、锁内CAS和保留历史的新epoch，取证有界 | RPR-012、RUN-006覆盖 |
| 旧原语/删字段可能降级新合同 | T§1：所有写入口按权威注册/迁移事实选择合同，旧TTY/grant不构成新policy旁路 | EVD-006覆盖 |
| Inbox提交后广播丢失 | M§5：既有details的pending/delivered、恢复扫描、同Inbox ID at-least-once投递与消费者幂等 | NTF-005/007覆盖，不能声称物理exactly-once |
| 充分原始自由文本的两仓受理条件不同 | T§2与M§1统一逐字段source_bindings、可信原事件/明确接受附件snapshot或默认版本及独立提取核验 | 第三轮只读复审明确一致 |
| 固定套餐/内容gates边界偏泛 | T§5新旧合同对照表，回写输入与长期源明确 | EVD-001/002覆盖 |
| 通知命名空间与受众为空 | M§5明确workspace/project/CR、规范非空受众及跨run稳定键 | NTF-005/006覆盖 |

准入提交即计次、撤销取消不退款已随Gate2获批；其为明确取舍，不伪装为目标方案最初就已确定的细节。新合同/源签名/持久化唯一键等实现细节在中置信设计中供用户审核。

## 3. 自动结构与覆盖核验

只读解析所有canonical YAML并与Human View、test-plan、agent spec和阶段状态比较，结果通过：

| 项目 | 能力 | Requirement | Scenario | TC | CP |
|---|---:|---:|---:|---:|---:|
| tools | 3 | 12 | 32 | 32 | 32 |
| multica | 2 | 7 | 17 | 17 | 17 |
| 合计 | 5 | 19 | 49 | 49 | 49 |

- REQ/SC/TC/CP全局唯一，每Requirement至少一Scenario；每Scenario有GIVEN/WHEN/含SHALL的THEN、evidence与有效confidence，AND逐Scenario均≤5。
- 49个Scenario都有一一对应的TC和CP；TC优先级P0=41、P1=8、P2=0；Scenario置信度高37、中12、低0。
- 证据源文件、跨仓Markdown链接与5份spec.md存在；Human View的THEN与canonical相同。能力列表与已批准proposal一致，无TODO占位。
- 两份`.stdd.yaml`的understand确认原文均“确认这份 Gate 1”，current_phase=spec，spec.status=in_progress；无Gate2确认。
- 输入逐次CRLF→LF规范化后解析，结构不匹配立即失败；未静默把空提取当无能力。

## 4. 原生CLI结果与限定

- 两项目`stdd proposal validate`通过；`stdd canon verify`均2/2。后者只检查proposal，不扩大解读为全部spec已验证。
- `stdd validate`：multica通过；tools无错误但有2条AND聚合警告。源码`validate.py`按整文件计算9/8个AND，而STDD规格规则是每Scenario≤5；已独立核对每个Scenario均符合。不删要求迎合告警，不修改STDD产品。
- TC详细横表采用原生`**ID**`字段标记，定义各TC一次；32/17案例被原生validator识别。初次格式不兼容已修正，不以自报案例数替代结构验证。
- `extract-proposal`空capabilities与`canon generate --type spec`只生成proposal的差异已在[Phase Context](phase-context.md)记录。草稿Human View由版本化原生`_generate_spec`定向渲染，不自写第二套renderer，也不通过批准Gate2来生成文件。

## 5. 明确未完成事项

- **49个业务TC均未实现/未运行**；尚未业务RED/GREEN、迁移、生产部署、真实CR派发/试点或实际独立交付验收。
- 实际部署二进制、开关、安装文本、活动CR及存量任务未核实，不能把本地HEAD/CI pin当线上证明。
- 没有Git commit/push、生产DB操作、全局权限修改或STDD产品修改。tools既有`.crctl/`及知识库用户原有文档改动保留。
- 用户确认Gate2后，才能登记Gate2、选择BUILD执行模式并实施；DB测试先显式验证隔离DATABASE_URL，任何skip/零选中/未运行不算通过。
