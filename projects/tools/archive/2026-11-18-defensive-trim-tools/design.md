# Tools 防御性编程精简 — 技术设计

## Context

本 change 落实《Multica与Tools防御性编程精简方案》§3 OutputGuard、§4 交付就绪和 §5 回写与恢复；范围以 Gate 1 的 canonical proposal 为准。核对基准：Tools `main` `6dacbaf64db69d57fe70c935c0dd640ef00e086d`。下文 `crctl/` 指 `skills/shared/crctl/scripts/`，`writeback/` 指 `skills/writeback/scripts/`，平台 SDD 路径相对知识仓。本次针对误选、误配置、并发覆盖与中断重跑，操作者故意改库、改账本或重签凭证不在威胁模型内。

## Decisions

### C1：交付配置读错不是未配置

**现状**：`readDeclaredComponents` 把读失败和非列表声明当空列表；默认 YAML 解析器已经会抛错。交付采集器先选合同，却无条件读组件配置。`loadGates` 读的是安装根，和交付工作区不是同一读取边界。

**方案**：`collectEvidenceDeliveryFacts` 复用权威合同选择，只为已选合同且未被合同非法、登记非法、降级或不一致诊断拒绝的 CR 读取交付工作区的 `dir-graph.yaml`。读失败（含 `ENOENT`）或已声明的 `workspace.components` 非列表（含显式 `null`）时抛局部 `ComponentConfigError`，由 CLI 的现有 `fail` 信封返回 `EVIDENCE_COMPONENT_CONFIG_INVALID`、文件路径及原因；解析器原有异常原样上抛。缺省和 `[]` 视为未启用。

**为什么**：成功读取才有依据判断未声明，合同诊断优先；采集器不调用 `process.exit`，使回写门禁的事务清理能先于 CLI 退出。

### C2：组件判定器产出 findings，交付只合并

**现状**：判定器总是产出 `ready === (findings.length === 0)`，交付按 `ready` 补兜底的分支对生产输入不可达。

**方案**：非空声明由 `observeComponents → evaluateComponentReadiness` 判断一次，采集端只传可选的 `components.findings`；空声明时可以省略 `components`。交付按原位置追加 `facts.components?.findings ?? []`；需要展示 `ready` 的消费者由自己的同组 findings 推导。

**为什么**：findings 足以表达就绪及阻断原因；只传布尔值会丢失诊断。

### C3：生成时同读，应用时独立复读

**现状**：PRD/SDD、traceability、任务索引和规格索引分开读取正文与摘要；任务索引还把空内容当成缺失。应用预检的 `readHashRaw` 吞掉了所有读错误。

**方案**：`readWritebackBase(path)` 单次读 Buffer。仅 `ENOENT` 返回 `{ text: null, beforeSha256: null }`，其余读错上抛；存在时把 Buffer 解码为 UTF-8，先对解码文本计算摘要，再由同一文本将 CRLF 归一为 LF 供生成。各生成器用这份底稿做内容生成、幂等判断和 manifest，索引由调用方读后把正文传给 `buildIndex`，删掉被替代的生成侧 `readHashRaw`。缺失或零字节任务索引可从 `tasks:` 起建；规格索引仅缺失才用首写模板，已有的仍检查 `features:`。应用预检在共用 `readHashRaw` 边界只对 `ENOENT` 返回 `null`，由现有事务应用按 before/after 冲突判定独立读盘。

**为什么**：正文和 CAS 锚点应来自同一时刻；应用端仍要看到生成后的变化。现行 `beforeSha256` 对 UTF-8 解码后、不归一换行的文本求摘要，合法 UTF-8 时等于原始字节的 SHA-256。改为直接哈希原始字节会改变非法 UTF-8 的口径，并牵连 `durable-tx` 的共享读取，超出本次范围。

### C4：新事务校验当前生成器，续办只认冻结候选

**现状**：新事务和 journal 续办都经 `readPreparedCandidate → validateWritebackManifest` 比较当前脚本 SHA，仅升级脚本就会使旧 journal 无法继续。

**方案**：两函数传递调用方指定的 `checkGenerator` 布尔；新事务传 `true`，比对当前固定脚本 SHA；续办传 `false`，跳过生成器的 Tools Root 解析和脚本读取，不运行生成器。续办凭业务输入、冻结 manifest 与 journal 摘要绑定、路径及 allowlist、blob 与 `afterSha256`、锁内 payload 复核和目标冲突核对；候选缺失或校验失败即停止。manifest 的生成器 ID 和 SHA 仍须符合声明及 stage 校验，SHA 作为来源记录参与摘要。traceability 已发布而 outbox 待补发时，既有快路径仅在目标版本守卫通过后补发。

**为什么**：当前安装版本不是旧事务的输入；manifest 摘要现以 LF 归一文本计算，改为直接哈希原始字节会使在途 journal 的组合摘要失配。

### C5：删掉 OutputGuard 恒假的换行条件

**现状**：Pre/Post 都取命令首行，原因捕获也不跨行，`singleLine` 所守卫的换行条件恒假。

**方案**：删除该条件和分发 policy 的 `escapeHatch.singleLine`。

**为什么**：两端仍按首行判断；Pre 可能因多行命令普通透传，应以 `ruleId` 区分，而非仅凭 `passthrough`。

## Architecture

```text
evidence-check / evidenceDelivery gate / evidence-baseline
  → collectEvidenceDeliveryFacts → 权威合同选择
  → 适用时读交付配置 → 非空声明：观测 → 组件 findings → 合并到交付结论
    配置 I/O 或组件非列表 → CLI fail

固定生成器 → 单读 UTF-8 底稿 → LF 正文与 beforeSha256 → 候选 manifest/blob
writeback-apply
  ├─ 新事务：固定生成器 → 当前脚本 SHA、独立 before 预检
  ├─ 续办：业务输入 → 冻结候选与 journal 摘要核对
  └─ 已发布且 trace 待补发：只消费 outbox intent
  → 需应用时按事务锁与 before/after 比对读盘、发布

OutputGuard Pre 命令 / Post 同次调用命令 → 首行判定 → 逃生或普通封顶
```

### 逐文件范围

| 文件 | 允许的改动 | 对照 |
|---|---|---|
| `crctl/crctl.mjs` | 按既有合同选择分流交付采集、传 findings 并输出配置诊断，`loadGates` 安装根读取在范围外。 | SC-EVD-101/102/103 |
| `crctl/lib/component-readiness.mjs` | 区分读取失败和非法组件声明，默认 YAML 解析器及其他 `dir-graph.yaml` 读者在范围外。 | SC-EVD-101 |
| `crctl/lib/evidence-delivery.mjs` | 交付只合并可选组件 findings。 | SC-EVD-103 |
| `writeback/lib.mjs` | 增加 `readWritebackBase` 并删除生成侧旧摘要读者。 | SC-WSC-001/002/003 |
| `writeback/writeback-prd-sdd.mjs` | PRD、SDD 与规格索引使用同读底稿。 | SC-WSC-001/002/003 |
| `writeback/writeback-tasks.mjs` | 任务索引使用同读底稿及正确的空内容摘要。 | SC-WSC-001/002/003 |
| `writeback/writeback-traceability.mjs` | traceability 目标使用同读底稿。 | SC-WSC-001/003 |
| `crctl/lib/workspace-transactions.mjs` | 收紧预检和 CR 归档写集合共用的 `readHashRaw`，并按新事务或续办选择是否比较当前 SHA；`durable-tx.mjs`、事务格式与锁边界在范围外。 | SC-WSC-003/004/005/006/007 |
| `output-guard/core.mjs` | 删除恒假条件，首行标记及原因校验、非 shell 和缺命令分支、审批边界均在范围外。 | SC-OGE-001/002 |
| `output-guard/policy.json` | 仅删 `escapeHatch.singleLine`。 | SC-OGE-001/002 |
| `crctl/test/evidence-delivery-gate.test.mjs` | 以真实 CLI 测配置、合同优先级和组件 findings。 | SC-EVD-101/102/103 |
| `crctl/test/evidence-components-false.test.mjs` | 迁移可达保证后删除。 | SC-EVD-103 |
| `crctl/test/delivery-contract.test.mjs` | 仅迁出原 TC-EVD-007 的交付用例及其专用夹具。 | SC-EVD-103 |
| `crctl/test/writeback-tx.test.mjs` | 用现有事务入口与故障点测预检、冲突和冻结续办。 | SC-WSC-003/004/005/006/007 |
| `writeback/test/writeback.test.mjs` | 用固定生成器子进程测交错同读、缺失、空文件和读错。 | SC-WSC-001/002/003 |
| `crctl/test/gate-registry.json` | 同步受影响文件与用例统计。 | SC-EVD-103 |
| `output-guard/test/core.test.mjs` | 成对验证 Pre/Post 首行与第二行标记。 | SC-OGE-001/002 |
| `canonical/specs/code/evidence-delivery-contract.yaml` | 补交付配置及 findings 的增量契约。 | SC-EVD-101/102/103 |
| `canonical/specs/code/writeback-source-consistency.yaml` | 写明候选同源、目标冲突与冻结续办的契约。 | SC-WSC-001/002/003/004/005/006/007 |
| `canonical/specs/code/output-guard-escape-hatch.yaml` | 写明 Pre/Post 首行契约。 | SC-OGE-001/002 |

### 验证与完成条件

通过现有生产入口验证 12 个 Scenario（见 `test-plan.md`），核对下列验收项后停止。

## 与方案/Proposal 不符之处

无范围偏离。方案与 proposal 对「原始字节」的简写以 C3 的现行 UTF-8 摘要口径为准；空索引修复指任务索引，零字节规格索引仍报 `STRUCTURE_MISMATCH`。

## Phase 3 验收清单

- 用生产及测试 diff 对照逐文件范围表，核对改动落点。
- 对照 `specs/ai-first-platform/SDD.md:476` 的 D-04 原句和新事务校验，核实其对新事务仍成立；核对项目规格 REQ-WSC-003 明确 journal 续办不比较当前生成器 SHA。
- 审查组件采集与消费 diff：交付只合并 findings、无第二次 `ready` 判定；其他消费者若展示 `ready`，从同组 findings 推导。
- 搜索 `output-guard/policy.json` 和 `output-guard/core.mjs`，确认无 `singleLine`，并顺着 metrics 调用核对 `parseEscapeHatch` 仍有导出。
- 对照迁移用例确认可达保证已移至真实入口，再删 `evidence-components-false.test.mjs`；用 suite-gate 报告核对 `gate-registry.json` 的 `manifest.files`、`manifest.cases` 与计数，按 `.github/workflows/crctl-ci.yml` 在 Windows/Linux 同口径跑 crctl、writeback、OutputGuard 与 metrics 回归。

## 未决事项

无。
