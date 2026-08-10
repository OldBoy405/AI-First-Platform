---
id: CR-2026-028
title: tools 流程步骤优化 v2 — 前移优化项独立 CR（tools-root 唯一解析 + Skill 路径统一 + crctl 配置加载修正 + cr-init 注册入口复用）
summary: "从《tools流程步骤优化v2》Phase 2～7 候选路线中单独抽出的基础路径与入口契约优化，不并入已在实施中的 Phase 0/1 CR：① 唯一 tools-root 解析契约——以目标 workspace 的 dir-graph.yaml#workspace.tools_package_path 为唯一配置来源，相对路径相对于 workspace root 解析，验证 AGENTS.md/skills/_index.yml/crctl.mjs 标志文件，失败返回 TOOLS_PACKAGE_NOT_FOUND，不静默回退 workspace 内同名空壳 tools/、cwd 或调用方 package root，同一调用链只解析一次；② Skill 与脚本入口路径统一——Skill 文档不得假设 workspace 内存在 tools/ 子目录，执行 tools 内脚本统一从 toolsRoot 派生绝对路径，文档示例须标明相对基准，回写/crctl/适配器/测试不得各自发明路径推导；③ crctl 配置加载顺序修正——先读 workspace.tools_package_path 并验证 tools root，再从该 root 加载 dir-graph.yaml 与 Pipeline 只读配置，仅独立运行且无 workspace 配置时回退 crctl 自身 package root，空壳目录不作隐式候选；④ Registration 复用 crctl cr-init 注册元数据入口——注册元数据优先经 cr-init 参数传入，不新增 register-preflight/registration-check/stage-context 命令，cr.md/_backlog.yml/_index.yml 原子建档继续由 cr-init 负责，worktree 复用 worktree-path 与 repositories。验收边界：多目录调用解析到同一 tools root、空壳 tools/ 不误读、标志文件缺失硬失败、cr-init 一次建档无第二次 frontmatter 旁路写入、现有状态机/gate/审批/账本语义不变。"
owner: Ray
owners:
  requirement:
    id: Ray
    assigned-at: "2026-08-10T15:06:42+08:00"
  development:
    id: Ray
    assigned-at: "2026-08-10T15:06:42+08:00"
  test:
    id: Ray
    assigned-at: "2026-08-10T15:06:42+08:00"
target-version: tbd
source: "docs/analysis/tools流程步骤优化v2-前移优化项.md"
status: tech-designing
created: "2026-08-10T15:06:42+08:00"
updated: "2026-08-10T15:06:42+08:00"
remote-ref: ""
last-push-at: ""
last-push-by: ""
owner-history:
  - { role: requirement, from: "", to: Ray, at: "2026-08-10T15:06:42+08:00", reason: initial-assignment }
  - { role: development, from: "", to: Ray, at: "2026-08-10T15:06:42+08:00", reason: initial-assignment }
  - { role: test, from: "", to: Ray, at: "2026-08-10T15:06:42+08:00", reason: initial-assignment }
handover-history: []
---
