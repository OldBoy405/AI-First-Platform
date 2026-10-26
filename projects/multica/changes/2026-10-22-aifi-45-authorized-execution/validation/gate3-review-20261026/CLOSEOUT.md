# AIFI-45 Gate3 评审收口（2026-10-26）

## 结论

| 轴 | 结论 | session |
|---|---|---|
| 规格 | **BLOCK** | `01a177c6-c2ff-77b9-a3c5-0f64ff1af43c` |
| 安全 | **BLOCK** | `01a177c6-c324-77b9-a3c5-0f6812b8fc3c` |
| 测试/配置 | **INCOMPLETE** | `01a177c6-c315-77b9-a3c5-0f66461af0d8` |
| 文档/记录 | **INCOMPLETE**（已在同批修正） | `01a177c6-c334-77b9-a3c5-0f6b540e1c5b` |

- **Gate 保持 NO-GO。** 台账仍 **41/49**，无 TC 新增/降级，未 commit/push，未部署。
- 四路均为非作者只读评审；requested 见各文件，actual 无后端回执记 unknown。
- 评审基线 `source-manifest.json`（`9b80fec5…`，162 文件）。评审期间 `tools/lib/workspace-transactions.mjs` 又改两次，正是安全轴两条 major 所指处。

## 本轮因评审而实际修正的

1. **EVD-009 merge 守卫三轮收敛**（tools，已动态验证）
   - 初版：无条件以 receipt 比对。
   - 第二轮：改为"已发布才钉住"——修掉零发布恢复死锁（我自证 + 安全轴独立发现同一处）。
   - 第三轮：把"已发布"从本地 `rec.pushed` 改为**远端祖先核对**——修掉 push 成功但 journal 未落盘窗口（安全轴发现，我的修补引入的）。
   - 证据：`projects/tools/changes/2026-10-22-aifi-45-authorized-execution/validation/evd-009-wiring-20261026/meta-current.json`（当前版本；同目录 `meta.json` 对应旧源码 `ae5ad1c8…`，已作废）；4 例全过，两条变异各只打红对应用例，还原 sha 逐字一致；merge 23/23、邻接 69/69。
2. **记录与代码对齐**：`evd-009-wiring-plan` 写明"仅在远端已发布时钉住"；`tc-coverage` 增量 20 同步；作废增量 15 的"测试内打开准入"与 run-r2 正文的"端点被显式禁用/503"；补正"40 条"引文出处；EVD-009 覆盖面（"规范授权"≠"有必要"）在 `evd-callsite-audit` 说清；RUN-009 缺口不再写死数字。
3. **CUSTOM #201**：登记 mergeCr 的 EVD-009 接线（依 #194 先例以"无 multica 产品文件（tools 侧…）"形式）。

## 待办 A：不需要新决策、可在 tools/multica 内直接做

| 项 | 来源 | 说明 |
|---|---|---|
| `run.mjs` 只判 `leaf_pass>0`，`-skip` 合法 → 允许"决定性用例被 skip 仍算 verified" | 测试轴 major（实证 `f4-headrecord-20261026-green.meta.json` `skip:1`） | 断言 `counts.skip===0` 或白名单；拒绝 `-skip` 覆盖关键 TC |
| 643–647 的 **down 从未被执行** | 测试轴 major | 用 `-migration=…down.sql` 跑一次 up→down→up 往返并留证 |
| 新用例 `t.Skip("no database connection")` | 测试轴 major（`approval_gate_binding_test.go:157` 等） | 改 `t.Fatal("dedicated database required")`；`test-go.sh` 断言 skip==0 |
| `crsync_test.go` 空 `DATABASE_URL` 回退 localhost | 测试轴 major | 空即 `t.Fatal`，禁默认回退 |
| TC-EVD-009 的 CP 用合成 receipt，不经过 `releaseReceiptOf` | 测试轴 major | 补一条端到端断言（从真实 approval 取 receipt） |
| `tools/lib/execution-sensitive-action.mjs` 的 `// AIFIRST:` 无登记 | 文档轴 major | 先定登记载体（tools 内部能力 vs 跨仓定制），再登记 |
| `run.mjs` 双 `-timeout` 矛盾 flag | 测试轴 minor | 仅用户未给时注入默认 |

## 待办 B：需要规范/设计决策或依赖已搁置通道（不得自行拍板）

> **更正（2026-10-26 后续）**：本节和下面“建议的下一条路径”的三堆划分已被 `../backlog-b-disposition-20261026.md` 取代。其 §0 更正了三处说法：v0.3 已覆盖 strict 降级（只是关键词没搜到）；RUN-004/005 生产接线本来就在 M003 S1；不再建议为准入链本体另开独立 change。并入 M003 的项已写进方案 v0.4。本节原文保留作历史。

- **F1 代签能力（安全轴 blocker）**：agent 拿到 endpoint URL 即可让 daemon 代签自报值。隔离未接通前，任何"控制证明"写入口都不应视为可信 → 直接影响 RUN-007 与 M002 的判定。
- **claim TOCTOU / 跨签发复用 challenge / strict 可降级 / 终态 fence 可自行退出**（安全轴 4×major）：都属准入链本体，与 M001/M002 同域。
- **repair-admit 未验签、敏感动作绕过、trust-root 可复制**（安全轴 major / 规格轴 blocker）：属 RPR 与 AUTH-006/008，需要可信当前 head 与唯一验签追加协议。
- **SC-AUTH-004 实际 diff 检查缺失**、**SC-EVD-005/006 授权摘要与合同归属**、**SC-EVD-001/002/004 未接 gate/交付入口**、**SC-RUN-004/005 永久根无生产调用点**、**NTF 无产出方**、**EVD-007/008 无入口**、**EVD-009 只部分满足**。
- 这些与 `ADJ-AIFI45-M001/M002/M003` 高度重叠：M003 的通道仍搁置，M001/M002 仍 major/unresolved。

## 建议的下一条路径

先做**待办 A**（都是"让证据变可信"的机械项，不改语义），再决定是否把待办 B 中与准入链本体相关的整批转入一个独立 change（与 M003 的通道同一决策口径），而不是继续在 AIFI-45 尾部逐条打补丁。
