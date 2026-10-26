# 通道方案 v0.4 非作者复核记录（2026-10-26）

> 对象：`trusted-verdict-channel-implementation-plan-20261026.md` v0.4 初稿（raw sha256 `07705198e40a2a7c379bd32c43650e815413da72e18f8e7d23d5afccc3e00fd6`）+ `backlog-b-disposition-20261026.md` 初稿。
> 三路均只读、未运行 DB/测试；requested 模型如下，actual 无后端回执，记 unknown。只到计划层，不是 Gate、TC 或上线结论。

| 轴 | session | requested | 结论 |
|---|---|---|---|
| 设计/安全 strong | `01a177f7-4296-77b9-a3c5-0f71009f42ce` | `OpenAIPersonal/gpt-6.1-sol:high` | **BLOCK** |
| 测试/选择器 balanced | `01a177f7-42ad-77b9-a3c5-0f7213e01b14` | `Gobao/deepseek-flash:max` | **INCOMPLETE** |
| 文档 economy | `01a177f7-42be-77b9-a3c5-0f7576085a3f` | `GB-JP/deepseek-flash:high` | **INCOMPLETE** |

## 处置（补正后方案 sha 见文末）

| 来源 | 发现 | 处置 |
|---|---|---|
| strong | B9 把追加授权误写成裁决日志追加 | Spec §2 新增 `execution-repair-extension/v1` 域 + CAS；S3 改称“帧链完整性”，明说不等于追加授权；S5 增追加子例 |
| strong | B7 peer credential 不足（真实 PID、fd 转交、PID 复用、`/proc/root`≠安装根） | P0 改为 daemon 按 launch 登记自填事实 + 私有 socket + pidfd；增 5 个子例与 2 条 mutation |
| strong | B2 加 `FOR SHARE` 与 `BindCurrentTaskToCR` 成环 | disposition：B2 先出锁图、建议统一 task→CR→approval_record；方案 Architecture 写明成环事实；S6 green 前置 |
| strong | B3 过渡可被重领绕过、替换不单调 | 改为持久单调 `fence_required`（任一 generation 已消费 ∨ Strict 创建），并集；终态 Tx 持行锁判定，读失败即拒 |
| strong | B6 换账本位置会清零；“同 commit 重验 head”与无分布式事务矛盾 | 额度键/幂等键分离、旧账本导入、授权效力在 M settlement 线性化；B6 整体归通道，AIFI-45 记为已知限制 |
| strong | EVD-005/006 混写；RPR 业务身份缺陷漏归属；B1 签发签名缺 generation；B15 零发布刷新是语义问题 | 拆 B12a/B12b；新增 B16（标注待逐条复核）；B1 扩为签发+消费+Node schema；新增决策 X5 |
| strong | 1979 行号引用不准、终态“缺字段”表述不准 | 改引 `readExecutionGrant`/`verifyExecutionEnvelope`；改为“两者都缺” |
| balanced F1 | repair 未验签子例挂在 Go 包，mutation 在 Node | Go 子例改为 `fact_refs` 断言，未验签 RED leaf 固定在 Node |
| balanced F2 | sensitive 反例写反（同 op 重放本应成功）、`.crctl` agent 可写 | 反例改为“复制根 + 新 operation_id ⇒ EXHAUSTED”，另加同 op 重放正例；不用 `.crctl` |
| balanced F3/F4 | isolation 行无 `$` 锚、EXPECT 非硬前置 | isolation 改 `'^TestChannelIsolation$'` + EXPECT label、缺 profile `t.Fatalf`；验收证据检查列出全部 v0.4 必达 leaf |
| balanced F5–F7 | 撤销重验/T store 比对无 mutation；竞争用结局计数 | 补 mutation；竞争与终态前消费改用 `55P03` + `lock_timeout` |
| balanced F8/F9 | B2 缺 sqlc 重生成、两态断言；B13 实为迁移+决策 | disposition 补上；B13 移入决策 X6 |
| balanced F10/F11 | `TestChannelTaskTx` 无主；revoked-permit 只被聚合 label 选中；S6 依赖范围外修复 | S1 新增 service 测试文件与顶层名；模板加 `revoked-permit` label；S6 写明 green 前置 |
| economy 1–10 | 复核指针矛盾、Review Focus 表头、清单粒度、落点/键不一致、CLOSEOUT 证据路径、增量 21 无原始证据、“0 命中”无出处、643–647 down 未执行限定 | 全部按建议修正；增量 21 证据补落盘 `todo-a-20261026/`（变异 RED + 还原逐字一致 + GREEN 9/9 + vet） |

## 状态

- 补正后的 v0.4 **未经再复核**，不得称“已批准”。是否再跑一轮复核，等 X1–X6 定下后一并进行更省事。
- 方案仍搁置、未注册。
- 补正后：方案 raw sha256 `5ae7bff4ab4999e5d6101f74a5cf8fd5dbb357c558b9dd8e786335244cdc597d`（430 行，LF）；disposition raw sha256 `8e683345ae567f781f23e60c18f54e60fc383aa90a7b919a7994c7a8769ef3ad`。
