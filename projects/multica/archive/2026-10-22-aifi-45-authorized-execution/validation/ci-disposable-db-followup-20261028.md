# CI/local 隔离测试库 — 调查待办（未实施）

状态：**未关闭、不可合入**。`cmd/server` 的 `TestMain` 在 setup/cleanup 前校验实际一次性库与受限身份；现有 `.github/workflows/ci.yml`、`scripts/test-go.sh` 仍使用普通测试库。不得通过给普通库设置 marker 或加 bypass 适配。

只读计划审查：session `01a181f6-61d0-7020-aecc-d17365ada764`；未跑数据库、未修改源码。其完整原文见会话记录。建议保持门禁，在明确归属的测试专用集群中，为 `cmd/server` 与需要隔离库的 governance 包**分别、每次**新建 nonce DB/受限 owner/双 marker，并执行正式迁移；需要建库权限的其他 regular 包不能简单换成同一无 CREATEDB 用户。守护现有 CLI、race、agent-only 无数据库访问、包不遗漏及 agent CLI guard；同步检查 `Makefile`、`scripts/check.sh`、`release.yml` 和 CI path filters。

核验证据必须分层：先用 fake Go/provisioner 检验 wrapper 路由和失败清理；真正的隔离资源创建、正式迁移、受限身份连接与无遗留清理仍须单独实测。现有 `scripts/aifi45-db/run.mjs` 固定保全容器/端口与单包白名单、仅运行受控 `go test`，不能直接作为泛用 CI provisioner；它的 schema-only 数据库缺正式迁移账本，既有 readiness 失败不能称为全套通过。现有约束要求 DB evidence 只走该 runner，目前尚未实现可验证新通用 provisioner 全生命周期的路径。候选方案是在该 runner 内增加受控测试模式，启动独占临时 PostgreSQL 实例并确保销毁，再在其中验证真正 provisioner；实施前需先设计实例所有权、身份核对和异常清理，不得碰保全库。在验证完成前，不宣称已解决或用假数据/跳过掩盖。

## 为什么不能只随机化 fixture 后共享普通库

只读调查 session `01a1820e-f4fa-7020-aecc-d179ef9ae28b` 结论 **INCOMPLETE**，但已定位跨 fixture 实际危险：`server/cmd/server/runtime_gc_test.go:369` 运行真实全库 GC，`runtime_sweeper.go:529,693` 最终删除 runtime；同包 sweeper/scheduler 测试也会处理其他 scope。另 `cr_attribution_test.go:27,34` 按固定 CR ID、无 workspace 条件删除，`integration_test.go:370,825` 仍有固定 email/slug。该调查没有穷尽所有间接调用，不能把随机 workspace/email 当足够隔离，也不能据此放松 TestMain。所列为静态可达性，不表示本次碰过任何数据。

该调查不改变原 TestMain 审查、TC-RUN-003、BUILD 状态或 Gate3 NO-GO。
