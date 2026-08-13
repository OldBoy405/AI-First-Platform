---
id: CR-2026-037-TASK-01
type: TASK
cr-ref: CR-2026-037
plan-ref: CR-2026-037-plan
sdd-ref: CR-2026-037-sdd
title: 失败优先实现 task init 深原语
status: pending
estimate: 8h
depends-on: []
owner: Ray
created: "2026-08-13T10:42:00+08:00"
updated: "2026-08-13T10:42:00+08:00"
---

# TASK-01：失败优先实现 task init 深原语

## 目标

在现有 `crctl.mjs` 和 `crctl.test.mjs` 内，以失败优先方式实现 `crctl task init`；复用 parser/CAS/audit，不新增模块、依赖、事务或 manifest。

## 输入

- PRD FR-01～FR-05、AC-01～AC-07；
- SDD §2～§4.4；
- 现有 `cmdTaskDone`、`parseYaml`、`matchFrontmatter`、`resolveCrState`、`casWrite`、`auditLog`。

## 实施步骤

1. 在现有测试文件加入集中 task-init 测试组，先证明命令缺失导致失败。
2. 增加 `task init` dispatch/help，拒绝额外业务输入和未知 task 子命令。
3. 实现严格 TASK 文件枚举、CRLF 规范化、frontmatter 字段校验、唯一性和总工时计算。
4. 用简单 DFS 校验悬空依赖、自环和多节点环。
5. 实现 canonical 五字段 YAML 渲染，title 复用 `yamlStringScalar`，按编号稳定排序。
6. 实现允许态、existing index 全 pending/progress guard、TASK 集合 freshness 重核。
7. 首次写用 `openSync('wx')`；刷新用现有 `casWrite`；no-op 不写、不 audit。
8. `wx` 创建后的 write/close 失败只清理由当前进程创建的目标，EEXIST 不清理。

## 产出

- `skills/shared/crctl/scripts/crctl.mjs` 的 `task init` 深原语；
- `skills/shared/crctl/scripts/test/crctl.test.mjs` 的定向测试。

## 验收标准

- [ ] 合法 TASK 集合生成按编号排序的 canonical `_index.yml`，返回正确 taskCount/totalEstimateHours/changed。
- [ ] 相同输入重跑 `changed=false`，文件字节和成功 audit 数不变。
- [ ] 全 pending 索引可在两个允许态刷新；developing 和其他状态拒绝。
- [ ] 空集、坏 frontmatter、ID/CR/type/title/status/estimate/depends-on 错误均在写入前失败。
- [ ] 悬空依赖、自环和多节点环使用约定错误码且零写入。
- [ ] done/done-at/未知状态/损坏索引返回 `TASK_INDEX_HAS_PROGRESS`，原字节不变。
- [ ] LF/CRLF 产生同一索引；TASK 集合或 SHA 变化返回 `TASK_SET_CHANGED`。
- [ ] create EEXIST 与 replace CAS 冲突拒绝覆盖；create 写失败只清理本进程产物。
- [ ] 现有 `task done` 接口和测试零回归。

## 排除

不改 gate、Skill/Pipeline、README、状态机、generic validate；不新增 production fault point。
