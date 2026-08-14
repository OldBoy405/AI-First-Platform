---
id: CR-2026-037-TASK-02
type: TASK
cr-ref: CR-2026-037
plan-ref: CR-2026-037-plan
sdd-ref: CR-2026-037-sdd
title: 接入索引门禁与 Skill Pipeline 契约
status: pending
estimate: 5h
depends-on: [CR-2026-037-TASK-01]
owner: Ray
created: "2026-08-13T10:42:00+08:00"
updated: "2026-08-13T10:42:00+08:00"
---

# TASK-02：接入索引门禁与 Skill/Pipeline 契约

## 目标

让 `task-breakdown` 在 `_index.yml` 缺失时 fail-closed，并让 `write-dev-tasks`、code-implementation Pipeline 与 crctl Skill/help 采用已完成的 task-init 接口，不复制其算法。

## 依赖

- CR-2026-037-TASK-01 已完成，`task init` 接口与错误语义稳定。

## 实施步骤

1. 在 `gates.json#statusGates.task-breakdown` 增既有 `fileExists` 条目。
2. 为缺索引 gate/advance 阻断和补齐后通过增加回归测试。
3. 在 `cmdNext(task-breakdown)` 增缺索引恢复建议，指向 `write-dev-tasks`/`task init`。
4. 更新 `write-dev-tasks/SKILL.md`：只生成 TASK 卡，再调用 task init、核对总工时、advance、controlled Git。
5. 更新 `code-implementation.pipeline.json`：删除模型直接生成 `_index.yml`，仅保留调用编排与失败中止。
6. 更新 `crctl/SKILL.md` 和 CLI help：登记 init/done 接口、允许态和核心错误语义。
7. 保持 Agent/matrix、README、其他 Pipeline、状态机不变。

## 产出

- `skills/shared/crctl/gates.json`；
- `skills/shared/crctl/scripts/crctl.mjs` 的 next/help 小改；
- `skills/develop/write-dev-tasks/SKILL.md`；
- `pipeline-templates/code-implementation.pipeline.json`；
- `skills/shared/crctl/SKILL.md`；
- 对应现有测试文件回归断言。

## 验收标准

- [ ] 缺 `_index.yml` 时 task-breakdown gate 和 advance 失败，补齐后既有 plan/TASK gate 通过。
- [ ] task-breakdown 漂移态缺索引时 `crctl next` 建议 write-dev-tasks/task init，不错误建议 review-dev-plan。
- [ ] write-dev-tasks 不再指导模型或 Agent 手写 `_index.yml`。
- [ ] Pipeline 只编排“写卡→task init→advance”，无字段/DAG/CAS/YAML 算法副本。
- [ ] crctl Skill/help 可发现 init 和 done，未知 task 子命令错误文案同步。
- [ ] Pipeline JSON 可解析且节点数、dependsOn、状态映射不变。
- [ ] README、Agent/matrix、状态机、版本化脚本和 Multica 零 diff。

## 排除

不增加 gate type 或深内容 gate；TASK 业务质量继续由 review-dev-plan 判断。
