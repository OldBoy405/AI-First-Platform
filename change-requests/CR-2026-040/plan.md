---
id: CR-2026-040-plan
type: PLAN
cr-ref: CR-2026-040
sdd-ref: "change-requests/CR-2026-040/sdd.md"
target-version: tbd
status: draft
created: 2026-08-15T12:00:00+08:00
updated: 2026-08-15T12:00:00+08:00
---

# 1. 交付里程碑

| 里程碑 | 内容 | 估算 | 出口 |
|---|---|---|---|
| M1 事务底座 | `durable-tx` 增加 `test` op/payload，复用既有 journal/lock/write-set | 2h | 事务测试可加载，无业务逻辑 |
| M2 测试深接口 | `workspace-transactions` 新增 `testCr` 及其纯函数 | 8h | plan 校验、执行、marker、写集编排可单测 |
| M3 CLI 迁移 | `crctl.mjs` `test` 子命令改为 `--plan`，删除 `--cmd`/shell 执行路径 | 4h | `crctl test --plan` 可黑盒调用 |
| M4 功能回归 | `crctl.test.mjs` 结构化/安全/幂等测试 | 6h | 核心功能矩阵绿 |
| M5 故障恢复 | `fault-harness.test.mjs` 记录阶段故障矩阵 | 4h | 故障点红测与恢复闭环 |
| M6 调用方收敛 | Skill/Pipeline/crctl SKILL 文案与静态契约 | 4h | 文本 contract/lint/pipeline JSON 全绿 |

总计估算 28h。

# 2. 任务依赖图

```text
TASK-01 durable-tx test op/payload
   └─ TASK-02 workspace-transactions testCr 深接口
         └─ TASK-03 crctl.mjs test dispatch 迁移 --plan
               ├─ TASK-04 crctl.test.mjs 结构化测试矩阵
               ├─ TASK-05 fault-harness test 记录阶段故障矩阵
               └─ TASK-06 Skill/Pipeline 文案与静态契约收敛
```

- TASK-04/05/06 均依赖 TASK-03，且彼此无依赖，可在 M3 后按需并行推进。
- TASK-05 复用 TASK-04 已建立的 test 黑盒 runner 与 fixture helper，但不要求串行。

# 3. 资源与分工

| 角色 | 负责 | 工时 |
|---|---|---|
| development | TASK-01~03、TASK-06 | 18h |
| test | TASK-04、TASK-05 | 10h |

单仓（Tools），无跨仓协调；全程复用现有 `crctl.test.mjs` / `fault-harness.test.mjs` 黑盒 runner 与 fixture。

# 4. 风险与回滚策略

| 风险 | 应对 | 回滚 |
|---|---|---|
| `test` journal 与既有 op 语义冲突 | 只扩展 `OPS`/`PAYLOAD_KEYS` 白名单与 payload 槽位，不新设 envelope 版本 | revert 该 commit，不影响 register/merge/checkpoint/writeback |
| Windows 直接 spawn 可执行文件形式差异 | plan 校验明确 executable 必须可直接 spawn（如 `node.exe`/有扩展名），测试覆盖 | 单点回滚 CLI/Skill 文案 |
| marker 历史报告无唯一 literal | 缺失/重复硬失败，人工修复 | 不回滚为猜测分界 |
| review-loop 与测试写集半状态 | 复用 `applyWriteSet`/`recoverWriteSet`，第三值阻断 | 恢复后完整重试，不新增事务框架 |
| 调用方 `--cmd` 残留 | TASK-06 同步迁移 Skill/Pipeline/crctl SKILL，lint-prompts 阻断 | 同一提交内收敛，不做双入口 |

# 5. 验收与发布策略

发布前 checklist：

- `node --test skills/shared/crctl/scripts/test/crctl.test.mjs` 全绿
- `node --test skills/shared/crctl/scripts/test/fault-harness.test.mjs` 全绿
- `node --test skills/shared/crctl/scripts/test/pipeline-structure.test.mjs` 全绿
- `node skills/shared/crctl/scripts/lint-prompts.mjs --mode enforce` 通过
- `crctl test --plan` 成功路径与业务 block 路径均返回结构化 JSON，exit 0
- `--cmd` 已被移除；Skill/Pipeline 无 shell 字符串执行或直接 traceability/review-loop 写入描述
- 不修改状态机、gates、Agent/matrix、README、writeback 脚本

无 feature-flag；本 CR 是对单一治理工具测试入口的一次性替换，合入 `custom/main` 后旧 `--cmd` 不再可用。
