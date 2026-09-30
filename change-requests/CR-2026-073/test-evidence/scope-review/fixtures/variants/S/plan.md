---
id: __CR__-plan
type: PLAN
cr-ref: __CR__
sdd-ref: "change-requests/__CR__/sdd.md"
target-version: 0.46
status: draft
created: "__AT__"
---

# __CR__ 开发计划（fixture 快照 S：子集冒充全量）

## 1. 交付里程碑

| 阶段 | 交付 | 估算 |
|---|---|---|
| 设计 | 已批准 SDD/AC 对齐、接口与验证范围确认 | 0.5 人天 |
| 实现 | `tools/scripts/duration.mjs` 两个纯函数 | 0.5 人天 |
| 验证 | 定向用例 + 全量声称核对 | 0.5 人天 |

## 2. 交付覆盖表

| FR/关键AC | SDD交付项 | 主责/关联TASK | 验收证据 | 回滚 |
|---|---|---|---|---|
| FR-1 / AC-1 | §2、§3 `parseDuration` | __CR__-TASK-01 | cmd-01 | 撤 TASK-01 |
| FR-2 / AC-2 | §2、§3 `formatDuration` | __CR__-TASK-01 | cmd-02 | 撤 TASK-01 |

## 3. 证据命令表

| 证据ID | repo | cwd | executable | args | timeout |
|---|---|---|---|---|---|
| cmd-01 | tools | . | node | `["--test","--test-name-pattern","duration parse targeted case","scripts/duration.test.mjs"]` | 120 |
| cmd-02 | tools | . | node | `["--test","--test-name-pattern","duration format targeted case","scripts/duration.test.mjs"]` | 120 |

## 4. 风险与回滚策略

| 风险 | 缓解与回滚 |
|---|---|
| 解析边界（不进位的单位、超长输入） | 定向用例覆盖非法输入 → `null`；失败单独撤 TASK-01 |

## 5. 验收与发布策略

本 CR 的验收要求**全量测试通过**：AC-1 / AC-2 均以「全量通过」为通过条件，证据为 `cmd-01`、`cmd-02` 两条关键命令。无 feature flag、无 schema/数据迁移。

## 6. AC/业务闭环覆盖矩阵

| AC/业务闭环 | SDD 落点 | TASK owner | 验收证据 |
|---|---|---|---|
| AC-1 `parseDuration` 纯函数 | §2 / §3 | __CR__-TASK-01 | cmd-01 |
| AC-2 `formatDuration` 纯函数 | §2 / §3 | __CR__-TASK-01 | cmd-02 |
