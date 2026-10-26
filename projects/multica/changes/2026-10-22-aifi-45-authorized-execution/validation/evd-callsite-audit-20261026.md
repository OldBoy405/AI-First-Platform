# 台账口径核查：EVD-007/008/009 只有判定函数，没有生产入口

日期 2026-10-26。主会话只读核实，未改 tools 源码。

> **同日后续决定（D7/D8）**：以下“v0.2 不覆盖/不该覆盖”保留为当时审计结论，不再代表最新范围。用户已同意 D7 的就绪控制面由后续通道 change 交付，独立方案已原位补入 `trusted-verdict-channel-implementation-plan-20261026.md` **v0.3 Spec §7 / S8**；D8=A 本期不迁移 legacy，保留旧合同/历史并禁止借新 lineage 清零。新计划不回填任何 TC；EVD-008 既有正分支与“无生产入口”仍保留，不把拒绝侧当完整能力。EVD-009 仍在当前主线单独接线，未因方案修订声称已实现。

## 核实方法

对 `C:/Users/GOBAO/Downloads/AI/tools/skills/shared/crctl` 全目录 grep 四个判定符号的非测试引用，并列出 `crctl.mjs` 全部命令动词：

| 符号 | 非测试调用点 |
|---|---|
| `evaluateMechanicalException`（EVD-004） | `crctl.mjs:56` 导入、`:5826` 调用、动词 `evidence-mechanical` ✅ |
| `evaluateComponentReadiness`（EVD-007） | **无**（仅 `lib/component-readiness.mjs:94` 定义 + 测试） |
| `evaluateExplicitMigration`（EVD-008） | **无**（仅 `lib/legacy-migration.mjs:19` 定义 + 测试） |
| `evaluateReleaseRecovery`（EVD-009） | ~~**无**~~ → **已有：`lib/workspace-transactions.mjs::mergeCr`**（2026-10-26 接线，见下方更新） |

`crctl` 动词表里没有任何 component / migration / release / recover 类动词。

## 这意味着什么

规范给这三条的 CP 都是**单测**（`node --test --test-name-pattern="^TC-EVD-007$"` 等），所以按既有台账口径（CP 命令通过 + 四条断言）它们确实算 PRESENT——台账没写错。

但**能力不可达**：没有任何真实入口调用这三个判定，操作者无法"请求显式迁移"（SC-EVD-008 的 when）、无法"恢复同一发布操作"（SC-EVD-009 的 when）、也无法在"启用新 policy"时被这条规则拦住（SC-EVD-007 的 when）。这与本 change 自己给 F7（`relayExecutionBinding` 无生产调用点）记的**死代码**是同一类问题。

## 通道 v0.2 方案是否覆盖这三条？（已查原文）

**v0.2 当时不覆盖。** 以下仅为修订前 v0.2 快照的检索结果，不是当前 v0.3 的命中数：对 `trusted-verdict-channel-implementation-plan-20261026.md` 当时全文检索：`EVD-00[789]` **0 处**，`component` **0 处**。命中的 `legacy` 指合同 `Selection=Legacy` 模式、`migration` 指 DB 迁移 648、`recover` 指 worker/owner 重启恢复，均与 SC-EVD-007/008/009 无关。

而且**不该由那个方案覆盖**：这三条是 AIFI-45 自己的 EVD 验收项（计入本 change 41/49），通道 change 管的是“可信裁决运输”，不是 evidence-delivery 的启停能力。

重叠只在语义层面，且未映射：

| TC | 规范 when | 通道方案里有无对应 |
|---|---|---|
| EVD-007 | 尝试启用新 policy 或删除旧接力 | **无对应**。P0 验的是 OS 隔离，不是“声明组件 vs 观测版本”的就绪度 |
| EVD-008 | 请求显式迁移 | 仅部分：§5 “推荐仅新 lineage 切入、历史 ledger 不自动导入”有相邻语义，但未提 SC-EVD-008，也没接 `evaluateExplicitMigration` |
| EVD-009 | 恢复同一发布操作 | 语义被子纳（S3/S6 “重发原 bytes、只返回既有 mapping、不重复消费”），但未提 SC-EVD-009，也没接 `evaluateReleaseRecovery` |

## 规范自己点名了接缝（这很重要）

## 追加核实（2026-10-26）：SC-EVD-010 的“拒绝不适用证据”在 tools 侧有真执行点

先前的建议里把 `evidence-check` 当成了唯一入口、并担心它只是查询工具。读码后更正：`evaluateEvidenceDelivery` 确实是 `evidence-check` 专用（`crctl.mjs:1802`，单个调用点），但**同一套 subject 事实有四个真门禁调用点**，不靠这个命令：

| 门禁 | 位置 | 行为 |
|---|---|---|
| approve（含 approve-code） | `approveAndAdvance`：`crctl.mjs:1490` → `verifyReleaseSubjects` `:1502` | 审批时按当前仓重核 `approval.yml#code.release-subjects`；不匹配即拒（只有受控 artifact 正文漂移在“合法本地信任”下降为 warning，属 CR-2026-076 既定取舍） |
| 记录评审 | `cmdReviewRecord`：`:3388` → `subjectMatchesAnnotation` `:3417` | 被评审对象已变就拒绝记录，不靠事后发现 |
| checkpoint | `cmdCheckpoint`：`:3759` → `:3794` | 发布阶段同样按当次对象重核 |
| merge | `mergeCr`（`lib/workspace-transactions.mjs`） | 合并前重新验证快照；本轮又加了重放 receipt 比对 |
| （恢复期） | `assertReviewSubjectUnchanged` `:3244` | 恢复时不允许“已提交评审描述另一个对象”，也不重算覆盖 |
| evidence-check | `cmdEvidenceCheck` `:1759` | 汇总只读报告，`state:'stale'` 仅在报告里 |

因此：
- SC-EVD-010 的“subject / release tree 已变 → 拒绝不适用证据”**有生产执行点**，不属于“函数存在但无入口”那类。`evidence-check` 只是同一事实的汇总视图，不是唯一入口。
- `subjectMatchesAnnotation` 是“当前对象是什么”的唯一实现（`:1755-1758` 注释明写），所以**不该在 Go 侧重写一份 subject 比对**——这条留给 multica 的 RUN-009 缺口（`runner.go:1434` 只查非空）走可信裁决通道或单独设计。
- 未动态验证：以上为读码结论；multica 侧 `runner.go:1434` 的非空检查本轮未改、也未跑 DB 用例。cycle 维度由 `review-loop` 轮次与 `attempt` 承载，未逐项实测。

`evaluateReleaseRecovery` 现在有生产调用点：`lib/workspace-transactions.mjs::mergeCr` 在快照校验之后、prepare/publish 之前复核发布 receipt（`replayed:true`），审批或发布主体变化即 fail-closed。原始日志与源码 sha 见 `evd-009-wiring-20261026/`。

因此上文“这三条都没有生产入口”的计数口径**只对 EVD-007 / EVD-008 继续成立**；EVD-009 变为“仅 merge 路径可达，checkpoint / writeback 仍无入口”。台账计数与 CP 口径均未因此改变（EVD-009 的 CP 本来就是单测），也不据此宣称 SC-EVD-009 整体已覆盖。
- **SC-EVD-009 的 given 明写：`checkpoint/merge/writeback` 在既有发布事务边界失败**。所以把 `evaluateReleaseRecovery` 接进 `merge` / `writeback-apply` 的恢复路径是**规范授权**，不是我发明缝。这是三条里唯一可立即动、不需额外决策的。（**补充**：“规范授权”≠“那里确有必要”：读码确认 `writeback` 只在 `if (!found)` 读审批、`checkpoint` 全路径不读，重放本就复用冻结快照，不存在重新决策面；实际暴露面只有 `merge`，已接线。详见 `evd-009-wiring-plan-20261026.md`。）
- **SC-EVD-008 的 when 是“请求显式迁移”**：需要一个显式请求入口，规范未点名。
- **SC-EVD-007 的 when 是“启用新 policy 或删除旧接力”**：决策函数在 tools，而“启用”是部署动作，跨仓归属未定，需先决。


1. **接线**：需要先定"哪个动词是这三个 when 的真实入口"。我查过现有动词，没有天然宿主；接进 `evidence-check` 是我能想到的最近似者，但规范并没有指定，属于我替规范做决定——上一轮 RUN-009 就是这么被 BLOCK 的，不建议再来一次。
2. **如实标注**：在台账里给这三条加"判定函数已交付、无生产入口"标记，不降低 PRESENT 计数（CP 口径不变），但禁止据此宣称能力可用。这与 F7 的记录方式一致。
3. 若希望真正可用，最小增量是新增显式动词（如 `component-check` / `evidence-migrate` / `release-recover`），但那是新增命令面，应先补规范再由 SPEC 确认。

## 另一处已核实事实

`AI First Platform/dir-graph.yaml` 与 `tools/dir-graph.yaml` **都没有 `workspace.components` 键**，因此缺少可用于 strict 启用的合法完整声明。精确纠正：纯函数在 declared/observed **同时为空**时会返回 ready；若实际观测含 tools 而声明为空，则会报 undeclared，并非“declared 为空就恒 ready”。目前没有生产入口，不存在已证明的现网 ready 结论；v0.3 因此要求受保护非空 profile、完整观测及严格入口校验，不能靠缺声明默认放行。

## 顺带纠正我自己的一个误判

我先按 `SC-RUN-00[0-9]` 搜 tools 侧，得出"SC-RUN-008/010 不存在"的错误结论。实际 SC-RUN-001～010 全在 **multica** 记录根的 `canonical/specs/{agent,code}/authorized-runner.yaml`，只是我的正则与目录都错了。已在 multica 侧确认 SC-RUN-008 原文：given 旧 run 存活或新 policy 任一入口/恢复/安装版本未配套；when 切换/迁移/回退；then 保留旧合同与历史、拒绝未就绪切换、回退仅停新准入、不清历史不双派。
