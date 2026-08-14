---
id: CR-2026-037-plan
type: PLAN
cr-ref: CR-2026-037
title: crctl TASK 索引初始化与 task-breakdown 门禁闭环开发计划
status: draft
owner: Ray
created: "2026-08-13T10:42:00+08:00"
updated: "2026-08-13T10:42:00+08:00"
total-estimate: 16h
---

# 开发计划

## 1. 目标与边界

以最小改动补齐 `crctl task init`，让 `TASK-NN.md` 到受控 `tasks/_index.yml` 的首次物化只有 crctl 一个写入口，并在 `task-breakdown` 前阻止缺索引放行。

直接复用现有 `parseYaml`、`matchFrontmatter`、`resolveCrState`、`sha256`、`casWrite`、`auditLog`、`fileExists` gate 和 controlled Git；不新增事务框架、manifest、版本化脚本、第三方依赖、状态、Agent 权限或 README 算法。generic Plan/TASK validate 与 schema ID 统一不在本计划内。

## 2. 里程碑

| 里程碑 | TASK | 产出 | 完成条件 |
|---|---|---|---|
| M1 深原语可用 | TASK-01 | task init 核心、help/dispatch、定向测试 | create/refresh/no-op/失败/并发测试通过 |
| M2 流程采纳闭环 | TASK-02 | task-breakdown gate、next、Skill/Pipeline/crctl Skill | 缺索引阻断；消费者不再指导直写账本 |
| M3 回归与发布准备 | TASK-03 | 全套测试、静态范围检查、CR-032 恢复命令核验 | 全量门禁通过，changed-files 与 SDD 一致 |

## 3. TASK 清单

| TASK | 标题 | 估算 | 依赖 | 主要仓库 |
|---|---|---:|---|---|
| CR-2026-037-TASK-01 | 失败优先实现 task init 深原语 | 8h | 无 | tools |
| CR-2026-037-TASK-02 | 接入索引门禁与 Skill/Pipeline 契约 | 5h | TASK-01 | tools |
| CR-2026-037-TASK-03 | 执行回归、范围审计与发布恢复准备 | 3h | TASK-02 | tools + knowledge-base evidence |

总估算：**16h**。

## 4. 依赖与执行顺序

```text
TASK-01 -> TASK-02 -> TASK-03
```

严格串行：TASK-01 独占 `crctl.mjs` 核心与主定向测试；TASK-02 在命令稳定后修改 gate/next 和消费者；TASK-03 只做必要修复、验证与证据，不提前并行编辑同一文件。

外部依赖：

- 权威 tools `custom/main` 与 Node >= 18；
- CR-2026-037 的 PRD/SDD 与审批证据；
- CR-2026-032 已提交的 4 张 TASK 卡，仅在本修复合入后做发布验收。

## 5. 实施策略

### 5.1 测试优先

TASK-01 先在现有 `crctl.test.mjs` 写一个集中测试组，至少覆盖合法 create、no-op、pending refresh、进度拒绝、坏卡、悬空/环、状态、CRLF、freshness 和 CAS；确认新断言在实现前失败，再写最短实现。

### 5.2 最小代码路径

- `crctl.mjs` 内局部 helper，不建新模块；
- 标准库 `openSync('wx')` 负责首次 create-only，现有 `casWrite` 负责刷新；
- 简单 DFS 校验 DAG；
- 固定数组 join 渲染五字段 canonical YAML；
- no-op 不写文件、不追加 audit；
- `task done` 零行为改动。

### 5.3 消费者采纳

TASK-02 只同步接口：Skill 生成 TASK 卡后调用 `task init`；Pipeline 只编排调用顺序；crctl Skill/help 登记命令。README、Agent 和其他 Pipeline 不动。

## 6. 资源与环境

- 负责人：Ray；单人串行实施，无并行资源需求。
- 工具：Node 标准库、现有 crctl test fixture、`lint-prompts.mjs`、Skill/Agent contract tests。
- Worktree：只在 CR-2026-037 对应 tools/knowledge-base worktree 修改和留证；Multica worktree必须保持零 diff。

## 7. 验证矩阵

| 验证 | 对应 TASK | 对应 AC |
|---|---|---|
| create/排序/字段/总工时 | TASK-01 | AC-01 |
| no-op 字节与 audit 稳定 | TASK-01 | AC-02 |
| 卡片字段硬失败 | TASK-01 | AC-03 |
| 悬空依赖与环 | TASK-01 | AC-04 |
| 状态与 pending refresh | TASK-01 | AC-05 |
| done/done-at/损坏进度保护 | TASK-01 | AC-06 |
| CAS、TASK freshness、CRLF | TASK-01 | AC-07 |
| task-breakdown gate | TASK-02 | AC-08 |
| Skill/Pipeline 采纳 | TASK-02 | AC-09 |
| task done/dev-plan/dev-start 回归与静态契约 | TASK-03 | AC-10 |
| changed-files 范围 | TASK-03 | AC-11 |
| CR-2026-032 已合入工具恢复 | 发布后 | AC-12 |

## 8. 风险与控制

| 风险 | 控制 |
|---|---|
| create 写失败留下损坏新文件 | 仅在本进程成功 `wx` 创建后清理失败产物；EEXIST 不删除他人文件 |
| TASK 解析后并发变化 | 写前重核文件集合和原始 SHA，变化即 `TASK_SET_CHANGED` |
| refresh 覆盖开发进度 | 允许态 + existing index 全 pending 双重守卫 |
| Pipeline/Skill 复制算法 | 只写调用顺序和失败中止，算法唯一在 crctl |
| 顺手接 generic validate | changed-files 与 TASK 验收显式排除 |
| 自举例外扩散 | 仅人类为 CR-2026-037 首次创建 `_index.yml`；合入后失效 |

## 9. 回滚与发布

### 9.1 回滚

按 TASK 提交逆序 revert。保留已经生成的合法 `_index.yml`，不删除账本；回滚仅撤销首次生成能力和 gate/Prompt 采纳，不回退为 Agent/Skill 手写。

### 9.2 发布顺序

1. CR-2026-037 通过代码评审、人工代码审批并合入 tools `custom/main`；
2. 确认 AI First Platform 的 `workspace.tools_package_path` 解析到已合入版本；
3. 在 CR-2026-032 权威 knowledge-base worktree 调用正式 `crctl task init`；
4. 提交索引并推进 task-breakdown；
5. 执行 review-dev-plan，完成 AC-12。

禁止用 CR-2026-037 候选 tools worktree治理 CR-2026-032。

## 10. 自举说明

本计划生成的三张 TASK 卡完成后，由人类一次性审阅并创建 CR-2026-037 自身 `_index.yml`。Agent 不写该账本、不生成会话脚本；其余 status、review、approval、done 仍全部走 crctl。该外部 bootstrap 在 task init 合入后永久终止。

## 11. 完成定义

- 三张 TASK 均经 `crctl task done` 登记 done；
- tools 定向/全量测试、Prompt lint、contract 测试通过；
- Multica production/test/CUSTOM.md 均零 diff；
- changed-files 不超 SDD 白名单；
- test-report、代码评审和审批证据完整；
- 发布后按 §9.2 恢复 CR-2026-032。

## 12. 变更记录

| 日期 | 版本 | 作者 | 说明 |
|---|---|---|---|
| 2026-08-13 | v0.1.0 | Ray | 3 个串行 TASK、16h；核心实现、流程采纳、回归发布三里程碑 |
