# 开发计划 · CR-2026-029

- **版本**：v0.1.0
- **cr-ref**：CR-2026-029
- **状态**：tech-design-reviewed
- **总计**：8h = 1.0 人天

## 1. 目标与范围

按 SDD §1 修改 tools 仓两处 active surface（merge-feature-branch skill + feature-writeback pipeline prompt），并在 knowledge-base 仓迁移 CR-2026-028 TASK-10。不新增 crctl 子命令、不改门禁与 task done 前置态。

## 2. 里程碑与任务

### M1 — merge pipeline 联调走查（4h）

| 任务 | 内容 | 估算 | 依赖 |
|---|---|---|---|
| TASK-01 | merge-feature-branch/SKILL.md 新增 Step 6 发布联调走查 + merge-verification.md 契约 + 发布类任务约定段 | 2h | — |
| TASK-02 | feature-writeback.pipeline.json merge-feature-branch 节点 prompt 同步（含联调走查描述） | 1h | TASK-01 |
| TASK-03 | 文本静态断言用例：SKILL/pipeline 含联调步骤与约定、无发布类 TASK 拆分指引；既有 158+9 回归 | 1h | TASK-02 |

### M2 — 迁移 CR-2026-028 TASK-10（3h）

| 任务 | 内容 | 估算 | 依赖 |
|---|---|---|---|
| TASK-04 | CR-2026-028 tasks/_index.yml 移除 TASK-10 块（CRLF 容错定点编辑）+ 删除 TASK-10.md + id 集合校验 | 2h | — |
| TASK-05 | CR-2026-028 sdd.md/test-report.md 变更记录与覆盖矩阵同步（注明移交 CR-2026-029） | 1h | TASK-04 |

### M3 — 验证与发布（1h）

| 任务 | 内容 | 估算 | 依赖 |
|---|---|---|---|
| TASK-06 | 全量验证：crctl.test.mjs + writeback.test.mjs + 三件套 + pipeline JSON + 七禁止模式定向检索；write-test-report；merge 双仓 | 1h | TASK-03, TASK-05 |

## 3. 风险与回滚

| 风险 | 缓解 |
|---|---|
| 迁移定点编辑破坏 _index.yml（T04 教训） | CRLF 归一 + 块锚定 + 删除后校验 id 集合不变 + 硬失败不静默 |
| merge-verification 与 _backlog merge-commits 漂移 | 走查时以 merge-metadata 输出核对；SKILL 注明 |
| pipeline prompt 与 skill 不一致 | 静态断言用例 + lint-prompts enforce |

## 4. 发布顺序

tools 仓 `requirement/CR-2026-029` merge → custom/main（新 skill/pipeline 语义生效）→ knowledge-base merge（迁移带至 trunk）。multica 无代码改动。

## 5. 变更记录

| 日期 | 版本 | 说明 |
|---|---|---|
| 2026-08-10 | v0.1.0 | 初稿 |
