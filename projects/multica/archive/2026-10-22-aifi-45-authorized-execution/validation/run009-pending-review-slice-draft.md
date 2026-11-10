# RUN-009：平台外评审材料待核接收（候选，BLOCK）

> 本文是方案比较，不是已批准设计、已实现功能或测试结果。用户确认的是：平台外人工评审仅作待核材料、不自动推进；无权威绑定不能一律判为旧轮，未经认证的声称不取得阻塞资格（包括有限阻塞），也不能推进 closure。可信绑定、本人确认入口和本切片范围均未获批准。原 AIFI-45 RUN-009、Gate3 与既有测试责任不变。
>
> 早期草案经独立 strong 静态审阅 **BLOCK**，发现身份、现有拒收后果与设计范围问题；见 `run009-pending-review-slice-review.md`。本文据此原位收敛；独立复核认为候选稿可交人类决定，不代表批准，不能直接实施。

## 1. 已核实的现状与风险

- tools `cmdReviewNote` 将文字写入本地 `approval.yml` 的 `supplemental-reviews`，随后尽力发 outbox；现有 outbox 的 `review-note` 只有 stage/status，不含材料正文、稳定材料 ID 或已认证 reviewer。不能把它当作可信评审材料接收协议。
- multica 的 CR-event kind allowlist 不接受 `review-note`；现有事件去重键也不提供本切片需要的材料身份。正式 `review` 投影会改变 review/run 状态，因此不能为收材料而直接复用。
- 独立审阅发现：`review-note` 被拒时，若拒收文件恰在 terminal settle 当批且尚未进入 dead 目录，ACK/collector/settle 失败链可能使原本 completed 的 CR 绑定任务被报为 `blocked` / `CR_EVENTS_SETTLE_FAILED`；同 UID 可写 outbox 的坏事件也可能产生类似结果。dead-letter 的拒收计数在内存中，重启会重置。此机械后果与“未认证声称不取得阻塞资格、也不能推进 closure”的方向有待协调；不能只设计新入口而忽略既有路径，也不能擅自放松 #284 严格 settle。
- daemon token 的认证分支未清除客户端自带 `X-User-ID`；服务端不能把这个头或来源自报当作已认证的人类身份。真实 daemon 当前可能使用 PAT，同 UID Agent 能读取相关凭据或写 spool；先到内容、共享主体配额与本地回执都可能被伪造或抢占。
- 上述是当前源码和静态信任边界，不证明真实部署的网络可达性、所有写入者或任何材料的作者身份。

## 2. 最小候选与未决选择

### A. 人通过独立平台入口上传（优先评估，不是批准）

现有 `RequireHumanActor` 不等于已证明真人：人类 PAT 仍可能通过，而同 UID Agent 可能读取 daemon 凭据。先核实平台是否存在可可靠区分真人与 Agent 的认证能力及 workspace/CR 成员授权，再评估独立的限额接收接口：经授权的人提交材料，单个数据库事务持久化并返回接收结果；查询须重新认证。接口只收待核材料，不改变正式 review、任务、run/cycle、门禁或 Runner 判定。

这条候选省去本地 spool、collector、ACK 删文件、重试及死信机制。**认证主体、材料实际作者和评审结论是不同事实**：即使上传者通过认证，也不能自动证明其是评审者本人或材料内容可信。若无法证明真人认证、授权和部署隔离，不得称该入口可信或启用生产接收。

### B. 经本地工具和 daemon 转交

仅在实际需求证明离线提交不可缺少后再设计。PAT/spool 既有边界下，不能把持有凭据者、声称的 reviewer 或先到版本当作真人作者/原件；须单独解决稳定 ID、可验证提交来源、同键冲突、容量隔离、掉电恢复、ACK、旧服务兼容和恶意队列阻塞。服务端查询才可证明服务端状态；CLI 读取的本地回执不证明平台已接收。

A/B 都不能直接接入现有 `review` 投影；不预设新增消息类型可以安全复用 `/cr-events`。人可访问的服务端查询/处置能力、保存时限与隐私责任也须另定；不预设升级通知、墓碑、转派或流程引擎。

## 3. 新材料最低安全边界（建议，待批准）

1. **只接收，不背书**：页面和 API 明确标记未核材料及实际认证通道；不可因自报身份、格式、先到记录或传输凭据授予阻塞、恢复、评审通过或执行资格。
2. **租户和身份**：按服务端认证上下文和 workspace/CR 授权隔离；不能读取未经该认证路径验证的 `X-User-ID`。证明真人认证能力后，才可宣称是授权真人的上传行为；作者归属仍需独立核实。
3. **稳定性和冲突**：持久提交成功后仅表示材料耐久接收。重复请求可定位同一提交；同一提交身份对应不同内容时应拒绝并审计，不将先到材料称为原件；审计记录也须纳入限额或聚合，避免冲突请求无限增长。具体标识、事务和回执由选定入口的设计决定。
4. **容量和隐私**：在解析前限定请求体和条目大小、并发及配额；不能让未认证材料无限占用空间，也不能让它耗尽合法人类使用配额。保留期、读取权限、删除和审计责任由人类确定，不自动无限保存或删除。
5. **既有拒收治理**：单独评估停止发出不兼容 `review-note` 或调整其处置等候选；必须保持真实失败可见，审查 CUSTOM #284 的严格 settle 与 healthy outbox 先投递、cursor 不误推进语义。不得因不信任材料就静默吞掉所有拒收，也不得在未获批准前修改既有合同。

## 4. 假定实施后的验证要求（未执行）

- 认证路径/伪造头、跨 workspace/CR、PAT 与同 UID Agent、未授权读写、泄露与限额：不产生审核结论或 Runner 状态变化。
- 持久提交失败、并发重复、同键异文、提交成功而响应丢失、重试及重启：核真实提交结果和不重复语义，不能以客户端本地文件当远端回执。
- 原 `review-note` 拒收→ACK/settle/任务被报 blocked、重启与 dead-letter；同时验证原已批准的 healthy outbox、cursor 和非 CR 行为。任何合同变动先获相应批准。
- 平台外材料无法替代经验证的正式 review；旧轮迟到、新轮早到、闭合和可信补齐仍按 RUN-009 全量合同单独测试。
- 现行 AIFI-45 test-plan 的 RUN-003 补充回归段指定版本化 `multica/scripts/aifi45-db/run.mjs`，但该入口绑定历史事故资源，现处于 HOLD，**不得运行或改向**。新实例、入口和基线须按 BUILD 重大设计偏离处理：账本中已有 `ADJ-AIFI45-M006`，其写入方式合规处理待核；具体变更、资源及执行计划仍须决定，最终随 Gate3 审议。未发现原 Gate2 的 BUILD 中途重开入口；未获批准或安全隔离不明即 BLOCK，不连接历史事故库、共享库或真实 CR。

## 5. 人类需要决定

- 是否确需新增平台外材料接收能力，以及 A/B/暂不做；是否另立 proposal 和真实 Gate1，再决定设计及 Gate2。原 proposal 的新增能力和非目标不得自行改写。
- 真人认证与 workspace/CR 授权的权威事实来源，谁可以提交、阅读、核验和删除；材料可归属于谁、何时可升级为可信证据。
- 既有 `review-note` 拒收导致 settle 失败的处置范围，与原严格 settle 合同的兼容和恢复责任。
- 容量、保留、审计、隐私、上线与回退责任；是否存在合法的非阻断提醒。原通知合同未批准待核材料主动升级通知。

## 6. 主要来源

- `validation/run009-option-a-decision-table.md`、`run009-option-a-review.md`、`run009-binding-candidate-20261029.md`、生产者/终态写入者盘点。
- tools `skills/shared/crctl/scripts/crctl.mjs`、`lib/outbox-contract.mjs`；multica `server/internal/governance/crsync.go`、`server/internal/daemon/{crevents.go,daemon.go}`、`server/internal/middleware/daemon_auth.go`、`server/internal/governance/daemon_workspace.go`。
- 两侧原 proposal/design/test-plan，以及 `validation/run009-pending-review-slice-review.md`。源码未冻结到提交；实施前须重新核对同一快照。
