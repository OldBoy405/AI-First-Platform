# Supervisor collector 双 EOF 即时擦除计划

**目标**：仅在 stdout/stderr 都到 EOF 且 stdout 非空时，解码为固定字段并立即擦除 collector 私有 stdout 缓冲，不等调用者 `result()`。EOF 返回值、未到双 EOF 的处理、失败优先级及无进程/清理权限边界不变。

**涉及文件**：`scripts/aifi45-db/supervisor-collector.mjs`；`supervisor-erase.test.mjs`（双 EOF 前后私有分配对照，正常与畸形、双 EOF 顺序）；`supervisor-collector.test.mjs`（延迟暴露解码错误、后续 abort/duplicate EOF/data/invalid event 优先级）。不修改 protocol、引擎、真实进程或 DB。

1. 保存旧源码/测试原始字节 SHA；先用 test-only allocator 引用证明私有缓冲确实接收 canary，再断言双 EOF 后、`result()` 前清零，避免空测试伪绿；只输出固定诊断，不泄漏 canary。
2. 原行为 RED；实现双 EOF 仅内部缓存 decoder 固定字段结果并用 finally 擦除。格式错误在 `result()` 时才成为 sticky failure，让它之前到达的 abort、重复 EOF、额外数据和无效事件仍抢先。
3. 跑 collector、protocol、erase、buffer-brand 的 no-DB 单测，选中数非零、skip 0；至少用隔离副本变异“延迟清除”验证擦除测试真正失败。独立复核最新哈希与优先级。

**不证明**：未到双 EOF 就丢弃 collector、caller 自有 Buffer、同进程内置对象被篡改、进程退出/进程树、stdout 来源、journal/fsync、engine 清理授权和端到端 RUN 都不在此覆盖范围。
