# RUN-009 生产者字段与摄入：只读盘点

独立 balanced 请求会话 `01a186c8-9539-7020-aecc-d2be1844ca01`；actual backend 回执 unknown。只读当前可见源码，未运行测试/DB/容器或读取真实事件；不证明部署状态、事件真实性、签名覆盖或完整调用范围。引用行号相对于 sibling 源码根。

| 来源 | 可见构造与缺口 | 可能的原始事实 |
|---|---|---|
| `tools/.../crctl.mjs:3661-3712,3769-3776` review outbox | envelope 含 CR、commit SHA、actor；payload 含 stage、verdict、blockerCount、attempt、blockers、reviewed_at、subject_sha256；此构造不含 run/cycle/reviewer UUID。actor/reviewer 来自本地 identity，不自动是已验证身份；code 的 subjectDigest 为 null，annotation 的 release-subjects 是另一结构。 | commit 中 annotation，traceability 及有 bump 时 review-loop；outbox evidence 是路径摘要而非原文。恢复依赖对象仍可访问。 |
| `crctl.mjs:1244-1260,3661-3735` annotation/loop | annotation 写 reviewer、时间、裁决、blockers 和 current-attempt；此构造不写 cycle/run。traceability/loop 可携 cycle；tools 现有 legacy 对缺 cycle 作 1 的解释不是跨合同可信绑定。 | 精确提交的 annotation、traceability/review-loop。 |
| `multica/server/internal/daemon/crevents.go:1238-1271,1345-1399` commit-scan review | 解析 stage、verdict、blockers、attempt、reviewer、reviewed_at、subject；可选自报 CR/type、repair-target、release-subjects、正 cycle；无平台 run ID。自报 CR/type 不一致可拒绝，但不能证明 reviewer/subject 属于受控执行。 | 指定 commit annotation blob；读取或解析失败则跳过。 |
| `crevents.go:1173-1208,1451-1548` commit-scan test | stage、test-status、commands 与非空 command digest，可选 revision 校验；不含 run/cycle/attempt/reviewer/review subject。可见字段非真实执行绑定。 | 指定 commit 的 test-report 与 trace 测试证据，仍依赖 Git 对象可访问。 |

`crctl.mjs:3754` 当前 commit 标题使用 `[cr] review-record ...`；`crevents.go:351-362` 可见 review 正则使用 `[cr] review-(requirement|tech-design|code) ...: verdict=...`。二者所见形状不同；不据此断言生产一定丢事件或不存在其他构造/扫描路径，需要单独验证。

## 去重与恢复重要细节

- crctl 本地 outbox 去重由 `crctl.mjs:486-538` 与 `lib/outbox-contract.mjs:11-64` 实施；daemon 同批 review 按 `(cr_id, commit_sha, event_kind, stage)` 去重且 outbox 优先，不合并被压制的 scan payload（`crevents.go:1403-1429`）。
- 服务器 `crsync.go:280-335` 的持久键为 `(workspace_id, cr_id, commit_sha, event_kind)`，**不含 stage**。冲突时若已有 evidence 为 `{}` 且后到 evidence 非空，仅补 evidence；不替换首条 payload/actor/time。已 processed 直接 ACK；未 processed 时用**当前到达的 wire event**做 apply 后标 processed，仍不替换 ledger 首条 payload。于是 ledger 首包与实际投影输入可能不同，必须保留输入来源与处置证明；不能笼统写成“总是用首包投影”。同 commit 不同 stage/test 是否因 event_kind 形状实际碰撞，仍须实测对应生产者，不能只看键推出必然发生。
- ACK 后 outbox 文件删除（`crevents.go:1005-1031`）；原 Git blob 是否可恢复为 unknown。若实现 pending/enrichment，必须解决摄入副本、processed 与业务 effect 的独立状态和持久可重放性。
- 当前所见 review outbox/scan 构造未体现事件签名/验签，其他路径及实际部署签名覆盖 unknown。审批 grant 的 Ed25519 canonical 约束 CR/stage/decision/approver/time/evidence digest（`governance/approval.go:46-60,241-242`），并可间接约束已纳入的 evidence 版本，但这不自动证明 review 事件、reviewer UUID 或 run/cycle 已签名绑定。
- 投影 `gate_projection.go:314-325,356-431` 解码自报 CR、stage、verdict、attempt、repair-target；不凭 cycle/reviewer/subject/run 建立可信绑定。可信来源、legacy 策略、签名合同影响和冻结身份仍待评审；纯字段存在不构成权威。
