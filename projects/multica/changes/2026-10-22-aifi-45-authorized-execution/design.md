# AIFI-45 授权内自治执行与有界修复 — multica 技术设计

> BUILD当前边界：T独立receipt试作已撤回，current-head/revoke/claim/消费事务未接通时拒绝消费；HTTP生产配置仍默认503。MDispatch的顺序fixture缺陷在本change按真实RED→公共setup修复，并加DB测试进程lease，不改生产Runner。真实CLI/临时镜像PoC已获依赖授权，仅离线实验；受保护trust root/安装器、真实daemon任务与永久派发仍未完成，major保持unresolved。

> Gate2已真实登记；BUILD可信绑定/来源补正方向获用户采纳并要求继续。普通模式保持，不是Gate3/上线批准；真实实现/验证以phase-context/tasks记录为准。
> Gate 1 原文“确认这份 Gate 1”已由原生CLI登记；开发用STDD，不操作实际CR。
> 需求：[目标方案](../../../../docs/AIFI-45-CR流程减负目标方案.md)。跨仓签名、额度与门禁字段唯一设计源：[tools设计](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/design.md)。本文引用而不另造协议或第二套预算。
> M=multica仓，T=tools仓。精确共享合同以[tools wire contract](../../../tools/changes/2026-10-22-aifi-45-authorized-execution/wire-contract.md)为唯一源；设计不代表已实现，不另造字段/预算。

## Context

- 已核实 M HEAD=`f6e90ab8090c8a712c7fe2a324e977f10a39499c`，T HEAD=`9e41ad74ce631459bc007a29c3d0cdaaa1e49e75`；与线上运行版本无等价关系。
- `server/internal/governance/approval.go` 已有 Ed25519 v1阶段grant、owner/admin与非task-token校验；`approval_record` 存原grant JSON和delivered_at，没有业务consumed_at。daemon `deliverGrants` 可信传输、公钥校验、原子落盘后ACK；ACK只证明送达。
- `runner.go` 的 advisory lock、节点唯一身份、TaskService和任务lineage可复用。四阶段registry与walker存在，但router、Reconcile、启动发现和periodic resume并未因此自动全阶段闭环，必须验证实际生产调用链。
- 已有真实UUID独立性检查和review evidence校验，不能只凭UUID隔离宣称实际diff/测试已核验。旧cycle与run、attempt、subject、template必须联合适用。
- `four_phase_dispatch_cp_test.go` 的fake enqueuer和直接ReconcileCode调用不能代替本轮统一wake链验收。`governance/crsync_test.go` 会使用DATABASE_URL且缺省可能指向共享本机DB；本轮测试必须显式创建隔离数据库并先验证，不能直接跑缺省命令。
- `server/internal/governance/gen/generate-gate-nodes.mjs` 和CI tools pin负责生成一致性；本地生成与CI pin不证明已安装文本/服务二进制一致。

## Decisions

### 1. 可信授权入口使用现有认证和签名基础，不把Agent候选包当原请求

**方案**：扩展既有project gate/审批服务入口与`approval_record`，记录`execution-authorization/v1`原始可信事件、结构化授权包和签名。字段及byte签名域只引用tools设计。

- 人类owner/admin认证与可信actor来源从middleware得到；task-token、自由文本转述、Git owner字符串和客户端自报header不能签授权。
- 若原始认证请求已明确目标、范围/交付位置、验收、禁止项和已接受执行上限，直接绑定，无第二次阶段确认。Agent后补包只可作为候选；不能据候选签发更宽授权。敏感动作需原请求或后续明确专项授权。
- 原事件与结构化字段可以同一可信请求提交；已有可信自由文本也允许按T设计§2的逐字段原文提取路径受理，不要求字段同时提交。每个字段须可验证地关联原事件/已明确接受的引用附件snapshot或默认规则版本，独立验证只确认提取未新增语义；平台核验source_digest与source_bindings，不把候选者的自然语言解释当新授权。不能证明充分则只询问欠缺内容，不能默认“已同意6次及任意发布”。
- 扩展原pending/ACK传输，不另建私钥分发渠道。签名记录采用明确grant kind/purpose；不得用原stage批准唯一码吞掉新授权，不可为方便去重而覆盖历史grant。新增签名域不重用v1阶段签名。
- delivered与consumed严格分开。只有T已提交且经既有可信daemon/CR事件通道验证的授权receipt可投影为已消费；平台收到HTTP200、ACK或Agent回复不算。

**为什么**：保留可信来源且避免每阶段机械确认。**排除**：另建审批组织、Agent自签、用ACK代消费或为同一事实重复要求人确认。

### 2. T先裁决与提交准入，Runner后以原身份幂等派发

**方案**：Runner只解释T的`status/next/gate`及committed receipt，保存执行身份/结果引用，不另算六次额度或两次停止。

```text
可信人类请求 → approval service → daemon送达 → T绑定/准入事务
    → committed receipt → Runner锁内协调 → 真实TaskService幂等入队
    → 执行/测试 → 独立reviewer → T评估/状态事实 → wake同一Runner
```

- 每个纠正性任务在入队前必须有当前authorization/repair receipt；首次正常实施不走修复消费。receipt和任务绑定拆分为不可变workspace/project/CR、原origin、repair_id、原logical_step，以及当前run/node/attempt/cycle、subject、template/policy的execution binding。supersede不换repair/根键；需平台可信adoption映射和T锁内adoption receipt绑定旧根→新run。原task归因不覆盖，当前节点只有重验subject/版本/授权后才能采纳映射结果；无映射的旧run证据仍仅留历史。身份attestation不能代替业务授权。
- 复用run/node/task lineage。现有run内节点唯一性不足以独自覆盖supersede后的同一修复：需要在**既有任务记录/约束**补充按可信scope+repair_id+执行步骤的持久化idempotency关联，不创建预算表或中央去重表。
- 已核实run为`pipeline_run.execution_context`、node为`pipeline_node_run.detail`、task为`agent_task_queue.context`；run没有直接project_id，tenant/project必须由可信绑定与task/run关联共同校验。执行引用分别保留在`execution_context.execution`、`detail.execution`，所有认领/更新路径合并保留，不能被`setRunnerDetail`或upsert整体替换。
- 新增`agent_task_queue.logical_dispatch_key TEXT NULL`：仅逻辑步骤的**根任务**写入，由可信scope+repair_id+原logical_step_id的带域摘要构造；新partial UNIQUE索引`WHERE logical_dispatch_key IS NOT NULL`在终态后仍保留唯一性。新query按键查询根及现有retry lineage，冲突返回原任务；现有仅活动node-run唯一键不能充当永久键。
- 技术retry子任务的该列为NULL，通过现有parent/retry字段和context携带根键；不创建第二个根，不再扣额。根已终态时查询其子链决定恢复/完成/技术阻断，不把根复活。后续真正纠正性修复需要新origin与新T准入。
- 初始/纠正分类由T当前阻断与next裁决，不由Runner把新run自行标成“首次正常实施”规避消耗。新增schema/query/sqlc/model按现有生成方式同步，不新增FK/cascade；旧行NULL保持旧行为。当前最大迁移641，实施时重核编号：列迁移与每个CONCURRENTLY索引使用独立顺序文件，并登记concurrentIndexCleanups。
- 数据库事务中原子保存receipt引用、逻辑派发关联和入队记录；唯一冲突返回同一已有任务。receipt已提交但DB尚无task时恢复补入同一任务；DB已插入但响应丢失时查原键，不创建第二次逻辑派发。
- 技术重试保持同一repair_id和lineage，沿用既有有界重试；技术attempt变化不新增T准入。任务是否创建未知时暂停查询，不发送新identity。
- T事务未提交、不适用scope、缺当前授权head或停止时禁止**新纠正性准入**。额度恰用完不阻断已admitted修复的测试、独立reviewer、安全恢复或PASS交付；它们复用原receipt，不新增消费。T查询/传输故障不能降级旧路径。
- 首版不新增时钟到期协议，不宣称过期grant支持；撤销使用T设计的签名revoke revision，平台入队/实际启动前重查当前head。失联不能启动新准入/敏感动作；未启动的撤销任务取消且已消费保留，运行中只允许既有有界安全收尾/只读核验，不承诺回滚已发生的不可逆副作用。
- 无进展恢复只接受T的repair-resume已提交receipt（精确stop version、签名恢复授权和独立新证据），不靠ACK、reset或本地streak放行。

**排除**：Runner内另设remaining counter会双裁决；只靠run_id,node_id,attempt无法覆盖跨run重复；不可能将Git事务和DB写入伪装为单个原子提交。

### 3. 四阶段必须接到真正的入口、wake、发现与恢复

- 在原`router.go`/服务入口补齐当前目标阶段的受控启动，统一`Reconcile`路由及`StartupScan`/periodic resume发现，不只单独暴露walker。
- 注册新policy时固定阶段模板、policy和安装版本；stage gate消费充分授权，缺授权只请求具体补充，仍保留独立评审与实际交付检查。
- 所有wake包括人工真实新授权、grant ACK、已提交CR事实、任务完成及启动恢复都归同一Runner；协调者只解释、澄清和通知，不再次spawn作者/reviewer。ACK可wake，但不能直接完成审批或enqueue旧continuation。
- 旧合同与未接通阶段保持原路径。新版本只有在入口、periodic发现、失败恢复及安装文本同时验收后启用，不先删除旧恢复能力。新旧不能同时接管同一动作。
- 各stage的pipeline输入和business output必须按实际registry schema校验；缺参数不能靠Issue标题猜target版本/spec，也不能因新policy跳过既有合法发布/回写检查。

### 4. 证据采用联合执行身份，独立性与内容适用性同时成立

有效review/assessment须同时满足workspace/project/CR、当前execution binding的run/node/attempt/cycle、subject/release-subjects、template/policy、authorization/repair receipt及真实reviewer身份；跨run仅允许§2的显式adoption映射加当前适用性重验，不自动采纳旧结果。字段来源是可信任务归因和committed CR证据，不是Agent自填描述。

- 迟到/旧cycle/旧run/旧subject证据留历史但不推进当前节点。内容相同不自动证明执行身份适用；模板升级也不自动获新授权/预算。
- 作者、reviewer必须真实UUID不同；reviewer查看实际差异和可运行证据。作者自报PASS、旧报告和仅字段齐全都不能交付。
- 机械例外由独立确定性检查身份和当前输入/工具/subject证明；生成规则、输入、工具、授权或验收有语义变化仍需要独立reviewer。平台不自行推导第二套免审标准。
- 新policy减少人工阶段门不等于普通部署授权。敏感动作必须向T提交当前具体action/target/environment/operation_id检查；受控运维入口保留身份校验与审计。

### 5. 最小通知复用现有记录与投递，不建全局去重账本

- 主动通知仅三类：需要补充授权/业务判断；有界恢复后需责任人处置的阻断；约定交付完成。普通节点完成、ACK和固定status/next快照只留可查询运行记录。
- 授权/范围/验收/追加额度找有权决策者；环境/凭据/部署/绑定故障找维护责任人。两角色可同人，维护权限不变成业务授权。
- 复用既有run/node/issue/comment/通知事务上下文记录最近通知事实；键明确包含可信workspace/project/CR、原因类别、稳定root cause/事件、规范证据摘要和规范化非空接收者。同CR跨run保持键；不同CR不能因同名原因互吞通知，不按日志文本或重放时间变化。
- 已有`cr_sync_event`按workspace/CR/commit/event-kind持久去重，但不能覆盖跨新commit的同一未变化阻断；`Inbox CreateIfEligible`和读侧issue-group聚合也不是发送去重。新策略在既有node/run的execution上下文记录原因/证据/受众引用，在既有`inbox_item.details`写`execution_notification_key`。
- 对新字段存在的行新增按`workspace_id,recipient_type,recipient_id,details->>execution_notification_key`的partial UNIQUE索引（独立CONCURRENTLY迁移）；新策略Create路径ON CONFLICT返回原记录而不再创建Inbox。它是既有收件箱记录身份，不是新全局去重账本；旧通知无该字段，行为不变。
- 在同一既有记录的details保存`execution_delivery.status=pending|delivered`和稳定Inbox ID；提交后广播成功再标delivered。提交后广播前崩溃扫描pending恢复；广播后标记前崩溃允许同ID重投，消费者按Inbox ID幂等更新/展示，不新增主动提醒。不得宣称广播物理exactly-once；已delivered相同事件重放不再广播。
- 同一事务持久化运行通知引用与Inbox记录，重放复用原引用。未变化阻断不产生第二条用户可见提醒；新失败、重要证据变化、接收者变化及交付必须得到不同的规范事件身份，不能被去重吞掉。
- 通知失败不回滚已提交业务事实、重签授权或重新派发writer；沿原通知投递语义有界恢复。平台内部持久化唯一性不冒充任意第三方通知端到端exactly-once。
- 内容仅结论、必要错误、canonical证据链接及需做的动作。无授权问题不要求人回复“继续”；无固定节点全文报告或JSON复制。

### 6. 新CR试点、迁移、回退和交付边界

- `authorized-execution/v1`默认不启用；新CR明确opt-in，校验T源/policy/registry、Go生成物、平台实际二进制、Agent/Skill安装和运行开关一致。任何未知标未就绪。
- 旧CR与旧run保留原pin与历史；显式迁移需要新授权、历史消耗/剩余、原未决任务/副作用处置和新旧合同绑定。历史无法核实不清零、不静默迁移。
- 回退停止新准入，不抹掉已admitted任务、已消费额度或证据，不降级成legacy来绕过门禁。
- 本轮交付是经验证的代码/合同与本地证据；实际生产发布、真实CR试点或存量接管需要专项授权，未执行必须清楚标注。不能把三条隔离回放当通用可靠性或上线证明。

## Architecture

### 拟修改范围

| M路径（已有，除注明外） | 修改责任 |
|---|---|
| `server/internal/governance/approval.go`、`internal/handler/project_gates.go`、`internal/middleware/auth.go`相关入口 | 新grant kind、可信原请求绑定、敏感动作与审批权限，不改变旧v1安全边界 |
| `server/internal/daemon/crevents.go`、`pkg/db/queries/approval.sql`、既有审批migration/schema/model | 扩展grant传输及消费投影，ACK仍只送达；迁移文件用实施时下一个可用编号 |
| `server/internal/governance/runner*.go`、`cmd/server/router.go` | 统一全阶段wake/启动扫描/恢复、准入receipt、证据联合身份 |
| `server/internal/service/task.go`及实际pipeline/task query/model/migration | 持久化逻辑派发幂等，不新增额度账本；技术重试lineage保留 |
| 原issue/comment/notification服务及run/node上下文 | 三类通知、责任人分流与原身份重放 |
| `packages/core/inbox/ws-updaters.ts`、`packages/core/platform/system-notification.ts`、`packages/core/realtime/use-realtime-sync.ts`及已有inbox realtime测试；`apps/mobile/data/realtime/use-inbox-realtime.ts` | 按稳定Inbox ID处理at-least-once广播与用户可见通知；每个启用新policy的客户端都须验证，不默认各客户端已有去重 |
| `server/internal/governance/gen/generate-gate-nodes.mjs`、生成物、`.github/workflows/ci.yml` | 同源合同与tools pin一致；不把临时working tree注释当发布证据 |
| 对应`*_test.go`、隔离验收夹具、`CUSTOM.md` | Gate2后以公开入口测试；代码英文注释，台账按当时实际结构登记 |

### 公开测试边界

1. 真实认证route/approval service → pending → daemon校验落盘/ACK → 临时T CLI验签与消费；用测试密钥、临时workspace/Git，不触碰真实grant。
2. 真实stage入口 → 原统一wake/ResumeActiveRuns → 真实TaskService与隔离Postgres；断言入队记录、归因和幂等。不能用fake enqueuer或直接调用ReconcileCode代替端到端验收。
3. 真实事件投影/通知入口 → 原comment/通知持久化；断言接收者、可见通知数量和canonical链接。只测内部helper不算完成。

### BUILD切片与跨仓顺序

T签名/授权golden → M可信入口/传输消费 → T修复准入与assessment → M实际DB幂等和四阶段wake → T内容gates/registry+M生成 → 通知/显式迁移边界 → 三路径失效测试 → 独立评审 → Gate3。每个切片先一条RED再最小GREEN，不先批量写全部实现。

## Risks / Trade-offs

| 风险 | 缓解 |
|---|---|
| task-token或候选包伪装人类原请求 | 原middleware身份、owner/admin、可信事件与签名域；失败无授权记录、无任务 |
| ACK、HTTP成功与实际消费混淆 | delivered与committed receipt分开；最终仍核T状态/subject |
| 跨run重复或双派发 | 原identity+持久化唯一约束+真实TaskService测试；新旧路径互斥 |
| migration影响存量/共享DB | 新列可空、旧行legacy、隔离DB先验、生成query和回滚计划；不直接对共享DB跑测试 |
| 没有完整原生授权入口却先删人工路径 | 新policy显式opt-in、充分性缺口停止；旧恢复保持 |
| 迟到证据误推进 | 联合身份与版本核验，保留历史不应用当前 |
| 去重漏掉重要变化 | 固定业务原因+证据+受众，测试变化与重放、通知提交故障；不以日志时间做键 |
| 声称上线但无部署证明 | server标签/CLI版本仅线索，核二进制/镜像/安装digest，未知明确披露 |

## 审查与状态说明

L3锚定已有签名/TaskService/Runner锁及两份旧STDD模式，安全与跨系统的最低等级满足；新授权包/任务唯一键/阶段条件仍为中置信技术设计，需Gate2审核及BUILD故障验证。Go经验库CLI返回空列表，未据此声称无风险。`extract-proposal`能力提取为空，已对照canonical，未改STDD产品。此段为SPEC原快照：Gate2现已由原生CLI登记，普通BUILD进行中；来源/Auth/资源/客户端已有组件代码、CUSTOM登记和专用隔离DB证据，详见phase-context及T build-evidence。完整业务TC/切片完成仍0，无新migration、真实CR或生产DB操作，未自行Gate3。
