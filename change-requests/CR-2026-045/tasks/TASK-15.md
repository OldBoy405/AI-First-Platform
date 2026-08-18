---
id: CR-2026-045-TASK-15
type: TASK
cr-ref: CR-2026-045
plan-ref: "change-requests/CR-2026-045/plan.md"
sdd-ref: "change-requests/CR-2026-045/sdd.md"
title: "issue origin constraint migration repair"
slug: issue-origin-constraint-repair
status: pending
estimate: 3h
depends-on:
  - CR-2026-045-TASK-14
created: 2026-08-18T18:39:17+08:00
---

# TASK-15 issue origin constraint migration repair

## 1. 任务描述

修复 migration 259/263 重建 `issue_origin_type_check` 时丢失 `project_chat`/`project_discussion` 的回归。不得修改已发布 migration 的历史语义；新增向前修复 migration，恢复完整合法 origin 集合，使项目 Chat/Discussion 容器 issue 创建不再返回 500。

## 2. 涉及文件 / 模块

- `server/migrations/267_issue_origin_type_restore.up.sql`
- `server/migrations/267_issue_origin_type_restore.down.sql`
- `server/migrations/268_issue_origin_type_restore_validate.up.sql`
- `server/migrations/268_issue_origin_type_restore_validate.down.sql`
- `server/internal/service/project_chat_test.go` 或 migration/integration fixture
- `CUSTOM.md`（迁移编号和上游核对策略）

## 3. 实现要点

- 完整合法集合必须包含既有 `autopilot`、`quick_create`、`lark_chat`、`slack_chat`、`agent_create`、`project_chat`、`project_discussion`、`dingtalk_chat`、`wecom_chat`。
- up 侧沿用现有 `NOT VALID` + 独立 `VALIDATE` 模式；不新增 foreign key、表或依赖。
- down 侧不能静默留下不受约束的数据；沿用仓库 migration 回滚约定并在注释中说明。
- 增加升级后约束/容器创建回归验证。

## 4. 验收条件

1. 干净数据库执行完整 migration 后，`project_chat` 与 `project_discussion` 均可插入，非法 origin 仍被约束拒绝。
2. 从当前已受影响 migration 状态升级后，constraint 包含全部九种合法值；项目 Chat/Discussion container integration test 通过。
3. migration 文件符合 Multica `CREATE INDEX CONCURRENTLY` 与单语句约束纪律，go test/build/vet 通过。

## 5. 完成标志

repair migrations、约束验证和项目容器回归测试全部通过，并登记 CUSTOM.md；正式 test-report 记录 clean-upgrade 与 affected-upgrade 两条证据。

## 6. 接口契约

- 消费：TASK-04 迁移结构纪律、现有 160/163/259/263/264 origin constraint 事实。
- 产出：最终数据库约束允许完整 origin 集合，服务层无需新增 fallback 或特殊分支。
