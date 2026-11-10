# SPEC 审查记录 — 2026-11-06-stdd-default-cr-opt-in

> 本记录是阶段审阅说明，不是原生 TC 执行证据、CR review-record 或 Gate 批准。
> 本文记录 Gate 2 前的审阅；Gate 1 原文为“确认 Gate 1，standard”。此后 Gate 2 已确认方案 A，当前阶段以 STDD 状态为准，BUILD 验收结果另见 `test-report.md`。

## 已实际完成的阶段检查

| 检查 | 实际结果 | 覆盖边界 |
|---|---|---|
| `proposal validate <本ID>` | 退出 0 | 提案字段，不代表所有运行语义 |
| `canon generate <本ID> --type proposal` | 退出 0 | 仅 proposal 的 CLI Human View |
| `canon verify <本ID>` | 退出 0，hash／body 2/2 | 不覆盖两个人工 CP 副本 |
| `stdd validate <本ID>` | 修正格式后退出 0，输出“验证通过” | 结构检查，不是业务 CP 执行 |
| Canonical YAML、归属与断言类型 | 3 份 YAML 可解析，change／documentation 类型正确 | 只读自检，无状态脚本写入 |
| CP action 语法 | 10 个 Python action 均可解析 | 仅语法检查，尚未执行 action |
| Requirement／Scenario／CP／TC 映射 | 9／10／10／10，ID 唯一、映射完整 | 规格定义数，不是通过数 |
| 原生提取辅助函数 | 识别 10 Scenario、10 正式 TC；最大 AND=3 | 原生定义识别，不是执行证据覆盖 |
| 人工副本路径与映射 | 本地链接有效，按 CP 对照 | 人工视图，不伪称 CLI 自动生成 |
| 六个实施目标文件的 LF 哈希 | 均与 design 记录相同 | 本阶段未修改正式入口或全局偏好 |

自检过程中出现的只读检查脚本转义错误已改正并重跑成功，没有据失败结果写入任何账本。初次原生 validate 识别不到 Scenario 并出现 AND 警告；在两个人工副本与 TC 定义的共同格式边界修正后重新验证通过，未修改 STDD 校验器。

## 独立设计审查与修订

1. **用户已有账本保护**：在设计、Canonical CP、人工副本和 TC 同步保留完整限定：执行账本须合法入口及入库、可测试的版本化脚本；禁止会话内现写脚本；精准编辑例外仅为指定用途的 STDD pending-adjustments.yaml，其他 YAML 归属不明按执行账本；保留来源、方向／决定／授权／未决区分、解析／字段／编号／冲突／差异核对、原记录／扩展字段、resolved 如实及权限／唯一入口／CAS／审计／门禁。
2. **定义格式与计数**：采用 `#### Scenario:` 及正式 ID 行，已实际核对原生识别 10／10。没有将人工数量宣称为执行覆盖。
3. **绑定语义**：WFR-002 覆盖知识库 cwd 无绑定但目标 tools 已明确且绑定有效的正例；WFR-005 仅在目标、其绑定或归属无法确认时失败关闭。
4. **文件范围验收**：PG-001 补 README 和 CONTEXT；PG-002 补 graph 注释逐行检查，并限制 YAML 业务值变化范围。
5. **lint 模式**：保留 quality 的默认 report，另外计划运行 enforce 并记录 findings；report 退出 0 不等于无漂移。

## 尚待用户决定的验证边界

非代码 CP 不能由当前 CLI 自动渲染；本次两个 spec.md 是明确标注来源的人工评审副本，需用户在 Gate 2 接受。

原生 TC 执行覆盖仍未闭合：当前 agent verify 的 --change 分支仍需项目级合同、覆盖共享报告，可能影响其他 change 的证据摘要；冻结根也不覆盖本次知识库根和用户全局文件。不能通过直接运行它或复制输入来伪装完成。本次未调用该入口，未新增项目级合同，未修 STDD 工具。

用户须按 design D6 选择仅本 change 的文档契约验收，或保持完整机器覆盖并先确认合法证据方案／工具支持。普通 Gate 2 不隐含该选择；当前没有“全部验收通过”的结论。

## 未执行与禁止推定

- 10 个业务 CP、场景实施验收、tools quality 全套测试及 BUILD 评审均尚未执行；它们不是通过状态。
- 未推进 Gate 2／BUILD，未修改既有 CR、审批、基线或其他在途变更；未提交、推送或部署。
- 未实测最终请求 token；没有运行时路由、已部署或模型实际档位的证明。
