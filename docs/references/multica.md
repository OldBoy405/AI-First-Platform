# multica

- 仓库：https://github.com/multica-ai/multica.git
- 分支：main
- 引用 commit：`b4137fc5b5ff7b929e4a42a3c5864b6b1dd3b2b7`（2026-08-19 刷新；前值 `f7ca045fb181efbc7f1dca481abd2bccd4c40ea6`，已陈旧）
- fork 侧对应点：`../multica` HEAD `2f46a0988c3f31bf0c6ddd72d29f7ebebc11bde4`（`Merge upstream/main (b4137fc5b, 258 commits) per CUSTOM.md merge principles`）——上游 pin 已完成双周 rebase 吸收
- 本地路径（评审/开发时按需 clone）：`C:\Users\GOBAO\Downloads\AI\multica`
- 用途：平台 fork 基座，见[《AI-First平台-完整技术方案.html》](../product/AI-First平台-完整技术方案.html) §9；Agent CLI 抽象（`server/pkg/agent/`，14 种 CLI 类型）、任务分发（`FOR UPDATE SKIP LOCKED` claim 机制）是我们复用的核心能力
- 最后核对日期：**2026-08-19**（本次仅刷新 commit 指针与 P3 相关基础设施清单；上次全面核对 2026-07-30，详见[平台方案评审报告.md](../analysis/平台方案评审报告.md) §1.1）
- 2026-08-19 新增核对结论（P3 开工前基础设施盘点，详见[P3-组织智能设计.md](../product/P3-组织智能设计.md) §7）：
  - 可直接复用：`internal/scheduler`（`sys_cron_executions` 分布式 DB cron，唯一键 insert + lease 轮换 + 重试 + 心跳）、`internal/governance/gate_projection.go`（已将 crctl 事件流投影至 `pipeline_node_run.attempt`）、`pkg/redact`（16 条密钥正则）、`pkg/skillbundle.BuildManifest`（内容哈希）、`packages/views` + recharts 3.8.0
  - **不存在**（文档历史误记）：`task_usage_daily`（迁移 103 故意删除）、`task_usage_rollup_state`（真名 `task_usage_hourly_rollup_state`）、通用事务型 outbox 抽象
  - 硬约束：新迁移从 **375** 起（fork 自有迁移已占至 374）；禁新增 FOREIGN KEY；索引必 `CREATE INDEX CONCURRENTLY` 且一个迁移文件一条；代码注释必英文
