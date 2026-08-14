# 废止 CR 壳 Issue 设计，shell_issue_id 改语义为「CR 关联 Issue」

P0 §2.1/§4.1 与 PRD §4.2 曾承诺「`issue.cr_id` 1:1 挂指针 → 壳 Issue 映射 7 态进
`metadata.cr_status_bucket` → 看板禁拖拽 CR 壳」三件套，但自 P0 落地以来从未实现，
CR 的项目内可见性实际由 `project_gates` 端点 + 聊天窗口门禁徽标承担（CR-2026-011）。
2026-08-07 敲定：**废止三件套设计，不补实现**——看板上的禁拖拽卡片从未被要求过，
补实现要动 issue 表 DDL + crsync 写入 + 前端拖拽逻辑，三处改动换一个无需求场景不值。

连带处置：`cr.shell_issue_id` 列保留，语义从「CR 壳 Issue」改为「CR 关联 Issue」，
由 crsync 投影时从 `cr.md` 的 `origin: {type:issue}` 回填——它是 project_gates
项目级 CR 列表的唯一关联锚点，此前无生产写入路径（仅测试 fixture 填过），
门禁徽标列表存在空心化风险，回填是顺势修复而非新机制。

被否决的备选：B（连 JOIN 一起废、门禁列表退化为 workspace 级）丢失项目归属；
C（补全三件套）成本与需求不匹配。P0 §3.5 的 TASK 子 Issue 投影锚定壳 Issue，
随本决策一并悬置——TASK 投影待有真实诉求再定锚点。
