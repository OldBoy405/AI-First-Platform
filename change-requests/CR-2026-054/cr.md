---
id: CR-2026-054
title: CR 归档安全、Agent 执行边界与任务终态闭环 — 归档候选严格写前校验、共享服务边界与存活 daemon 终态补投
summary: "一个 CR 统一改造三个共同验收的业务域：(1) crctl archive 在新 write-set 建立前对 _backlog/_history/_index/cr.md 四个候选做严格 YAML 解析与归档后置条件校验（新增 ARCHIVE_YAML_INVALID 稳定错误类别，初始构建与远端 rebuild 同套校验）；(2) Agent 在实现与评审期间遵守共享服务边界——dev-agent.md 只声明职责，implement-code 独有 ENVIRONMENT_MISMATCH 技术失败语义（Pipeline onFail=abort 处理，不掩盖代码缺陷、不生成代码 blocker），review-code 不采信无对应关系的共享实例输出；(3) multica daemon 在 CompleteTask/FailTask 有限重试耗尽且仍为瞬时错误时，按 task ID 入内存待重试集合，30 秒周期单 worker 幂等补投，进程存活期间至少一次重放、依赖服务端幂等收敛，不新增状态/队列/持久化。修改范围：tools（yaml-subset.mjs 严格模式、workspace-transactions.mjs 校验、cr-archive SKILL 失败分类、dev-agent/implement-code/review-code/README）、multica（terminal_report_retry.go 定制 + daemon.go 两个 AIFIRST 挂钩 + CUSTOM.md 登记）。三个业务域不得拆 CR，任一未完成不得进入代码审批。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-29T12:13:07+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-29T12:13:07+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-29T12:13:07+08:00"
target-version: tbd
source: "docs/product/CR归档安全与Agent执行边界及任务终态闭环方案.md"
origin: ""
status: code-reviewing
created: "2026-08-29T12:13:07+08:00"
updated: "2026-08-29T21:29:18+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-29T12:13:07+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-29T12:13:07+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-29T12:13:07+08:00", reason: initial-assignment }
handover-history: []
---
