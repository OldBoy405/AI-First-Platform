# 作者单次隔离库验证：迁移 101 seed

只验证 runner 种子修改的一个受控实际路径；不是独立执行、整包回归、CI 适配、TC-RUN-003 验收或 Gate 变更。独立只读复审原文与清单位于本目录；复审后 README 曾进一步澄清 TestMain 检查只在启动时执行，runner 源码与其 manifest 匹配。

- 既有批准的 pinned 容器；单执行者、单次调用，`node scripts/aifi45-db/run.mjs ./internal/handler '^TestRollupTaskUsageHourlyIdempotentAndWatermark$' <prefix>`；无 `-skip` 和附加迁移。
- 作者进程 exit 0；真实顶层 `TestRollupTaskUsageHourlyIdempotentAndWatermark` 1 RUN / 1 PASS / 0 FAIL / 0 SKIP；runner `leaf_pass=1`。
- `seed-state-initialized.verified={rows:1, default_rows:1}`；受限角色身份核验、原库 approval 表拒读成立。该读回发生于可选迁移之前，本次无附加迁移；它不证明 schema/触发器或迁移历史全等。
- 原库前后**行内容摘要**一致，其他原库会话 0、advisory locks 0；本次数据库与角色均经 catalog 验证缺席，`owned_resources_cleaned=true`。行摘要不覆盖全部 schema、权限或序列，不称完整数据库未变。
- 执行前后 3863 个选定 checkout `.go`/`.sql` 与 Go module 文件的聚合均为 `b739d3b8c87082964969b01ad8bf6fa22bc6aeb7a570138e630bae21bed15823`，选法、测试文件与 Go 版本见 `author-test-inputs.json`；不覆盖外部依赖缓存、忽略文件或环境。
- 私有原始证据前缀：`C:/Users/GOBAO/.pi/aifi45-evidence/seed-default-20261028T104500Z`。approval SQL 包含敏感保留库数据，**不得提交**。
- 原始文件 SHA-256：`.events.jsonl` `1d09c0c57a3f17646dc344b99ef0784ddc5c7b6d1d318c6dcf58f973ea2e08c5`；`.meta.json` `c07f9c18136c55ea71b99249a003a80e20a850394a65b1228e73a63f14d3c00a`；`.stdout.jsonl` `c02a3943791642ac90c29a0cd2a012f2480610aeb06651bf2222a57b7c87c49c`；`.stderr.log` `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`；`.original-before.json` / `.original-after.json` 均为 `8355951516e440af97aa7b394a0081dd21a5168786329dd82349d62bee5bbb3c`。

独立复核只核作者回执与当前输入：首轮 `RECEIPT-REVIEW-INCOMPLETE.md`，续核 `RECEIPT-REVIEW-LIMITED.md`；未亲跑、未查 catalog，拒读回执无 SQLSTATE。原两份报告均保留，不能将限定回执核验升级成独立测试。

常规 CI/local 测试入口仍不能使用普通数据库通过 `cmd/server` TestMain；继续保留 BLOCK。旧审查 verdict、事故记录、BUILD 44/49 和 Gate3 NO-GO 不变。
