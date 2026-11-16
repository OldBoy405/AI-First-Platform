# design-adjustments — 2026-11-16-multica-execution-evidence-closure

本文件汇总 BUILD Part C（C6）对 `pending-adjustments.md` 的收口结论，作为后续迭代输入。结论（2026-11-16 延期修订后更新）：**本轮发生一处经用户明确裁定的受审承诺变化——TC-MEC-003（真实 CI 必需证据）延期为 not_applicable（接受风险），已按 `_shared/revision-rules.md` 一轮同步受审文档并重审 Gate 1+2，旧证据在新 run 重跑。** 实现本身与 Gate 2 锁定的规格一致（守卫/selection/pin/wiring 字节同 f8a23564a）；其余未决项为测量口径与仓外副本，逐条如下。原「无受审承诺偏离」结论已被本次用户裁定取代，原文保留于下供追溯。

## 0. 本轮受审承诺变化（用户裁定延期，已重审 Gate 1+2）

- 触发：真实 CI run 43752944966 被平台账单/额度阻塞（runner_id=0、六测试 skipped，未启动有效执行）。用户裁定（原话「修订计划延期 TC-MEC-003」）把 TC-MEC-003 的必需证据本轮延期为 not_applicable（接受风险），先收口其余已验证项。
- 性质：改变受审承诺（required manual 的验收处置），**不是**实现选择偏离，须重审 Gate。
- 同步修订（一轮）：proposal.yaml/proposal.md、canonical/specs/code/ci-backend-environment.yaml（REQ-MEC-006 描述 + SC-MEC-006 第三 and）及其 spec.md、design.md（Context/决策5/Risks/方案审查）、test-plan.md（TC-MEC-003 改 not_applicable + reason、执行矩阵/回归风险/补充顺序/第六节证据计划）；agent spec 核实未变。完整差异一次性展示。
- 重审：用户原话「确认重签Gate 1+2」→ Gate 1 confirmed 2026-11-16T10:23:55、Gate 2 confirmed 2026-11-16T10:25:47（dialog）。Gate 2 先因 spec.md Human View 漂移拒绝，删除派生视图后经 CLI 重生确认。
- 旧证据重跑：新 run `0ccb7130-dbe0-4c0c-b7f4-28aeca9a38a6`，CP-MEC-001（race 一次性库 pass=4/0/0）与 CP-MEC-002（离线 fail0/skipped0）均真实重通过；旧 run 2d5d4330 冻结修订前 test-plan，作废。
- **延期≠豁免≠绿灯**：TC-MEC-003 权威 CI 验证仍未完成，额度恢复后须对最终 SHA 另行验证满足 SC-MEC-006 全部 SHALL；不继承前驱 TC-BTO-005 N/A，非用户裁定的自动 N/A 仍禁止。CLI 机械覆盖 4/4 把 not_applicable 计入分子，报告/Gate 3 显式标延期未验证。
- 收口：TC-MEC-004 经用户原话「执行 confirm 并继续后续流程」确认（run 0ccb7130），切片3 登记 done（tc 1/1、new_tests 0）；切片4（TC-MEC-003）沿用前驱惯例不登记 done（前驱含 not_applicable 真实 CI 的 slice 7 同样未登记），收口经 Gate 3。CUSTOM 快照行时效性按用户裁定 A 于 DELIVER 回填。

## 1. 与受审规格的一致性（无设计偏离）

- 三个恢复入口锁后身份守卫（runner.go / runner_code.go / runner_requirement.go）：在 `withRunLock` 回调内重读活动 run 改名 `current`，`current.ID != run.ID` 本次无效果返回，`ErrNoRows` 无效果、其余错误传播，`withRunLock` 原语一行未改 —— 与 SC-MEC-001/002 及 design 决策一致。
- `TestReconcileRunIdentity`：三入口 × unchanged/changed/no-active 九例普通表循环、独占池 MaxConns=4 ＋ 独立控制连接、AcquireCount 增量、B 持锁正向对照 —— 与 TC-MEC-001 测试方案一致；两处夹具修正（requirement `inputs.source` 空串、跨入口同名 reviewer 清名）属测试夹具，不改生产接口或受审承诺。
- 事件元数据（OutputType/FailedBuild）、精确四项 expected、单一 pin 7a0a2ab、rules.json 必需文件与 backend env、CI 接线顺序 —— 与 SC-MEC-003/004/005 一致。
- 生成物只 `--check`，未重生成、未漂移。

## 2. 环境/授权阻塞（非设计偏离）

- BLOCK-MEC-01（race/cgo 前置）：**已解除**。用户原话「授权 cgo/race 环境，以及独立的发布/CI」后建立 mingw-w64 gcc 16.2.0 ＋ CGO_ENABLED=1，切片2 CP-MEC-001 经一次性库 `-race -count=1` GREEN（pass=4 fail=0 skip=0）。详见 pending-adjustments.md 带日期解除指针。
- BLOCK-MEC-02（发布/CI 授权）：授权**已取得**（MEC-12 完成），业务提交 `f8a23564a` 已 push 到 origin/main。但真实 CI run 43752944966 **被账单/额度阻塞**：所有 job `runner_id=0`、零步骤、`log not found`，`backend-tests` 等全部 skipped，六测试与真实 rules.json 从未执行。这是外部基础设施状态（ci.yml:9-10 台账 #113：私有库免费 2000 min/月、实测需 3652 min/月），**不是设计偏离、不是代码失败**。SC-MEC-006 未验证。

## 3. 测量口径未决（非设计偏离）

- NOTE-MEC-01：`packages/` 第四数无获确认口径，按用户指示本轮不测量、不沿用历史 314。CUSTOM 测量行已写明未决。属待用户取口径，不改受审承诺。

## 4. 后续迭代输入（须用户决定，AI 不代签）

- **TC-MEC-003 本轮已延期为 not_applicable（接受风险，见 §0），权威 CI 验证仍未完成。** 待用户解除 Actions 额度后对最终 SHA `f8a23564a`（或其后继交付 SHA）重跑 CI 并核对六测试/真实 rules.json/backend/admin/对账/两个生成 --check，再交用户原话确认以满足 SC-MEC-006 全部 SHALL；届时若改变 not_applicable 处置仍须按 revision-rules 同步并重审对应 Gate。
- TC-MEC-004 台账事实已经用户原话「执行 confirm 并继续后续流程」确认（run 0ccb7130，前三数 629/1722/789、5816 文件、+0/+4/+4 归因经 commit diff 核实、第四数未决、CRLF 1126/0），切片3 已登记。
- 第四数 `packages/` 口径仍待用户取（NOTE-MEC-01），本轮不测量、不沿用 314。
- CUSTOM 变更追溯第203行与 #343/#344 的写作时快照（「未提交、未推送」等）按用户裁定 A 于 DELIVER 回填，计数中性、不改交付 SHA。
- 仓外部署 rules 副本不在本次覆盖范围，报告写明未覆盖。