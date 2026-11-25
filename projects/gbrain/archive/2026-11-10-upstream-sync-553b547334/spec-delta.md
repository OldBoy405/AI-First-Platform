# 主规范待更新项（spec delta）

> 目标文件：`specs/upstream-sync-merge/spec.md`（上一轮 STDD CLI 生成的 Human View）
> **本轮不直接修改该文件**：它是 CLI 产物，头部标注 `Auto-generated Human View`，
> 手工改会与 canonical 源失去对应。此处登记差异，供下轮开 change 时由 CLI 重新生成。

## 已过时的具体值

| 位置 | 现文 | 本轮事实 | 建议改法 |
|------|------|----------|----------|
| 页首 Change | `2026-10-26-upstream-sync-2568d32ac8` | 已有第二轮 `2026-11-10-upstream-sync-553b547334` | 改为「主规范，历次实例见 archive/」或由 CLI 重新生成 |
| SC-001 GIVEN | `sync/upstream-2026-10-26-2568d32ac8` | 分支名随窗口变化 | 泛化为「在当轮 sync 分支上完成 `merge upstream/master`」 |
| SC-004 GIVEN / THEN | `239 顺延到 275` / `latest v274 (275)` | 本轮 `275 → 298` / `latest v297 (298)` | 改为规则：**永远取上游最新号 + 1**；THEN 用占位 `latest vN (N+1)` |
| SC-006 THEN | `registry.generated.ts 与 latest.generated.ts 含 v275` | `v298` | 泛化为「含当轮迁移导出名，且为生成器输出」 |
| SC-007 GIVEN | `冲突中涉及 7 个生成物文件` | 本轮 12 个 | 泛化为「当轮冲突中的全部生成物」 |
| SC-007 THEN | `check:regen-all SHALL 绿` | 本轮 `all 16 generated artifacts fresh`（上轮 13） | 去掉固定数量 |
| SC-008 AND | `fork 上调的 9 行 SHALL 保留 GBrain Custom 标注` | 本轮 11 行 `GBrain Custom`、上调 9 个文件 | 泛化为「所有 `GBrain Custom` 行」 |
| SC-009 GIVEN/WHEN | `在 pre-sync/2026-10-26 worktree 上实测同一检查` | 回滚锚点随轮次变化 | 泛化为「在当轮 `pre-sync/<date>` worktree」 |

## 本轮应新增的场景（建议）

### SC-013：按路径登记的基线 TSV 随迁移改名同步

- **GIVEN** `inbox_workflow_frontmatter` 迁移号由 `v275` 顺延为 `v298`
- **WHEN** 执行 `bun run verify`
- **THEN** `check:page-body-readers` SHALL 绿
- **AND** `scripts/page-body-readers-baseline.tsv` 中 SHALL 不存在旧 `v275` 的 reviewed row，
  且新 `v298-*` 文件 SHALL 有登记行

> 本轮此项首跑为红（stale + new whole-body reader），是真实合并事故；修复见 `design-adjustments.md` D2。

### SC-014：上游新增 ratchet 的基线重贴

- **GIVEN** 上游本窗口新增 `check:core-world-reads` 并把 `process_env` 基线钉在 13
- **WHEN** fork 的 `DEEPSEEK_BASE_URL` 使实际计数为 15
- **THEN** SHALL 按守卫的 raise-with-justification 出口改基线并写明理由，不得删 fork 增量

### SC-015：llms-full 体积预算

- **GIVEN** 上游 `llms-full.txt` 距 `FULL_SIZE_BUDGET` 不足 fork `AGENTS.md` 的增量体积
- **WHEN** 执行 `bun run build:llms`
- **THEN** SHALL 通过 `scripts/llms-config.ts` 的 `includeInFull: false` 改 link-only，
  `llms.txt` 索引 SHALL 不变，且 SHALL NOT 删除 `AGENTS.md` 的 `CUSTOM (Qoder)` 围栏

### SC-016：fork-delta 双向审计

- **GIVEN** 合并完成
- **WHEN** 比对合并前后相对上游的 delta 文件集合
- **THEN** 任何 PRE-only 文件 SHALL 有明确解释（上游吸收 / 有替代产物 / 改名），
  **AND** 上游自行删除、fork HEAD 上零修改的文件 SHALL 按「上游为基底」删除，不计为静默丢失

## 保持有效的部分

SC-002 / SC-003 / SC-005 / SC-010 / SC-011 / SC-012 的规则性表述仍然成立，
只需把其中的具体路径与轮次占位化，不改变验收语义。
