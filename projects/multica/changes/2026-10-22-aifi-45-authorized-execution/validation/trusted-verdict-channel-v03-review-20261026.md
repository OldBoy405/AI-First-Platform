# 可信 T verdict channel v0.3：D7/D8 方案修订与独立复核

日期：2026-10-26。仅文档与计划级复核；**不是动态验证、Gate 批准、部署许可或 TC 完成**。

## 用户决定与修订对象

- D8：选 A，本期不迁移 legacy 业务历史；旧 run/合同/历史保持原样；新 CR/lineage 不得承接旧债后清零。不是删除原 EVD-008 正分支，也不提升既有 CP/TC 口径。
- D7：同意挂到后续通道 change，要求独立解决方案并在原方案文档修订。通道 change **仍搁置、未注册**；本次不创建其目录、不写产品源码。
- 原文件原位升为 **v0.3**：`trusted-verdict-channel-implementation-plan-20261026.md`；D8 在 Spec §5，D7 在 Spec §7 / S8。
- 最终文档 raw UTF-8 SHA256：`6f34b279d86cc8da7f4a0ae393bfa4dcf44b84811edb558002b5d55f32953300`（407 个 split 行，LF，无 CRLF）。这是**文档修订快照**，不是运行时 source freeze 或产品测试 manifest。
- 同步：`decisions-pending-20261025T153000Z.md` D7/D8、`evd-callsite-audit-20261026.md` 历史限定与空集合结论更正、`tc-coverage-20261025T153000Z.md` 增量19、上级 `pending-adjustments.yaml` M003。

## 分层与身份

本轮在 tools/multica 两实际项目根读取 `stdd config models --format json`：均 exit 0、schema_version=1、kind=configured。design=strong；review.code/ test_config/ docs_skills 分别 strong/balanced/economy。模型映射来自 user defaults，review/design 档位为 builtin；无后端回执，所有 actual 记 unknown。

| 角色 | session | requested | 结论 |
|---|---|---|---|
| 只读设计顾问（不充当非作者审核） | `01a17769-d4a5-77b9-a3c5-0f5ce38d3fc4` | `OpenAIPersonal/gpt-6.1-sol:high` | D7 可在通道 change 内独立交付，但当前不能启用 strict |
| 非作者安全复核 | `01a17770-c5f1-77b9-a3c5-0f5edf36301f` | `OpenAIPersonal/gpt-6.1-sol:high` | 初审 BLOCK → 定点补正后 **APPROVABLE-AS-PLAN** |
| 非作者验收/配置复核 | `01a17772-5e4b-77b9-a3c5-0f6341391bf4` | `Gobao/deepseek-flash:max` | 初审 BLOCK → 定点补正后 **SUFFICIENT-AS-PLAN** |
| 非作者文档复核 | `01a17772-1bad-77b9-a3c5-0f60825736ef` | `GB-JP/deepseek-flash:high` | 发现精确定义问题 → 补正后 **PASS** |

上述结论只覆盖本轮修订设计；v0.2 原评审不直接沿用。最终审核后仅补充计划级结论元数据与本记录，未改规范契约。

## Strong F1–F5 处置

| Finding | 计划级闭合内容 | 最终状态 |
|---|---|---|
| F1 停新单/过期后的恢复例外不明确 | 持久 issued/admission seq、STOP_NEW cutoff 与 expiry；服务端从 DB 原事实解析 CheckDeploymentAccessTx；checkpoint/ingest/no_effect/原 request/原 mapping/resume/新准入分别定义。不能用 caller 自报或仅同 origin 放行。 | CLOSED-AS-PLAN |
| F2 preflight 到实际加载仍可换安装 | 完整不可变安装快照 + supervisor install/launch 互锁；task binding 固定一次 launch ID/lease/原字节 permit；只能加载原已批准 pin 或 freeze，不能改载 current 路径；未知启动结果不盲目重启。 | CLOSED-AS-PLAN |
| F3 旧接力退役的工作集可漂移 | DRAINING 先封新 legacy 工作；全部 writer 纳管，变化递增 work revision；FinalizeLegacyRetirementTx 最终 CAS；READY_TO_RETIRE 不直接授权删文件，实际发布另需授权。 | CLOSED-AS-PLAN |
| F4 新 lineage 缺权威业务身份 | 受保护 intake 的稳定 origin/source；完整 legacy 覆盖与 UNKNOWN 拒绝；control_fact 不可变 identity/proof、registry revision、跨 CR unique；selection/reservation 同事务，仍13表。 | CLOSED-AS-PLAN |
| F5 协议闭集与摘要构造环 | 完整 request/observation/verdict/launch schema 与 domain/purpose/scope/action 矩阵；请求只固定 observation_slots，observer 签原 request digest，最终 verdict 才固定 observation_refs/facts_digest；snapshot 不含本轮待生成摘要。 | CLOSED-AS-PLAN |

## Balanced / Economy 处置

- 13 表使用精确单一清单；AfterUp/AfterDown/AfterReapply 每表独立 leaf；ProtectedData 在本次 nonce 库验证 643–647 对象/行不被648生命周期破坏，不改 DB runner。
- S1 FoundationFreshWork、S2 Protocol、S6 IngestSettlement/IngestBinding/WorkerClient、S7 Reader/Composition、S8 Observer/Protocol/Access/Activation/FreshWork/Retirement/ComponentBoundary/Launch/Composition 均有固定命名与独立精确命令。aggregate 只作额外回归，不掩盖缺组。
- SPEC 先冻结实际期望 leaf 名单；未来版本化证据 checker 对照 raw Go JSON/TAP 树逐项检查。RED 须指定失败 leaf、该 leaf 条件断言 marker、未受 mutation 影响的正对照，以及 mutation/恢复源码 hash；未实现/未运行 checker，不能称已有证明。
- D8 的原字节/原映射恢复正例与换 grant/lineage/store/CR/source alias、UNKNOWN 和并发注册拒绝反例成对；component READY/retirement 不能误用生产 activation，strict 缺 decider 固定 NOT_READY。
- 历史审计0命中仅指旧 v0.2；“空声明恒ready”更正为 declared/observed 同时为空才可能 ready；有 tools observation 而无声明会报 undeclared。决策文档旧计数标历史，不作当前进度；正式修订记录与引用现有实指。

## 本轮检查及未验证边界

- 进行了文档静态校验：版本/章节/13表清单、关键 selector、无旧访问接口名、协议无环顺序、无 NUL/冲突标记/行尾空格、代码围栏配对。不是产品单测。
- `git diff --check` 返回0，但这些记录文件为既存 untracked，不能据此单独证明全文格式；另对当前文件原文做了上述静态扫描。保留 TC 台账既有 CRLF，其余改动文档为 LF。
- 未执行产品 RED/GREEN、DB命令、迁移、Linux部署/隔离探针、实际签名协议或安装切换。P0、observer/inventory、实际 immutable pin、全部旧 writer fence、历史覆盖与完整生产 profile 仍需日后获授权验证；无法证明即 NOT_READY。
- AIFI-45 仍 **41/49、NO-GO**，M003 仍 major/unresolved；D7 组件验收不自动回填 EVD-007/RUN-008 或其他业务 TC。EVD-009 主线接线不因本次方案修订而被转交或冒称完成。
- 无 Gate3/commit/push/部署授权；本记录不改变这些边界。
