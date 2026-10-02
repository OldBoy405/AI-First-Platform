---
id: CR-2026-075
title: CR 执行入口与声明一致性修订方案
summary: "依据 AIFI-41 附件《CR 执行入口与声明一致性修订方案》v4，在一个 CR 内按两个内部任务 A/B 实施：A 复用 daemon 预检，将 Pipeline 与普通 Issue 委派的可信 operational workspace 绑定到 task 和 crctl 公共入口；B 补齐规划与竞品两个业务专用受控写入入口及确定性转换，对齐生成、日期、索引、校验、版本和审批合同，限定同 run 一次本地纠正，验证绑定后收敛重复提示并同步线上部署。复用现有事务、CAS、审计、隔离提交与测试，保持独立评审、人工审批、路径及授权边界；不新增执行器、通用写入或权限框架，不纳入 source 默认值修复及 PRD/SDD validator，不关联其他 CR。"
owner: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
owners:
  requirement:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-10-02T21:07:07+08:00"
  development:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-10-02T21:07:07+08:00"
  test:
    id: a0e71a32-509d-4ee9-aea4-d086a5b1ff93
    assigned-at: "2026-10-02T21:07:07+08:00"
target-version: 0.48
target-spec-id: ai-first-platform
source: ""
origin: ""
status: tech-designing
created: "2026-10-02T21:07:07+08:00"
updated: "2026-10-02T21:43:16+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-10-02T21:07:07+08:00", reason: initial-assignment }
  - { role: development, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-10-02T21:07:07+08:00", reason: initial-assignment }
  - { role: test, from: "", to: a0e71a32-509d-4ee9-aea4-d086a5b1ff93, at: "2026-10-02T21:07:07+08:00", reason: initial-assignment }
handover-history: []
---
