---
id: CR-2026-017
title: P3 组织智能 CR-E — 内部 Skill Market（E6）
summary: >-
  P3 组织智能第五个 CR（独立线，与其他 CR 无依赖）：内部 Skill Market——把个人工作流
  沉淀为组织资产的流通面。① 数据模型扩展——skill 表加 visibility（private/org/builtin，
  对齐 CodeBanana 私有/组织可见，builtin=tools 包内置）+ version + owner_actor
  （对齐 agent-skill-matrix 唯一 owns）；skill_usage_event 表（排行与"哪些技能真的被用"，
  任务完成回调附带 skills_used[] 落库，零额外探针）。② 生命周期——创建（与 Agent
  对话打包/上传/P2 §7 会话导出草稿）→ 私有库 → Add to Project → 发布到组织（选可见
  范围，内部版只有 org 一档）→ 版本更新（新版本号）；列表带作者、版本、使用量排行
  （skill_usage_event 聚合）、运行时要求标签（该 Skill 需要哪些本机 CLI/网络/TTY，
  从 SKILL.md 前置要求半自动提取）。③ 发布 = 授权——Skill 从 private 升 org 的发布
  动作即视为作者对"团队复用该工作方法"的显式授权，发布确认框明示此含义；发布校验含
  敏感信息扫描（API Key/内网凭据/个人路径等模式匹配，复用平台内部敏感判定能力）。
  ④ 治理钩子——发布/更新时服务端校验（dir-graph.yaml#agents.contract 4 条不变式
  变成代码）：name+description frontmatter 必填；org 可见 Skill 必须指定唯一
  owner_actor；SKILL.md 需通过 validate-doc 结构校验（daemon 侧跑）；内置 59 个
  builtin Skill 只随 tools 包版本更新，Market 内不可编辑。⑤ 资产元数据卡——org 可见
  Skill 增加 4 个必填 frontmatter 字段：applicable-scenarios（适用场景）/
  context-dependencies（依赖上下文）/ permission-declaration（能读写哪些目录）/
  failure-handling（失败后怎么办）；四字段渲染为 Market 详情页"使用说明卡"；
  permission-declaration 与 P1 rules.json#protectedPaths 做一致性提示；builtin Skill
  四字段由 tools 包一次性补齐。⑥ 过程记录资产化（可选，P3+）——对接 P2 §7「导出为
  Skill 草稿」：Team Agent 会话多选 → SKILL.md 草稿 → 私有库 → 人工修订 → 经治理
  钩子发布；导出草稿带 source: session-export 标记（Market 列表可筛），不单独排期，
  随 Market 前端顺带。
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-04T06:55:00+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-04T06:55:00+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-04T06:55:00+08:00"
target-version: "0.24"
source: "docs/product/P3-组织智能设计.md §3（E6）"
status: drafting
created: "2026-08-04T06:55:00+08:00"
updated: "2026-08-04T06:55:00+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - role: requirement
    from: ""
    to: Ray
    at: "2026-08-04T06:55:00+08:00"
    reason: initial-assignment
  - role: development
    from: ""
    to: Ray
    at: "2026-08-04T06:55:00+08:00"
    reason: initial-assignment
  - role: test
    from: ""
    to: Ray
    at: "2026-08-04T06:55:00+08:00"
    reason: initial-assignment
handover-history: []
---
