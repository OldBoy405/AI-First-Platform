# Legacy 执行授权与历史消耗迁移

<!-- source_hash: 8090c8e160362032 -->
<!-- generated_at: 2026-11-15T10:11:54.828513 -->
<!-- canonical: canonical/proposals/2026-10-29-legacy-execution-migration.yaml -->

## Why

AIFI-45 的 TC-EVD-008 要求：历史事实可核实时，显式迁移并保留授权及历史消耗，并计算剩余额度。
D8=A：本期不迁移 legacy 业务历史。2026-11-10 用户范围裁定：该正例移出 AIFI-45 本期分母，记 OUT_OF_SCOPE（不是 PASS），由本变更在启动条件发生时验收。

事实更新（2026-11-15 对照源码核实）：tools 已有公开可写的 `crctl evidence-migrate` 命令（`crctl.mjs` 的 `cmdEvidenceMigrate`，
调用 `lib/legacy-migration.mjs` 的 `evaluateExplicitMigration`，2026-11-08 随 commit `ea8d081` 接入），所以早先“判定函数没有生产入口”的前提已不成立。
该命令要求：已安装且可验证的初始授权；`approval.yml` 中每个历史阶段都有 subject 与 receipt digest；`--consumed`、`--limit` 为合法整数且 consumed 不超过 limit；已有合同登记与本次事实一致。
该命令不做：核验各 receipt 本身的真伪；把 `--consumed` 与历史对账；核验未决任务、当前 head 或迁移者权限——消耗量和上限来自调用参数。
该命令是否已部署、是否被用于真实旧 workspace，均无证据。因此它不能视为“可信存量迁移已验收”，TC-EVD-008 仍为 OUT_OF_SCOPE。

启动条件（可观察事实，满足任一才启动本变更）：
1. D8 被改为“迁移 legacy 业务历史”。
2. 出现必须在新合同下继续执行、且带旧授权或旧消耗的非终态 CR（包括任何人拟对真实旧 workspace 运行 `evidence-migrate`）。
2026-11-15 核对：知识库主 checkout 的 76 个 CR frontmatter 为 68 archived、8 withdrawn，均为终态，`_backlog.yml` 活动列表为空，未发现满足条件 2 的存量。该核对不覆盖 CR 事务工作区，也不覆盖本知识库之外的 workspace。


## What Changes

- 未来在独立需求和架构审查后，制定并验证 legacy 授权与历史消耗的显式迁移方案；本登记不实施迁移。

### New Capabilities

- **legacy-execution-migration**：在可信事实充分且迁移获批准的前提下，保留原授权和已核实消耗并计算剩余额度。

## Success Criteria

- [ ] 未来变更须以可复核事实证明历史授权和消耗得以保留、剩余额度计算正确，并覆盖未知和冲突事实的拒绝。
- [ ] 未来变更须经实际评审及批准后实施；验证与部署证据由该变更各自记录。
