# 两份 verdict-outcome 草稿：proposal 生成流程静态核对

请求独立只读会话 `01a186e1-920b-7020-aecc-d2c6c718fbf0`，actual backend unknown；未重跑 `stdd validate`、写文件或代表用户确认 Gate。两份历史校验因缺 `proposal.md` 退出 1，不代表 Gate 已通过或失败。

- `../stdd/.stdd/skills/understand.md:42–60` 要求确认前提供 Human View，`:96–141` 又写确认前不生成文件、确认后自动生成；当前流程文本相互冲突，不能自行把文档生成当作确认。
- `stdd canon generate <change> --type proposal` 技术上能定向渲染，但 `stdd/stdd/cli/commands/canon.py:430–523` 直接 `write_text`，未调用 Gate 的漂移保护；没有原子仅新建/禁止覆盖选项。`--all` 影响范围更广，不得用于本任务；先检查不存在也不能排除并发覆盖。`--dry-run` 对 generate 会拒绝，不是预览；verify 也可能触发生成。不能为补校验文件擅自使用这些写操作。
- 当前渲染器只展示部分 canonical 字段，不等于模板所需完整可审查草案，也不能仅凭渲染文件把签名合同变更视作批准。两侧 canonical 草稿记录 Ray 为负责人；本次复核未核验确认原文或当前 raw SHA。
- 安全后续：先由流程负责人解释冲突及明确无覆盖生成方案；若需要持久文件，应先核目标路径/符号链接与并发所有权，并分别处理两项目绑定。展示完整草案后，Gate 1 仍须用户明确确认并留证；本自动续作不代行。独立 readiness/签名变更及存量兼容仍需另行评审。
