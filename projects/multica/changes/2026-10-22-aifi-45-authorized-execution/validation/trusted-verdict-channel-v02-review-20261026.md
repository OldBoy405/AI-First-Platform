# 通道方案 v0.2：STDD 三路复核与处置

## 对象、来源和结论边界

- 对象：`trusted-verdict-channel-implementation-plan-20261026.md`。v0.1 的 BLOCK 仍保留在 `trusted-verdict-channel-review-20261026-strong.md`，没有用后续结论覆盖历史。
- design/strong 作者会话 `01a176ef-402a-77b9-a3c5-0f47830ba4c7`；requested `OpenAIPersonal/gpt-6.1-sol:high`。
- code/strong 非作者会话 `01a17703-a5bb-77b9-a3c5-0f4ff7cbead9`；requested `OpenAIPersonal/gpt-6.1-sol:high`。
- test_config/balanced 非作者会话 `01a17703-a597-77b9-a3c5-0f4afe71847c`；requested `Gobao/deepseek-flash:max`。
- docs_skills/economy 非作者会话 `01a17703-a5ac-77b9-a3c5-0f4d67f836e6`；requested `GB-JP/deepseek-flash:high`。
- 三档均来自两仓 `stdd config models --format json` 的有效 configured/schema_version=1 配置；无后端 actual-model 回执，actual 均记 unknown。没有用推测主会话档位跳过必要独立审查。
- reviewers 全部只读，未动态执行 Go/Node/DB/Podman。以下为主会话归纳，不冒称逐字原始报告；原始回复可在对应子会话记录检查。

## strong：APPROVABLE-AS-PLAN

复核了作者 v0.2 初稿（提取时 SHA256 `7d071f170c8d9e6bd04dc11ebb2dfbf534ca4655c27af082b9d1515443beb407`）。八条原 finding 均为 **closed（仅计划级）**：

| 原 finding | v0.2 解决方式 |
|---|---|
| 隔离未知却直接实施 C | P0 前置，首期单一已验证 Linux 独立身份；失败停止，B 需另审，无 silent fallback。 |
| 首次任务/generation 循环 | control/task exact-key union；不可执行 reservation；643–645 按实际 generation 在代码启动前验证，不伪造任务。 |
| 两 change 互相等待验收 | Foundation 归 Channel S1；Channel reader 组件可独立验收；AIFI-45 的业务集成是下游，无第三 change。 |
| 重投 bytes 漂移 | 首次 protected commit 冻结完整签名结果，重投原 bytes，不重算累计值/replayed。 |
| restart/rollback/owner 回退 | M 单调 fence、journal/checkpoint/cursor/open-command 对账；落后/分叉/缺失冻结，普通重启不重置 epoch/额度。 |
| revoke/stop/slot 没有线性化 | 同 Tx effect commit、revoke 不等 slot、stop 按 T 序列、unknown timeout 冻结、pending/deny 明确 no_effect。 |
| key-purpose 不完整 | 默认独立 command key，双方验证 purpose/domain/scope；attestation 不签 human grant/resume。 |
| 可信 selection/legacy/replay 含糊 | 持久可信选择、缺失/读失败不降级；settled replay 仅原 mapping，未 settled 仅原固定 candidate；strict projection fence。 |

strong 明确：此结论只允许将计划作为后续实施依据；不是已验证部署、实现、测试或 Gate3。F4 已修和 RUN009 撤回状态已核对。

## balanced：SUFFICIENT-AS-PLAN

- 第一轮对 v0.2 的 R1/R2/R3 为 NEEDS-REVISION，主会话采纳：明确函数名而非文件名筛选、捕获预期 RED 非零退出码、up/down/reapply 分别在独占新库验证。
- 后续复核给出 SUFFICIENT-AS-PLAN：rungo/runnode 机器检查真实计数、零 skip、非零 PASS leaf、原库不变与清理；RED 含指定业务断言标记；每命令 phase/label/nonce 前缀；包与迁移在批准边界内；没有放宽 runner。
- 最后留一条非阻塞覆盖声明缺口：S1/S5 缺具名 Go 测试，整包通过可能掩盖缺测。**主会话已补** `{,_test}.go` 文件和四条精确命令：`TestChannelFoundationSelection`、`TestChannelFoundationReservation`、`TestChannelPolicyFacts`、`TestChannelPolicyResume`。这四个名称/命令由主会话自检，不谎称 reviewer 又做了一次动态复跑。
- 普通回归正则排除生命周期专例；AfterDown 只断言新表/对象移除，AfterReapply 断言恢复，不把缺表变成业务失败。禁止对保留库或真实审计执行 down。

## economy：PASS（文档一致性）

- 已核未注册状态、暂存归属、新 change evidence 根、当前 F4/RUN009/41/49 事实、S1 文件修改/生成物、S4 worker 测试、命名约束、P0 单独环境和 DAG 下游关系。
- 最后一条建议是给 strong 的 APPROVABLE-AS-PLAN 自述补记录指针。**已由本文件落盘闭合**；方案头部已链接本记录。
- M003 原“strong 起草中”已更新为方案路径、未注册、建议无环归属与前置环境授权，不把 proposed 范围误写为已实现。

## 主会话额外静态自检

- 对方案内 bash block 执行 `bash -n`：exit 0；三个内嵌 Node 片段语法通过。
- 用纯内存样例检查七种模板断言：合法 GREEN、拒 SKIP、预期 RED、合法 Go meta、拒全叶无 PASS、拒未清理、识别业务 RED；均通过。
- 这些仅验证文档命令模板，不是 Channel 动态 TC；新文件/迁移/接口仍未实现，P0 未执行。

## 继续实施条件

新 change 须先由用户审阅该方案，并按原生 STDD 登记/SPEC/Gate 流程推进。Linux 服务身份/launcher、keys/profile 及真实隔离探针的环境操作需单独批准。无 production admission、Gate3、commit/push 或部署授权；AIFI-45 台账仍 41/49，全量 Gate 仍 NO-GO。
