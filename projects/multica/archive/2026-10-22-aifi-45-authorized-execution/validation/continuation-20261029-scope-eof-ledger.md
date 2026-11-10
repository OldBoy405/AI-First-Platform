# AIFI-45 续作：scope、collector 与台账对账

## 用户确认

`2026-10-29-trusted-verdict-outcome-binding` 的负责人为 Ray，multica/tools 两份草案已同步；变更仍在 understand，所有阶段 pending。负责人确认不是 Gate 批准。新的原字节快照及 hash：`verdict-outcome-owner-ray-20261029/`；旧无主快照及原复核保留。

## 已做的局部修改

- Readiness 数据查询按 request ID **及 scope**：覆盖启用、签发、退役、访问分类四个调用点。`readiness-scope-binding-20261029/AUDIT-RED.json` 在去 scope overlay 下十五个异 scope audit leaf 命中语义断言、十五个同 scope 正控通过；最终 fake-Tx 子包独立复跑 9 顶层/152 leaf、0 skip（`REVIEW-AUDIT-BALANCED.md`）。包含五个 audit 操作 × ACTIVE/过期/带 verdict_ref 的 STOP_NEW。不是签名验证、真实 DB 锁或历史数据兼容证明。跨 scope 的 audit/recovery 也会被拒绝，兼容须核；静态复核还发现既有锁序潜在环，未在 PG 复现。
- Supervisor collector 双 EOF 后解码并擦除私有 stdout，再发布固定结果；擦除异常不发布成功，已登记首错可在后续事件重试擦除。最终四个 Node 测试文件独立复跑 66/66、0 skip；代码及六个测试/协议快照在 `ci-supervisor-eof-wipe-20261029/source-final-rechecked/`，作者 RED/GREEN 与变异在同目录 JSON。异常仍可能逸出，复次擦除失败或未闭合时明文可能保留；未来 pump 的异常和清理要求见 multica `scripts/aifi45-db/README.md`。
- multica `CUSTOM.md` #276/#277 登记相关改动。测试均只取派生事件，未保存原始测试 stdout/stderr；独立复核 backend receipt unknown。不声称实际隔离、进程树退出、生产安全或可部署。

## 计数与下一步

旧 **44/49** 和「缺 5」重复计算 EVD-007 且遗漏 RUN-008/009，不可作当前验收数。按历史 CP 原口径去重为 43/49；进一步按 EVD-008 完整能力口径扣除为 42/49（缺 EVD-008 与 RUN-001/003/006/007/008/009），两者均未对当前源码重跑，统一口径待负责人核定。见 `tc-ledger-reconciliation-20261029.md` 和 `pending-adjustments.yaml`；历史报告不改写。

`run008-009-gap-20261029.md` 记录真实切换入口、评审轮次/代次、乱序与终态并发的前置；`run009-binding-candidate-20261029.md` 给出经独立静态质疑后修订的待评审候选，尚未批准或实施。仍须核签名结果权威、generation/subject/producer、锁图和真实入口；不能把当前 non-nil decider guard 当可信实现，不能提前注入旧 decider。M001–M005 未解决，Gate3 **NO-GO**。现有源码若启用 architecture runner，因 main 未注入 decider 将拒绝启动；未部署。

## 操作和风险边界

本轮未运行 DB、容器、真实 CR、server 或 CLI 执行体，未部署、提交或推送。隔离数据库验证仍需受批准 runner、精确选择、0 skip、原库未变和独占资源清理回执。保留历史 BLOCK/INCOMPLETE、旧快照及未知资源。

一次审查搜索被工具自动存成含内部源码的随机临时日志，独占创建和原有状态不可核；另有硬编码测试标记被误回显。详见 `readiness-scope-binding-20261029/INCIDENT-AUTO-LOG-20261029.md`；日志未删除、不得转储正文。
