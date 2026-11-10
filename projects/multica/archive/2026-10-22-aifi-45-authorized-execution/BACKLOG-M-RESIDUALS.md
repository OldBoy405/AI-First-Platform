# M 侧残余的移交登记（2026-11-09，决策 D1）

本文件是**来源登记**，不是需求理解产物；不构成已批准范围，也不代表已开 change。四条 ADJ 的共同点是都需要本 change 之外的前置（资源审批、签名合同裁定、跨仓身份收敛），因此从 `2026-10-22-aifi-45-authorized-execution` 移交，待触发条件满足后由负责人开 change 承接（用 `crctl register` 取得真实身份，届时以本项目记录的 `crctl` 契约为准）。

| ADJ | 缺的前置 | 关闭条件（可验证） |
|---|---|---|
| `ADJ-AIFI45-M006` | 一次性隔离 PG 的**技术身份/隔离/执行计划与证据**（资源授权已于 2026-10-30 记录；第一阶段范围排除建库） | 按已确认范围实现，并在获准的隔离库上跑 DB/业务用例；全程不访问原 HOLD 实例 |
| `ADJ-AIFI45-M007` | 五项合同裁定：人类补充来源、后继 profile、前驱 CAS、敏感授权、既有额度继承 | 真实消费/activation/任务/状态入口对“不足”fail-closed 实测通过，且五项均有裁定后放开签发 |
| `ADJ-AIFI45-M010` | 跨仓投递身份设计（T 确定性名称 vs M 跨实例 ACK） | T 确定性名称与 M ACK 按原投递身份闭合；旧文件/旧 writer 切换有证据；覆盖混版、未知/迟到结果、合法重放 |
| `ADJ-AIFI45-M005`（含 M003 的 TC-RUN-006、M008 的真实恢复入口证据） | 服务端签发者与 pinned manifest（上线就绪清单项，责任人按三角色/发起人规则解析）；task→command 单一权威关联；新 spec 与 Gate 2（verdict 签发由 T 改为服务端，信任模型已于 2026-11-10 批准，见 design §2） | 生产链路 `ADMITTED` 可得：命令由服务端冻结、`request_id = reservation.proposed_task_id = consumption.task_id` 由代码强制、verdict 只对服务端可核实事实签发并经 `ControlWorker.ApplyTx` 入链；部署检查两项（agent 身份读不到私钥、可用 DB 登录对四张信任表无写权限）；TC-RUN-001/006 与 M008 恢复入口真实通过；T 侧随之清理死代码（`signControlEnvelope`/`verdictPayloadV2`、种子私钥夹具）。 |

## 不在本登记内

- `ADJ-AIFI45-M004/M009` 已有处置（M003/M008 的剩余证据并入上表 M005 行），见 `pending-adjustments.yaml#dispositions_20261109`。
- 本登记不改变任何 `resolved`，也不改变 M 侧 17 条 TC 的分母归属。
