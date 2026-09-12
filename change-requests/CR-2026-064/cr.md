---
id: CR-2026-064
title: CR-R：结构化恢复合同原子迁移 — `recoverCommand`/`recover_command` 全量退役为结构化 `recovery`
summary: "把 crctl 可恢复结果统一为唯一结构化字段 `recovery`（executable / args[] / cwd / requiresTTY / promptFor[]），在同一个 CR 内迁移全部已知生产者（register、workspace sync、merge、publication lag、checkpoint、writeback traceability、writeback apply、archive、test）与全部活跃消费者（crctl.mjs 投影、crctl / merge-feature-branch / push-progress / cr-archive Skill、multica overlay Agent、README 与 openwiki 事实源、活跃测试），并在同一个 CR 内删除 `recoverCommand` 与 `recover_command`，复用既有 contract-scan 把两个名字加入退役禁止名单。消费方一律按 argv 边界执行，禁止 shell:true 与 Invoke-Expression；需人工重新输入的值（如 reset reason）只经 promptFor[] 声明，不进入 args[]。不做双写兼容期、deprecated alias、migration shim、第二个删除 CR；不改 reviewLoop / archive / merge / checkpoint / writeback 的业务算法，也不改错误码、状态转换、transaction id、rollback 与 files 语义；不包含 AIFI-18 的 SDD review 规则、`_context.md` 删除、plan/TASK 增量回修、Pipeline 节点调整、Multica API 或 importer 改造；不新增使用量、失败率、SLO 或迁移统计；tools 发布后的平台 Prompt 部署由 owner 另行执行。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-09-12T22:07:08+08:00"
  development:
    id: Ray
    assigned-at: "2026-09-12T22:07:08+08:00"
  test:
    id: Ray
    assigned-at: "2026-09-12T22:07:08+08:00"
target-version: 0.37
target-spec-id: ai-first-platform
source: AIFI-25
origin: ""
status: drafting
created: "2026-09-12T22:07:08+08:00"
updated: "2026-09-12T22:07:08+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-09-12T22:07:08+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-09-12T22:07:08+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-09-12T22:07:08+08:00", reason: initial-assignment }
handover-history: []
---
