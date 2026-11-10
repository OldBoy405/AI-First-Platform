## 本次补充：LIMITED PASS（仅限回执及当前输入一致性）

**原 INCOMPLETE 记录保留，不追溯改写。**未重读作者文档，未执行测试、数据库或容器操作，未改文件，未触碰 approval SQL 原始行。

### 已完成核对

| 项目 | 只读核对结果 |
|---|---|
| 六个指定文件 | **6/6 SHA-256 与报告一致**；stderr 为空 |
| 精确顶层测试 | `TestRollupTaskUsageHourlyIdempotentAndWatermark`：**1 RUN / 1 PASS / 0 FAIL / 0 SKIP**；无其他测试名，package PASS |
| 作者执行结果 | `meta.test.exit=0`，`leaf_pass=1` |
| Seed | 一个初始化事件；`verified.rows=1`、`default_rows=1` |
| 身份与拒读 | 身份中的角色、数据库均匹配回执目标；`original_audit_table_read_denied=true` |
| 原库行摘要 | 前后 **137 个 digest 全部相同**，两份快照 SHA 也相同；`original_unchanged=true` |
| 会话／锁 | 回执均为 `sessions=0`、`locks=0` |
| 资源缺席 | 创建、身份、删除记录的目标内部比对一致；缺席事件为 `database_present=false`、`role_present=false`，且 `owned_resources_cleaned=true` |

按实际嵌套字段复核后，`meta.test`、`created.target`、`isolation.identity` 均匹配；此前顶层试取值产生的 null/false **不是实际证据不一致**。

### 当前源码输入

- `scripts/aifi45-db/run.mjs` SHA：匹配 manifest。
- `server/internal/handler/dashboard_test.go` SHA：匹配 manifest。
- `server/go.mod`、`server/go.sum` SHA：均匹配。
- 按清单选法重新计算 **3863 个文件**，无缺失或跳过，聚合为：
  ```
  b739d3b8c87082964969b01ad8bf6fa22bc6aeb7a570138e630bae21bed15823
  ```
  与报告及 manifest 一致。

### 仍有的边界

- **只核作者回执，未亲跑、未查询 catalog。**拒读只有布尔断言，无错误原文／SQLSTATE交叉验证；缺席事件本身未附目标标识，只能结合前述目标链确认回执口径。
- 行摘要不证明全部 schema、权限或序列未变；当前聚合匹配也不能追溯证明作者执行前后两次采样均实际完成。聚合不覆盖依赖缓存、忽略文件及环境。
- `scripts/aifi45-db/README.md` 当前确有工作区修改；**不能将它视为旧四文件清单已覆盖的内容**，也不在本次源码聚合内。本轮未审其文本。

**CI BLOCK、既有 verdict 与 Gate3 NO-GO 均不关闭、不变更。**