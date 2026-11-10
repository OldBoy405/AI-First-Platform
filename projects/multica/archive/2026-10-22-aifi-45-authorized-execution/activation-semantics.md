# 不可删 activation：语义推导与实现边界

> 触发：`tasks.md` 反复出现「不可删 activation」，但 `design.md`、`slices.md`、`test-plan.md` 与 tools 侧 wire-contract **都没有定义它是什么**。本文件把语义钉死、写明推导依据，再据此实现最小本体；**语义本身是本次推导**，需在 Gate 前被确认，不能被当成既有设计。

## 现有事实（推导依据）

| 环节 | 已实现含义 | 证据 |
|---|---|---|
| 签发 binding | 平台在某个 head + 某个 run 代次上，回答了这串 challenge | `execution_binding_issue.go` |
| 消费 receipt | **这个 run 代次**花掉了那份证明；一代次一张、append-only | `execution_consumption.go` + 迁移 644 |
| 撤销 grant | 换 head（新事实），不是删旧事实 | revoke 端点 |

## 因此 activation 只能意味着

**平台声明「这个 run 代次在当前 head 上已满足准入前置」，且这条声明一旦写入不可删除。**

三条推论：

1. **必须有 receipt 才能激活**：没消费就激活等于绕过消费，activation 会变成第二条准入旁路。
2. **不可删 ≠ 可撤销**：要停下来只能产生**新事实**（撤销 head / 后续 supersede），不能 DELETE 或 UPDATE 掉"曾经激活过"这件事。否则审计链可以被抹掉——这正是"不可删"要防的东西。
3. **一代次一条**：与 receipt 同一粒度（`workspace, cr, runtime, task, dispatched_at`），否则同一代次可以有多条互相矛盾的激活声明。

## 不做什么（防越界）

- **不翻** `EXECUTION_CONSUMPTION_REQUIRED`：activation 写入后，T 仍以它退出，daemon 也不读 activation 做准入。**activation 记录 ≠ 已准入**。
- 不提供 DELETE/UPDATE 路由，也不在 DB 层留"软删"列（软删等于可删）。
- 不引入 FK/级联；不新增全局开关。

## 可验证判据

| 判据 | 预期 |
|---|---|
| 无 receipt 直接激活 | 409 `EXECUTION_CONSUMPTION_REQUIRED_FOR_ACTIVATION`，0 行 |
| receipt 存在、challenge 一致 | 201 `changed=true`，1 行，`consumption_id` 指向该 receipt |
| 同代次重放同 challenge | 200 `changed=false`，同一 `activation` id，仍 1 行 |
| 同代次换 challenge（该 challenge 也已签发并消费？） | 409 `EXECUTION_ACTIVATION_CONFLICT` |
| 直接 `UPDATE`/`DELETE`/`TRUNCATE` 表 | 全部报错（触发器） |
| 对 activation 路径发 `DELETE` | 404/405（无路由） |
| 撤销 head 后激活 | 409（head 校验先于幂等分支） |
